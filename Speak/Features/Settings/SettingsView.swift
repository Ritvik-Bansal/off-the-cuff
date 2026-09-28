import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @AppStorage(AppSettings.Keys.sessionLength) private var sessionLength = AppSettings.Defaults.sessionLength
    @AppStorage(AppSettings.Keys.prepTime) private var prepTime = AppSettings.Defaults.prepTime
    @AppStorage(AppSettings.Keys.cameraEnabled) private var cameraEnabled = AppSettings.Defaults.cameraEnabled
    @AppStorage(AppSettings.Keys.keepRecordings) private var keepRecordings = AppSettings.Defaults.keepRecordings
    @AppStorage(AppSettings.Keys.enabledCategories) private var enabledCategoriesRaw = AppSettings.Defaults.enabledCategories
    @AppStorage(AppSettings.Keys.aiCoachEnabled) private var aiCoachEnabled = AppSettings.Defaults.aiCoachEnabled
    @AppStorage(AppSettings.Keys.reminderEnabled) private var reminderEnabled = AppSettings.Defaults.reminderEnabled
    @AppStorage(AppSettings.Keys.reminderHour) private var reminderHour = AppSettings.Defaults.reminderHour
    @AppStorage(AppSettings.Keys.reminderMinute) private var reminderMinute = AppSettings.Defaults.reminderMinute
    @AppStorage(AppSettings.Keys.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    @Environment(WhisperModelManager.self) private var whisperManager
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [PracticeSession]

    @State private var downloadingOptions: Set<WhisperModelOption> = []
    @State private var recordingsSize: Int64 = 0
    @State private var reminderPermissionDenied = false
    @State private var showDeleteRecordingsConfirm = false
    @State private var showDeleteAllDataConfirm = false

    var body: some View {
        Form {
            practiceSection
            promptsSection
            speechRecognitionSection
            aiCoachSection
            reminderSection
            dataSection
            aboutSection
        }
        .navigationTitle("Settings")
        .onAppear { refreshRecordingsSize() }
    }

    // MARK: - Practice

    private var practiceSection: some View {
        Section {
            Picker("Session Length", selection: $sessionLength) {
                Text("30 sec").tag(30)
                Text("1 min").tag(60)
                Text("1.5 min").tag(90)
                Text("2 min").tag(120)
            }
            Picker("Thinking Time", selection: $prepTime) {
                Text("None").tag(0)
                Text("5 sec").tag(5)
                Text("10 sec").tag(10)
                Text("15 sec").tag(15)
                Text("30 sec").tag(30)
            }
            Toggle("Record Video", isOn: $cameraEnabled)
            Toggle("Keep Recordings", isOn: $keepRecordings)
        } header: {
            Text("Practice")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(cameraEnabled
                     ? "Your practice is recorded on the front camera."
                     : "Audio only — no video will be recorded.")
                Text(keepRecordings
                     ? "Recordings stay on your iPhone until you delete them."
                     : "Recordings are removed right after scoring; transcripts and scores are kept.")
            }
        }
    }

    // MARK: - Prompts

    private var categoriesBinding: Binding<Set<PromptCategory>> {
        Binding(
            get: { AppSettings.decodeCategories(enabledCategoriesRaw) },
            set: { enabledCategoriesRaw = AppSettings.encodeCategories($0) }
        )
    }

    private var categoriesSummary: String {
        let count = AppSettings.decodeCategories(enabledCategoriesRaw).count
        return count == PromptCategory.allCases.count ? "All" : "\(count) of \(PromptCategory.allCases.count)"
    }

    private var promptsSection: some View {
        Section {
            NavigationLink {
                PromptCategoryPickerView(selection: categoriesBinding)
            } label: {
                HStack {
                    Text("Categories")
                    Spacer()
                    Text(categoriesSummary).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Prompts")
        }
    }

    // MARK: - Speech recognition

    private var speechRecognitionSection: some View {
        Section {
            ForEach(WhisperModelOption.allCases) { option in
                modelRow(option)
            }
            if !whisperManager.statusText.isEmpty {
                Text(whisperManager.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Speech Recognition")
        } footer: {
            Text("The verbatim model runs entirely on your iPhone and keeps every \"um\" and stutter. Without it, Apple Speech is used, which drops many filler words.")
        }
    }

    private func modelRow(_ option: WhisperModelOption) -> some View {
        let isSelected = whisperManager.selectedModel == option
        let downloaded = whisperManager.isDownloaded(option)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.displayName)
                    .font(.body.weight(.medium))
                Text(option.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(option.approximateSizeMB) MB")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            modelTrailing(option, isSelected: isSelected, downloaded: downloaded)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard downloaded, !isSelected, !whisperManager.isBusy else { return }
            whisperManager.select(option)
        }
        .swipeActions(edge: .trailing) {
            if downloaded, !isSelected {
                Button("Delete", role: .destructive) {
                    whisperManager.delete(option)
                }
                .disabled(whisperManager.isBusy)
            }
        }
        .contextMenu {
            if downloaded, !isSelected {
                Button(role: .destructive) {
                    whisperManager.delete(option)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(whisperManager.isBusy)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func modelTrailing(_ option: WhisperModelOption, isSelected: Bool, downloaded: Bool) -> some View {
        if isSelected {
            switch whisperManager.state {
            case .notDownloaded:
                downloadButton(option)
            case .downloading(let progress):
                downloadProgress(progress)
            case .downloaded, .ready:
                inUseLabel
            case .loading:
                ProgressView().controlSize(.small)
            case .failed:
                Button("Retry") { startDownload(option) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } else if downloadingOptions.contains(option) {
            ProgressView().controlSize(.small)
        } else if downloaded {
            Text("Downloaded")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            downloadButton(option)
        }
    }

    private var inUseLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
            Text("In Use").font(.caption.weight(.semibold))
        }
        .foregroundStyle(Theme.accent)
    }

    private func downloadButton(_ option: WhisperModelOption) -> some View {
        Button("Download") { startDownload(option) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Theme.accent)
            .disabled(whisperManager.isBusy)
    }

    private func downloadProgress(_ progress: Double) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            ProgressView(value: progress).frame(width: 64)
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func startDownload(_ option: WhisperModelOption) {
        downloadingOptions.insert(option)
        Task {
            await whisperManager.download(option)
            downloadingOptions.remove(option)
        }
    }

    // MARK: - AI coach

    private var aiCoachSection: some View {
        Section {
            Toggle("Content Feedback", isOn: $aiCoachEnabled)
            aiAvailabilityRow
        } header: {
            Text("AI Coach")
        } footer: {
            Text("Uses Apple Intelligence, entirely on your device, to comment on relevance, structure and clarity.")
        }
    }

    @ViewBuilder
    private var aiAvailabilityRow: some View {
        switch AICoach.availability {
        case .available(let modelName):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Available — \(modelName)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .unavailable(let reason):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
                Text(reason)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Reminder

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? .now
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminderHour = components.hour ?? reminderHour
                reminderMinute = components.minute ?? reminderMinute
                Task { await ReminderScheduler.schedule(hour: reminderHour, minute: reminderMinute) }
            }
        )
    }

    private var reminderSection: some View {
        Section {
            Toggle("Daily Reminder", isOn: $reminderEnabled)
                .onChange(of: reminderEnabled) { _, newValue in handleReminderToggle(newValue) }
            if reminderEnabled {
                DatePicker("Time", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
            }
            if reminderPermissionDenied {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications are off for Off the Cuff. Turn them on in Settings to get a daily reminder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") { openSystemSettings() }
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                }
            }
        } header: {
            Text("Daily Reminder")
        }
    }

    private func handleReminderToggle(_ enabled: Bool) {
        if enabled {
            Task {
                let granted = await ReminderScheduler.requestAuthorization()
                if granted {
                    reminderPermissionDenied = false
                    await ReminderScheduler.schedule(hour: reminderHour, minute: reminderMinute)
                } else {
                    reminderEnabled = false
                    reminderPermissionDenied = true
                }
            }
        } else {
            reminderPermissionDenied = false
            ReminderScheduler.cancel()
        }
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    // MARK: - Data

    private var formattedRecordingsSize: String {
        ByteCountFormatter.string(fromByteCount: recordingsSize, countStyle: .file)
    }

    private var completedSessions: [PracticeSession] {
        sessions.filter { $0.status == .complete }
    }

    private var dataSection: some View {
        Section {
            HStack {
                Text("Recordings")
                Spacer()
                Text(formattedRecordingsSize).foregroundStyle(.secondary)
            }
            Button("Delete All Recordings", role: .destructive) {
                showDeleteRecordingsConfirm = true
            }
            .disabled(recordingsSize == 0)
            ShareLink(item: csvExportURL) {
                Label("Export Sessions (CSV)", systemImage: "square.and.arrow.up")
            }
            .disabled(completedSessions.isEmpty)
            Button("Delete All Data", role: .destructive) {
                showDeleteAllDataConfirm = true
            }
            .disabled(sessions.isEmpty)
        } header: {
            Text("Data")
        }
        .confirmationDialog(
            "Delete all recordings?",
            isPresented: $showDeleteRecordingsConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete All Recordings", role: .destructive) { deleteAllRecordings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your saved video and audio files. Transcripts and scores are kept.")
        }
        .confirmationDialog(
            "Delete all data?",
            isPresented: $showDeleteAllDataConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) { deleteAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every session, transcript and recording. This can't be undone.")
        }
    }

    private func refreshRecordingsSize() {
        recordingsSize = MediaStore.recordingsSize()
    }

    private func deleteAllRecordings() {
        MediaStore.deleteAllRecordings()
        for session in sessions where session.videoFileName != nil {
            session.videoFileName = nil
        }
        try? modelContext.save()
        refreshRecordingsSize()
    }

    private func deleteAllData() {
        MediaStore.deleteAllRecordings()
        for session in sessions {
            modelContext.delete(session)
        }
        try? modelContext.save()
        refreshRecordingsSize()
    }

    private var csvExportURL: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OffTheCuffSessions.csv")
        let csv = makeCSV(from: completedSessions)
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeCSV(from sessions: [PracticeSession]) -> String {
        let header = ["date", "prompt", "category", "score", "fillers", "fillers_per_min", "wpm", "stutters_repeats", "long_pauses", "words"]
        var lines = [header.joined(separator: ",")]
        let formatter = ISO8601DateFormatter()
        for session in sessions.sorted(by: { $0.date < $1.date }) {
            let fields = [
                formatter.string(from: session.date),
                session.promptText,
                session.promptCategory.displayName,
                String(session.overallScore),
                String(session.fillerCount),
                String(format: "%.1f", session.fillersPerMinute),
                String(format: "%.1f", session.wordsPerMinute),
                String(session.stutterCount),
                String(session.longPauseCount),
                String(session.wordCount),
            ].map(csvField)
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    private func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    // MARK: - About

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var aboutSection: some View {
        Section {
            NavigationLink("How Scoring Works") {
                ScoringExplainerView()
            }
            Button("Replay Intro") {
                hasCompletedOnboarding = false
            }
        } header: {
            Text("About")
        } footer: {
            Text("Off the Cuff \(appVersion) (\(buildNumber))")
        }
    }
}
