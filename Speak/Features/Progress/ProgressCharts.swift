import Charts
import SwiftUI

/// Shared date-axis formatting so every time-series chart in Progress reads the same way.
private func dateAxis() -> some AxisContent {
    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
        AxisGridLine()
        AxisTick()
        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
    }
}

// MARK: - Overall score trend

/// PointMark per session (tier-colored) plus a 5-session rolling average line.
/// Tap or drag to inspect a session's date and score.
struct ScoreTrendCard: View {
    let sessions: [PracticeSession]

    @State private var selectedDate: Date?

    private var rollingAverage: [(date: Date, value: Double)] {
        sessions.indices.map { index in
            let windowStart = max(0, index - 4)
            let window = sessions[windowStart...index]
            let average = window.map { Double($0.overallScore) }.reduce(0, +) / Double(window.count)
            return (sessions[index].date, average)
        }
    }

    private var selectedSession: PracticeSession? {
        guard let selectedDate else { return nil }
        return sessions.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(selectedDate)) < abs(rhs.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overall Score")
                .font(.headline)
            Text("Each session, with a 5-session rolling average")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(sessions) { session in
                    PointMark(x: .value("Date", session.date), y: .value("Score", session.overallScore))
                        .foregroundStyle(Theme.color(for: session.overallScore))
                        .symbolSize(50)
                }
                ForEach(rollingAverage, id: \.date) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Average", point.value))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .foregroundStyle(Theme.accent)
                }
                if let selectedSession {
                    RuleMark(x: .value("Date", selectedSession.date))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedSession.date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(selectedSession.overallScore)")
                                    .font(.system(.headline, design: .rounded, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.color(for: selectedSession.overallScore))
                            }
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis { dateAxis() }
            .chartXSelection(value: $selectedDate)
            .frame(height: 200)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Overall score trend")
            .accessibilityValue(accessibilitySummary)
        }
        .card()
    }

    private var accessibilitySummary: String {
        guard let latest = sessions.last else { return "No sessions yet." }
        let trend: String
        if sessions.count >= 2 {
            let previous = sessions[sessions.count - 2].overallScore
            let delta = latest.overallScore - previous
            trend = delta == 0 ? "unchanged from the previous session"
                : "\(abs(delta)) points \(delta > 0 ? "higher" : "lower") than the previous session"
        } else {
            trend = "your only session in this range"
        }
        return "\(sessions.count) sessions plotted. Latest score \(latest.overallScore), \(trend)."
    }
}

// MARK: - Fillers per minute

/// Bar per session (lower is better) with a dashed rule at the average.
struct FillerRateCard: View {
    let sessions: [PracticeSession]

    private var average: Double {
        guard !sessions.isEmpty else { return 0 }
        return sessions.map(\.fillersPerMinute).reduce(0, +) / Double(sessions.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fillers per Minute")
                .font(.headline)
            Text("Lower is better — dashed line is your average")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(sessions) { session in
                    BarMark(
                        x: .value("Date", session.date, unit: .day),
                        y: .value("Fillers per minute", session.fillersPerMinute)
                    )
                    .foregroundStyle(Theme.filler.gradient)
                    .cornerRadius(3)
                }
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg \(average, specifier: "%.1f")/min")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartXAxis { dateAxis() }
            .frame(height: 160)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Fillers per minute")
            .accessibilityValue("Average \(average, specifier: "%.1f") fillers per minute across \(sessions.count) sessions.")
        }
        .card()
    }
}

// MARK: - Pace

/// WPM per session with the 130–170 conversational sweet spot shaded.
struct PaceCard: View {
    let sessions: [PracticeSession]

    private var domain: ClosedRange<Date> {
        guard let first = sessions.first?.date, let last = sessions.last?.date else {
            let now = Date()
            return now...now
        }
        if first == last {
            let calendar = Calendar.current
            let lower = calendar.date(byAdding: .hour, value: -12, to: first) ?? first
            let upper = calendar.date(byAdding: .hour, value: 12, to: first) ?? first
            return lower...upper
        }
        return first...last
    }

