import Foundation

protocol SpeechTranscribing {
    func transcribe(samples: [Float], sampleRate: Double) async throws -> TranscriptionOutput
}

enum TranscriptionError: LocalizedError {
    case noSpeechDetected
    case recognizerUnavailable
    case permissionDenied
    case modelUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noSpeechDetected: "No speech was detected in the recording."
        case .recognizerUnavailable: "Speech recognition isn't available on this device right now."
        case .permissionDenied: "Speech recognition permission was denied. Enable it in Settings."
        case .modelUnavailable: "The speech model isn't downloaded yet."
        case .failed(let message): message
        }
    }
}

/// Picks the best available engine: the Whisper verbatim model when downloaded, otherwise Apple Speech.
@MainActor
final class TranscriptionService {
    static let shared = TranscriptionService()

    private let whisperTranscriber = WhisperTranscriber()
    private let appleSpeechTranscriber = AppleSpeechTranscriber()

    func transcribe(samples: [Float], sampleRate: Double) async throws -> TranscriptionOutput {
        guard WhisperModelManager.shared.isDownloaded(WhisperModelManager.shared.selectedModel) else {
            return try await appleSpeechTranscriber.transcribe(samples: samples, sampleRate: sampleRate)
        }

        do {
            return try await whisperTranscriber.transcribe(samples: samples, sampleRate: sampleRate)
        } catch TranscriptionError.noSpeechDetected {
            throw TranscriptionError.noSpeechDetected
        } catch {
            return try await appleSpeechTranscriber.transcribe(samples: samples, sampleRate: sampleRate)
        }
    }
}
