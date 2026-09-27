import Foundation

/// Central place for UserDefaults keys and defaults.
/// Views use `@AppStorage(AppSettings.Keys.x) var x = AppSettings.Defaults.x`;
/// services read the static accessors below.
enum AppSettings {
    enum Keys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        /// Int seconds: 30, 60, 90, 120.
        static let sessionLength = "sessionLength"
        /// Int seconds of thinking time before recording: 0, 5, 10, 15, 30.
        static let prepTime = "prepTime"
        /// Bool — record video (true) or audio only (false).
        static let cameraEnabled = "cameraEnabled"
        /// Bool — keep the recording file after analysis.
        static let keepRecordings = "keepRecordings"
        /// String — comma-separated PromptCategory raw values. Empty string = all categories.
        static let enabledCategories = "enabledCategories"
        /// String — WhisperModelOption raw value.
        static let whisperModel = "whisperModel"
        /// Bool — use Apple Intelligence for content feedback when available.
        static let aiCoachEnabled = "aiCoachEnabled"
        static let reminderEnabled = "reminderEnabled"
        /// Int 0...23
        static let reminderHour = "reminderHour"
        /// Int 0...59
        static let reminderMinute = "reminderMinute"
        /// String — JSON array of recently used prompt texts (to avoid repeats).
        static let recentPrompts = "recentPrompts"
    }

    enum Defaults {
        static let sessionLength = 60
        static let prepTime = 5
        static let cameraEnabled = true
        static let keepRecordings = true
        static let enabledCategories = ""
        static let whisperModel = "openai_whisper-base.en"
        static let aiCoachEnabled = true
        static let reminderEnabled = false
        static let reminderHour = 19
        static let reminderMinute = 0
    }

    private static var defaults: UserDefaults { .standard }

    static var sessionLength: Int {
        defaults.object(forKey: Keys.sessionLength) as? Int ?? Defaults.sessionLength
    }

    static var prepTime: Int {
        defaults.object(forKey: Keys.prepTime) as? Int ?? Defaults.prepTime
    }

    static var cameraEnabled: Bool {
        defaults.object(forKey: Keys.cameraEnabled) as? Bool ?? Defaults.cameraEnabled
    }

    static var keepRecordings: Bool {
        defaults.object(forKey: Keys.keepRecordings) as? Bool ?? Defaults.keepRecordings
    }

    static var aiCoachEnabled: Bool {
        defaults.object(forKey: Keys.aiCoachEnabled) as? Bool ?? Defaults.aiCoachEnabled
    }

    static var whisperModel: String {
        defaults.string(forKey: Keys.whisperModel) ?? Defaults.whisperModel
    }

    /// Enabled prompt categories; all categories when none are explicitly selected.
    static var enabledCategories: Set<PromptCategory> {
        decodeCategories(defaults.string(forKey: Keys.enabledCategories) ?? Defaults.enabledCategories)
    }

    static func decodeCategories(_ raw: String) -> Set<PromptCategory> {
        let parsed = Set(raw.split(separator: ",").compactMap { PromptCategory(rawValue: String($0)) })
        return parsed.isEmpty ? Set(PromptCategory.allCases) : parsed
    }

    static func encodeCategories(_ categories: Set<PromptCategory>) -> String {
        if categories.isEmpty || categories.count == PromptCategory.allCases.count { return "" }
        return categories.map(\.rawValue).sorted().joined(separator: ",")
    }
}
