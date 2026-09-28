#if DEBUG
import Foundation
import SwiftData

/// Seeds an in-memory `ModelContainer` with realistic fake sessions for `#Preview`s in both
/// Progress and History (this agent's two owned directories).
enum PreviewData {
    /// Deterministic generator so every demo launch shows the same data.
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    private static var rng = SplitMix64(state: 42)

    private static let prompts: [SpeakingPrompt] = [
        SpeakingPrompt(text: "Tell me about a time you failed and what you learned.", category: .interview),
        SpeakingPrompt(text: "Should college be free?", category: .opinion),
        SpeakingPrompt(text: "Describe your perfect Saturday.", category: .personal),
        SpeakingPrompt(text: "If you could master any skill overnight, what would it be?", category: .hypothetical),
        SpeakingPrompt(text: "Explain how the internet works to a ten-year-old.", category: .explain),
        SpeakingPrompt(text: "Tell a story about the best trip you've ever taken.", category: .storytelling),
        SpeakingPrompt(text: "Pitch a product you wish existed.", category: .business),
        SpeakingPrompt(text: "What does it mean to live a good life?", category: .abstract),
        SpeakingPrompt(text: "Convince us pineapple belongs on pizza.", category: .fun)
    ]

    private static let fillerPhrases = ["um", "uh", "like", "you know", "basically", "actually", "kind of", "i mean"]

