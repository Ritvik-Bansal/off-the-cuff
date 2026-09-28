import SwiftData
import SwiftUI

/// The full scored report for a completed session: score ring, component breakdown,
/// key stats, filler breakdown, AI + rule feedback and highlighted transcript.
/// Used by the post-recording results screen and by History's session detail.
///
/// Renders a bare `VStack(spacing: 16)` with 16pt horizontal padding and no background —
/// callers are expected to place it inside their own `ScrollView` on a grouped background.
struct SessionReportView: View {
    let session: PracticeSession
    private let analysis: SessionAnalysis?

    @Query(sort: \PracticeSession.date, order: .reverse) private var allSessions: [PracticeSession]

    init(session: PracticeSession) {
        self.session = session
        self.analysis = session.analysis
    }

    var body: some View {
        VStack(spacing: 16) {
            content
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var content: some View {
        switch session.status {
        case .complete:
            if let analysis {
                HeroSection(session: session, analysis: analysis, comparisonText: comparisonText(for: analysis))
                KeyStatsSection(metrics: analysis.metrics)
                fillerChipsSection(analysis)
                ScoreBreakdownSection(scores: analysis.scores)
                coachSection(analysis)
                transcriptSection(analysis)
                footerSection(analysis)
            } else {
                statusMessage(
                    icon: "questionmark.circle",
                    title: "Analysis missing",
                    message: "This session is marked complete, but its analysis couldn't be read."
                )
            }
        case .processing:
            statusMessage(
                icon: "hourglass",
                title: "Still processing",
                message: "This session hasn't finished being analyzed yet."
            )
        case .failed:
            statusMessage(
                icon: "exclamationmark.triangle.fill",
                title: "Analysis failed",
                message: session.errorMessage ?? "Something went wrong analyzing this recording."
            )
        }
    }

    // MARK: - Comparison

    private func comparisonText(for analysis: SessionAnalysis) -> String {
        let others = allSessions.filter { $0.status == .complete && $0.id != session.id }
        guard !others.isEmpty else { return "First session — this is your baseline" }
        let average = others.map { Double($0.overallScore) }.reduce(0, +) / Double(others.count)
        let diff = Int((Double(analysis.scores.overall) - average).rounded())
        if diff > 0 { return "+\(diff) vs your average" }
        if diff < 0 { return "\(diff) vs your average" }
        return "Right at your average"
    }

    // MARK: - Filler breakdown

    @ViewBuilder
    private func fillerChipsSection(_ analysis: SessionAnalysis) -> some View {
        let breakdown = analysis.metrics.fillerBreakdown.sorted { $0.value > $1.value }
        if breakdown.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                Text("No filler words detected. Clean delivery!")
                    .font(.subheadline.weight(.medium))
            }
            .card()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Filler breakdown", systemImage: "text.bubble")
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(breakdown, id: \.key) { phrase, count in
                        fillerChip(phrase: phrase, count: count, analysis: analysis)
                    }
                }
            }
            .card()
        }
    }

    private func fillerChip(phrase: String, count: Int, analysis: SessionAnalysis) -> some View {
        let tag = tag(forPhrase: phrase, analysis: analysis)
        let color = Theme.color(for: tag) ?? Theme.filler
        return Text("\(phrase) ×\(count)")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.16), in: Capsule())
    }

    private func tag(forPhrase phrase: String, analysis: SessionAnalysis) -> WordTag {
        let normalizedPhrase = phrase.lowercased()
        for word in analysis.words where word.tag == .filler || word.tag == .crutch {
            let normalizedWord = word.text.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if normalizedWord == normalizedPhrase || normalizedWord.contains(normalizedPhrase) {
                return word.tag
            }
        }
        return .filler
    }

    // MARK: - Coach

    @ViewBuilder
    private func coachSection(_ analysis: SessionAnalysis) -> some View {
        if let ai = analysis.ai {
            aiCoachCard(ai)
        }
        ForEach(analysis.feedback) { item in
            feedbackCard(item)
        }
    }

    private func aiCoachCard(_ ai: AIFeedback) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Coach's take", systemImage: "person.crop.circle.badge.checkmark")
            Text(ai.summary)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            if !ai.strengths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ai.strengths, id: \.self) { strength in
                        bulletRow(strength, icon: "checkmark.circle.fill", tint: .green)
                    }
                }
            }

            if !ai.improvements.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ai.improvements, id: \.self) { improvement in
                        bulletRow(improvement, icon: "arrow.up.forward.circle.fill", tint: .orange)
                    }
                }
            }

            if let opening = ai.suggestedOpening, !opening.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Try opening with:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\u{201C}\(opening)\u{201D}")
                        .font(.subheadline.italic())
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            Text("Feedback by \(ai.modelName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func bulletRow(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func feedbackCard(_ item: FeedbackItem) -> some View {
        let (icon, color): (String, Color) = {
            switch item.kind {
            case .strength: ("checkmark.seal.fill", .green)
            case .improvement: ("arrow.up.forward.circle.fill", .orange)
            case .tip: ("lightbulb.fill", .yellow)
            }
        }()
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    // MARK: - Transcript

    private func transcriptSection(_ analysis: SessionAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Transcript", systemImage: "text.quote")
            TranscriptView(words: analysis.words, pauses: analysis.metrics.pauses)
        }
        .card()
    }

    // MARK: - Footer

    private func footerSection(_ analysis: SessionAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcribed with \(analysis.engine.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if analysis.engine == .appleSpeech {
                Text("Apple Speech can miss some filler words. Download the verbatim model in Settings for more accurate counts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NavigationLink("How scoring works") {
                ScoringExplainerView()
            }
            .font(.subheadline.weight(.medium))
        }
        .card()
    }

    // MARK: - Status message

    private func statusMessage(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .card()
    }
}

