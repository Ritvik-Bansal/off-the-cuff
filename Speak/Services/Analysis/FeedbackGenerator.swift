import Foundation

/// Rule-based, specific feedback from the metrics (works without AI).
enum FeedbackGenerator {
    private static let shortClipWordThreshold = 25

    static func generate(metrics: SpeechMetrics, scores: ScoreBreakdown, words: [TranscriptWord]) -> [FeedbackItem] {
        guard metrics.wordCount >= shortClipWordThreshold else {
            return [
                FeedbackItem(
                    kind: .improvement,
                    title: "Too short to score reliably",
                    detail: "Only \(metrics.wordCount) word\(metrics.wordCount == 1 ? "" : "s") came through — the recording may have been too short or too quiet for the analyzer to give you a fair read. Make sure you're close to the mic and try to speak for the full time.",
                    component: nil
                ),
                FeedbackItem(
                    kind: .tip,
                    title: "Try again",
                    detail: "Re-record this prompt in a quiet room and aim to fill at least 30 seconds — that gives the scorer enough material to work with.",
                    component: nil
                )
            ]
        }

        let ranked: [(ScoreComponent, Int)] = [
            (.fillers, scores.fillers),
            (.fluency, scores.fluency),
            (.pace, scores.pace),
            (.flow, scores.flow),
            (.timeUse, scores.timeUse),
            (.vocabulary, scores.vocabulary)
        ] + (scores.content.map { [(ScoreComponent.content, $0)] } ?? [])

        let strengthCandidates = ranked.filter { $0.1 >= 80 }.sorted { $0.1 > $1.1 }
        let weakCandidates = ranked.filter { $0.1 < 75 }.sorted { $0.1 < $1.1 }

        var strengths = Array(strengthCandidates.prefix(2))
        var improvements = Array(weakCandidates.prefix(3))

        // Guarantee at least 3 items overall (strengths + improvements + 1 tip).
        if strengths.count + improvements.count < 2 {
            let used = Set((strengths + improvements).map(\.0))
            let remaining = ranked.filter { !used.contains($0.0) }.sorted { $0.1 < $1.1 }
            for candidate in remaining {
                if strengths.count + improvements.count >= 2 { break }
                if improvements.count < 3 {
                    improvements.append(candidate)
                } else if strengths.count < 2 {
                    strengths.append(candidate)
                }
            }
        }

        var items: [FeedbackItem] = []
        for (component, score) in strengths {
            items.append(strengthItem(component: component, score: score, metrics: metrics, words: words))
        }
        for (component, score) in improvements {
            items.append(improvementItem(component: component, score: score, metrics: metrics, words: words))
        }
        let weakest = (strengths + improvements).min { $0.1 < $1.1 } ?? ranked.first ?? (.fillers, scores.fillers)
        items.append(tipItem(for: weakest.0, metrics: metrics))

        return items
    }

    // MARK: Strengths

    private static func strengthItem(component: ScoreComponent, score: Int, metrics: SpeechMetrics, words: [TranscriptWord]) -> FeedbackItem {
        let detail: String
        switch component {
        case .fillers:
            let total = metrics.fillerCount + metrics.crutchCount
            detail = "Only \(total) filler word\(total == 1 ? "" : "s") in \(formatSeconds(metrics.speakingDuration)) — that reads as confident and prepared."
        case .fluency:
            detail = "No repeated words or false starts — your sentences ran clean from start to finish."
        case .pace:
            detail = "You spoke at \(Int(metrics.wordsPerMinute.rounded())) words per minute, right in the natural conversational zone."
        case .flow:
            detail = metrics.longPauseCount == 0
                ? "No long silences — you kept the energy moving the whole time."
                : "Your pauses stayed short and purposeful instead of turning into dead air."
        case .timeUse:
            detail = "You used \(formatSeconds(metrics.speechEnd)) of your \(formatSeconds(metrics.targetDuration)) — you had enough to say and paced it well."
        case .vocabulary:
            detail = "Nice varied word choice — you weren't leaning on the same handful of words."
        case .content:
            detail = "Your answer stayed on topic with a clear structure a listener could follow."
        }
        return FeedbackItem(kind: .strength, title: strengthTitle(for: component), detail: detail, component: component)
    }