    private var averagePace: Double {
        guard !sessions.isEmpty else { return 0 }
        return sessions.map(\.wordsPerMinute).reduce(0, +) / Double(sessions.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pace")
                .font(.headline)
            Text("Words per minute — shaded band is the 130–170 sweet spot")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart {
                RectangleMark(
                    xStart: .value("Start", domain.lowerBound),
                    xEnd: .value("End", domain.upperBound),
                    yStart: .value("Low", 130),
                    yEnd: .value("High", 170)
                )
                .foregroundStyle(Theme.accent.opacity(0.12))
                ForEach(sessions) { session in
                    LineMark(x: .value("Date", session.date), y: .value("WPM", session.wordsPerMinute))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.accent)
                    PointMark(x: .value("Date", session.date), y: .value("WPM", session.wordsPerMinute))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(30)
                }
            }
            .chartXAxis { dateAxis() }
            .frame(height: 160)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Speaking pace")
            .accessibilityValue("Average \(averagePace, specifier: "%.0f") words per minute across \(sessions.count) sessions. Sweet spot is 130 to 170.")
        }
        .card()
    }
}

// MARK: - Skill breakdown

/// Horizontal grouped bars: this range's average per component vs. the range before it.
struct SkillBreakdownCard: View {
    let averages: [SkillAverage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Skill Breakdown")
                .font(.headline)
            Text("Average score per component, this range vs. the one before it")
                .font(.caption)
                .foregroundStyle(.secondary)

            if averages.isEmpty {
                emptyState
            } else {
                Chart {
                    ForEach(averages) { item in
                        if let current = item.current {
                            BarMark(
                                x: .value("Score", current),
                                y: .value("Component", item.component.displayName)
                            )
                            .position(by: .value("Period", "This range"))
                            .foregroundStyle(by: .value("Period", "This range"))
                        }
                        if let previous = item.previous {
                            BarMark(
                                x: .value("Score", previous),
                                y: .value("Component", item.component.displayName)
                            )
                            .position(by: .value("Period", "Previous range"))
                            .foregroundStyle(by: .value("Period", "Previous range"))
                        }
                    }
                }
                .chartForegroundStyleScale([
                    "This range": Theme.accent,
                    "Previous range": Color.secondary.opacity(0.35)
                ])
                .chartXScale(domain: 0...100)
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: CGFloat(averages.count) * 42 + 24)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Skill breakdown")
                .accessibilityValue(accessibilitySummary)
            }
        }
        .card()
    }

    private var emptyState: some View {
        Text("Finish a few more sessions to see your skill breakdown.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    private var accessibilitySummary: String {
        averages.compactMap { item -> String? in
            guard let current = item.current else { return nil }
            return "\(item.component.displayName) \(Int(current.rounded()))"
        }.joined(separator: ", ")
    }
}

// MARK: - Most common fillers

/// Horizontal bars of the top filler/crutch phrases used across the range.
struct TopFillersCard: View {
    let fillers: [TopFiller]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Most Common Fillers")
                .font(.headline)
            Text("Top phrases across this range")
                .font(.caption)
                .foregroundStyle(.secondary)

            if fillers.isEmpty {
                Text("No fillers logged in this range — nice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                Chart(fillers) { item in
                    BarMark(
                        x: .value("Count", item.count),
                        y: .value("Phrase", item.phrase)
                    )
                    .foregroundStyle(Theme.filler.gradient)
                    .cornerRadius(3)
                    .annotation(position: .trailing) {
                        Text("\(item.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: CGFloat(fillers.count) * 30 + 24)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Most common fillers")
                .accessibilityValue(fillers.map { "\($0.phrase) \($0.count) times" }.joined(separator: ", "))
            }
        }
        .card()
    }
}
