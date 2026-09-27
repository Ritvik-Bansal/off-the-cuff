import Foundation

// MARK: - Transcript

/// How the analyzer classified a transcribed word.
enum WordTag: String, Codable, Hashable, Sendable {
    case normal
    /// Vocalized hesitation or filler usage: "um", "uh", filler "like", "you know", "I mean".
    case filler
    /// Verbal crutch / hedge words that weaken delivery: "basically", "actually", "literally", "kind of".
    case crutch
    /// Partial word or immediate word repeat: "I- I", "th- the", "the the".
    case stutter
    /// Repeated multi-word phrase / restart: "I think I think".
    case repetition
}

struct TranscriptWord: Codable, Hashable, Identifiable, Sendable {
    /// Index of the word in the transcript (stable, 0-based).
    var id: Int
    /// The word as transcribed, including attached punctuation (e.g. "um," or "Hello.").
    var text: String
    /// Start time in seconds from the beginning of the recording.
    var start: Double
    /// End time in seconds from the beginning of the recording.
    var end: Double
    /// Recognizer confidence 0...1 when available.
    var confidence: Double?
    var tag: WordTag = .normal
}

enum TranscriptionEngine: String, Codable, Hashable, Sendable {
    case whisper
    case appleSpeech

    var displayName: String {
        switch self {
        case .whisper: "Verbatim model (Whisper)"
        case .appleSpeech: "Apple Speech"
        }
    }
}

struct TranscriptionOutput: Hashable, Sendable {
    var text: String
    /// Words in chronological order, all tagged `.normal` (tagging is the analyzer's job).
    var words: [TranscriptWord]
    var engine: TranscriptionEngine
}

// MARK: - Metrics

struct DetectedPause: Codable, Hashable, Sendable {
    /// Seconds from the beginning of the recording.
    var start: Double
    var duration: Double
}

struct SpeechMetrics: Codable, Hashable, Sendable {
    /// Length of the audio that was analyzed, in seconds.
    var recordingDuration: Double = 0
    /// The session length the speaker was aiming for (e.g. 60s).
    var targetDuration: Double = 60
    /// Time of the first spoken word.
    var speechStart: Double = 0
    /// Time the last spoken word ended.
    var speechEnd: Double = 0
    /// speechEnd - speechStart.
    var speakingDuration: Double = 0
    /// Spoken words excluding fillers and crutch words.
    var wordCount: Int = 0
    /// wordCount / speaking minutes.
    var wordsPerMinute: Double = 0
    var fillerCount: Int = 0
    var crutchCount: Int = 0
    /// Normalized filler phrase -> occurrences, e.g. ["um": 4, "like": 3, "you know": 1]. Includes crutch words.
    var fillerBreakdown: [String: Int] = [:]
    /// (fillerCount + 0.5 * crutchCount) per speaking minute.
    var fillersPerMinute: Double = 0
    var stutterCount: Int = 0
    var repetitionCount: Int = 0
    /// (stutterCount + repetitionCount) per speaking minute.
    var disfluenciesPerMinute: Double = 0
    /// Silent gaps >= 0.6s inside the speaking span.
    var pauses: [DetectedPause] = []
    /// Pauses >= 2.0s.
    var longPauseCount: Int = 0
    var longestPause: Double = 0
    /// Fraction (0...1) of the speaking span that was silent.
    var silenceRatio: Double = 0
    /// Moving-average type-token ratio (0...1) over non-filler words.
    var vocabularyDiversity: Double = 0
    /// speechEnd / targetDuration, clamped 0...1.
    var timeUtilization: Double = 0
}

// MARK: - Scores

