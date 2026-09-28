import Foundation
import Observation
import SwiftData
import UIKit

/// Runs a recorded session through extraction → transcription → analysis → AI coaching → scoring,
/// and writes the result onto the `PracticeSession`.
@MainActor
@Observable
final class SessionProcessor {
    enum Stage: Equatable {
        case idle
        case extractingAudio
        case transcribing
        case analyzing
        case coaching
        case finished
        case failed(String)

        var title: String {
            switch self {
            case .idle: "Getting ready"
            case .extractingAudio: "Reading your recording"
            case .transcribing: "Transcribing every word"
            case .analyzing: "Counting fillers and pauses"
            case .coaching: "Reviewing your content"
            case .finished: "Done"
            case .failed: "Something went wrong"
            }
        }

        /// Rough 0...1 progress for a progress bar.
        var progress: Double {
            switch self {
            case .idle: 0
            case .extractingAudio: 0.1
            case .transcribing: 0.35
            case .analyzing: 0.7
            case .coaching: 0.85
            case .finished, .failed: 1
            }
        }
    }

    private(set) var stage: Stage = .idle

    /// Processes (or re-processes) a session whose recording is in `MediaStore`.
    func process(_ session: PracticeSession, context: ModelContext) async {
        guard let url = session.videoURL else {
            fail(session, context: context, message: "The recording file is missing, so this session can't be analyzed.")
            return
        }

        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "AnalyzeSession")
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }

        session.status = .processing
        session.errorMessage = nil
        try? context.save()

        do {
            stage = .extractingAudio
            let sampleRate = AudioExtractor.sampleRate
            let samples = try await AudioExtractor.loadSamples(from: url)
            let recordingDuration = Double(samples.count) / sampleRate
            session.recordedDuration = recordingDuration
            guard recordingDuration >= 3 else { throw TranscriptionError.noSpeechDetected }

            stage = .transcribing
            let transcription = try await TranscriptionService.shared.transcribe(samples: samples, sampleRate: sampleRate)
            guard !transcription.words.isEmpty else { throw TranscriptionError.noSpeechDetected }

            stage = .analyzing
            let targetDuration = session.targetDuration
            let (words, metrics) = await Task.detached(priority: .userInitiated) {
                DeliveryAnalyzer.analyze(
                    transcription: transcription,
                    samples: samples,
                    sampleRate: sampleRate,
                    recordingDuration: recordingDuration,
                    targetDuration: targetDuration
                )
            }.value

            var ai: AIFeedback?
            if AppSettings.aiCoachEnabled, case .available = AICoach.availability, metrics.wordCount >= 15 {
                stage = .coaching
                ai = await AICoach.feedback(prompt: session.promptText, transcript: transcription.text, metrics: metrics)
            }

            let scores = ScoringEngine.score(metrics: metrics, ai: ai)
            let feedback = FeedbackGenerator.generate(metrics: metrics, scores: scores, words: words)
            let analysis = SessionAnalysis(
                transcript: transcription.text,
                words: words,
                metrics: metrics,
                scores: scores,
                feedback: feedback,
                ai: ai,
                engine: transcription.engine
            )
            session.apply(analysis)

            if !AppSettings.keepRecordings, let fileName = session.videoFileName {
                MediaStore.deleteRecording(named: fileName)
                session.videoFileName = nil
            }
            try? context.save()
            stage = .finished
        } catch {
            fail(session, context: context, message: error.localizedDescription)
        }
    }

    /// Marks sessions left in `.processing` by a previous launch as failed so they can be retried.
    static func recoverInterruptedSessions(in context: ModelContext) {
        let processing = SessionStatus.processing.rawValue
        let descriptor = FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.statusRaw == processing })
        guard let stuck = try? context.fetch(descriptor), !stuck.isEmpty else { return }
        for session in stuck {
            session.status = .failed
            session.errorMessage = "Analysis was interrupted. Tap Retry to analyze it again."
        }
        try? context.save()
    }

    private func fail(_ session: PracticeSession, context: ModelContext, message: String) {
        session.status = .failed
        session.errorMessage = message
        try? context.save()
        stage = .failed(message)
    }
}
