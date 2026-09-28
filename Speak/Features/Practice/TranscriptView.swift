import SwiftUI

/// Renders a full transcript as one flowing, selectable block of text with
/// filler/crutch/stutter words tinted and long pauses shown as inline markers.
struct TranscriptView: View {
    let words: [TranscriptWord]
    let pauses: [DetectedPause]

    /// Minimum pause duration (seconds) that gets an inline marker.
    private let markerThreshold: Double = 1.5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if words.isEmpty {
                Text("No transcript available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(attributedTranscript)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                legend
            }
        }
    }

    private var attributedTranscript: AttributedString {
        var result = AttributedString()
        let sortedPauses = pauses.filter { $0.duration >= markerThreshold }.sorted { $0.start < $1.start }
        var pauseIndex = 0

        for (index, word) in words.enumerated() {
            var wordString = AttributedString(word.text)
            if let color = Theme.color(for: word.tag) {
                wordString.backgroundColor = color.opacity(0.28)
            }
            result += wordString

            let nextWordStart = index < words.count - 1 ? words[index + 1].start : Double.greatestFiniteMagnitude
            while pauseIndex < sortedPauses.count, sortedPauses[pauseIndex].start < nextWordStart {
                let pause = sortedPauses[pauseIndex]
                var marker = AttributedString(" ⏸ \(String(format: "%.1f", pause.duration))s ")
                marker.foregroundColor = Theme.pause
                marker.font = .caption.italic()
                result += marker
                pauseIndex += 1
            }

            if index < words.count - 1 {
                result += AttributedString(" ")
            }
        }
        return result
    }

    private var legend: some View {
        FlowLayout(spacing: 14, lineSpacing: 6) {
            legendItem(color: Theme.filler, label: "Filler")
            legendItem(color: Theme.crutch, label: "Crutch")
            legendItem(color: Theme.stutter, label: "Stutter / repeat")
            pauseLegendItem
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color.opacity(0.28))
                .frame(width: 12, height: 12)
            Text(label)
        }
    }

    private var pauseLegendItem: some View {
        HStack(spacing: 4) {
            Text("⏸")
                .foregroundStyle(Theme.pause)
            Text("Pause ≥ 1.5s")
        }
    }
}

#Preview {
    ScrollView {
        TranscriptView(
            words: [
                TranscriptWord(id: 0, text: "So,", start: 0, end: 0.3, tag: .normal),
                TranscriptWord(id: 1, text: "um,", start: 0.3, end: 0.6, tag: .filler),
                TranscriptWord(id: 2, text: "I", start: 2.5, end: 2.6, tag: .normal),
                TranscriptWord(id: 3, text: "think", start: 2.6, end: 2.9, tag: .normal),
                TranscriptWord(id: 4, text: "think", start: 2.9, end: 3.1, tag: .repetition),
                TranscriptWord(id: 5, text: "basically", start: 3.1, end: 3.5, tag: .crutch),
                TranscriptWord(id: 6, text: "it's", start: 3.5, end: 3.7, tag: .normal),
                TranscriptWord(id: 7, text: "th-", start: 3.7, end: 3.8, tag: .stutter),
                TranscriptWord(id: 8, text: "the", start: 3.8, end: 3.9, tag: .normal),
                TranscriptWord(id: 9, text: "answer.", start: 3.9, end: 4.2, tag: .normal),
            ],
            pauses: [DetectedPause(start: 0.6, duration: 1.9)]
        )
        .padding()
    }
}
