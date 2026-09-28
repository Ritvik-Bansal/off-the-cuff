import SwiftUI
import UIKit

/// Full-screen camera (or audio-only) recording screen: setup → optional prep countdown →
/// recording with a live timer → finishing. Reports the finished temp file back via `onFinish`.
struct RecordingView: View {
    let prompt: SpeakingPrompt
    let onFinish: (URL) -> Void
    let onCancel: () -> Void

    @State private var recorder = CameraRecorder()

    @AppStorage(AppSettings.Keys.sessionLength) private var sessionLength = AppSettings.Defaults.sessionLength
    @AppStorage(AppSettings.Keys.prepTime) private var prepTime = AppSettings.Defaults.prepTime

    private enum Phase: Equatable {
        case preparingCamera
        case prep
        case recording
        case finishing
        case tooShort(String)
    }

    @State private var phase: Phase = .preparingCamera
    @State private var prepStart: Date?
    @State private var prepRemaining: Int = 0
    @State private var recordingStart: Date?
    @State private var elapsed: Double = 0
    @State private var didFireLateHaptic = false
    @State private var showDiscardConfirm = false
    @State private var recPulse = false
    @State private var idleTimerDisabled = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                topOverlay
                statusContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 8)
        }
        .statusBar(hidden: true)
        .persistentSystemOverlays(.hidden)
        .task { await configureFlow() }
        .task { await runClock() }
        .onDisappear { teardownFlow() }
        .confirmationDialog("Discard this attempt?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { discardAndCancel() }
            Button("Keep Recording", role: .cancel) {}
        }
        .sensoryFeedback(.warning, trigger: didFireLateHaptic)
    }

    // MARK: - Top overlay

    private var topOverlay: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                Button(action: closeTapped) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(12)
                }
                .floatingSurface(cornerRadius: 22)
                .accessibilityLabel("Close")

                Spacer()

                Label(prompt.category.displayName, systemImage: prompt.category.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .floatingSurface(cornerRadius: 20)
            }

            Text(prompt.text)
                .font(.title3.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .floatingSurface()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if recorder.videoEnabled {
            CameraPreviewView(session: recorder.session)
                .ignoresSafeArea()
        } else {
            AudioVisualizerBackground(level: recorder.audioLevel, isActive: phase == .recording)
                .ignoresSafeArea()
        }
    }

    // MARK: - Status-driven content

    @ViewBuilder
    private var statusContent: some View {
        switch recorder.status {
        case .unauthorized:
            unauthorizedOverlay
        case .failed(let message):
            failedOverlay(message)
        case .idle, .configuring, .ready, .recording:
            phaseContent
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .preparingCamera:
            setupOverlay
        case .prep:
            prepOverlay
        case .recording:
            recordingOverlay
        case .finishing:
            finishingOverlay
        case .tooShort(let message):
            tooShortOverlay(message)
        }
    }

    private var setupOverlay: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .tint(.white)
                .controlSize(.large)
            Text("Getting ready…")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
    }

    private var finishingOverlay: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .tint(.white)
                .controlSize(.large)
            Text("Saving your recording…")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
    }

    private var prepOverlay: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("\(prepRemaining)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(prepRemaining)))
                .foregroundStyle(.white)
            Text("Think about your answer")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button(action: beginRecording) {
                Text("Start now")
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.brandGradient, in: Capsule())
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
    }

    private var recordingOverlay: some View {
        VStack {
            Spacer()
            VStack(spacing: 20) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .opacity(recPulse ? 1 : 0.25)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: recPulse)
                    Text("REC")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(remainingSeconds.mmss)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .floatingSurface(cornerRadius: 16)

                Button(action: stopButtonTapped) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 6)
                            .frame(width: 84, height: 84)
                        Circle()
                            .trim(from: 0, to: progressFraction)
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 84, height: 84)
                            .animation(.linear(duration: 0.1), value: progressFraction)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 28, height: 28)
                    }
                }
                .accessibilityLabel("Stop recording")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear { recPulse = true }
    }

    private func tooShortOverlay(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.white)
            Text(message)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button(action: startPrepPhase) {
                Text("Keep going")
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.brandGradient, in: Capsule())
            }
            .padding(.horizontal, 40)
            Button("Close", action: onCancel)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, 24)
        }
    }

    private var unauthorizedOverlay: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "video.slash.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white)
            Text("Camera & microphone access needed")
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Off the Cuff needs camera and microphone access to record your practice.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.brandGradient, in: Capsule())
            }
            .padding(.horizontal, 40)
            Button("Close", action: onCancel)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, 24)
        }
    }

    private func failedOverlay(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white)
            Text("Couldn't start the camera")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            if recorder.videoEnabled {
                Button {
                    Task {
                        await recorder.configure(videoEnabled: false)
                        if recorder.status == .ready { startPrepPhase() }
                    }
                } label: {
                    Text("Record audio only")
                        .font(.headline)
                        .fontDesign(.rounded)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.brandGradient, in: Capsule())
                }
                .padding(.horizontal, 40)
            }
            Button("Close", action: onCancel)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, 24)
        }
    }

    // MARK: - Derived values

    private var remainingSeconds: Double {
        max(0, Double(sessionLength) - elapsed)
    }

    private var progressFraction: Double {
        guard sessionLength > 0 else { return 0 }
        return min(1, elapsed / Double(sessionLength))
    }

    private var ringColor: Color {
        remainingSeconds <= 10 ? .orange : .white
    }

    // MARK: - Lifecycle

    private func configureFlow() async {
        UIApplication.shared.isIdleTimerDisabled = true
        idleTimerDisabled = true
        AICoach.prewarm()
        await recorder.configure(videoEnabled: AppSettings.cameraEnabled)
        if recorder.status == .ready {
            startPrepPhase()
        }
    }

    private func teardownFlow() {
        recorder.teardown()
        if idleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = false
            idleTimerDisabled = false
        }
    }

    private func runClock() async {
        while !Task.isCancelled {
            tick()
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func tick() {
        switch phase {
        case .prep:
            guard let prepStart else { return }
            let remaining = prepTime - Int(Date().timeIntervalSince(prepStart).rounded(.down))
            if remaining <= 0 {
                beginRecording()
            } else if remaining != prepRemaining {
                prepRemaining = remaining
            }
        case .recording:
            guard let recordingStart else { return }
            elapsed = Date().timeIntervalSince(recordingStart)
            if remainingSeconds <= 10, !didFireLateHaptic {
                didFireLateHaptic = true
            }
            if elapsed >= Double(sessionLength) {
                Task { await finishRecording() }
            }
        default:
            break
        }
    }

    // MARK: - Actions

    private func closeTapped() {
        if phase == .recording {
            showDiscardConfirm = true
        } else {
            onCancel()
        }
    }

    private func discardAndCancel() {
        Task {
            if let url = await recorder.stopRecording() {
                try? FileManager.default.removeItem(at: url)
            }
            onCancel()
        }
    }

    private func startPrepPhase() {
        if prepTime <= 0 {
            beginRecording()
        } else {
            prepRemaining = prepTime
            prepStart = Date()
            phase = .prep
        }
    }

    private func beginRecording() {
        recorder.startRecording()
        recordingStart = Date()
        elapsed = 0
        didFireLateHaptic = false
        recPulse = false
        phase = .recording
    }

    private func stopButtonTapped() {
        Task { await finishRecording() }
    }

    private func finishRecording() async {
        guard phase == .recording, let recordingStart else { return }
        let finalElapsed = Date().timeIntervalSince(recordingStart)
        phase = .finishing
        let url = await recorder.stopRecording()
        guard let url else {
            phase = .tooShort("Something went wrong saving that recording. Let's try again.")
            return
        }
        if finalElapsed < 5 {
            try? FileManager.default.removeItem(at: url)
            phase = .tooShort("Too short — keep going next time.")
        } else {
            onFinish(url)
        }
    }
}

// MARK: - Audio-only background

/// Dark, brand-tinted background with pulsing rings driven by the live microphone level,
/// used when recording without the camera.
private struct AudioVisualizerBackground: View {
    let level: Float
    let isActive: Bool

    var body: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [Theme.accent.opacity(0.35), .black],
                center: .center,
                startRadius: 20,
                endRadius: 420
            )
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Theme.accent.opacity(0.45 - Double(index) * 0.12), lineWidth: 2)
                    .frame(width: 140 + CGFloat(index) * 70, height: 140 + CGFloat(index) * 70)
                    .scaleEffect(1 + CGFloat(level) * 0.35)
                    .animation(.easeOut(duration: 0.15), value: level)
            }
            Circle()
                .fill(Theme.brandGradient)
                .frame(width: 96, height: 96)
                .scaleEffect(1 + CGFloat(level) * 0.2)
                .opacity(isActive ? 1 : 0.6)
                .animation(.easeOut(duration: 0.15), value: level)
            Image(systemName: "mic.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white)
        }
    }
}
