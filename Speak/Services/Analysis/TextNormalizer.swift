import Foundation

/// Normalizes transcript word text for rule matching. The analyzer keeps the
/// original punctuated text on `TranscriptWord` untouched; everything here operates
/// on derived, disposable strings.
enum TextNormalizer {
    private static let stripSet = CharacterSet(charactersIn: ".,?!…—–\"'“”‘’()[]{}:;")

    /// Lowercases and strips leading/trailing punctuation and quotes, but preserves
    /// internal apostrophes and hyphens (e.g. "i'd", "th-the"). Also strips a lone
    /// leading/trailing hyphen, so "th-" -> "th".
    static func normalize(_ text: String) -> String {
        var s = normalizeKeepTrailingHyphen(text)
        while s.hasPrefix("-") { s.removeFirst() }
        while s.hasSuffix("-") { s.removeLast() }
        return s
    }

    /// Same as `normalize` but keeps a trailing hyphen, so partial-word stutters like
    /// "th-" can still be recognized as such by the disfluency detector.
    static func normalizeKeepTrailingHyphen(_ text: String) -> String {
        var s = text.lowercased()
        while let f = s.unicodeScalars.first, stripSet.contains(f) {
            s.removeFirst()
        }
        while let l = s.unicodeScalars.last, stripSet.contains(l) {
            s.removeLast()
        }
        return s
    }

    /// Collapses runs of the same character to a single instance: "ummm" -> "um".
    /// Used to recognize elongated filler variants ("uhhh", "hmmm", ...).
    static func collapseRepeatedLetters(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        var last: Character?
        for c in s {
            if c != last { result.append(c) }
            last = c
        }
        return result
    }

    static func endsWithComma(_ rawText: String) -> Bool {
        rawText.hasSuffix(",")
    }

    /// True when the raw (un-normalized) token ends a sentence or clause.
    static func endsWithClauseBreak(_ rawText: String) -> Bool {
        guard let last = rawText.unicodeScalars.last else { return false }
        return CharacterSet(charactersIn: ".?!,…").contains(last)
    }
}

/// A transcript word paired with its normalized forms and index, shared across the
/// filler/crutch/stutter/repetition detectors.
struct AnalysisToken {
    var index: Int
    /// Fully stripped lowercase form used for matching and counting, e.g. "th".
    var normalized: String
    /// Same as `normalized` but keeps a trailing hyphen, e.g. "th-".
    var normalizedKeepHyphen: String
    /// The word exactly as transcribed (with attached punctuation).
    var rawText: String

    var isEmpty: Bool { normalized.isEmpty }
}

enum TokenBuilder {
    static func makeTokens(_ words: [TranscriptWord]) -> [AnalysisToken] {
        words.enumerated().map { index, word in
            AnalysisToken(
                index: index,
                normalized: TextNormalizer.normalize(word.text),
                normalizedKeepHyphen: TextNormalizer.normalizeKeepTrailingHyphen(word.text),
                rawText: word.text
            )
        }
    }
}

extension Array {
    /// Bounds-safe subscript used by the disfluency detector when looking one step
    /// before the start of a content-word scan.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