// MARK: - Shared small pieces

private struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

private struct HeroSection: View {
    let session: PracticeSession
    let analysis: SessionAnalysis
    let comparisonText: String

    private var tier: ScoreTier { ScoreTier(score: analysis.scores.overall) }

    var body: some View {
        VStack(spacing: 16) {
            ScoreRing(score: analysis.scores.overall, lineWidth: 16)
                .frame(width: 160, height: 160)

            VStack(spacing: 4) {
                Text(tier.label)
                    .font(.headline)
                    .foregroundStyle(tier.color)
                Text(comparisonText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text(session.promptText)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(session.date.formatted(date: .abbreviated, time: .shortened)) · \(session.recordedDuration.mmss) spoken")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}

private struct KeyStatsSection: View {
    let metrics: SpeechMetrics

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Key stats", systemImage: "gauge.with.dots.needle.50percent")
            LazyVGrid(columns: columns, spacing: 12) {
                StatTile(
                    value: "\(metrics.fillerCount)",
                    label: String(format: "%.1f/min", metrics.fillersPerMinute),
                    systemImage: "text.bubble.fill",
                    tint: Theme.filler
                )
                StatTile(
                    value: "\(Int(metrics.wordsPerMinute.rounded())) wpm",
                    label: "Pace",
                    systemImage: "speedometer",
                    tint: Theme.accent
                )
                StatTile(
                    value: "\(metrics.longPauseCount)",
                    label: "Long pauses · \(String(format: "%.1fs", metrics.longestPause)) max",
                    systemImage: "pause.circle.fill",
                    tint: Theme.pause
                )
                StatTile(
                    value: "\(metrics.stutterCount + metrics.repetitionCount)",
                    label: "Stutters & repeats",
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: Theme.stutter
                )
            }
        }
    }
}

private struct ScoreBreakdownSection: View {
    let scores: ScoreBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Score breakdown", systemImage: "chart.bar.doc.horizontal")
                .padding(.bottom, 8)
            ForEach(Array(ScoreComponent.allCases.enumerated()), id: \.offset) { index, component in
                ScoreComponentRow(component: component, value: scores.value(for: component))
                if index != ScoreComponent.allCases.count - 1 {
                    Divider()
                }
            }
        }
        .card()
    }
}

private struct ScoreComponentRow: View {
    let component: ScoreComponent
    let value: Int?

