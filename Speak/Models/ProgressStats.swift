import Foundation

/// Aggregate practice statistics derived from completed sessions.
struct ProgressStats {
    let totalSessions: Int
    let currentStreak: Int
    let bestStreak: Int
    let practicedToday: Bool
    /// Start-of-day dates with at least one completed session.
    let practiceDays: Set<Date>
    /// Mean score of the most recent 7 completed sessions.
    let recentAverage: Double?
    /// Mean score of the 7 completed sessions before those.
    let previousAverage: Double?
    let personalBest: Int?
    let averageFillersPerMinute: Double?
    let averageWordsPerMinute: Double?

    init(sessions: [PracticeSession], calendar: Calendar = .current, now: Date = .now) {
        let completed = sessions
            .filter { $0.status == .complete }
            .sorted { $0.date > $1.date }

        totalSessions = completed.count
        practiceDays = Set(completed.map { calendar.startOfDay(for: $0.date) })

        let today = calendar.startOfDay(for: now)
        practicedToday = practiceDays.contains(today)

        // Current streak: consecutive days ending today (or yesterday, if today isn't done yet).
        var streak = 0
        var cursor = practicedToday ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        while practiceDays.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        currentStreak = streak

        var best = 0
        var run = 0
        var previous: Date?
        for day in practiceDays.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        bestStreak = best

        let recent = completed.prefix(7).map { Double($0.overallScore) }
        let earlier = completed.dropFirst(7).prefix(7).map { Double($0.overallScore) }
        recentAverage = recent.isEmpty ? nil : recent.reduce(0, +) / Double(recent.count)
        previousAverage = earlier.isEmpty ? nil : earlier.reduce(0, +) / Double(earlier.count)
        personalBest = completed.map(\.overallScore).max()

        let recentSessions = Array(completed.prefix(7))
        averageFillersPerMinute = recentSessions.isEmpty ? nil
            : recentSessions.map(\.fillersPerMinute).reduce(0, +) / Double(recentSessions.count)
        averageWordsPerMinute = recentSessions.isEmpty ? nil
            : recentSessions.map(\.wordsPerMinute).reduce(0, +) / Double(recentSessions.count)
    }

    /// Change of the recent average vs the previous window, if both exist.
    var trendDelta: Double? {
        guard let recentAverage, let previousAverage else { return nil }
        return recentAverage - previousAverage
    }
}
