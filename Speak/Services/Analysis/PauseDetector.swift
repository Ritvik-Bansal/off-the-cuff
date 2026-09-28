import Foundation
import Accelerate

/// Finds silent pauses either acoustically (RMS-based voice activity detection) or,
/// when the audio isn't usable, from gaps between transcribed word timestamps.
enum PauseDetector {
    struct Result {
        var pauses: [DetectedPause]
        var usedAcoustic: Bool
    }

    private static let frameDuration = 0.030
    private static let hopDuration = 0.010
    private static let minSilenceDuration = 0.6
    private static let bridgeGapDuration = 0.15

    static func detect(
        samples: [Float],
        sampleRate: Double,
        words: [TranscriptWord],
        speechStart: Double,
        speechEnd: Double
    ) -> Result {
        if let acoustic = detectAcoustic(samples: samples, sampleRate: sampleRate, speechStart: speechStart, speechEnd: speechEnd) {
            return Result(pauses: acoustic, usedAcoustic: true)
        }
        return Result(pauses: detectFromWordGaps(words: words), usedAcoustic: false)
    }

    // MARK: Acoustic

    private static func detectAcoustic(
        samples: [Float],
        sampleRate: Double,
        speechStart: Double,
        speechEnd: Double
    ) -> [DetectedPause]? {
        guard !samples.isEmpty, sampleRate > 0 else { return nil }
        let frameSamples = max(1, Int((frameDuration * sampleRate).rounded()))
        let hopSamples = max(1, Int((hopDuration * sampleRate).rounded()))
        guard samples.count >= frameSamples else { return nil }

        var frameDb: [Double] = []
        var frameStartTimes: [Double] = []
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var start = 0
            while start + frameSamples <= samples.count {
                var meanSquare: Float = 0
                vDSP_measqv(base + start, 1, &meanSquare, vDSP_Length(frameSamples))
                let rms = sqrt(Double(meanSquare))
                frameDb.append(20 * log10(max(rms, 1e-9)))
                frameStartTimes.append(Double(start) / sampleRate)
                start += hopSamples
            }
        }
        guard frameDb.count >= 3 else { return nil }

        let sortedDb = frameDb.sorted()
        let p10 = percentile(sortedDb, 0.10)
        let p90 = percentile(sortedDb, 0.90)
        guard (p90 - p10) >= 10 else { return nil } // not enough dynamic range to be reliable

        let threshold = p10 + max(6, 0.35 * (p90 - p10))
        var isSilent = frameDb.map { $0 < threshold }

        // Bridge brief non-silent blips (< 0.15s) sandwiched between silence, so a
        // stray noisy frame doesn't split one long pause into two short ones.
        bridgeShortNonSilentRuns(&isSilent, frameStartTimes: frameStartTimes)

        var pauses: [DetectedPause] = []
        var runStart: Int?
        for i in 0...isSilent.count {
            let silentHere = i < isSilent.count && isSilent[i]
            if silentHere, runStart == nil {
                runStart = i
            } else if !silentHere, let rs = runStart {
                let start = frameStartTimes[rs]
                let end = frameStartTimes[i - 1] + frameDuration
                let duration = end - start
                if duration >= minSilenceDuration, start >= speechStart, end <= speechEnd {
                    pauses.append(DetectedPause(start: start, duration: duration))
                }
                runStart = nil
            }
        }
        return pauses
    }

    private static func bridgeShortNonSilentRuns(_ isSilent: inout [Bool], frameStartTimes: [Double]) {
        var i = 0
        while i < isSilent.count {
            guard !isSilent[i] else { i += 1; continue }
            var j = i
            while j < isSilent.count, !isSilent[j] { j += 1 }
            let duration = (frameStartTimes[j - 1] + frameDuration) - frameStartTimes[i]
            let silenceBefore = i > 0 && isSilent[i - 1]
            let silenceAfter = j < isSilent.count && isSilent[j]
            if duration < bridgeGapDuration, silenceBefore, silenceAfter {
                for k in i..<j { isSilent[k] = true }
            }
            i = j
        }
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let idx = Int((p * Double(sorted.count - 1)).rounded())
        return sorted[max(0, min(sorted.count - 1, idx))]
    }

    // MARK: Word-gap fallback

    private static func detectFromWordGaps(words: [TranscriptWord]) -> [DetectedPause] {
        let realWords = words.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard realWords.count >= 2 else { return [] }
        var pauses: [DetectedPause] = []
        for i in 0..<(realWords.count - 1) {
            let gap = realWords[i + 1].start - realWords[i].end
            if gap >= minSilenceDuration {
                pauses.append(DetectedPause(start: realWords[i].end, duration: gap))
            }
        }
        return pauses
    }
}
