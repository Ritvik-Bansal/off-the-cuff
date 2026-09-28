import SwiftUI

/// GitHub-style practice calendar: 7 rows (weekday) x 16 columns (week), colored by that
/// day's best score. Always shows the last 16 weeks, independent of the range picker.
struct PracticeHeatmapCard: View {
    /// All completed sessions (any date range — this card looks back 16 weeks on its own).
    let sessions: [PracticeSession]

    private let weekCount = 16
    private let calendar = Calendar.current
    private let cellSize: CGFloat = 14
    private let cellSpacing: CGFloat = 3

    private var bestScoreByDay: [Date: Int] {
        var result: [Date: Int] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.date)
            result[day] = max(result[day] ?? 0, session.overallScore)
        }
        return result
    }

    /// Sunday of the earliest displayed week.
    private var gridStart: Date {
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday
        let currentWeekStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        return calendar.date(byAdding: .day, value: -7 * (weekCount - 1), to: currentWeekStart) ?? currentWeekStart
    }

    private func date(week: Int, weekday: Int) -> Date {
        calendar.date(byAdding: .day, value: week * 7 + weekday, to: gridStart) ?? gridStart
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Practice Calendar")
                .font(.headline)
            Text("Last 16 weeks — color shows your best score that day")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    weekdayLabels
                    HStack(spacing: cellSpacing) {
                        ForEach(0..<weekCount, id: \.self) { week in
                            VStack(spacing: cellSpacing) {
                                ForEach(0..<7, id: \.self) { weekday in
                                    cell(for: date(week: week, weekday: weekday))
                                }
                            }
                        }
                    }
                }
            }

            legend
        }
        .card()
    }

    private var weekdayLabels: some View {
        let symbols = ["S", "M", "T", "W", "T", "F", "S"]
        return VStack(spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { row in
                Text(row % 2 == 1 ? symbols[row] : "")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: cellSize)
            }
        }
    }

    @ViewBuilder
    private func cell(for day: Date) -> some View {
        let today = calendar.startOfDay(for: .now)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let isFuture = day > today
        let score = bestScoreByDay[calendar.startOfDay(for: day)]

        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fillColor(score: score, isFuture: isFuture))
            .frame(width: cellSize, height: cellSize)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(isToday ? Theme.accent : .clear, lineWidth: 1.5)
            )
            .accessibilityLabel(accessibilityLabel(day: day, score: score, isFuture: isFuture))
    }

    private func fillColor(score: Int?, isFuture: Bool) -> Color {
        guard !isFuture, let score else { return Color(.tertiarySystemFill) }
        let intensity = 0.35 + 0.65 * (Double(score) / 100)
        return Theme.color(for: score).opacity(intensity)
    }

    private func accessibilityLabel(day: Date, score: Int?, isFuture: Bool) -> String {
        let dateString = day.formatted(.dateTime.month(.wide).day())
        if isFuture { return dateString }
        if let score { return "\(dateString): best score \(score)" }
        return "\(dateString): no practice"
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less")
                .font(.caption2)
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 10, height: 10)
            ForEach([35, 60, 80, 100], id: \.self) { score in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.color(for: score).opacity(0.35 + 0.65 * Double(score) / 100))
                    .frame(width: 10, height: 10)
            }
            Text("More")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}
