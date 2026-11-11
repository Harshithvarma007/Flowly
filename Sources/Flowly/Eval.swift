import Foundation

/// `Flowly --eval tests/polish_cases.json [engine] [model]` runs a test set through the real cleanup pipeline and scores it.
struct EvalCase: Codable {
    var name: String, input: String
    var app: String?, bundle: String?, before: String?, hints: [String]?
    var contains: [String]?, contains_cs: [String]?, not_contains: [String]?
    var bullets: String?, min_bullets: Int?, max_chars: Int?, first_lower: Bool?, min_paragraphs: Int?
}

@MainActor
enum Eval {
    static func bulletCount(_ s: String) -> Int {
        let re = try! NSRegularExpression(pattern: "^\\s*([-*•]|\\d+[.)])\\s", options: .anchorsMatchLines)
        return re.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s))
    }
    static func words(_ s: String) -> Set<String> { Set(s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)) }

    static func check(_ c: EvalCase, out: String) -> [String] {
        var fails: [String] = []
        let l = out.lowercased()
        for s in c.contains ?? [] where !l.contains(s.lowercased()) { fails.append("missing “\(s)”") }
        for s in c.contains_cs ?? [] where !out.contains(s) { fails.append("missing exact “\(s)”") }
        let w = words(out)
        for s in c.not_contains ?? [] where w.contains(s.lowercased()) { fails.append("should not contain “\(s)”") }
        let b = bulletCount(out)
        if c.bullets == "yes", b < max(2, c.min_bullets ?? 2) { fails.append("expected bullets (got \(b))") }
        if c.bullets == "no", b > 0 { fails.append("should not be bulleted") }
        if let m = c.max_chars, out.count > m { fails.append("too long (\(out.count) > \(m))") }
        if let f = c.first_lower, let ch = out.trimmingCharacters(in: .whitespaces).first {
            if f && ch.isUppercase && !out.hasPrefix("I ") && !out.hasPrefix("I'") { fails.append("first word should be lowercase") }
            if !f && ch.isLowercase { fails.append("first word should be capitalized") }
        }
        if let p = c.min_paragraphs, out.components(separatedBy: "\n\n").filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count < p { fails.append("expected \(p)+ paragraphs") }
        return fails
    }

    static func run(path: String) async {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: path)), let cases = try? JSONDecoder().decode([EvalCase].self, from: d) else { print("Could not read \(path)"); return }
        let engine = await LLM.resolve()
        print("Engine: \(engine?.label ?? "none")  Ollama model: \(LLM.pickOllamaModel(await LLM.ollamaModels()) ?? "-")  Cases: \(cases.count)\n")
        var passed = 0, totalTime = 0.0
        var failed: [String] = []
        for c in cases {
            var t = TextProcessor.removeFillers(TextProcessor.convertDigitRuns(c.input))
            t = TextProcessor.spokenFormatting(t); t = TextProcessor.tidy(t); t = TextProcessor.capitalize(t)
            let ctx = TextContext(app: c.app ?? "", bundle: c.bundle ?? "", before: c.before ?? "")
            let t0 = Date()
            let polished = ((try? await LLM.polish(t, ctx: ctx, hints: c.hints ?? [])) ?? nil)
            let out = polished ?? t   // same fallback the live app uses when the AI output is rejected
            totalTime += Date().timeIntervalSince(t0)
            let fails = check(c, out: out)
            if fails.isEmpty { passed += 1; print("PASS  \(c.name)\(polished == nil ? "  (fallback: AI output rejected)" : "")") }
            else { failed.append(c.name); print("FAIL  \(c.name): \(fails.joined(separator: "; "))\n      in:  \(c.input)\n      out: \(out.replacingOccurrences(of: "\n", with: "\\n"))") }
        }
        print("\nScore: \(passed)/\(cases.count) (\(Int(Double(passed) / Double(cases.count) * 100))%)   avg \(String(format: "%.2f", totalTime / Double(cases.count)))s per case")
        if !failed.isEmpty { print("Failed: \(failed.joined(separator: ", "))") }
    }
}
