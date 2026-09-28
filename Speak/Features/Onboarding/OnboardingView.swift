import AVFoundation
import Speech
import SwiftUI

struct OnboardingView: View {
    @AppStorage(AppSettings.Keys.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @State private var page = 0

    private let lastPage = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                howItWorksPage.tag(1)
                PermissionsPageView().tag(2)
                SpeechModelPageView(onFinish: finish).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .animation(.easeInOut, value: page)

            primaryButton
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var primaryButton: some View {
        Button {
            if page == lastPage {
                finish()
            } else {
                withAnimation { page += 1 }
            }
        } label: {
            Text(page == lastPage ? "Start Practicing" : "Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .controlSize(.large)
    }

    private func finish() {
        hasCompletedOnboarding = true
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.brandGradient)
                    .frame(width: 160, height: 160)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 24, y: 12)
                Image(systemName: "bubble.left.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .foregroundStyle(.white.opacity(0.22))
                Image(systemName: "waveform")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 54)
                    .foregroundStyle(.white)
            }
            VStack(spacing: 8) {
                Text("Off the Cuff")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("One random topic. One minute. Every day.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Page 2: How it works

    private var howItWorksPage: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("How It Works")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            VStack(spacing: 24) {
                stepRow(
                    icon: "dice.fill",
                    title: "Get a random topic",
                    detail: "A fresh prompt every day, pulled from categories you choose."
                )
                stepRow(
                    icon: "video.fill",
                    title: "Speak for a minute, on camera",
                    detail: "Talk to the front camera like you would in an interview."
                )
                stepRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Get scored, and watch it improve",
                    detail: "See fillers, pace, pauses and content feedback, then track your trend over time."
                )
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func stepRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(Theme.brandGradient).frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Page 3: Permissions

private struct PermissionsPageView: View {
    private enum PermissionState {
        case unknown, granted, denied
    }

    @State private var cameraState: PermissionState = .unknown
    @State private var microphoneState: PermissionState = .unknown
    @State private var speechState: PermissionState = .unknown
    @State private var isRequesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("A Few Permissions")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("Off the Cuff needs these to record and transcribe your practice.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 14) {
                permissionRow(
                    icon: "video.fill",
                    title: "Camera",
                    detail: "Records your practice so you can watch it back.",
                    state: cameraState
                )
                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    detail: "Captures your voice for transcription and scoring.",
                    state: microphoneState
                )
                permissionRow(
                    icon: "waveform",
                    title: "Speech Recognition",
                    detail: "A fallback transcriber if the on-device model isn't ready yet.",
                    state: speechState
                )
            }
            Button {
                Task { await requestAll() }
            } label: {
                Group {
                    if isRequesting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Allow Access")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .disabled(isRequesting)
            Text("You can continue either way — access can always be granted later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .task { await refreshCurrentStatuses() }
    }

    private func permissionRow(icon: String, title: String, detail: String, state: PermissionState) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            statusIcon(state)
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func statusIcon(_ state: PermissionState) -> some View {
        switch state {
        case .unknown:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        case .granted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private func refreshCurrentStatuses() async {
        cameraState = permissionState(for: AVCaptureDevice.authorizationStatus(for: .video))
        microphoneState = permissionState(for: AVCaptureDevice.authorizationStatus(for: .audio))
        speechState = speechPermissionState(for: SFSpeechRecognizer.authorizationStatus())
    }

    private func requestAll() async {
        isRequesting = true
        defer { isRequesting = false }
        async let cameraGranted = AVCaptureDevice.requestAccess(for: .video)
        async let microphoneGranted = AVCaptureDevice.requestAccess(for: .audio)
        async let speechStatus = requestSpeechAuthorization()
        let (camera, microphone, speech) = await (cameraGranted, microphoneGranted, speechStatus)
        cameraState = camera ? .granted : .denied
        microphoneState = microphone ? .granted : .denied
        speechState = speechPermissionState(for: speech)
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func permissionState(for status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .granted
        case .notDetermined: .unknown
        default: .denied
        }
    }

    private func speechPermissionState(for status: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .granted
        case .notDetermined: .unknown
        default: .denied
        }
    }
}

// MARK: - Page 4: Speech model

private struct SpeechModelPageView: View {
    @Environment(WhisperModelManager.self) private var whisperManager
    @AppStorage(AppSettings.Keys.reminderEnabled) private var reminderEnabled = AppSettings.Defaults.reminderEnabled
    @AppStorage(AppSettings.Keys.reminderHour) private var reminderHour = AppSettings.Defaults.reminderHour
    @AppStorage(AppSettings.Keys.reminderMinute) private var reminderMinute = AppSettings.Defaults.reminderMinute

    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("Your On-Device Speech Model")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("147 MB, downloaded once. It runs privately on your iPhone and catches every \"um,\" stutter and pause — nothing ever leaves your device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            modelStatusCard
            if !isReady {
                Button("Skip for Now") { onFinish() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Toggle(isOn: reminderBinding) {
                Label("Remind me daily at 7:00 PM", systemImage: "bell.fill")
            }
            .tint(Theme.accent)
            .card(padding: 14)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var isReady: Bool {
        if case .ready = whisperManager.state { return true }
        return false
    }

    @ViewBuilder
    private var modelStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch whisperManager.state {
            case .notDownloaded:
                downloadButton
            case .downloading(let progress):
                downloadingView(progress)
            case .downloaded, .loading:
                optimizingView
            case .ready:
                readyView
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                downloadButton
            }
        }
        .card()
    }

    private var downloadButton: some View {
        Button {
            Task {
                await whisperManager.download(whisperManager.selectedModel)
                await whisperManager.prepare()
            }
        } label: {
            Label("Download (147 MB)", systemImage: "arrow.down.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .controlSize(.large)
    }

    private func downloadingView(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Downloading…", systemImage: "arrow.down.circle")
                .font(.subheadline.weight(.semibold))
            ProgressView(value: progress).tint(Theme.accent)
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var optimizingView: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Optimizing for your iPhone…")
                .font(.subheadline.weight(.semibold))
        }
    }

    private var readyView: some View {
        Label("Ready — verbatim transcription is set up", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.green)
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { reminderEnabled },
            set: { newValue in
                if newValue {
                    Task {
                        let granted = await ReminderScheduler.requestAuthorization()
                        if granted {
                            reminderEnabled = true
                            await ReminderScheduler.schedule(hour: reminderHour, minute: reminderMinute)
                        } else {
                            reminderEnabled = false
                        }
                    }
                } else {
                    reminderEnabled = false
                    ReminderScheduler.cancel()
                }
            }
        )
    }
}

#Preview {
    OnboardingView()
        .environment(WhisperModelManager.shared)
}
