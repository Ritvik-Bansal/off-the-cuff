import SwiftData
import SwiftUI

/// History detail: recording playback + `SessionReportView`, with retry for failed sessions
/// and inline progress while analysis is running.
struct SessionDetailView: View {
    @Bindable var session: PracticeSession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var processor = SessionProcessor()
    @State private var isRetrying = false
    @State private var showDeleteSessionConfirm = false
    @State private var showDeleteRecordingConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                playbackCard
                statusContent
            }
            .padding(.top, Theme.spacing)
            .id(session.statusRaw)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                optionsMenu
            }
        }
        .confirmationDialog(
            "Delete this session?",
            isPresented: $showDeleteSessionConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Session", role: .destructive) { deleteSession() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the recording and all stats for this session. This can't be undone.")
        }
        .confirmationDialog(
            "Delete recording?",
            isPresented: $showDeleteRecordingConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Recording", role: .destructive) { deleteRecordingOnly() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The video will be removed, but your score and stats stay.")
        }
    }

    @ViewBuilder
    private var playbackCard: some View {
        if let url = session.videoURL {
            if session.hasVideoTrack {
                VideoPlayerCard(url: url)
            } else {
                AudioPlayerCard(url: url)
            }
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        if isRetrying {
            retryProgressCard
        } else {
            switch session.status {
            case .complete:
                SessionReportView(session: session)
            case .processing:
                processingCard
            case .failed:
                failedCard
            }
        }
    }

    private var processingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            Text("Analyzing your recording…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .card()
        .padding(.horizontal)
    }

    private var retryProgressCard: some View {
        VStack(spacing: 12) {
            ProgressView(value: processor.stage.progress)
                .tint(Theme.accent)
            Text(processor.stage.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .card()
        .padding(.horizontal)
    }

    private var failedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Analysis Failed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(session.errorMessage ?? "Something went wrong while analyzing this session.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if session.videoURL != nil {
                Button {
                    retry()
                } label: {
                    Label("Retry Analysis", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .card()
        .padding(.horizontal)
    }

    private var optionsMenu: some View {
        Menu {
            if let url = session.videoURL {
                ShareLink(item: url) {
                    Label("Share Recording", systemImage: "square.and.arrow.up")
                }
                Button {
                    showDeleteRecordingConfirm = true
                } label: {
                    Label("Delete Recording Only", systemImage: "video.slash")
                }
            }
            Button(role: .destructive) {
                showDeleteSessionConfirm = true
            } label: {
                Label("Delete Session", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Session options")
    }

    private func retry() {
        isRetrying = true
        Task {
            await processor.process(session, context: modelContext)
            isRetrying = false
        }
    }

    private func deleteRecordingOnly() {
        guard let fileName = session.videoFileName else { return }
        MediaStore.deleteRecording(named: fileName)
        session.videoFileName = nil
        try? modelContext.save()
    }

    private func deleteSession() {
        if let fileName = session.videoFileName {
            MediaStore.deleteRecording(named: fileName)
        }
        modelContext.delete(session)
        try? modelContext.save()
        dismiss()
    }
}

#if DEBUG
#Preview("Complete") {
    let container = PreviewData.makeContainer()
    let context = container.mainContext
    let descriptor = FetchDescriptor<PracticeSession>(
        predicate: #Predicate<PracticeSession> { $0.statusRaw == "complete" }
    )
    let session = (try? context.fetch(descriptor))?.first ?? PreviewData.makeSession(status: .complete, in: context)
    return NavigationStack {
        SessionDetailView(session: session)
    }
    .modelContainer(container)
}

#Preview("Failed") {
    let container = PreviewData.makeContainer(sessionCount: 1)
    let context = container.mainContext
    let session = PreviewData.makeSession(status: .failed, in: context)
    return NavigationStack {
        SessionDetailView(session: session)
    }
    .modelContainer(container)
}

#Preview("Processing") {
    let container = PreviewData.makeContainer(sessionCount: 1)
    let context = container.mainContext
    let session = PreviewData.makeSession(status: .processing, in: context)
    return NavigationStack {
        SessionDetailView(session: session)
    }
    .modelContainer(container)
}
#endif
