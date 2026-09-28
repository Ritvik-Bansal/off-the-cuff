import Foundation

enum ScoringEngine {
    /// Computes 0...100 component scores and the weighted overall score.
    static func score(metrics: SpeechMetrics, ai: AIFeedback?) -> ScoreBreakdown {
        guard metrics.wordCount > 0 else {
            return ScoreBreakdown(overall: 0, fillers: 0, fluency: 0, pace: 0, flow: 0, timeUse: 0, vocabulary: 0, content: ai != nil ? 0 : nil)
        }

        let fillers = fillerScore(fillersPerMinute: metrics.fillersPerMinute)
        let fluency = fluencyScore(disfluenciesPerMinute: metrics.disfluenciesPerMinute)
        let pace = paceScore(wordsPerMinute: metrics.wordsPerMinute)
        let longPauseDurations = metrics.pauses.filter { $0.duration >= 2.0 }.map(\.duration)
        let flow = flowScore(longPauseDurations: longPauseDurations, silenceRatio: metrics.silenceRatio)
        let timeUse = timeUseScore(timeUtilization: metrics.timeUtilization)
        let vocabulary = vocabularyScore(mattr: metrics.vocabularyDiversity)
        let content = ai?.contentScore

        var weightedSum = 0.0
        var totalWeight = 0.0
        for (component, value) in zip(
            [ScoreComponent.fillers, .fluency, .pace, .flow, .timeUse, .vocabulary],
            [fillers, fluency, pace, flow, timeUse, vocabulary]
        ) {
            weightedSum += component.weight * Double(value)
            totalWeight += component.weight
        }
        if let content {
            weightedSum += ScoreComponent.content.weight * Double(content)
            totalWeight += ScoreComponent.content.weight
        }

        var overall = totalWeight > 0 ? Int((weightedSum / totalWeight).rounded()) : 0
        overall = clampScore(Double(overall))
        if metrics.wordCount < 25 {
            overall = min(overall, 40)
        }

        return ScoreBreakdown(
            overall: overall,
            fillers: fillers,
            fluency: fluency,
            pace: pace,
            flow: flow,
            timeUse: timeUse,
            vocabulary: vocabulary,
            content: content
        )
    }

    // MARK: Component curves (exposed for tests and the scoring explainer UI)

    static func fillerScore(fillersPerMinute fpm: Double) -> Int {
        clampScore(100 * exp(-0.10 * max(0, fpm - 1)))
    }

    static func fluencyScore(disfluenciesPerMinute dpm: Double) -> Int {
        clampScore(100 * exp(-0.18 * max(0, dpm - 0.5)))
    }

    static func paceScore(wordsPerMinute wpm: Double) -> Int {
        if wpm >= 130, wpm <= 170 { return 100 }
        let distance = wpm < 130 ? (130 - wpm) : (wpm - 170)
        return clampScore(100 - 1.6 * distance)
    }

    static func flowScore(longPauseDurations: [Double], silenceRatio: Double) -> Int {
        let pausePenalty = longPauseDurations.reduce(0.0) { $0 + (8 + 4 * min($1 - 2, 3)) }
        let silencePenalty = max(0, silenceRatio - 0.20) * 150
        return clampScore(100 - pausePenalty - silencePenalty)
    }

    static func timeUseScore(timeUtilization u: Double) -> Int {
        if u >= 0.9 { return 100 }
        return clampScore(100 * max(0, (u - 0.3) / 0.6))
    }

    /// Piecewise-linear on MATTR: <=0.45 -> 20, 0.55 -> 50, 0.65 -> 80, >=0.72 -> 100.
    static func vocabularyScore(mattr: Double) -> Int {
        let points: [(x: Double, y: Double)] = [(0.45, 20), (0.55, 50), (0.65, 80), (0.72, 100)]
        if mattr <= points[0].x { return clampScore(points[0].y) }
        if mattr >= points[points.count - 1].x { return clampScore(points[points.count - 1].y) }
        for i in 0..<(points.count - 1) {
            let lower = points[i]
            let upper = points[i + 1]
            if mattr <= upper.x {
                let t = (mattr - lower.x) / (upper.x - lower.x)
                return clampScore(lower.y + t * (upper.y - lower.y))
            }
        }
        return clampScore(points[points.count - 1].y)
    }

    private static func clampScore(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return max(0, min(100, Int(value.rounded())))
    }
}