    private static func strengthTitle(for component: ScoreComponent) -> String {
        switch component {
        case .fillers: "Clean of fillers"
        case .fluency: "Fluent delivery"
        case .pace: "Great pace"
        case .flow: "Steady flow"
        case .timeUse: "Used the time well"
        case .vocabulary: "Varied vocabulary"
        case .content: "On-topic and clear"
        }
    }

    // MARK: Improvements

    private static func improvementItem(component: ScoreComponent, score: Int, metrics: SpeechMetrics, words: [TranscriptWord]) -> FeedbackItem {
        let detail: String
        switch component {
        case .fillers:
            detail = fillerImprovementDetail(metrics: metrics, words: words)
        case .fluency:
            detail = fluencyImprovementDetail(metrics: metrics, words: words)
        case .pace:
            detail = paceImprovementDetail(metrics: metrics)
        case .flow:
            detail = flowImprovementDetail(metrics: metrics)
        case .timeUse:
            detail = timeUseImprovementDetail(metrics: metrics)
        case .vocabulary:
            detail = vocabularyImprovementDetail(words: words)
        case .content:
            detail = "Try answering the prompt more directly in your first sentence, then back it up with one concrete reason or example."
        }
        return FeedbackItem(kind: .improvement, title: improvementTitle(for: component), detail: detail, component: component)
    }

    private static func improvementTitle(for component: ScoreComponent) -> String {
        switch component {
        case .fillers: "Cut the fillers"
        case .fluency: "Smooth out restarts"
        case .pace: "Adjust your pace"
        case .flow: "Tighten your pauses"
        case .timeUse: "Use the full time"
        case .vocabulary: "Widen your vocabulary"
        case .content: "Sharpen your content"
        }
    }

    private static func fillerImprovementDetail(metrics: SpeechMetrics, words: [TranscriptWord]) -> String {
        let top = topFillers(metrics: metrics, limit: 2)
        let listText = top.map { "\"\($0.0)\" \($0.1)×" }.joined(separator: " and ")
        let fpm = String(format: "%.1f", metrics.fillersPerMinute)
        var detail = listText.isEmpty
            ? "You averaged \(fpm) fillers per minute."
            : "You said \(listText) — \(fpm) fillers per minute."

        let fillerStarts = words.filter { $0.tag == .filler || $0.tag == .crutch }.map(\.start)
        let earlyCount = fillerStarts.filter { $0 <= 15 }.count
        if !fillerStarts.isEmpty, Double(earlyCount) / Double(fillerStarts.count) > 0.5 {
            detail += " Most of them landed in your first 15 seconds — try silently planning your opening sentence during the prep countdown so you start clean."
        } else if metrics.crutchCount > metrics.fillerCount {
            detail += " Crutch words like these dominate more than the vocalized \"um\"/\"uh\" fillers — try stating the point directly instead of hedging."
        } else {
            detail += " Next time, take a silent breath instead of reaching for a filler when you need a beat to think."
        }
        return detail
    }

    private static func fluencyImprovementDetail(metrics: SpeechMetrics, words: [TranscriptWord]) -> String {
        let example = words.first(where: { $0.tag == .stutter || $0.tag == .repetition })?.text
        let dpm = String(format: "%.1f", metrics.disfluenciesPerMinute)
        var detail = "You had \(metrics.stutterCount) stutter\(metrics.stutterCount == 1 ? "" : "s") and \(metrics.repetitionCount) repeated phrase\(metrics.repetitionCount == 1 ? "" : "s") — \(dpm) per minute."
        if let example {
            detail += " For example: \"\(example)\"."
        }
        detail += " Commit to the first 3-4 words of a sentence before you start speaking so you don't need to restart it."
        return detail
    }

    private static func paceImprovementDetail(metrics: SpeechMetrics) -> String {
        let wpm = Int(metrics.wordsPerMinute.rounded())
        if metrics.wordsPerMinute < 130 {
            return "You spoke at \(wpm) WPM, a bit slower than the natural 130-170 range. Aim closer to 150 by trimming the gaps between thoughts rather than stretching individual words."
        } else {
            return "You spoke at \(wpm) WPM, faster than the natural 130-170 range. Aim closer to 150 by pausing briefly at commas so listeners can keep up."
        }
    }

