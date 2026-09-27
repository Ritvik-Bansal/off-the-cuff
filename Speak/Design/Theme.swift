import SwiftUI

/// Shared visual language. Warm "ember" accent on system backgrounds, rounded numerals,
/// 20pt continuous-corner cards.
enum Theme {
    static let accent = Color.accentColor
    /// Secondary brand color used for gradients alongside the accent.
    static let accentSecondary = Color(red: 1.0, green: 0.30, blue: 0.45)
    static let brandGradient = LinearGradient(
        colors: [Color.accentColor, accentSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Transcript highlight colors
    static let filler = Color.orange
    static let crutch = Color.yellow
    static let stutter = Color.purple
    static let pause = Color.secondary

    static let cornerRadius: CGFloat = 20
    static let spacing: CGFloat = 16

    static func color(for score: Int) -> Color {
        ScoreTier(score: score).color
    }

    static func color(for tag: WordTag) -> Color? {
        switch tag {
        case .normal: nil
        case .filler: filler
        case .crutch: crutch
        case .stutter, .repetition: stutter
        }
    }
}

extension ScoreTier {
    var color: Color {
        switch self {
        case .needsWork: Color(red: 0.90, green: 0.28, blue: 0.30)
        case .developing: Color(red: 0.96, green: 0.62, blue: 0.04)
        case .solid: Color(red: 0.19, green: 0.70, blue: 0.40)
        case .excellent: Color(red: 0.39, green: 0.40, blue: 0.95)
        }
    }
}

// MARK: - Card

struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.spacing

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}

extension View {
    /// Standard content card on a grouped background.
    func card(padding: CGFloat = Theme.spacing) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Translucent floating surface for controls over the camera / imagery.
    /// Uses Liquid Glass on iOS 26+, material otherwise.
    @ViewBuilder
    func floatingSurface(cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

// MARK: - Score ring

/// Circular score gauge, 0...100, colored by tier. Animates from empty on appear.
struct ScoreRing: View {
    let score: Int
    var lineWidth: CGFloat = 14
    var showsLabel: Bool = true
    var animated: Bool = true

    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Theme.color(for: score).gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if showsLabel {
                GeometryReader { proxy in
                    Text("\(score)")
                        .font(.system(size: proxy.size.width * 0.34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(score)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if animated {
                withAnimation(.spring(duration: 1.2, bounce: 0.15).delay(0.1)) {
                    progress = Double(score) / 100
                }
            } else {
                progress = Double(score) / 100
            }
        }
        .onChange(of: score) { _, newValue in
            withAnimation(.spring(duration: 0.6)) { progress = Double(newValue) / 100 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(score) out of 100")
    }
}

/// Small colored capsule with a score, for list rows.
struct ScoreBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)")
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: 40)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Theme.color(for: score).gradient, in: Capsule())
    }
}

/// Compact stat tile: big rounded number with a caption.
struct StatTile: View {
    let value: String
    let label: String
    var systemImage: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .card(padding: 12)
    }
}

extension Double {
    /// "1:05" style formatting for durations in seconds.
    var mmss: String {
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
