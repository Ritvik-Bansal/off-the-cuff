import Foundation

/// Tags hard fillers ("um", "uh", ...), context-dependent fillers ("like", "you know",
/// "I mean") and crutch/hedge words ("basically", "kind of", "right?", ...).
enum FillerDetector {
    struct Result {
        var tags: [WordTag]
        var fillerCount: Int = 0
        var crutchCount: Int = 0
        /// Normalized phrase -> occurrence count. Includes crutch words.
        var breakdown: [String: Int] = [:]
    }

    static func detect(tokens: [AnalysisToken]) -> Result {
        var tags = [WordTag](repeating: .normal, count: tokens.count)
        var fillerCount = 0
        var crutchCount = 0
        var breakdown: [String: Int] = [:]

        func addFiller(_ key: String) {
            fillerCount += 1
            breakdown[key, default: 0] += 1
        }
        func addCrutch(_ key: String) {
            crutchCount += 1
            breakdown[key, default: 0] += 1
        }
        func nextIndex(after i: Int) -> Int? {
            var j = i + 1
            while j < tokens.count {
                if !tokens[j].isEmpty { return j }
                j += 1
            }
            return nil
        }
        func previousIndex(before i: Int) -> Int? {
            var j = i - 1
            while j >= 0 {
                if !tokens[j].isEmpty { return j }
                j -= 1
            }
            return nil
        }

        // Pass 1: hard fillers (single token): um, uh, uhm, er, erm, ah, eh, hm, mhm
        // and elongated variants, but not "uh-huh".
        for token in tokens where !token.isEmpty {
            if isHardFiller(token.normalized) {
                tags[token.index] = .filler
                addFiller(token.normalized)
            }
        }

        // Pass 2: "you know" (with the fixed-phrase exception "you know what I mean").
        do {
            var i = 0
            while i < tokens.count {
                defer { i += 1 }
                guard tags[i] == .normal, tokens[i].normalized == "you" else { continue }
                guard let knowIdx = nextIndex(after: i), tokens[knowIdx].normalized == "know", tags[knowIdx] == .normal else { continue }

                let prevWord = previousIndex(before: i).map { tokens[$0].normalized }
                // "would/could/should you know" is ambiguous on its own (could be a genuine
                // question or discourse filler); only do/did/if/what/as/that reliably signal
                // real verb usage regardless of what follows.
                let strongPrecedeExclusion: Set<String> = ["do", "did", "don't", "didn't", "if", "what", "as", "that"]
                if let prevWord, strongPrecedeExclusion.contains(prevWord) { continue }

                if let w1 = nextIndex(after: knowIdx), tokens[w1].normalized == "what",
                   let w2 = nextIndex(after: w1), tokens[w2].normalized == "i",
                   let w3 = nextIndex(after: w2), tokens[w3].normalized == "mean" {
                    for idx in [i, knowIdx, w1, w2, w3] { tags[idx] = .filler }
                    addFiller("you know what i mean")
                    i = w3
                    continue
                }

                let followedExclusion: Set<String> = [
                    "how", "that", "what", "why", "who", "when", "where", "if", "the", "a", "an",
                    "about", "it", "him", "her", "them", "me", "this", "those", "these", "my", "your"
                ]
                let commaAdjacent = TextNormalizer.endsWithComma(tokens[knowIdx].rawText)
                let nextWord = nextIndex(after: knowIdx).map { tokens[$0].normalized }
                if !commaAdjacent, let nextWord, followedExclusion.contains(nextWord) { continue }

                tags[i] = .filler
                tags[knowIdx] = .filler
                addFiller("you know")
                i = knowIdx
            }
        }

        // Pass 3: "I mean".
        do {
            var i = 0
            while i < tokens.count {
                defer { i += 1 }
                guard tags[i] == .normal, tokens[i].normalized == "i" else { continue }
                guard let meanIdx = nextIndex(after: i), tokens[meanIdx].normalized == "mean", tags[meanIdx] == .normal else { continue }

                let prevIdx = previousIndex(before: i)
                let prevWord = prevIdx.map { tokens[$0].normalized }
                if let prevWord, ["what", "do", "did"].contains(prevWord) { continue }

                let endsComma = TextNormalizer.endsWithComma(tokens[meanIdx].rawText)
                let isClauseStart = prevIdx == nil
                    || TextNormalizer.endsWithClauseBreak(tokens[prevIdx!].rawText)
                    || tags[prevIdx!] == .filler

                let nextWord = nextIndex(after: meanIdx).map { tokens[$0].normalized }
                let nextExempt = nextWord.map { ["it", "that", "to", "what"].contains($0) } ?? false

                if endsComma || (isClauseStart && !nextExempt) {
                    tags[i] = .filler
                    tags[meanIdx] = .filler
                    addFiller("i mean")
                    i = meanIdx
                }
            }
        }

        // Pass 4: filler "like" (verb and comparison/preposition usages are exempt).
        let verbExclusion: Set<String> = [
            "i", "you", "we", "they", "he", "she", "who", "people", "would", "do", "does", "did",
            "don't", "doesn't", "didn't", "not", "really", "also", "to", "still", "genuinely"
        ]
        let comparisonExclusion: Set<String> = [
            "look", "looks", "looked", "looking", "sound", "sounds", "sounded", "seem", "seems",
            "seemed", "feel", "feels", "feeling", "felt", "something", "anything", "nothing",
            "things", "stuff", "more", "much", "exactly"
        ]
        for token in tokens where tags[token.index] == .normal && token.normalized == "like" {
            let prevWord = previousIndex(before: token.index).map { tokens[$0].normalized }
            let nextWord = nextIndex(after: token.index).map { tokens[$0].normalized }

            if let prevWord, verbExclusion.contains(prevWord) || prevWord.hasSuffix("'d") { continue }
            if let prevWord, comparisonExclusion.contains(prevWord) { continue }
            if let prevWord, prevWord == "just", let nextWord, ["a", "the", "that", "this"].contains(nextWord) { continue }
            if let prevWord, ["is", "was", "were", "be", "been"].contains(prevWord), let nextWord, ["a", "an", "the"].contains(nextWord) { continue }

            tags[token.index] = .filler
            addFiller("like")
        }

        // Pass 5: crutch / hedge words.
        let singleCrutches: Set<String> = [
            "basically", "actually", "literally", "honestly", "totally", "essentially", "obviously", "seriously"
        ]
        for token in tokens where tags[token.index] == .normal && singleCrutches.contains(token.normalized) {
            tags[token.index] = .crutch
            addCrutch(token.normalized)
        }

        let hedgePrecedeExclusion: Set<String> = [
            "what", "this", "that", "the", "a", "any", "some", "every", "which", "one", "same",
            "different", "new", "another"
        ]
        for token in tokens where tags[token.index] == .normal && (token.normalized == "kind" || token.normalized == "sort") {
            guard let ofIdx = nextIndex(after: token.index), tokens[ofIdx].normalized == "of", tags[ofIdx] == .normal else { continue }
            let prevWord = previousIndex(before: token.index).map { tokens[$0].normalized }
            if let prevWord, hedgePrecedeExclusion.contains(prevWord) { continue }
            let afterOfWord = nextIndex(after: ofIdx).map { tokens[$0].normalized }
            if let afterOfWord, ["a", "an", "the"].contains(afterOfWord) { continue }
            tags[token.index] = .crutch
            tags[ofIdx] = .crutch
            addCrutch("\(token.normalized) of")
        }

        let lastRealIndex = tokens.last(where: { !$0.isEmpty })?.index
        for token in tokens where tags[token.index] == .normal && token.normalized == "right" {
            let isQuestionMark = token.rawText.hasSuffix("?")
            let isLast = token.index == lastRealIndex
            if isQuestionMark || isLast {
                tags[token.index] = .crutch
                addCrutch("right")
            }
        }

        for token in tokens where tags[token.index] == .normal && (token.normalized == "so" || token.normalized == "and") {
            guard let yeahIdx = nextIndex(after: token.index), tokens[yeahIdx].normalized == "yeah", tags[yeahIdx] == .normal else { continue }
            tags[yeahIdx] = .crutch
            addCrutch("yeah")
        }

        return Result(tags: tags, fillerCount: fillerCount, crutchCount: crutchCount, breakdown: breakdown)
    }

    // MARK: Hard fillers

    private static let hardFillerBases: Set<String> = ["um", "uh", "uhm", "er", "erm", "ah", "eh", "hm", "mhm"]

    /// Matches "um", "uh", "uhm", "er", "erm", "ah", "eh", "hm", "mhm" and elongated
    /// variants ("ummm", "uhhh", "hmmm", ...), but never a token containing a hyphen
    /// (so "uh-huh" is excluded).
    static func isHardFiller(_ word: String) -> Bool {
        guard !word.isEmpty, !word.contains("-"), word.allSatisfy(\.isLetter) else { return false }
        if word.count >= 2, Set(word) == Set("m") { return true } // "mm", "mmm", ...
        return hardFillerBases.contains(TextNormalizer.collapseRepeatedLetters(word))
    }
}
