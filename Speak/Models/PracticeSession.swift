import Foundation
import SwiftData

enum SessionStatus: String, Codable, Sendable {
    case processing, complete, failed
}

@Model
final class PracticeSession {
    var id: UUID = UUID()
    var date: Date = Date()
    var promptText: String = ""
    var promptCategoryRaw: String = PromptCategory.opinion.rawValue
    /// Seconds the speaker was aiming for.
    var targetDuration: Double = 60
    /// Seconds actually recorded.
    var recordedDuration: Double = 0
    /// File name inside `MediaStore.recordingsDirectory`, nil when not kept.
    var videoFileName: String?
    /// False when the session was recorded audio-only.
    var hasVideoTrack: Bool = true
    var statusRaw: String = SessionStatus.processing.rawValue
    var errorMessage: String?

    // Denormalized metrics so lists and charts don't need to decode `analysisData`.
    var overallScore: Int = 0
    var fillerCount: Int = 0
    var fillersPerMinute: Double = 0
    var wordsPerMinute: Double = 0
    var stutterCount: Int = 0
    var longPauseCount: Int = 0
    var wordCount: Int = 0

    /// JSON-encoded `SessionAnalysis`.
    @Attribute(.externalStorage) var analysisData: Data?

    init(prompt: SpeakingPrompt, targetDuration: Double, date: Date = .now) {
        self.id = UUID()
        self.date = date
        self.promptText = prompt.text
        self.promptCategoryRaw = prompt.category.rawValue
        self.targetDuration = targetDuration
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var promptCategory: PromptCategory {
        PromptCategory(rawValue: promptCategoryRaw) ?? .opinion
    }

    var prompt: SpeakingPrompt {
        SpeakingPrompt(text: promptText, category: promptCategory)
    }

    /// Decodes the full analysis. Not cached — call once per view and hold the result.
    var analysis: SessionAnalysis? {
        guard let analysisData else { return nil }
        return try? JSONDecoder().decode(SessionAnalysis.self, from: analysisData)
    }

    /// URL of the kept recording, if the file still exists.
    var videoURL: URL? {
        guard let videoFileName else { return nil }
        let url = MediaStore.url(for: videoFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func apply(_ analysis: SessionAnalysis) {
        analysisData = try? JSONEncoder().encode(analysis)
        overallScore = analysis.scores.overall
        fillerCount = analysis.metrics.fillerCount
        fillersPerMinute = analysis.metrics.fillersPerMinute
        wordsPerMinute = analysis.metrics.wordsPerMinute
        stutterCount = analysis.metrics.stutterCount + analysis.metrics.repetitionCount
        longPauseCount = analysis.metrics.longPauseCount
        wordCount = analysis.metrics.wordCount
        errorMessage = nil
        status = .complete
    }
}
