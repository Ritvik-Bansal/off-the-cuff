import XCTest
@testable import Speak

// MARK: - Test helpers

private func makeWords(_ texts: [String], gap: Double = 0.35, start: Double = 0.0) -> [TranscriptWord] {
    var t = start
    var out: [TranscriptWord] = []
    for (i, text) in texts.enumerated() {
        let s = t
        let e = t + 0.3
        out.append(TranscriptWord(id: i, text: text, start: s, end: e, confidence: nil))
        t = e + max(gap - 0.3, 0.05)
    }
    return out
}

/// Splits `text` on spaces into synthetic, evenly-timed words and runs the full analyzer.
private func analyze(_ text: String, gap: Double = 0.35, targetDuration: Double = 60) -> (words: [TranscriptWord], metrics: SpeechMetrics) {
    let words = makeWords(text.split(separator: " ").map(String.init), gap: gap)
    let duration = (words.last?.end ?? 0) + 1
    let output = TranscriptionOutput(text: text, words: words, engine: .whisper)
    return DeliveryAnalyzer.analyze(
        transcription: output,
        samples: [],
        sampleRate: 16000,
        recordingDuration: duration,
        targetDuration: targetDuration
    )
}

private func tags(_ text: String) -> [(text: String, tag: WordTag)] {
    analyze(text).words.map { ($0.text, $0.tag) }
}

final class AnalysisTests: XCTestCase {

    // MARK: Filler "like"

    func testLikeAsVerbIsNotFiller() {
        XCTAssertTrue(tags("I like pizza").allSatisfy { $0.tag != .filler })
    }

    func testLikeAsComparisonIsNotFiller() {
        XCTAssertTrue(tags("It looks like rain").allSatisfy { $0.tag != .filler })
    }

    func testLikeSurroundedByCommasIsFiller() {
        let result = tags("It's, like, really hard")
        XCTAssertEqual(result.first(where: { $0.text.contains("like") })?.tag, .filler)
    }

    func testLikeAfterThingsIsNotFiller() {
        XCTAssertTrue(tags("things like apples").allSatisfy { $0.tag != .filler })
    }

    func testLikeInKindOfLikeIsStillFiller() {
        let result = tags("it was kind of like a dream")
        XCTAssertEqual(result.first(where: { $0.text == "like" })?.tag, .filler)
    }

    // MARK: "you know"

    func testYouKnowWhatIMeanIsOneFiller() {
        let result = tags("you know what I mean")
        XCTAssertTrue(result.allSatisfy { $0.tag == .filler })
        let (_, metrics) = analyze("you know what I mean")
        XCTAssertEqual(metrics.fillerCount, 1)
        XCTAssertEqual(metrics.fillerBreakdown["you know what i mean"], 1)
    }

    func testDoYouKnowIsNotFiller() {
        XCTAssertTrue(tags("do you know the answer").allSatisfy { $0.tag != .filler })
    }

    func testAsYouKnowIsNotFiller() {
        XCTAssertTrue(tags("as you know I have been practicing").allSatisfy { $0.tag != .filler })
    }

    // MARK: "I mean"

    func testIMeanFollowedByCommaIsFiller() {
        let result = tags("I mean, it's fine")
        XCTAssertEqual(result[0].tag, .filler)
        XCTAssertEqual(result[1].tag, .filler)
    }

    func testWhatIMeanIsNotFiller() {
        XCTAssertTrue(tags("what I mean is").allSatisfy { $0.tag != .filler })
    }

    // MARK: Crutch words

    func testKindOfAsHedgeIsCrutch() {
        let result = tags("kind of hard")
        XCTAssertEqual(result[0].tag, .crutch)
        XCTAssertEqual(result[1].tag, .crutch)
    }

    func testWhatKindOfIsNotCrutch() {
        XCTAssertTrue(tags("what kind of car").allSatisfy { $0.tag != .crutch })
    }

    func testSoYeahIsCrutch() {
        let result = tags("so yeah that worked")
        XCTAssertEqual(result[1].tag, .crutch)
    }