    private static func flowImprovementDetail(metrics: SpeechMetrics) -> String {
        let longest = metrics.pauses.max { $0.duration < $1.duration }
        var detail: String
        if let longest {
            detail = "You had \(metrics.longPauseCount) long pause\(metrics.longPauseCount == 1 ? "" : "s"), the longest \(String(format: "%.1f", longest.duration))s around \(formatTimestamp(longest.start))."
        } else {
            detail = "Your speaking was frequently interrupted by silence (\(Int((metrics.silenceRatio * 100).rounded()))% of your speaking time)."
        }
        detail += " When you feel yourself blanking, reach for a bridge phrase like \"Another reason is...\" or \"Here's an example...\" instead of going silent."
        return detail
    }

    private static func timeUseImprovementDetail(metrics: SpeechMetrics) -> String {
        "You wrapped up at \(formatTimestamp(metrics.speechEnd)) of \(formatTimestamp(metrics.targetDuration)). Try structuring your answer as PREP — Point, Reason, Example, Point — to naturally fill the rest of the time."
    }

    private static func vocabularyImprovementDetail(words: [TranscriptWord]) -> String {
        let content = words.filter { $0.tag == .normal || $0.tag == .repetition }
        var counts: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        for (order, word) in content.enumerated() {
            let normalized = TextNormalizer.normalize(word.text)
            guard normalized.count > 2, !stopwords.contains(normalized) else { continue }
            counts[normalized, default: 0] += 1
            if firstSeen[normalized] == nil { firstSeen[normalized] = order }
        }
        let ranked = counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? (firstSeen[lhs.key] ?? 0) < (firstSeen[rhs.key] ?? 0) : lhs.value > rhs.value
        }
        if let top = ranked.first, top.value > 1 {
            return "You repeated \"\(top.key)\" \(top.value) times. Before your next attempt, jot down two or three alternate words for the ideas you expect to reach for most."
        }
        return "Your word choice repeated more than it varied. Before your next attempt, jot down two or three alternate words for the ideas you expect to reach for most."
    }

    // MARK: Tip

    private static func tipItem(for weakestComponent: ScoreComponent, metrics: SpeechMetrics) -> FeedbackItem {
        let detail: String
        switch weakestComponent {
        case .fillers:
            detail = "Pause-instead-of-um drill: next time you feel a filler coming, close your mouth and count one silent beat instead of making a sound."
        case .fluency:
            detail = "Before your next recording, say the first sentence out loud once so it's already committed to memory and you don't need to restart it."
        case .pace:
            detail = "Record the same prompt again and read it back at a deliberately even pace, checking your WPM afterward."
        case .flow:
            detail = "PREP drill: outline Point, Reason, Example, Point in your head during the countdown so you always know what comes next."
        case .timeUse:
            detail = "Practice with a visible timer and plan four PREP beats so you naturally use the whole minute."
        case .vocabulary:
            detail = "Word-bank drill: before recording, write down three alternate words for the nouns you expect to repeat."
        case .content:
            detail = "Answer the prompt directly in your very first sentence, then use the rest of the time to back it up."
        }
        return FeedbackItem(kind: .tip, title: "Drill for next time", detail: detail, component: weakestComponent)
    }

    // MARK: Helpers

    private static func topFillers(metrics: SpeechMetrics, limit: Int) -> [(String, Int)] {
        metrics.fillerBreakdown
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }

    private static func formatSeconds(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        return "\(rounded) second\(rounded == 1 ? "" : "s")"
    }

    private static func formatTimestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "so", "if", "of", "to", "in", "on", "at", "for",
        "with", "about", "as", "is", "was", "were", "be", "been", "being", "am", "are", "it",
        "its", "this", "that", "these", "those", "i", "you", "we", "they", "he", "she", "him",
        "her", "them", "my", "your", "our", "their", "his", "me", "us", "do", "does", "did",
        "have", "has", "had", "will", "would", "could", "should", "can", "just", "not", "no",
        "yes", "then", "than", "there", "here", "what", "when", "where", "who", "how", "why",
        "which", "all", "one", "up", "out", "over", "into", "get", "got", "going", "go", "way",
        "some", "any", "more", "most", "much", "very", "really", "also", "because", "from"
    ]
}
