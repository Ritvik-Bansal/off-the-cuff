import SwiftData
import SwiftUI

/// Progress tab root: range picker, streak/summary stats, plain-language insights, trend
/// charts and a 16-week practice calendar.
struct ProgressDashboardView: View {
    @Query(filter: #Predicate<PracticeSession> { $0.statusRaw == "complete" }, sort: \PracticeSession.date)
    private var sessions: [PracticeSession]

    @State private var selectedRange: ProgressRange = .month
    @State private var skillAverages: [SkillAverage] = []
    @State private var topFillers: [TopFiller] = []

    private var stats: ProgressStats { ProgressStats(sessions: sessions) }

    private var rangeSpanDays: Int {
        if let days = selectedRange.days { return days }
        guard let first = sessions.first?.date else { return 1 }
        return max(1, Calendar.current.dateComponents([.day], from: first, to: .now).day ?? 1)
    }

    private var currentRangeStart: Date {
        Calendar.current.date(byAdding: .day, value: -rangeSpanDays, to: .now) ?? .distantPast
    }

    private var previousRangeStart: Date {
        Calendar.current.date(byAdding: .day, value: -2 * rangeSpanDays, to: .now) ?? .distantPast
    }

    private var currentSessions: [PracticeSession] {
        sessions.filter { $0.date >= currentRangeStart }
    }

    private var previousSessions: [PracticeSession] {
        sessions.filter { $0.date >= previousRangeStart && $0.date < currentRangeStart }
    }

    private var currentAverage: Double? {
        average(of: currentSessions)
    }

    private var previousAverage: Double? {
        average(of: previousSessions)
    }

    private var averageDelta: Double? {
        guard let currentAverage, let previousAverage else { return nil }
        return currentAverage - previousAverage
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "Your trends start after your first session",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Finish a practice session to start building your history.")
                )
            } else {
                ScrollView {
                    VStack(spacing: Theme.spacing) {
                        rangePicker
                        summarySection
                        insightsSection
                        ScoreTrendCard(sessions: currentSessions)
                        FillerRateCard(sessions: currentSessions)
                        PaceCard(sessions: currentSessions)
                        SkillBreakdownCard(averages: skillAverages)
                        TopFillersCard(fillers: topFillers)
                        PracticeHeatmapCard(sessions: sessions)
                    }
                    .padding()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Progress")
        .task(id: AnalyticsKey(range: selectedRange, count: sessions.count)) {
            skillAverages = ProgressAnalytics.skillAverages(current: currentSessions, previous: previousSessions)
            topFillers = ProgressAnalytics.topFillers(in: currentSessions)
        }
    }

    private struct AnalyticsKey: Equatable {
        let range: ProgressRange
        let count: Int
    }

    private func average(of sessions: [PracticeSession]) -> Double? {
        guard !sessions.isEmpty else { return nil }
        return sessions.map { Double($0.overallScore) }.reduce(0, +) / Double(sessions.count)
    }

    private var rangePicker: some View {
        Picker("Range", selection: $selectedRange) {
            ForEach(ProgressRange.allCases) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Date range")
    }

    private var summarySection: some View {
        VStack(spacing: Theme.spacing) {
            StreakCard(stats: stats)
            HStack(spacing: Theme.spacing) {
                StatTile(
                    value: "\(currentSessions.count)",
                    label: "Sessions",
                    systemImage: "list.bullet.rectangle",
                    tint: Theme.accent
                )
                AverageScoreTile(average: currentAverage, delta: averageDelta)
                StatTile(
                    value: stats.personalBest.map { "\($0)" } ?? "—",
                    label: "Personal Best",
                    systemImage: "trophy.fill",
                    tint: .yellow
                )
            }
        }
    }

    @ViewBuilder
    private var insightsSection: some View {
        let insights = ProgressInsights.generate(from: sessions)
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Insights", systemImage: "lightbulb.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                ForEach(insights, id: \.self) { insight in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(insight)
                            .font(.subheadline)
                    }
                }
            }
            .card()
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Summary components

private struct StreakCard: View {
    let stats: ProgressStats

    var body: some View {
        HStack(spacing: Theme.spacing) {
            Image(systemName: "flame.fill")
                .font(.system(size: 34))
                .foregroundStyle(.orange.gradient)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(stats.currentStreak)")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text(stats.currentStreak == 1 ? "day streak" : "day streak")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("Best: \(stats.bestStreak) day\(stats.bestStreak == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current streak \(stats.currentStreak) days. Best streak \(stats.bestStreak) days.")
    }
}

private struct AverageScoreTile: View {
    let average: Double?
    let delta: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "chart.bar.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(average.map { String(format: "%.0f", $0) } ?? "—")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let delta, abs(delta) >= 1 {
                    Label(String(format: "%.0f", abs(delta)), systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(delta > 0 ? .green : .red)
                        .labelStyle(.titleAndIcon)
                }
            }
            Text("Avg Score")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .card(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("With Data") {
    NavigationStack {
        ProgressDashboardView()
    }
    .modelContainer(PreviewData.makeContainer())
}

#Preview("Empty") {
    NavigationStack {
        ProgressDashboardView()
    }
    .modelContainer(PreviewData.makeContainer(sessionCount: 0))
}
#endif
