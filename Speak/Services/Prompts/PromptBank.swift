import Foundation

/// A large bank of speaking prompts (~35-40 per category). The actual prompt data lives in
/// `PromptBank+Data.swift`, split into one array per `PromptCategory` and concatenated into `all`.
enum PromptBank {
    static func prompts(in category: PromptCategory) -> [SpeakingPrompt] {
        all.filter { $0.category == category }
    }

    /// A random prompt from the enabled categories, avoiding recently used prompts where possible.
    static func random(in categories: Set<PromptCategory> = AppSettings.enabledCategories,
                       excluding recent: Set<String> = PromptBank.recent) -> SpeakingPrompt {
        let pool = all.filter { categories.contains($0.category) }
        let fresh = pool.filter { !recent.contains($0.text) }
        return (fresh.randomElement() ?? pool.randomElement() ?? all.randomElement())!
    }

    /// Texts of recently used prompts (persisted under `AppSettings.Keys.recentPrompts`).
    static var recent: Set<String> {
        guard let data = UserDefaults.standard.string(forKey: AppSettings.Keys.recentPrompts)?.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(list)
    }

    /// Records a prompt as used so `random` avoids it for a while (keeps the last 60).
    static func markUsed(_ prompt: SpeakingPrompt) {
        var list = (UserDefaults.standard.string(forKey: AppSettings.Keys.recentPrompts)?.data(using: .utf8))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        list.removeAll { $0 == prompt.text }
        list.append(prompt.text)
        if list.count > 60 { list.removeFirst(list.count - 60) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: AppSettings.Keys.recentPrompts)
        }
    }
}
