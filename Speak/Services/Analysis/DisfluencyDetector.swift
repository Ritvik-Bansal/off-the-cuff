import Foundation

/// Tags stutters (partial words, intra-token hyphen repeats, immediate word repeats)
/// and short repeated phrases. Runs after `FillerDetector` so that filler-tagged
/// words in between two repeated words don't break the repeat ("the, um, the").
enum DisfluencyDetector {
    struct Result {
        var tags: [WordTag]
        var stutterCount: Int = 0
        var repetitionCount: Int = 0
    }

    /// Legitimate immediate doubles that are not stutters.
    private static let legitDoubleExclusion: Set<String> = [
        "that", "had", "very", "really", "so", "no", "yeah", "ha", "bye", "go", "now",
        "well", "okay", "many", "far", "more", "again", "round"
    ]

    static func detect(tokens: [AnalysisToken], fillerTags: [WordTag]) -> Result {
        var tags = fillerTags
        var stutterCount = 0
        var repetitionCount = 0

        func nextContentIndex(after i: Int) -> Int? {
            var j = i + 1
            while j < tokens.count {
                if !tokens[j].isEmpty && tags[j] == .normal { return j }
                j += 1
            }
            return nil
        }

        // (a) Partial word followed by its completion: "th-" "the", "I-" "I".
        for token in tokens where tags[token.index] == .normal {
            guard token.normalizedKeepHyphen.hasSuffix("-") else { continue }
            let core = String(token.normalizedKeepHyphen.dropLast())
            guard !core.isEmpty else { continue }
            guard let nextIdx = nextContentIndex(after: token.index) else { continue }
            let nextWord = tokens[nextIdx].normalized
            if nextWord.count > core.count, nextWord.hasPrefix(core) {
                tags[token.index] = .stutter
                stutterCount += 1
            }
        }

        // (b) Intra-token hyphen repeats: "I-I", "th-the", "w-we".
        for token in tokens where tags[token.index] == .normal {
            guard let dashRange = token.normalized.range(of: "-") else { continue }
            let left = String(token.normalized[token.normalized.startIndex..<dashRange.lowerBound])
            let right = String(token.normalized[dashRange.upperBound...])
            guard !left.isEmpty, !right.isEmpty, left.count <= 4, left.count <= right.count else { continue }
            if right.hasPrefix(left) {
                tags[token.index] = .stutter
                stutterCount += 1
            }
        }

        // (c) Immediate exact word repeats: "the the". Filler/crutch words already
        // tagged sit between the two occurrences without breaking the repeat, since
        // we scan over the untagged "content" indices only.
        var contentIndices = tokens.indices.filter { !tokens[$0].isEmpty && tags[$0] == .normal }
        var p = 0
        while p < contentIndices.count - 1 {
            defer { p += 1 }
            let i = contentIndices[p]
            let j = contentIndices[p + 1]
            let a = tokens[i].normalized
            let b = tokens[j].normalized
            guard !a.isEmpty, a == b else { continue }

            if a == "is" {
                let prevBefore = contentIndices[safe: p - 1].map { tokens[$0].normalized }
                if prevBefore == "it" || prevBefore == "what" { continue }
            } else if legitDoubleExclusion.contains(a) {
                continue
            }
            tags[i] = .stutter
            stutterCount += 1
        }

        // Repeated 2-4 word phrases ("I think I think", "it was it was"), longest
        // match first so a 4-word repeat isn't also read as two 2-word repeats.
        contentIndices = tokens.indices.filter { !tokens[$0].isEmpty && tags[$0] == .normal }
        var q = 0
        outer: while q < contentIndices.count {
            for length in stride(from: 4, through: 2, by: -1) {
                guard q + 2 * length <= contentIndices.count else { continue }
                var matches = true
                for k in 0..<length where matches {
                    let left = tokens[contentIndices[q + k]].normalized
                    let right = tokens[contentIndices[q + length + k]].normalized
                    if left != right { matches = false }
                }
                if matches {
                    for k in 0..<length { tags[contentIndices[q + k]] = .repetition }
                    repetitionCount += 1
                    q += 2 * length
                    continue outer
                }
            }
            q += 1
        }

        return Result(tags: tags, stutterCount: stutterCount, repetitionCount: repetitionCount)
    }
}
