import Foundation
import WhisperKit

/// Verbatim transcription with WhisperKit, prompted to keep filler words and stutters.
struct WhisperTranscriber: SpeechTranscribing {
    /// OpenAI's documented technique for keeping disfluencies verbatim: an example of exactly the
    /// kind of speech we want transcribed, fillers and false starts included.
    private static let verbatimPrompt = "Umm, let me think like, hmm... Okay, here's what I'm, like, thinking. So, uh, I- I think the the main thing is, you know, basically that."

    /// The prompt's words, normalized, used to detect the model echoing the prompt back verbatim
    /// at the start of a transcription (a known hallucination failure mode).
    private static let promptEchoWords: [String] = tokenize(verbatimPrompt)

    private static let noisePhrases: Set<String> = [
        "blank_audio", "silence", "music", "applause", "laughter", "noise", "no speech", "inaudible"
    ]

    func transcribe(samples: [Float], sampleRate: Double) async throws -> TranscriptionOutput {
        let pipeline = try await WhisperModelManager.shared.pipeline()
        guard let tokenizer = pipeline.tokenizer else {
            throw TranscriptionError.modelUnavailable
        }

        let promptTokens = tokenizer.encode(text: " " + Self.verbatimPrompt)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }

        let options = DecodingOptions(
            task: .transcribe,
            language: "en",
            temperature: 0,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            promptTokens: promptTokens,
            chunkingStrategy: ChunkingStrategy.none
        )

        let results = try await pipeline.transcribe(audioArray: samples, decodeOptions: options)

        let words = Self.mapWords(from: results)
        guard !words.isEmpty else { throw TranscriptionError.noSpeechDetected }

        let text = words.map(\.text).joined(separator: " ")
        return TranscriptionOutput(text: text, words: words, engine: .whisper)
    }

    /// Flattens every result's segments into tagged `TranscriptWord`s, filtering hallucinated
    /// noise tokens, a leading echo of the verbatim prompt, and exact duplicate segments produced
    /// by decoder loop hallucinations.
    private static func mapWords(from results: [TranscriptionResult]) -> [TranscriptWord] {
        var words: [TranscriptWord] = []
        var previousSegmentText: String?

        for result in results {
            for segment in result.segments {
                let normalizedSegment = normalize(segment.text)
                if !normalizedSegment.isEmpty, normalizedSegment == previousSegmentText {
                    // Exact duplicate of the previous segment: a looping hallucination, not real speech.
                    continue
                }
                if !normalizedSegment.isEmpty { previousSegmentText = normalizedSegment }

                for timing in segment.words ?? [] {
                    let trimmed = timing.word.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !isNoise(trimmed) else { continue }

                    words.append(TranscriptWord(
                        id: words.count,
                        text: trimmed,
                        start: Double(timing.start),
                        end: Double(timing.end),
                        confidence: Double(timing.probability)
                    ))
                }
            }
        }
        return removingPromptEcho(from: words)
    }

    /// Drops a leading run of words that repeats the verbatim prompt. Only a run of at least
    /// `minimumEchoLength` words counts as an echo, so a real opening "Umm, let me…" survives.
    private static func removingPromptEcho(from words: [TranscriptWord]) -> [TranscriptWord] {
        let minimumEchoLength = 4
        var matched = 0
        for word in words {
            let normalizedWord = normalize(word.text)
            guard matched < promptEchoWords.count, normalizedWord == promptEchoWords[matched] else { break }
            matched += 1
        }
        guard matched >= minimumEchoLength else { return words }
        return words.dropFirst(matched).enumerated().map { index, word in
            var word = word
            word.id = index
            return word
        }
    }

    private static func isNoise(_ word: String) -> Bool {
        let lower = word.lowercased()
        if lower.hasPrefix("<|"), lower.hasSuffix("|>") { return true }
        let stripped = lower.trimmingCharacters(in: CharacterSet(charactersIn: "[](). "))
        return noisePhrases.contains(stripped)
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }

    /// Splits on whitespace (not punctuation) and normalizes each chunk the same way transcript
    /// words are normalized, so contractions like "I'm" compare equal to the model's own output.
    private static func tokenize(_ text: String) -> [String] {
        text.split(separator: " ")
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }
}