    func testRightAsTagQuestionIsCrutch() {
        let result = tags("that was great right?")
        XCTAssertEqual(result.last?.tag, .crutch)
    }

    // MARK: Hard fillers

    func testHardFillerVariants() {
        let variants = ["um", "umm", "uh", "uhh", "uhm", "er", "erm", "ah", "ahh", "eh", "hmm", "hm", "mm", "mmm", "mhm"]
        for variant in variants {
            XCTAssertTrue(FillerDetector.isHardFiller(variant), "\(variant) should be a hard filler")
        }
    }

    func testUhHuhIsNotAFiller() {
        XCTAssertFalse(FillerDetector.isHardFiller("uh-huh"))
    }

    // MARK: Stutters

    func testPartialWordStutter() {
        let result = tags("th- the thing")
        XCTAssertEqual(result[0].tag, .stutter)
        XCTAssertNotEqual(result[1].tag, .stutter)
    }

    func testIntraTokenHyphenStutter() {
        let result = tags("I-I want")
        XCTAssertEqual(result[0].tag, .stutter)
    }

    func testImmediateWordRepeatStutter() {
        let result = tags("the the thing")
        XCTAssertEqual(result[0].tag, .stutter)
        XCTAssertNotEqual(result[1].tag, .stutter)
    }

    func testFillerBetweenRepeatDoesNotBreakStutter() {
        let result = tags("the, um, the thing")
        XCTAssertEqual(result[0].tag, .stutter)
        XCTAssertNotEqual(result[2].tag, .stutter)
    }

    func testLegitimateDoublesAreNotStutters() {
        XCTAssertTrue(tags("that that is fine").filter { $0.text.hasPrefix("that") }.allSatisfy { $0.tag != .stutter })
        XCTAssertTrue(tags("very very good").allSatisfy { $0.tag != .stutter })
    }

    // MARK: Repetition

    func testPhraseRepetitionTagsFirstOccurrence() {
        let result = tags("I think I think this is right")
        XCTAssertEqual(result[0].tag, .repetition)
        XCTAssertEqual(result[1].tag, .repetition)
        XCTAssertNotEqual(result[2].tag, .repetition)
    }

    func testItWasItWasRepetition() {
        let result = tags("it was it was raining")
        XCTAssertEqual(result[0].tag, .repetition)
        XCTAssertEqual(result[1].tag, .repetition)
    }

    // MARK: Pauses

    func testAcousticPauseDetection() {
        let sampleRate = 16000.0
        var samples: [Float] = []
        func appendTone(duration: Double, freq: Double, amp: Float) {
            let n = Int(duration * sampleRate)
            for i in 0..<n {
                samples.append(amp * Float(sin(2 * Double.pi * freq * Double(i) / sampleRate)))
            }
        }
        func appendNoise(duration: Double, amp: Float) {
            let n = Int(duration * sampleRate)
            for _ in 0..<n {
                samples.append(Float.random(in: -amp...amp))
            }
        }
        appendTone(duration: 1.0, freq: 200, amp: 0.5)
        appendNoise(duration: 2.5, amp: 0.001)
        appendTone(duration: 1.0, freq: 200, amp: 0.5)

        let words = [
            TranscriptWord(id: 0, text: "hello", start: 0.0, end: 1.0, confidence: nil),
            TranscriptWord(id: 1, text: "world", start: 3.5, end: 4.5, confidence: nil)
        ]
        let result = PauseDetector.detect(samples: samples, sampleRate: sampleRate, words: words, speechStart: 0.0, speechEnd: 4.5)
        XCTAssertTrue(result.usedAcoustic)
        guard let pause = result.pauses.first else {
            XCTFail("expected a detected pause")
            return
        }
        XCTAssertEqual(pause.duration, 2.5, accuracy: 0.2)
    }

