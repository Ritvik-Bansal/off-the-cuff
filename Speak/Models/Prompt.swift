import Foundation

enum PromptCategory: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case interview
    case opinion
    case personal
    case hypothetical
    case explain
    case storytelling
    case business
    case abstract
    case fun

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .interview: "Interview"
        case .opinion: "Opinion"
        case .personal: "Personal"
        case .hypothetical: "Hypothetical"
        case .explain: "Explain It"
        case .storytelling: "Storytelling"
        case .business: "Business & Tech"
        case .abstract: "Big Ideas"
        case .fun: "Just for Fun"
        }
    }

    var systemImage: String {
        switch self {
        case .interview: "briefcase"
        case .opinion: "scale.3d"
        case .personal: "person"
        case .hypothetical: "sparkles"
        case .explain: "lightbulb"
        case .storytelling: "book"
        case .business: "chart.bar"
        case .abstract: "infinity"
        case .fun: "face.smiling"
        }
    }
}

struct SpeakingPrompt: Codable, Hashable, Identifiable, Sendable {
    var id: String { text }
    let text: String
    let category: PromptCategory
}
