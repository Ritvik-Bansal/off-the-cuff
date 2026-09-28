import SwiftData
import SwiftUI

/// History tab root: every session (any status), grouped by month, searchable by prompt,
/// filterable by category, swipe-to-delete.
struct HistoryListView: View {
    @Query(sort: \PracticeSession.date, order: .reverse) private var sessions: [PracticeSession]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var selectedCategory: PromptCategory?

    private var filteredSessions: [PracticeSession] {
        sessions.filter { session in
            (selectedCategory == nil || session.promptCategory == selectedCategory)
                && (searchText.isEmpty || session.promptText.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var sections: [MonthSection] {
        var result: [MonthSection] = []
        var currentKey: String?
        var currentTitle = ""
        var currentSessions: [PracticeSession] = []

        for session in filteredSessions {
            let key = Self.monthKeyFormatter.string(from: session.date)
            if key != currentKey {
                if let currentKey {
                    result.append(MonthSection(id: currentKey, title: currentTitle, sessions: currentSessions))
                }
                currentKey = key
                currentTitle = Self.monthTitleFormatter.string(from: session.date)
                currentSessions = [session]
            } else {
                currentSessions.append(session)
            }
        }
        if let currentKey {
            result.append(MonthSection(id: currentKey, title: currentTitle, sessions: currentSessions))
        }
        return result
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No practice sessions yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Finish your first recording to see it here.")
                )
            } else if filteredSessions.isEmpty {
                if !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView(
                        "No sessions found",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Try a different category filter.")
                    )
                }
            } else {
                List {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.sessions) { session in
                                NavigationLink(value: session) {
                                    HistoryRow(session: session)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(session)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("History")
        .searchable(text: $searchText, prompt: "Search prompts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                categoryMenu
            }
        }
        .navigationDestination(for: PracticeSession.self) { session in
            SessionDetailView(session: session)
        }
    }

    private var categoryMenu: some View {
        Menu {
            Button {
                selectedCategory = nil
            } label: {
                if selectedCategory == nil {
                    Label("All Categories", systemImage: "checkmark")
                } else {
                    Label("All Categories", systemImage: "square.grid.2x2")
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
            Image(systemName: selectedCategory == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel(selectedCategory == nil ? "Filter by category" : "Filtered by \(selectedCategory!.displayName)")
    }

    private func delete(_ session: PracticeSession) {
        if let fileName = session.videoFileName {
            MediaStore.deleteRecording(named: fileName)
        }
        modelContext.delete(session)
        try? modelContext.save()
    }

    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let monthKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
}

private struct MonthSection: Identifiable {
    let id: String
    let title: String
    let sessions: [PracticeSession]
}

private struct HistoryRow: View {
    let session: PracticeSession

    var body: some View {
        HStack(spacing: 12) {
            statusBadge
            VStack(alignment: .leading, spacing: 4) {
                Text(session.promptText)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: session.promptCategory.systemImage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if session.videoFileName != nil {
                        Image(systemName: "video.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let dateString = session.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        switch session.status {
        case .complete:
            return "\(dateString) · \(session.recordedDuration.mmss) · \(session.fillerCount) \(session.fillerCount == 1 ? "filler" : "fillers")"
        case .processing:
            return "\(dateString) · Analyzing…"
        case .failed:
            return "\(dateString) · Analysis failed"
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.status {
        case .complete:
            ScoreBadge(score: session.overallScore)
        case .processing:
            ProgressView()
                .frame(width: 40, height: 28)
                .accessibilityLabel("Analyzing")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 40, height: 28)
                .accessibilityLabel("Analysis failed")
        }
    }
}

#if DEBUG
#Preview("With Data") {
    NavigationStack {
        HistoryListView()
    }
    .modelContainer(PreviewData.makeContainer())
}

#Preview("Empty") {
    NavigationStack {
        HistoryListView()
    }
    .modelContainer(PreviewData.makeContainer(sessionCount: 0))
}
#endif