    func testWordGapFallback() {
        let words = [
            TranscriptWord(id: 0, text: "hello", start: 0.0, end: 1.0, confidence: nil),
            TranscriptWord(id: 1, text: "world", start: 2.0, end: 2.5, confidence: nil)
        ]
        let result = PauseDetector.detect(samples: [], sampleRate: 16000, words: words, speechStart: 0.0, speechEnd: 2.5)
        XCTAssertFalse(result.usedAcoustic)
        XCTAssertEqual(result.pauses.count, 1)
        XCTAssertEqual(result.pauses.first?.duration ?? 0, 1.0, accuracy: 0.01)
    }

    // MARK: Scoring curves

    func testFillerScoreSpotChecks() {
        XCTAssertEqual(ScoringEngine.fillerScore(fillersPerMinute: 1), 100)
        XCTAssertEqual(ScoringEngine.fillerScore(fillersPerMinute: 6), 61)
    }

    func testPaceScoreSpotChecks() {
        XCTAssertEqual(ScoringEngine.paceScore(wordsPerMinute: 150), 100)
        XCTAssertEqual(ScoringEngine.paceScore(wordsPerMinute: 110), 68)
    }

    func testScoreMonotonicity() {
        XCTAssertGreaterThan(ScoringEngine.fillerScore(fillersPerMinute: 2), ScoringEngine.fillerScore(fillersPerMinute: 5))
        XCTAssertGreaterThan(ScoringEngine.fluencyScore(disfluenciesPerMinute: 1), ScoringEngine.fluencyScore(disfluenciesPerMinute: 3))
        XCTAssertLessThan(ScoringEngine.vocabularyScore(mattr: 0.4), ScoringEngine.vocabularyScore(mattr: 0.7))
        XCTAssertLessThan(ScoringEngine.timeUseScore(timeUtilization: 0.4), ScoringEngine.timeUseScore(timeUtilization: 0.95))
        XCTAssertGreaterThanOrEqual(ScoringEngine.paceScore(wordsPerMinute: 150), ScoringEngine.paceScore(wordsPerMinute: 90))
    }

    func testContentRenormalization() {
        let metrics = SpeechMetrics(
            recordingDuration: 60, targetDuration: 60, speechStart: 0, speechEnd: 55, speakingDuration: 55,
            wordCount: 140, wordsPerMinute: 150, fillerCount: 1, crutchCount: 0, fillerBreakdown: ["um": 1],
            fillersPerMinute: 1.1, stutterCount: 0, repetitionCount: 0, disfluenciesPerMinute: 0,
            pauses: [], longPauseCount: 0, longestPause: 0, silenceRatio: 0.05, vocabularyDiversity: 0.6,
            timeUtilization: 0.92
        )
        let withoutAI = ScoringEngine.score(metrics: metrics, ai: nil)
        XCTAssertNil(withoutAI.content)

        let ai = AIFeedback(relevance: 90, structure: 90, clarity: 90, summary: "Great", strengths: [], improvements: [], suggestedOpening: nil, modelName: "test")
        let withAI = ScoringEngine.score(metrics: metrics, ai: ai)
        XCTAssertEqual(withAI.content, 90)
        // Both scores should be high and in the same ballpark despite the different denominators.
        XCTAssertGreaterThan(withoutAI.overall, 70)
        XCTAssertGreaterThan(withAI.overall, 70)
    }

    func testEffortCapForShortAttempts() {
        var metrics = SpeechMetrics()
        metrics.wordCount = 20
        metrics.speakingDuration = 12
        metrics.wordsPerMinute = 150
        metrics.fillersPerMinute = 0
        metrics.disfluenciesPerMinute = 0
        metrics.timeUtilization = 1
        metrics.vocabularyDiversity = 0.7
        let scores = ScoringEngine.score(metrics: metrics, ai: nil)
        XCTAssertLessThanOrEqual(scores.overall, 40)
    }

    func testZeroWordsGivesZeroScore() {
        let (_, metrics) = analyze("um uh um uh um")
        XCTAssertEqual(metrics.wordCount, 0)
        let scores = ScoringEngine.score(metrics: metrics, ai: nil)
        XCTAssertEqual(scores.overall, 0)
        XCTAssertEqual(scores.fillers, 0)
    }

