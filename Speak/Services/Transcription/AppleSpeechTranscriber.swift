import AVFoundation
import Foundation
import Speech

/// Fallback transcription with SFSpeechRecognizer (tends to drop some filler words).
struct AppleSpeechTranscriber: SpeechTranscribing {
    private static let contextualStrings = ["um", "uh", "like", "you know", "basically", "actually"]
    private static let safetyTimeout: TimeInterval = 90

    func transcribe(samples: [Float], sampleRate: Double) async throws -> TranscriptionOutput {
        try await Self.requestAuthorizationIfNeeded()

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = Self.contextualStrings

        let result = try await Self.runRecognition(recognizer: recognizer, request: request, samples: samples, sampleRate: sampleRate)

        let words = Self.mapWords(from: result)
        guard !words.isEmpty else { throw TranscriptionError.noSpeechDetected }
        let text = words.map(\.text).joined(separator: " ")
        return TranscriptionOutput(text: text, words: words, engine: .appleSpeech)
    }

    private static func runRecognition(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        samples: [Float],
        sampleRate: Double
    ) async throws -> SFSpeechRecognitionResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
            let box = RecognitionBox(continuation: continuation)
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    box.finish(.failure(error))
                    return
                }
                guard let result, result.isFinal else { return }
                box.finish(.success(result))
            }
            box.task = task

            DispatchQueue.main.asyncAfter(deadline: .now() + safetyTimeout) {
                box.finish(.failure(TranscriptionError.failed("Speech recognition timed out.")))
            }

            appendSamples(samples, sampleRate: sampleRate, to: request)
        }
    }

    /// Feeds samples into the recognition request in ~1 second chunks, then signals end of audio.
    private static func appendSamples(_ samples: [Float], sampleRate: Double, to request: SFSpeechAudioBufferRecognitionRequest) {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            request.endAudio()
            return
        }

        let chunkSize = max(1, Int(sampleRate))
        var offset = 0
        while offset < samples.count {
            let length = min(chunkSize, samples.count - offset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length)) else { break }
            buffer.frameLength = AVAudioFrameCount(length)
            if let channelData = buffer.floatChannelData {
                samples.withUnsafeBufferPointer { source in
                    channelData[0].update(from: source.baseAddress! + offset, count: length)
                }
            }
            request.append(buffer)
            offset += length
        }
        request.endAudio()
    }

    private static func requestAuthorizationIfNeeded() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return }
        guard status == .notDetermined else { throw TranscriptionError.permissionDenied }

        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { newStatus in
                continuation.resume(returning: newStatus == .authorized)
            }
        }
        guard granted else { throw TranscriptionError.permissionDenied }
    }

    private static func mapWords(from result: SFSpeechRecognitionResult) -> [TranscriptWord] {
        result.bestTranscription.segments.enumerated().map { index, segment in
            TranscriptWord(
                id: index,
                text: segment.substring,
                start: segment.timestamp,
                end: segment.timestamp + segment.duration,
                confidence: Double(segment.confidence)
            )
        }
    }
}

/// Bridges the delegate-style `SFSpeechRecognitionTask` callback to a single continuation resume,
/// guaranteed to fire exactly once (final result, error, or safety timeout).
private final class RecognitionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false
    private let continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>
    var task: SFSpeechRecognitionTask?

    init(continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<SFSpeechRecognitionResult, Error>) {
        lock.lock()
        guard !didFinish else { lock.unlock(); return }
        didFinish = true
        lock.unlock()

        task?.cancel()
        continuation.resume(with: result)
    }
}
