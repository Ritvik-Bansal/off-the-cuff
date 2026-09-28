import AVFoundation
import SwiftData
import SwiftUI

/// The full-screen practice flow presented from `PracticeHomeView`: record → process → report,
/// with a retry path on failure and a way to immediately start another round.
struct PracticeFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var prompt: SpeakingPrompt
    @State private var stage: FlowStage = .recording
    @State private var session: PracticeSession?
    @State private var processor = SessionProcessor()

    private enum FlowStage: Equatable {
        case recording
        case processing
        case report
        case failed(String)
    }

    init(prompt: SpeakingPrompt) {
        _prompt = State(initialValue: prompt)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .recording:
                    RecordingView(prompt: prompt, onFinish: handleFinish, onCancel: { dismiss() })
                        .id(prompt.id)
                case .processing:
                    ProcessingView(stage: processor.stage)
                case .report:
                    if let session {
                        reportView(session)
                    }
                case .failed(let message):
                    failedView(message)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(stage == .report ? .visible : .hidden, for: .navigationBar)
        }
    }

    // MARK: - Recording finished

    private func handleFinish(_ tempURL: URL) {
        stage = .processing
        Task {
            do {
                let fileName = try MediaStore.importRecording(from: tempURL)
                let newSession = PracticeSession(prompt: prompt, targetDuration: Double(AppSettings.sessionLength))
                newSession.videoFileName = fileName
                // The user may have fallen back to audio-only, so check the file rather than the setting.
                let videoTracks = try? await AVURLAsset(url: MediaStore.url(for: fileName)).loadTracks(withMediaType: .video)
                newSession.hasVideoTrack = !(videoTracks ?? []).isEmpty
                modelContext.insert(newSession)
                try? modelContext.save()
                PromptBank.markUsed(prompt)
                session = newSession

                await processor.process(newSession, context: modelContext)
                finishProcessing()
            } catch {
                stage = .failed(error.localizedDescription)
            }
        }
    }

    private func retry() {
        guard let session else { return }
        processor = SessionProcessor()
        stage = .processing
        Task {
            await processor.process(session, context: modelContext)
            finishProcessing()
        }
    }

    private func finishProcessing() {
        switch processor.stage {
        case .finished:
            stage = .report
        case .failed(let message):
            stage = .failed(message)
        default:
            stage = .report
        }
    }

    private func startNextRound() {
        let excluded = PromptBank.recent.union([prompt.text])
        prompt = PromptBank.random(in: AppSettings.enabledCategories, excluding: excluded)
        session = nil
        processor = SessionProcessor()
        stage = .recording
    }

    // MARK: - Report

    @ViewBuilder
    private func reportView(_ session: PracticeSession) -> some View {
        ScrollView {
            SessionReportView(session: session)
                .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: startNextRound) {
                Label("Next prompt", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .fontDesign(.rounded)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .background(.bar)
        }
    }

    // MARK: - Failed

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accentSecondary)
            Text("Analysis failed")
                .font(.title3.weight(.semibold))
                .fontDesign(.rounded)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.horizontal, 32)
            Button("Close") { dismiss() }
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
