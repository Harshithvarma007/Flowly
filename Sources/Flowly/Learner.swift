import Foundation
import AppKit

/// Learns from your manual corrections: after Flowly inserts text, it re-reads the field a few seconds later
/// and turns single-word fixes ("harshit" -> "Harshith") into dictionary entries. All local; password fields are never read.
@MainActor
enum Learner {
    static func normalize(_ w: String) -> String { w.lowercased() }

    static func tokens(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map { tok in
            var t = String(tok)
            while let f = t.first, !(f.isLetter || f.isNumber) { t.removeFirst() }
            while let l = t.last, !(l.isLetter || l.isNumber) { t.removeLast() }
            return t
        }.filter { !$0.isEmpty }
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }; if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count { cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)) }
            prev = cur
        }
        return prev[b.count]
    }

    /// Finds single-word substitutions between what we inserted and what the field now contains.
    static func corrections(inserted: String, current: String) -> [(from: String, to: String)] {
        let a = tokens(inserted)
        let bAll = tokens(current)
        guard a.count >= 4, !bAll.isEmpty else { return [] }
        let an = a.map(normalize), bn = bAll.map(normalize)
        // Locate where our text sits in the field using 3-word then 2-word anchors from the start or end.
        var start: Int? = nil
        outer: for k in [3, 2] {
            let head = Array(an.prefix(k))
            if bn.count >= k { for i in 0...(bn.count - k) where Array(bn[i..<i + k]) == head { start = i; break outer } }
            let tail = Array(an.suffix(k))
            if bn.count >= k { for j in 0...(bn.count - k) where Array(bn[j..<j + k]) == tail { start = max(0, j + k - an.count - 2); break outer } }
        }
        guard let s0 = start else { return [] }
        let end = min(bAll.count, s0 + a.count + 6)
        let b = Array(bAll[s0..<end]), bnW = Array(bn[s0..<end])
        // LCS alignment
        let n = a.count, m = b.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) { for j in stride(from: m - 1, through: 0, by: -1) {
            dp[i][j] = an[i] == bnW[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1]) } }
        var i = 0, j = 0
        var out: [(String, String)] = []
        var dels: [String] = [], inss: [String] = []
        func flush() { if dels.count == 1, inss.count == 1 { out.append((dels[0], inss[0])) }; dels = []; inss = [] }
        while i < n || j < m {
            if i < n, j < m, an[i] == bnW[j] { flush(); if a[i] != b[j] { out.append((a[i], b[j])) }; i += 1; j += 1 } // same word, fixed capitalization
            else if j < m, i == n || dp[i][j + 1] >= dp[i + 1][j] { inss.append(b[j]); j += 1 }
            else { dels.append(a[i]); i += 1 }
        }
        flush()
        return out.map { (from: $0.0, to: $0.1) }
    }

    static func isLearnable(from: String, to: String, store: Store) -> Bool {
        guard from.count >= 3, to.count >= 3, from.allSatisfy({ $0.isLetter }), to.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "-" }) else { return false }
        if from.lowercased() == to.lowercased() {
            // Capitalization-only fix: learn it only for real names (words the spell-checker doesn't know), never for ordinary words like "tomorrow".
            guard from.first!.isLowercase, to.first!.isUppercase else { return false }
            return NSSpellChecker.shared.checkSpelling(of: from, startingAt: 0).location != NSNotFound
        }
        let dist = levenshtein(from.lowercased(), to.lowercased())
        guard 1 - Double(dist) / Double(max(from.count, to.count)) >= 0.5 else { return false } // must look like a mis-hearing, not a rewrite
        return !store.dictionary.contains { $0.spoken.lowercased() == from.lowercased() && $0.written == to }
    }

    static func watch(inserted: String, store: Store, hud: HUD, isRecording: @escaping () -> Bool) {
        guard UserDefaults.standard.bool(forKey: "autoLearn"), inserted.split(whereSeparator: { $0.isWhitespace }).count >= 4 else { return }
        Task {
            for delay in [8.0, 10.0] {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
                guard let cur = (try? await raceTimeout(1.5) { await Task.detached { ContextReader.focusedValue() }.value }) ?? nil else { continue }
                let found = corrections(inserted: inserted, current: cur.value).filter { isLearnable(from: $0.from, to: $0.to, store: store) }
                guard !found.isEmpty, found.count <= 3 else { continue }
                for f in found {
                    store.dictionary.append(DictEntry(spoken: f.from.lowercased(), written: f.to, auto: true))
                }
                dlog("learned: \(found.map { "\($0.from)->\($0.to)" }.joined(separator: ", "))")
                if !isRecording() { hud.show(.message("Learned “\(found[0].to)”" + (found.count > 1 ? " +\(found.count - 1)" : ""), error: false), autoHide: 2.5) }
                return
            }
        }
    }
}
