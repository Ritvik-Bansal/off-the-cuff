import SwiftData
import SwiftUI

/// Practice tab root: today's greeting and streak, a shuffleable prompt, the big
/// "Start speaking" CTA, a speech-model download banner, and recent activity.
struct PracticeHomeView: View {
    @Environment(WhisperModelManager.self) private var whisperManager
    @Query(sort: \PracticeSession.date, order: .reverse) private var sessions: [PracticeSession]

    @AppStorage(AppSettings.Keys.sessionLength) private var sessionLength = AppSettings.Defaults.sessionLength
    @AppStorage(AppSettings.Keys.prepTime) private var prepTime = AppSettings.Defaults.prepTime

    @State private var selectedCategory: PromptCategory?
    @State private var currentPrompt: SpeakingPrompt = PromptBank.random()
    @State private var showRecorder = false

    private var stats: ProgressStats { ProgressStats(sessions: sessions) }

    private var categoryPool: Set<PromptCategory> {
        selectedCategory.map { [$0] } ?? AppSettings.enabledCategories
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                whisperBanner
                promptCard
                startButton
                statsRow
                recentSessionsSection
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Off the Cuff")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showRecorder) {
            PracticeFlowView(prompt: currentPrompt)
        }
        .onChange(of: showRecorder) { _, isPresented in
            if !isPresented { shuffle() }
        }
        .onChange(of: selectedCategory) { _, _ in shuffle() }
        .animation(.spring(duration: 0.4), value: currentPrompt)
        .sensoryFeedback(.selection, trigger: currentPrompt)
    }

    // MARK: - Header

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Good night"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)
                Text(stats.practicedToday ? "Today's rep is done. Nice work." : "Ready for today's rep?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            streakPill
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var streakPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .foregroundStyle(stats.currentStreak > 0 ? Theme.accentSecondary : .secondary)
            Text(stats.currentStreak > 0 ? "\(stats.currentStreak)-day streak" : "Start a streak")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }

    // MARK: - Whisper model banner

    @ViewBuilder
    private var whisperBanner: some View {
        switch whisperManager.state {
        case .downloaded, .ready, .loading:
            EmptyView()
        case .notDownloaded, .failed, .downloading:
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Download the verbatim speech model (\(whisperManager.selectedModel.approximateSizeMB) MB) for accurate filler counts")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .downloading(let progress) = whisperManager.state {
                        ProgressView(value: progress)
                            .tint(Theme.accent)
                        Text("Downloading…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Download") {
                            Task { await whisperManager.download(whisperManager.selectedModel) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .controlSize(.small)
                    }
                }
                Spacer(minLength: 0)
            }
            .card()
        }
    }

    // MARK: - Prompt card

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                categoryChip
                Spacer()
                Button(action: shuffle) {
                    Image(systemName: "die.face.5.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(8)
                        .background(Theme.accent.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Shuffle prompt")
            }

            Text(currentPrompt.text)
                .font(.title2.weight(.semibold))
                .fontDesign(.rounded)
                .fixedSize(horizontal: false, vertical: true)
                .id(currentPrompt.id)
                .transition(.opacity.combined(with: .move(edge: .trailing)))

            categoryMenu
        }
        .card()
    }

    private var categoryChip: some View {
        Label(currentPrompt.category.displayName, systemImage: currentPrompt.category.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.accent.opacity(0.12), in: Capsule())
    }

    private var categoryMenu: some View {
        Menu {
            Button {
                selectedCategory = nil
            } label: {
                if selectedCategory == nil {
                    Label("Any category", systemImage: "checkmark")
                } else {
                    Text("Any category")
                }
            }
            Divider()
            ForEach(PromptCategory.allCases) { category in
                Button {
                    selectedCategory = category
                } label: {
                    if selectedCategory == category {
                        Label(category.displayName, systemImage: "checkmark")
                    } else {
                        Label(category.displayName, systemImage: category.systemImage)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedCategory?.displayName ?? "Any category")
                Image(systemName: "chevron.up.chevron.down")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Prompt category, currently \(selectedCategory?.displayName ?? "Any category")")
    }

    // MARK: - Start CTA

    private var startButton: some View {
        VStack(spacing: 8) {
            Button {
                showRecorder = true
            } label: {
                Label("Start speaking", systemImage: "mic.fill")
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Theme.brandGradient, in: Capsule())
            }
            .buttonStyle(.plain)

            Text(startCaption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var startCaption: String {
        let prep = prepTime > 0 ? " · \(prepTime)s to think" : ""
        return "\(Double(sessionLength).mmss)\(prep)"
    }

    // MARK: - Stats row

    @ViewBuilder
    private var statsRow: some View {
        if let recentAverage = stats.recentAverage {
            HStack(spacing: 12) {
                StatTile(
                    value: "\(Int(recentAverage.rounded()))",
                    label: "7-day avg",
                    systemImage: "chart.bar.fill",
                    tint: Theme.accent
                )
                StatTile(
                    value: fillersPerMinuteText,
                    label: "Fillers/min",
                    systemImage: "text.bubble.fill",
                    tint: Theme.filler
                )
                StatTile(
                    value: "\(stats.personalBest ?? 0)",
                    label: "Personal best",
                    systemImage: "trophy.fill",
                    tint: Theme.accentSecondary
                )
            }
        }
    }

    private var fillersPerMinuteText: String {
        guard let value = stats.averageFillersPerMinute else { return "—" }
        return String(format: "%.1f", value)
    }

    // MARK: - Recent sessions

    @ViewBuilder
    private var recentSessionsSection: some View {
        if sessions.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent sessions")
                    .font(.headline)
                    .padding(.bottom, 8)
                ForEach(Array(sessions.prefix(3).enumerated()), id: \.offset) { index, session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        RecentSessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                    if index != min(sessions.count, 3) - 1 {
                        Divider()
                    }
                }
            }
            .card()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
            Text("Your first rep starts here")
                .font(.headline)
            Text("Speak for about a minute and we'll show you exactly how it went.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .card()
    }

    // MARK: - Actions

    private func shuffle() {
        let excluded = PromptBank.recent.union([currentPrompt.text])
        currentPrompt = PromptBank.random(in: categoryPool, excluding: excluded)
    }
}

private struct RecentSessionRow: View {
    let session: PracticeSession

    var body: some View {
        HStack(spacing: 12) {
            statusIndicator
            VStack(alignment: .leading, spacing: 2) {
                Text(session.promptText)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(session.date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch session.status {
        case .complete:
            ScoreBadge(score: session.overallScore)
        case .processing:
            Image(systemName: "hourglass")
                .foregroundStyle(.secondary)
                .frame(minWidth: 40)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .frame(minWidth: 40)
        }
    }
}

#Preview {
    NavigationStack {
        PracticeHomeView()
    }
    .environment(WhisperModelManager.shared)
    .modelContainer(for: PracticeSession.self, inMemory: true)
}