    // MARK: Feedback generator

    func testFeedbackGeneratorReturnsBetween3And6Items() {
        let text = "this is a normal length test recording um uh with a few fillers like you know some pauses and a decent amount of actual content words spoken at a reasonable pace for about a minute or so of talking to the camera about a random assigned topic that I have to think about on the spot without much preparation time given"
        let (words, metrics) = analyze(text)
        let scores = ScoringEngine.score(metrics: metrics, ai: nil)
        let feedback = FeedbackGenerator.generate(metrics: metrics, scores: scores, words: words)
        XCTAssertGreaterThanOrEqual(feedback.count, 3)
        XCTAssertLessThanOrEqual(feedback.count, 6)
        XCTAssertEqual(feedback.filter { $0.kind == .tip }.count, 1)

        // Should mention the top filler somewhere in the feedback text. Rank the same
        // way FeedbackGenerator does (count desc, then key asc) since Dictionary
        // iteration order is not guaranteed deterministic across runs.
        let ranked = metrics.fillerBreakdown.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        guard let topFiller = ranked.first?.key else {
            XCTFail("expected at least one filler in the fixture")
            return
        }
        XCTAssertTrue(feedback.contains { $0.detail.localizedCaseInsensitiveContains(topFiller) })
    }

    func testFeedbackGeneratorShortClip() {
        let (words, metrics) = analyze("this is way too short")
        let scores = ScoringEngine.score(metrics: metrics, ai: nil)
        let feedback = FeedbackGenerator.generate(metrics: metrics, scores: scores, words: words)
        XCTAssertEqual(feedback.count, 2)
        XCTAssertEqual(feedback.first?.kind, .improvement)
        XCTAssertEqual(feedback.last?.kind, .tip)
    }

    // MARK: Realistic fixture (app owner's own speaking style)

    func testRealisticFixtureCountsEssentiallyAndYouKnow() {
        let text = "I essentially want to create an application that I can have on my phone that essentially allows me to practice impromptu speaking over time and so how it would work is essentially I would have it hooked up you know it'd be on my phone I would speak and it would track my stutters my ums my uhs all my filler words and all that stuff and essentially would try it would give me a score and it would track that score over time it would give me trends it would you know obviously score each attempt it would give me feedback essentially it would work how it work is it would be like one minute of talking straight to the camera about a random topic random prompt essentially and I have one minute and then it gets sent"
        let (words, metrics) = analyze(text)

        let essentiallyCrutchCount = words.filter { $0.text.lowercased() == "essentially" && $0.tag == .crutch }.count
        XCTAssertGreaterThanOrEqual(essentiallyCrutchCount, 6)

        let youKnowFillerCount = metrics.fillerBreakdown["you know"] ?? 0
        XCTAssertGreaterThanOrEqual(youKnowFillerCount, 2)
    }

    // MARK: Normalization

    func testEmptyAndPunctuationOnlyTokensAreIgnored() {
        let words = [
            TranscriptWord(id: 0, text: "--", start: 0, end: 0.1, confidence: nil),
            TranscriptWord(id: 1, text: "Hello", start: 0.1, end: 0.5, confidence: nil),
            TranscriptWord(id: 2, text: "", start: 0.5, end: 0.5, confidence: nil),
            TranscriptWord(id: 3, text: "world.", start: 0.6, end: 1.0, confidence: nil)
        ]
        let output = TranscriptionOutput(text: "Hello world.", words: words, engine: .whisper)
        let (tagged, metrics) = DeliveryAnalyzer.analyze(transcription: output, samples: [], sampleRate: 16000, recordingDuration: 2, targetDuration: 60)
        XCTAssertEqual(metrics.wordCount, 2)
        XCTAssertEqual(tagged.count, 4)
        XCTAssertEqual(tagged[0].tag, .normal) // punctuation-only tokens are never tagged/counted
    }
}
