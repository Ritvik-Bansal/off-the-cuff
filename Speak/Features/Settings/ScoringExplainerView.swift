import SwiftUI

/// Explains how each score component is computed (uses ScoreComponent.explanation / weight).
struct ScoringExplainerView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                overallCard
                weightsCard
                fillersCard
                fluencyCard
                pausesCard
                tiersCard
                tipsCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("How Scoring Works")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Overall

    private var overallCard: some View {
        ExplainerCard(title: "Your Overall Score", systemImage: "gauge.with.dots.needle.67percent") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your overall score, from 0 to 100, is a weighted average of seven components measured from your recording and transcript.")
                    .font(.subheadline)
                Text("Content is worth 15%, but it only counts when Apple Intelligence is available on your device to judge it. Otherwise the remaining six weights are scaled up proportionally so they still add to 100%.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Weights

    private var weightsCard: some View {
        ExplainerCard(title: "How It's Weighted", systemImage: "chart.bar.doc.horizontal") {
            VStack(alignment: .leading, spacing: 16) {
                weightBar
                componentRows
            }
        }
    }

    private var weightBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(ScoreComponent.allCases) { component in
                    color(for: component)
                        .frame(width: max(0, proxy.size.width * component.weight - 2))
                }
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
    }

    private var componentRows: some View {
        VStack(spacing: 12) {
            ForEach(ScoreComponent.allCases) { component in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: component.systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(color(for: component))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(component.displayName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(component.weight, format: .percent.precision(.fractionLength(0)))
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(color(for: component).opacity(0.15), in: Capsule())
                                .foregroundStyle(color(for: component))
                        }
                        Text(component.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func color(for component: ScoreComponent) -> Color {
        switch component {
        case .fillers: Theme.filler
        case .fluency: .purple
        case .pace: .blue
        case .flow: .teal
        case .timeUse: .indigo
        case .vocabulary: .pink
        case .content: Theme.accent
        }
    }

    // MARK: - Fillers & crutch words

    private var fillersCard: some View {
        ExplainerCard(title: "Fillers & Crutch Words", systemImage: "text.bubble") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Full-weight fillers: \"um,\" \"uh,\" \"er,\" \"ah,\" \"hmm,\" filler \"like,\" \"you know,\" and \"I mean.\"")
                    .font(.subheadline)
                Text("Crutch words count at half weight: \"basically,\" \"actually,\" \"literally,\" \"honestly,\" \"totally,\" \"essentially,\" \"obviously,\" \"seriously,\" hedges like \"kind of\" / \"sort of,\" and the tag \"right?\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Fluency

    private var fluencyCard: some View {
        ExplainerCard(title: "Stutters & Repeats", systemImage: "waveform.path") {
            Text("Partial words and false starts (\"th- the\"), immediate repeats (\"I I\"), and repeated phrases (\"I think I think\") all count as disfluencies. Fewer per minute means a higher Fluency score.")
                .font(.subheadline)
        }
    }

    // MARK: - Pauses

    private var pausesCard: some View {
        ExplainerCard(title: "Pauses", systemImage: "pause.circle") {
            Text("Short, deliberate pauses are good — they replace fillers and give you a beat to think. Silences longer than 2 seconds, and a high overall share of silent time, count against your Pauses score.")
                .font(.subheadline)
        }
    }

    // MARK: - Tiers

    private var tiersCard: some View {
        ExplainerCard(title: "Score Tiers", systemImage: "square.stack.3d.up") {
            VStack(spacing: 10) {
                tierRow(.needsWork, range: "0–49")
                tierRow(.developing, range: "50–69")
                tierRow(.solid, range: "70–84")
                tierRow(.excellent, range: "85–100")
            }
        }
    }

    private func tierRow(_ tier: ScoreTier, range: String) -> some View {
        HStack {
            Circle().fill(tier.color).frame(width: 12, height: 12)
            Text(tier.label).font(.subheadline.weight(.medium))
            Spacer()
            Text(range)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tips

    private var tipsCard: some View {
        ExplainerCard(title: "Tips to Raise Your Score", systemImage: "arrow.up.right.circle") {
            VStack(alignment: .leading, spacing: 14) {
                tipRow(icon: "pause.circle", text: "Swap \"um\" for a silent pause. A half-second of quiet scores better than a filler.")
                tipRow(icon: "list.bullet.rectangle", text: "Use PREP: state your Point, give a Reason, an Example, then restate the Point.")
                tipRow(icon: "lightbulb", text: "Use your think time to plan just the opening sentence — the rest tends to follow.")
                tipRow(icon: "timer", text: "Aim to speak for the whole session. Stopping early usually costs Time Used points.")
            }
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
            Text(text).font(.subheadline)
        }
    }
}

/// A titled card used to lay out one explanatory section.
private struct ExplainerCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Theme.accent)
            content
        }
        .card()
    }
}

#Preview {
    NavigationStack {
        ScoringExplainerView()
    }
}
