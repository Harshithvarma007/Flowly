import Foundation

/// Rule-based cleanup that runs locally on every transcript (before the optional LLM polish).
enum TextProcessor {
    static let hallucinations: Set<String> = [
        "thank you", "thanks for watching", "thank you for watching", "you", "bye", "[blank_audio]", "(silence)", "[silence]",
        "[music]", "subtitles by the amara.org community", "thank you very much",
    ]

    static func isHallucination(_ s: String) -> Bool {
        let t = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return t.isEmpty || hallucinations.contains(t)
    }

    @MainActor
    static func process(_ raw: String, store: Store, backtrack: Bool = true) -> String {
        var t = raw.replacingOccurrences(of: "\\[[A-Z_ ]+\\]|\\([a-z ]+\\)", with: "", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if backtrack { t = applyBacktracking(t) } // when an AI engine will run, it handles self-corrections with full context
        t = convertDigitRuns(t)
        if Prefs.removeFillers { t = removeFillers(t) }
        t = spokenFormatting(t)
        for e in store.dictionary where !e.spoken.isEmpty && !e.written.isEmpty { t = replaceWord(e.spoken, with: e.written, in: t) }
        t = expandSnippets(t, snippets: store.snippets)
        t = tidy(t)
        if Prefs.autoCap { t = capitalize(t) }
        return t
    }

    /// "five five five one two three four" -> "555-1234". Done by rule so a language model can never alter digits.
    static func convertDigitRuns(_ s: String) -> String {
        let map: [String: String] = ["zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9"]
        let word = "(?:zero|oh|one|two|three|four|five|six|seven|eight|nine)"
        guard let re = try? NSRegularExpression(pattern: "\\b\(word)(?:[ ,.-]+\(word)\\b){2,}", options: .caseInsensitive) else { return s }
        var out = s
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let r = Range(m.range, in: out) else { continue }
            let digits = out[r].lowercased().split(whereSeparator: { !$0.isLetter }).compactMap { map[String($0)] }.joined()
            var formatted = digits
            if digits.count == 7 { formatted = digits.prefix(3) + "-" + digits.suffix(4) }
            else if digits.count == 10 { formatted = digits.prefix(3) + "-" + digits.dropFirst(3).prefix(3) + "-" + digits.suffix(4) }
            out.replaceSubrange(r, with: formatted)
        }
        return out
    }

    static func removeFillers(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "(?i)\\b(?:u+m+|u+h+|uhm|er+m*|a+h+m+|hm+|mm+h*m*)\\b[,.]?\\s*", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?i)\\b(\\w+)(\\s+\\1\\b)+", with: "$1", options: .regularExpression) // stutters: "the the"
        return t
    }

    /// "meet at 3, scratch that, meet at 4" -> "meet at 4"
    static func applyBacktracking(_ s: String) -> String {
        let triggers = "scratch that|delete that|strike that|never mind that|cancel that|no wait|wait no"
        guard let re = try? NSRegularExpression(pattern: "[,.;]?\\s*\\b(?:\(triggers))\\b[,.;]?\\s*", options: .caseInsensitive) else { return s }
        var t = s
        while let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), let r = Range(m.range, in: t) {
            var left = String(t[..<r.lowerBound]); let right = String(t[r.upperBound...])
            // drop the last sentence/clause of `left`
            if let idx = left.lastIndex(where: { ".!?".contains($0) }) { left = String(left[...idx]) }
            else if let idx = left.lastIndex(of: ",") { left = String(left[..<idx]) + "," }
            else { left = "" }
            t = (left.trimmingCharacters(in: .whitespaces) + " " + right).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    static func spokenFormatting(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "(?i)[,.]?\\s*\\bnew paragraph\\b[,.]?\\s*", with: "\n\n", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?i)[,.]?\\s*\\b(?:new line|next line)\\b[,.]?\\s*", with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?i)\\s*\\bquestion mark\\b", with: "?", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?i)\\s*\\bexclamation (?:mark|point)\\b", with: "!", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?i)\\s*\\bsmiley face\\b", with: " 🙂", options: .regularExpression)
        return t
    }

    static func replaceWord(_ from: String, with to: String, in s: String) -> String {
        let p = "(?i)(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: from) + "(?![\\p{L}\\p{N}])"
        return s.replacingOccurrences(of: p, with: NSRegularExpression.escapedTemplate(for: to), options: .regularExpression)
    }

    static func expandSnippets(_ s: String, snippets: [Snippet]) -> String {
        var t = s
        for sn in snippets where !sn.trigger.isEmpty {
            let p = "(?i)(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: sn.trigger) + "(?![\\p{L}\\p{N}])[.,!?]?"
            t = t.replacingOccurrences(of: p, with: NSRegularExpression.escapedTemplate(for: sn.text), options: .regularExpression)
        }
        return t
    }

    static func tidy(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+([,.;:!?])", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func capitalize(_ s: String) -> String {
        guard let f = s.first else { return s }
        var t = s
        t.replaceSubrange(t.startIndex...t.startIndex, with: String(f).uppercased())
        // capitalize after sentence end
        let re = try! NSRegularExpression(pattern: "([.!?]\\s+|\\n)([a-z])")
        let ns = t as NSString
        var out = t
        for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)).reversed() {
            let r = m.range(at: 2)
            out = (out as NSString).replacingCharacters(in: r, with: ns.substring(with: r).uppercased())
        }
        return out
    }
}
