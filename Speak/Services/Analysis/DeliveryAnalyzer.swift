import Foundation

enum DeliveryAnalyzer {
    /// Tags filler/crutch/stutter/repetition words and computes delivery metrics.
    /// - Parameters:
    ///   - samples: mono audio at `sampleRate`, used for acoustic pause detection.
    static func analyze(
        transcription: TranscriptionOutput,
        samples: [Float],
        sampleRate: Double,
        recordingDuration: Double,
        targetDuration: Double
    ) -> (words: [TranscriptWord], metrics: SpeechMetrics) {
        let words = transcription.words
        guard !words.isEmpty else {
            return (words, SpeechMetrics(recordingDuration: recordingDuration, targetDuration: targetDuration))
        }

        let tokens = TokenBuilder.makeTokens(words)
        let fillerResult = FillerDetector.detect(tokens: tokens)
        let disfluencyResult = DisfluencyDetector.detect(tokens: tokens, fillerTags: fillerResult.tags)
        let tags = disfluencyResult.tags

        var taggedWords = words
        for i in taggedWords.indices {
            taggedWords[i].id = i
            taggedWords[i].tag = tags[i]
        }

        let realWords = words.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let speechStart = min(max(realWords.first?.start ?? 0, 0), max(recordingDuration, 0))
        let speechEnd = min(max(realWords.last?.end ?? 0, speechStart), max(recordingDuration, 0))
        let speakingDuration = max(0, speechEnd - speechStart)

        let pauseResult = PauseDetector.detect(
            samples: samples,
            sampleRate: sampleRate,
            words: words,
            speechStart: speechStart,
            speechEnd: speechEnd
        )
        let pauses = pauseResult.pauses
        let longPauseCount = pauses.filter { $0.duration >= 2.0 }.count
        let longestPause = pauses.map(\.duration).max() ?? 0
        let totalPauseTime = pauses.reduce(0) { $0 + $1.duration }
        let silenceRatio = speakingDuration > 0 ? min(1, totalPauseTime / speakingDuration) : 0

        // Words that count toward speaking content: normal and repeated-phrase words,
        // but not fillers, crutches, stutters or empty/punctuation-only tokens.
        let countsTowardWords: Set<WordTag> = [.normal, .repetition]
        let wordCount = tokens.indices.filter { !tokens[$0].isEmpty && countsTowardWords.contains(tags[$0]) }.count

        // A short clip's per-minute rates would otherwise explode; floor the divisor
        // at 10s worth of minutes. For speakingDuration >= 10s this is the same as
        // dividing by speakingDuration directly.
        let minutes = max(speakingDuration, 10) / 60
        let wordsPerMinute = Double(wordCount) / minutes
        let fillersPerMinute = (Double(fillerResult.fillerCount) + 0.5 * Double(fillerResult.crutchCount)) / minutes
        let disfluenciesPerMinute = Double(disfluencyResult.stutterCount + disfluencyResult.repetitionCount) / minutes

        let vocabularyDiversity = computeMATTR(tokens: tokens, tags: tags, countsTowardWords: countsTowardWords)
        let timeUtilization = targetDuration > 0 ? min(max(speechEnd / targetDuration, 0), 1) : 0

        let metrics = SpeechMetrics(
            recordingDuration: recordingDuration,
            targetDuration: targetDuration,
            speechStart: speechStart,
            speechEnd: speechEnd,
            speakingDuration: speakingDuration,
            wordCount: wordCount,
            wordsPerMinute: wordsPerMinute,
            fillerCount: fillerResult.fillerCount,
            crutchCount: fillerResult.crutchCount,
            fillerBreakdown: fillerResult.breakdown,
            fillersPerMinute: fillersPerMinute,
            stutterCount: disfluencyResult.stutterCount,
            repetitionCount: disfluencyResult.repetitionCount,
            disfluenciesPerMinute: disfluenciesPerMinute,
            pauses: pauses,
            longPauseCount: longPauseCount,
            longestPause: longestPause,
            silenceRatio: silenceRatio,
            vocabularyDiversity: vocabularyDiversity,
            timeUtilization: timeUtilization
        )
        return (taggedWords, metrics)
    }

    /// Moving-average type-token ratio (window 50) over the normalized words that
    /// count toward `wordCount`; plain TTR when there are fewer than 50 of them.
    private static func computeMATTR(tokens: [AnalysisToken], tags: [WordTag], countsTowardWords: Set<WordTag>) -> Double {
        let qualifying = tokens.indices
            .filter { !tokens[$0].isEmpty && countsTowardWords.contains(tags[$0]) }
            .map { tokens[$0].normalized }
        guard !qualifying.isEmpty else { return 0 }

        let window = 50
        if qualifying.count < window {
            return Double(Set(qualifying).count) / Double(qualifying.count)
        }
        var total = 0.0
        var windowCount = 0
        for start in 0...(qualifying.count - window) {
            let slice = qualifying[start..<(start + window)]
            total += Double(Set(slice).count) / Double(window)
            windowCount += 1
        }
        return windowCount > 0 ? total / Double(windowCount) : 0
    }
}
