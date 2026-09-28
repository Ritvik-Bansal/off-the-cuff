import SwiftUI

/// Shown while `SessionProcessor` works through a freshly recorded session:
/// an animated pulse, the current stage, a progress bar and a step checklist.
struct ProcessingView: View {
    let stage: SessionProcessor.Stage

    @Environment(WhisperModelManager.self) private var modelManager
    @State private var tipIndex = 0
    @State private var pulse = false

    private let tips = [
        "Speak in complete sentences — it reads as more confident.",
        "A short silent pause beats a filler word every time.",
        "Open with your strongest point, not a warm-up.",
        "Varying your pace keeps listeners engaged.",
        "Pausing to think isn't failure — rushing to fill silence is worse.",
        "Concrete details land better than vague generalities.",
    ]

    private let checklist: [(title: String, stage: SessionProcessor.Stage)] = [
        ("Reading recording", .extractingAudio),
        ("Transcribing", .transcribing),
        ("Analyzing delivery", .analyzing),
        ("Content review", .coaching),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            waveform

            VStack(spacing: 6) {
                Text(stage.title)
                    .font(.title3.weight(.semibold))
                    .fontDesign(.rounded)
                    .contentTransition(.opacity)
                    .multilineTextAlignment(.center)

                if modelManager.state == .loading {
                    Text("Optimizing the speech model for your iPhone — first time only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            ProgressView(value: stage.progress)
                .tint(Theme.accent)
                .animation(.easeInOut(duration: 0.4), value: stage.progress)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(checklist, id: \.title) { step in
                    checklistRow(step)
                }
            }
            .card()
            .padding(.horizontal, 20)

            Spacer(minLength: 12)

            Text(tips[tipIndex])
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .id(tipIndex)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: tipIndex)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .task {
            pulse = true
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                tipIndex = (tipIndex + 1) % tips.count
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stage.title)
    }

    private var waveform: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(Theme.brandGradient)
                    .frame(width: 7, height: pulse ? barHeight(index) : 14)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: pulse
                    )
            }
        }
        .frame(height: 46)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        [22, 38, 46, 30, 18][index % 5]
    }

    private func checklistRow(_ step: (title: String, stage: SessionProcessor.Stage)) -> some View {
        let done = isDone(step.stage)
        let active = isActive(step.stage)
        return HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : (active ? "circle.dotted" : "circle"))
                .foregroundStyle(done ? Theme.accent : .secondary)
                .imageScale(.medium)
            Text(step.title)
                .font(.subheadline)
                .foregroundStyle(done || active ? .primary : .secondary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title), \(done ? "done" : (active ? "in progress" : "pending"))")
    }

    private func order(of value: SessionProcessor.Stage) -> Int {
        switch value {
        case .idle: 0
        case .extractingAudio: 1
        case .transcribing: 2
        case .analyzing: 3
        case .coaching: 4
        case .finished, .failed: 5
        }
    }

    private func isDone(_ target: SessionProcessor.Stage) -> Bool {
        order(of: stage) > order(of: target)
    }

    private func isActive(_ target: SessionProcessor.Stage) -> Bool {
        order(of: stage) == order(of: target)
    }
}

#Preview {
    ProcessingView(stage: .analyzing)
        .environment(WhisperModelManager.shared)
}
