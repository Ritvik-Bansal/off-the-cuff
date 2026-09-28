import Foundation

/// Computes plain-language insight sentences from a speaker's completed sessions.
/// Every insight is gated on having enough data so early users never see a shaky claim.
enum ProgressInsights {
    /// `sessions` should be all completed sessions, oldest first.
    static func generate(from sessions: [PracticeSession], calendar: Calendar = .current) -> [String] {
        guard sessions.count >= 5 else { return [] }

        var insights: [String] = []

        if let fillerInsight = fillerTrendInsight(sessions) {
            insights.append(fillerInsight)
        }
        if let paceInsight = paceInsight(sessions) {
            insights.append(paceInsight)
        }
        if let weekdayInsight = bestWeekdayInsight(sessions, calendar: calendar) {
            insights.append(weekdayInsight)
        }

        return Array(insights.prefix(3))
    }

    /// Compares the earliest 5 sessions' filler rate to the most recent 5.
    private static func fillerTrendInsight(_ sessions: [PracticeSession]) -> String? {
        let groupSize = 5
        guard sessions.count >= groupSize * 2 else { return nil }

        let first = sessions.prefix(groupSize)
        let last = sessions.suffix(groupSize)
        let firstAverage = first.map(\.fillersPerMinute).reduce(0, +) / Double(groupSize)
        let lastAverage = last.map(\.fillersPerMinute).reduce(0, +) / Double(groupSize)
        guard firstAverage > 0.1 else { return nil }

        let change = (firstAverage - lastAverage) / firstAverage * 100
        if change >= 15 {
            return "Fillers per minute are down \(Int(change.rounded()))% from your first \(groupSize) sessions."
        } else if change <= -20 {
            return "Fillers per minute have crept up \(Int((-change).rounded()))% since your first \(groupSize) sessions — worth a reset."
        }
        return nil
    }

    /// Looks at the most recent sessions' words-per-minute against the 130–170 sweet spot.
    private static func paceInsight(_ sessions: [PracticeSession]) -> String? {
        let recent = sessions.suffix(min(10, sessions.count))
        guard !recent.isEmpty else { return nil }

        let inSweetSpot = recent.filter { (130...170).contains($0.wordsPerMinute) }
        let fraction = Double(inSweetSpot.count) / Double(recent.count)
        if fraction >= 0.6 {
            return "Your pace has settled into the 130–170 sweet spot."
        }

        let averagePace = recent.map(\.wordsPerMinute).reduce(0, +) / Double(recent.count)
        if averagePace > 175 {
            return "You tend to speak faster than the 130–170 sweet spot — easing off slightly could help."
        } else if averagePace < 125 && averagePace > 0 {
            return "You tend to speak slower than the 130–170 sweet spot — a little more energy could help."
        }
        return nil
    }

    /// Finds the weekday with the highest average score, if it clearly stands out.
    private static func bestWeekdayInsight(_ sessions: [PracticeSession], calendar: Calendar) -> String? {
        var scoresByWeekday: [Int: [Int]] = [:]
        for session in sessions {
            let weekday = calendar.component(.weekday, from: session.date)
            scoresByWeekday[weekday, default: []].append(session.overallScore)
        }

        let overallAverage = sessions.map { Double($0.overallScore) }.reduce(0, +) / Double(sessions.count)
        let candidates = scoresByWeekday.filter { $0.value.count >= 2 }
        guard let best = candidates.max(by: { average($0.value) < average($1.value) }) else { return nil }

        let bestAverage = average(best.value)
        guard bestAverage - overallAverage >= 3 else { return nil }

        let symbols = calendar.weekdaySymbols
        guard best.key - 1 >= 0, best.key - 1 < symbols.count else { return nil }
        let name = symbols[best.key - 1]
        return "Best day: \(name)s — you average \(Int(bestAverage.rounded())) there, vs \(Int(overallAverage.rounded())) overall."
    }

    private static func average(_ values: [Int]) -> Double {
        values.map(Double.init).reduce(0, +) / Double(values.count)
    }
}
