import Foundation

/// Time window for the Progress dashboard's charts and summary stats.
enum ProgressRange: String, CaseIterable, Identifiable {
    case week = "7D"
    case month = "30D"
    case quarter = "90D"
    case all = "All"

    var id: String { rawValue }

    /// Number of days this range spans, or `nil` for "All" (the caller falls back to the
    /// span between the first session and now).
    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .all: nil
        }
    }
}

/// One score component's average over the selected range vs. the range before it.
struct SkillAverage: Identifiable {
    let component: ScoreComponent
    let current: Double?
    let previous: Double?
    var id: String { component.id }
}

/// A filler/crutch phrase and how many times it occurred.
struct TopFiller: Identifiable {
    let phrase: String
    let count: Int
    var id: String { phrase }
}

/// Aggregates that require decoding `PracticeSession.analysisData`. Callers should compute
/// these once (e.g. in a `.task(id:)`) rather than on every body pass.
enum ProgressAnalytics {
    /// Averages each `ScoreComponent` across the given sessions, for the current range and the
    /// equal-length range immediately before it. Components with no data in either range are omitted.
    static func skillAverages(current: [PracticeSession], previous: [PracticeSession]) -> [SkillAverage] {
        let currentAverages = averages(for: current)
        let previousAverages = averages(for: previous)
        return ScoreComponent.allCases.compactMap { component in
            let currentValue = currentAverages[component]
            let previousValue = previousAverages[component]
            guard currentValue != nil || previousValue != nil else { return nil }
            return SkillAverage(component: component, current: currentValue, previous: previousValue)
        }
    }

    /// Sums `metrics.fillerBreakdown` across the given sessions and returns the most common phrases.
    static func topFillers(in sessions: [PracticeSession], limit: Int = 8) -> [TopFiller] {
        var totals: [String: Int] = [:]
        for session in sessions {
            guard let breakdown = session.analysis?.metrics.fillerBreakdown else { continue }
            for (phrase, count) in breakdown {
                totals[phrase, default: 0] += count
            }
        }
        return totals
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { TopFiller(phrase: $0.key, count: $0.value) }
    }

    private static func averages(for sessions: [PracticeSession]) -> [ScoreComponent: Double] {
        var sums: [ScoreComponent: Double] = [:]
        var counts: [ScoreComponent: Int] = [:]
        for session in sessions {
            guard let scores = session.analysis?.scores else { continue }
            for component in ScoreComponent.allCases {
                if let value = scores.value(for: component) {
                    sums[component, default: 0] += Double(value)
                    counts[component, default: 0] += 1
                }
            }
        }
        var result: [ScoreComponent: Double] = [:]
        for (component, count) in counts where count > 0 {
            result[component] = sums[component, default: 0] / Double(count)
        }
        return result
    }
}