enum ScoreComponent: String, Codable, CaseIterable, Identifiable, Sendable {
    case fillers, fluency, pace, flow, timeUse, vocabulary, content

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fillers: "Filler Words"
        case .fluency: "Fluency"
        case .pace: "Pace"
        case .flow: "Pauses"
        case .timeUse: "Time Used"
        case .vocabulary: "Vocabulary"
        case .content: "Content"
        }
    }

    var systemImage: String {
        switch self {
        case .fillers: "text.bubble"
        case .fluency: "waveform.path"
        case .pace: "speedometer"
        case .flow: "pause.circle"
        case .timeUse: "timer"
        case .vocabulary: "character.book.closed"
        case .content: "brain.head.profile"
        }
    }

    /// Weight in the overall score. Content is only counted when AI feedback is available;
    /// otherwise the remaining weights are re-normalized.
    var weight: Double {
        switch self {
        case .fillers: 0.30
        case .fluency: 0.15
        case .pace: 0.15
        case .flow: 0.10
        case .timeUse: 0.10
        case .vocabulary: 0.05
        case .content: 0.15
        }
    }

    var explanation: String {
        switch self {
        case .fillers:
            "Fillers (um, uh, filler \"like\", \"you know\") per minute. Crutch words (basically, actually, literally, kind of) count half. 1 or fewer per minute scores 100."
        case .fluency:
            "Stutters, partial words and repeated phrases per minute. Clean, continuous sentences score highest."
        case .pace:
            "Words per minute. 130–170 WPM is the conversational sweet spot; much slower or faster costs points."
        case .flow:
            "Silences longer than 2 seconds and the share of your speaking time spent silent. Short, deliberate pauses are fine."
        case .timeUse:
            "How much of the time you used. Stopping early usually means you ran out of ideas."
        case .vocabulary:
            "Variety of words (moving-average type-token ratio). Repeating the same words lowers it."
        case .content:
            "On-device AI rating of relevance to the prompt, structure and clarity. Only counted when Apple Intelligence is available."
        }
    }
}

struct ScoreBreakdown: Codable, Hashable, Sendable {
    var overall: Int
    var fillers: Int
    var fluency: Int
    var pace: Int
    var flow: Int
    var timeUse: Int
    var vocabulary: Int
    /// nil when no AI content feedback was available.
    var content: Int?

    func value(for component: ScoreComponent) -> Int? {
        switch component {
        case .fillers: fillers
        case .fluency: fluency
        case .pace: pace
        case .flow: flow
        case .timeUse: timeUse
        case .vocabulary: vocabulary
        case .content: content
        }
    }
}

enum ScoreTier: String, CaseIterable, Sendable {
    case needsWork, developing, solid, excellent

    init(score: Int) {
        switch score {
        case ..<50: self = .needsWork
        case 50..<70: self = .developing
        case 70..<85: self = .solid
        default: self = .excellent
        }
    }

    var label: String {
        switch self {
        case .needsWork: "Needs Work"
        case .developing: "Developing"
        case .solid: "Solid"
        case .excellent: "Excellent"
        }
    }
}

// MARK: - Feedback

enum FeedbackKind: String, Codable, Hashable, Sendable {
    case strength, improvement, tip
}

struct FeedbackItem: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var kind: FeedbackKind
    var title: String
    var detail: String
    var component: ScoreComponent?
}

struct AIFeedback: Codable, Hashable, Sendable {
    /// 0...100 — did the speaker actually address the prompt?
    var relevance: Int
    /// 0...100 — clear opening, supporting points, conclusion.
    var structure: Int
    /// 0...100 — easy to follow, concrete, concise.
    var clarity: Int
    /// 1–2 sentence overall assessment addressed to the speaker ("You…").
    var summary: String
    var strengths: [String]
    var improvements: [String]
    /// A stronger opening sentence the speaker could have used.
    var suggestedOpening: String?
    /// Which model produced it, e.g. "Apple Intelligence (on-device)".
    var modelName: String

    /// Average of relevance/structure/clarity.
    var contentScore: Int { Int(((Double(relevance) + Double(structure) + Double(clarity)) / 3).rounded()) }
}

struct SessionAnalysis: Codable, Hashable, Sendable {
    var transcript: String
    /// Words with analyzer tags applied.
    var words: [TranscriptWord]
    var metrics: SpeechMetrics
    var scores: ScoreBreakdown
    var feedback: [FeedbackItem]
    var ai: AIFeedback?
    var engine: TranscriptionEngine
}