    /// An in-memory container with ~`sessionCount` fake sessions spread over 6 weeks, improving
    /// over time. The two most recent entries are left `.processing` and `.failed` so History's
    /// stub states have something to render.
    @MainActor
    static func makeContainer(sessionCount: Int = 30, includeEdgeStates: Bool = true) -> ModelContainer {
        let schema = Schema([PracticeSession.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            fatalError("Failed to create in-memory preview container.")
        }
        let context = container.mainContext
        for session in makeSessions(count: sessionCount, includeEdgeStates: includeEdgeStates) {
            context.insert(session)
        }
        try? context.save()
        return container
    }

    @MainActor
    static func makeSessions(count: Int, includeEdgeStates: Bool = true, now: Date = .now) -> [PracticeSession] {
        let calendar = Calendar.current
        guard count > 0 else { return [] }
        rng = SplitMix64(state: 42)

        var daysAgo: [Int] = []
        var day = Int(Double(count) * 1.3)
        while day >= 0 && daysAgo.count < count {
            daysAgo.append(day)
            day -= Int.random(in: 1...2, using: &rng)
        }
        while daysAgo.count < count {
            daysAgo.append(0)
        }
        daysAgo = Array(daysAgo.prefix(count)).sorted(by: >)

        var sessions: [PracticeSession] = []
        for (index, offset) in daysAgo.enumerated() {
            let progress = Double(index) / Double(max(count - 1, 1))
            let prompt = prompts[index % prompts.count]
            let hour = [8, 12, 17, 19, 21].randomElement(using: &rng) ?? 19
            let dayStart = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)) ?? now
            let scheduled = calendar.date(byAdding: .hour, value: hour, to: dayStart) ?? dayStart
            // Never in the future: today's sessions land in the past few hours.
            let date = min(scheduled, now.addingTimeInterval(-Double(count - index) * 1_800))

            let session = PracticeSession(prompt: prompt, targetDuration: 60, date: date)

            if includeEdgeStates, index == count - 1 {
                session.status = .processing
                sessions.append(session)
                continue
            }
            if includeEdgeStates, index == count - 2 {
                session.status = .failed
                session.errorMessage = "The recording file is missing, so this session can't be analyzed."
                sessions.append(session)
                continue
            }

            let recordedDuration = Double.random(in: 50...62, using: &rng)
            let analysis = makeAnalysis(progress: progress, recordedDuration: recordedDuration, prompt: prompt)
            session.apply(analysis)
            session.recordedDuration = recordedDuration
            if Bool.random(using: &rng) {
                session.videoFileName = "\(UUID().uuidString).mov"
            }
            sessions.append(session)
        }
        return sessions
    }

    /// Builds a single freestanding session for a specific status, inserted into `context` so
    /// SwiftUI Previews that mutate it (retry, delete) have somewhere real to write.
    @MainActor
    static func makeSession(status: SessionStatus, in context: ModelContext) -> PracticeSession {
        let prompt = prompts[1]
        let session = PracticeSession(prompt: prompt, targetDuration: 60, date: .now.addingTimeInterval(-3600))
        switch status {
        case .complete:
            session.apply(makeAnalysis(progress: 0.75, recordedDuration: 58, prompt: prompt))
        case .processing:
            session.status = .processing
        case .failed:
            session.status = .failed
            session.errorMessage = "The recording file is missing, so this session can't be analyzed."
        }
        context.insert(session)
        return session
    }

    private static func makeAnalysis(progress: Double, recordedDuration: Double, prompt: SpeakingPrompt) -> SessionAnalysis {
        let baseScore = 48 + progress * 40
        let noise = Double.random(in: -6...6, using: &rng)
        let overall = Int(min(98, max(30, baseScore + noise)).rounded())

        let fillersPerMinute = max(0.2, 6.5 - progress * 5.0 + Double.random(in: -0.8...0.8, using: &rng))
        let wpm = 110 + progress * 45 + Double.random(in: -10...10, using: &rng)
        let wordCount = max(20, Int((wpm / 60) * recordedDuration))
        let fillerCount = max(0, Int((fillersPerMinute / 60) * recordedDuration))
        let stutterCount = Int.random(in: 0...3, using: &rng)
        let longPauseCount = Int.random(in: 0...2, using: &rng)

        var breakdown: [String: Int] = [:]
        var remaining = fillerCount
        var phraseIndex = wordCount % fillerPhrases.count
        while remaining > 0 {
            let phrase = fillerPhrases[phraseIndex % fillerPhrases.count]
            let take = min(remaining, Int.random(in: 1...3, using: &rng))
            breakdown[phrase, default: 0] += take
            remaining -= take
            phraseIndex += 1
        }

        var metrics = SpeechMetrics()
        metrics.recordingDuration = recordedDuration
        metrics.targetDuration = 60
        metrics.speechStart = 1.2
        metrics.speechEnd = recordedDuration - 1
        metrics.speakingDuration = recordedDuration - 2.2
        metrics.wordCount = wordCount
        metrics.wordsPerMinute = wpm
        metrics.fillerCount = fillerCount
        metrics.crutchCount = Int.random(in: 0...2, using: &rng)
        metrics.fillerBreakdown = breakdown
        metrics.fillersPerMinute = fillersPerMinute
        metrics.stutterCount = stutterCount
        metrics.repetitionCount = Int.random(in: 0...1, using: &rng)
        metrics.disfluenciesPerMinute = Double(stutterCount) / (recordedDuration / 60)
        metrics.longPauseCount = longPauseCount
        metrics.longestPause = longPauseCount > 0 ? Double.random(in: 2.1...3.6, using: &rng) : Double.random(in: 0.6...1.8, using: &rng)
        metrics.silenceRatio = Double.random(in: 0.05...0.2, using: &rng)
        metrics.vocabularyDiversity = min(0.95, 0.5 + progress * 0.3 + Double.random(in: -0.05...0.05, using: &rng))
        metrics.timeUtilization = min(1, recordedDuration / 60)

        let scores = ScoreBreakdown(
            overall: overall,
            fillers: clampScore(90 - fillersPerMinute * 8),
            fluency: clampScore(85 - Double(stutterCount) * 6),
            pace: clampScore(100 - abs(wpm - 150) * 0.8),
            flow: clampScore(90 - Double(longPauseCount) * 10),
            timeUse: clampScore(70 + progress * 25),
            vocabulary: clampScore(60 + progress * 30),
            content: Bool.random(using: &rng) ? clampScore(60 + progress * 30) : nil
        )

        let transcript = "So, thinking about \(prompt.text.lowercased()) — honestly I think, um, it's important because uh, you know, it affects a lot of people."

        return SessionAnalysis(
            transcript: transcript,
            words: [],
            metrics: metrics,
            scores: scores,
            feedback: [],
            ai: nil,
            engine: .appleSpeech
        )
    }

    private static func clampScore(_ value: Double) -> Int {
        Int(min(100, max(0, value)).rounded())
    }
}
#endif
