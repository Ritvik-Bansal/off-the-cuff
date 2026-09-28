import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Content feedback (relevance, structure, clarity) from Apple's Foundation Models when available.
///
/// Everything that actually touches `FoundationModels` lives in the `@available(iOS 26.0, *)`
/// extension below; the public surface here stays callable from any iOS 18+ call site.
enum AICoach {
    enum Availability: Equatable {
        case available(modelName: String)
        case unavailable(reason: String)
    }

    /// How long we'll wait for a content-feedback generation before giving up.
    fileprivate static let timeoutNanoseconds: UInt64 = 40_000_000_000

    static var availability: Availability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return systemAvailability
        }
        #endif
        return .unavailable(reason: "Requires iOS 26 or later.")
    }

    /// Loads the model ahead of time (call when a recording starts). Safe to call repeatedly.
    static func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            prewarmSession()
        }
        #endif
    }

    /// Returns nil if the model is unavailable or generation fails (including on a 40s timeout).
    static func feedback(prompt: String, transcript: String, metrics: SpeechMetrics) async -> AIFeedback? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await generateFeedback(prompt: prompt, transcript: transcript, metrics: metrics)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)

@available(iOS 26.0, *)
extension AICoach {
    fileprivate static let modelName = "Apple Intelligence (on-device)"

    fileprivate static var systemAvailability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available(modelName: modelName)
        case .unavailable(let reason):
            return .unavailable(reason: unavailableMessage(for: reason))
        }
    }

    private static func unavailableMessage(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence, so content feedback isn't available."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to get content feedback."
        case .modelNotReady:
            return "Apple Intelligence is still finishing setup on this device. Content feedback will appear once it's ready."
        @unknown default:
            return "Content feedback isn't available right now."
        }
    }

    /// A prewarmed session waiting to be used by the next request. Each request consumes it (or
    /// makes a fresh one): sessions accumulate history, so reusing one would leak earlier
    /// transcripts into later feedback and eventually overflow the context window.
    @MainActor private static var warmSession: LanguageModelSession?

    @MainActor
    private static func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: instructionsText)
    }

    @MainActor
    private static func takeSession() -> LanguageModelSession {
        defer { warmSession = nil }
        return warmSession ?? makeSession()
    }

    fileprivate static func prewarmSession() {
        Task { @MainActor in
            guard case .available = SystemLanguageModel.default.availability, warmSession == nil else { return }
            let session = makeSession()
            session.prewarm()
            warmSession = session
        }
    }

    fileprivate static func generateFeedback(prompt: String, transcript: String, metrics: SpeechMetrics) async -> AIFeedback? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = await takeSession()

        return await withTaskGroup(of: AIFeedback?.self) { group in
            group.addTask {
                await runGeneration(session: session, prompt: prompt, transcript: transcript, metrics: metrics)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private static func runGeneration(
        session: LanguageModelSession,
        prompt: String,
        transcript: String,
        metrics: SpeechMetrics
    ) async -> AIFeedback? {
        do {
            let response = try await session.respond(
                to: buildPrompt(prompt: prompt, transcript: transcript, metrics: metrics),
                generating: ContentFeedback.self,
                options: GenerationOptions(temperature: 0.3)
            )
            return makeFeedback(from: response.content)
        } catch {
            return nil
        }
    }

    private static func buildPrompt(prompt: String, transcript: String, metrics: SpeechMetrics) -> String {
        let spoken = formattedDuration(metrics.speechEnd)
        let target = Int(metrics.targetDuration.rounded())
        return """
        Prompt given to the speaker: "\(prompt)"
        They had about \(target) seconds to answer, with no time to prepare beforehand.
        They spoke for \(spoken) and used \(metrics.wordCount) words (fillers excluded from that count).

        Verbatim speech-to-text transcript of what they said (it may contain filler words like \
        "um" and minor recognition errors — ignore those entirely and judge only the substance):
        \"\"\"
        \(transcript)
        \"\"\"

        Evaluate the content of this answer: its relevance to the prompt, its structure, and its clarity.
        """
    }

    private static func formattedDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func makeFeedback(from content: ContentFeedback) -> AIFeedback {
        func clamp(_ value: Int) -> Int { min(100, max(0, value)) }
        func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

        let strengths = content.strengths.map(trimmed).filter { !$0.isEmpty }
        let improvements = content.improvements.map(trimmed).filter { !$0.isEmpty }
        let opening = trimmed(content.suggestedOpening)

        return AIFeedback(
            relevance: clamp(content.relevance),
            structure: clamp(content.structure),
            clarity: clamp(content.clarity),
            summary: trimmed(content.summary),
            strengths: strengths,
            improvements: improvements,
            suggestedOpening: opening.isEmpty ? nil : opening,
            modelName: modelName
        )
    }

    private static let instructionsText = """
    You are a supportive but candid speaking coach helping someone practice impromptu speaking, \
    with the goal of getting better at job interviews and at speaking off the cuff in general. \
    For each attempt the speaker is given a random prompt and, with no preparation time, speaks \
    for about a target duration to answer it.

    Evaluate ONLY the content of what they said: how relevant and directly responsive it is to the \
    prompt, whether it has a clear structure (a clear main point, supporting reasons or examples, \
    and some kind of conclusion), and how clear and concrete the ideas are. Do not comment on filler \
    words, speaking pace, pauses, or stutters — those are measured separately and are not your concern.

    The transcript you're given is verbatim speech-to-text and may contain filler words and minor \
    recognition errors; ignore these entirely and judge only the substance of what was said. Reference \
    specific things the speaker actually said. Address the speaker directly as "you". Keep every point \
    to a single sentence. Calibrate your scores realistically: 70 represents a decent, coherent everyday \
    answer, and 90 or above should be reserved for an answer polished enough to impress an interviewer.
    """

    @Generable
    fileprivate struct ContentFeedback {
        @Guide(description: "How directly and fully the answer addresses the prompt, 0-100.", .range(0...100))
        var relevance: Int

        @Guide(
            description: "How clear the structure is — a main point, supporting reasons or examples, and a conclusion — 0-100.",
            .range(0...100)
        )
        var structure: Int

        @Guide(description: "How clear, concrete and easy to follow the language is, 0-100.", .range(0...100))
        var clarity: Int

        @Guide(description: "A one to two sentence overall assessment of the content of this answer, addressed to the speaker as \"you\".")
        var summary: String

        @Guide(description: "Exactly two specific things the speaker did well in this answer, each a single sentence.", .count(2))
        var strengths: [String]

        @Guide(
            description: "Exactly three specific, actionable things the speaker could improve in this answer, each a single sentence.",
            .count(3)
        )
        var improvements: [String]

        @Guide(description: "A stronger, more direct opening sentence the speaker could have used instead, in their own voice.")
        var suggestedOpening: String
    }
}

#endif