    @State private var isExpanded = false

    private var barColor: Color {
        guard let value else { return .secondary }
        return Theme.color(for: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: component.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(barColor)
                        .frame(width: 22)
                    Text(component.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(value.map { "\($0)" } ?? "—")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(value == nil ? .secondary : barColor)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let value {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(barColor.gradient)
                            .frame(width: max(4, proxy.size.width * CGFloat(value) / 100))
                    }
                }
                .frame(height: 8)
            } else {
                Text("Needs Apple Intelligence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isExpanded {
                Text(component.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(component.displayName), \(value.map { "\($0) out of 100" } ?? "needs Apple Intelligence")")
    }
}

#Preview {
    ScrollView {
        SessionReportView(session: .preview)
    }
    .background(Color(.systemGroupedBackground))
    .modelContainer(for: PracticeSession.self, inMemory: true)
}

private extension PracticeSession {
    static var preview: PracticeSession {
        let session = PracticeSession(
            prompt: SpeakingPrompt(text: "Describe your perfect Saturday.", category: .personal),
            targetDuration: 60
        )
        session.recordedDuration = 58
        let words: [TranscriptWord] = [
            TranscriptWord(id: 0, text: "So,", start: 0, end: 0.3, tag: .normal),
            TranscriptWord(id: 1, text: "um,", start: 0.3, end: 0.6, tag: .filler),
            TranscriptWord(id: 2, text: "my", start: 2.5, end: 2.6, tag: .normal),
            TranscriptWord(id: 3, text: "perfect", start: 2.6, end: 2.9, tag: .normal),
            TranscriptWord(id: 4, text: "Saturday", start: 2.9, end: 3.4, tag: .normal),
            TranscriptWord(id: 5, text: "basically", start: 3.4, end: 3.8, tag: .crutch),
            TranscriptWord(id: 6, text: "starts", start: 3.8, end: 4.1, tag: .normal),
        ]
        let metrics = SpeechMetrics(
            recordingDuration: 58, targetDuration: 60, speechStart: 0, speechEnd: 55,
            speakingDuration: 55, wordCount: 120, wordsPerMinute: 142,
            fillerCount: 4, crutchCount: 2, fillerBreakdown: ["um": 3, "like": 1, "basically": 2],
            fillersPerMinute: 5.5, stutterCount: 1, repetitionCount: 1, disfluenciesPerMinute: 2.2,
            pauses: [DetectedPause(start: 0.6, duration: 1.9)], longPauseCount: 1, longestPause: 2.4,
            silenceRatio: 0.08, vocabularyDiversity: 0.62, timeUtilization: 0.92
        )
        let scores = ScoreBreakdown(overall: 78, fillers: 70, fluency: 80, pace: 90, flow: 85, timeUse: 92, vocabulary: 75, content: 74)
        let ai = AIFeedback(
            relevance: 80, structure: 70, clarity: 72,
            summary: "You answered the prompt directly and painted a vivid picture.",
            strengths: ["Clear, concrete imagery", "Confident opening line"],
            improvements: ["Wrap up with a stronger closing thought"],
            suggestedOpening: "My perfect Saturday starts before the alarm even goes off.",
            modelName: "Apple Intelligence (on-device)"
        )
        let feedback = [
            FeedbackItem(kind: .strength, title: "Strong pace", detail: "142 words per minute is right in the conversational sweet spot.", component: .pace),
            FeedbackItem(kind: .tip, title: "Watch \"basically\"", detail: "You used it twice — try cutting it entirely.", component: .fillers),
        ]
        session.apply(SessionAnalysis(
            transcript: "So, um, my perfect Saturday basically starts…",
            words: words, metrics: metrics, scores: scores, feedback: feedback, ai: ai, engine: .whisper
        ))
        return session
    }
}
