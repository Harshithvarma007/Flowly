import Foundation
import AppKit
import ApplicationServices

/// What Flowly knows about where you're typing: app, window, and the text around the cursor.
struct TextContext {
    var app = "", bundle = "", window = "", before = "", after = "", selection = ""
    var isEmpty: Bool { before.isEmpty && after.isEmpty && selection.isEmpty && window.isEmpty }

    /// Capitalized words visible nearby (names, product terms) — used as spelling hints for the AI.
    var visibleTerms: [String] {
        let src = window + " " + before.suffix(600) + " " + after.prefix(200)
        let re = try! NSRegularExpression(pattern: "(?<![.!?]\\s)(?<!^)\\b[A-Z][A-Za-z]{2,}\\b")
        let ns = src as NSString
        var seen = Set<String>(), out: [String] = []
        for m in re.matches(in: src, range: NSRange(location: 0, length: ns.length)) {
            let w = ns.substring(with: m.range)
            if seen.insert(w.lowercased()).inserted { out.append(w) }
            if out.count >= 15 { break }
        }
        return out
    }
    var endsMidSentence: Bool {
        guard let c = before.trimmingCharacters(in: .whitespaces).last else { return false }
        return !".!?:\n".contains(c)
    }
}

enum ContextReader {
    private static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    /// Reads the focused text field via the Accessibility API. Never reads password fields. Stays on this Mac.
    static func capture() -> TextContext {
        let a = NSWorkspace.shared.frontmostApplication
        var ctx = TextContext(app: a?.localizedName ?? "", bundle: a?.bundleIdentifier ?? "")
        guard UserDefaults.standard.bool(forKey: "useContext"), AXIsProcessTrusted() else { return ctx }
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.3)
        if let appEl = a.map({ AXUIElementCreateApplication($0.processIdentifier) }), let w = attr(appEl, kAXFocusedWindowAttribute as String) {
            AXUIElementSetMessagingTimeout(appEl, 0.3); AXUIElementSetMessagingTimeout(w as! AXUIElement, 0.3)
            ctx.window = (attr(w as! AXUIElement, kAXTitleAttribute as String) as? String) ?? ""
        }
        guard let f = attr(sys, kAXFocusedUIElementAttribute as String) else { return ctx }
        let el = f as! AXUIElement
        AXUIElementSetMessagingTimeout(el, 0.3)
        let sub = (attr(el, kAXSubroleAttribute as String) as? String) ?? ""
        if sub == "AXSecureTextField" { return TextContext(app: ctx.app, bundle: ctx.bundle) } // privacy: never read passwords
        ctx.selection = (attr(el, kAXSelectedTextAttribute as String) as? String) ?? ""
        guard let value = attr(el, kAXValueAttribute as String) as? String, !value.isEmpty else { return ctx }
        let ns = value as NSString
        var loc = ns.length
        if let r = attr(el, kAXSelectedTextRangeAttribute as String), CFGetTypeID(r) == AXValueGetTypeID() {
            var range = CFRange(); if AXValueGetValue(r as! AXValue, .cfRange, &range) { loc = max(0, min(range.location, ns.length)) }
        }
        let start = max(0, loc - 800)
        ctx.before = ns.substring(with: NSRange(location: start, length: loc - start))
        let endLen = min(200, ns.length - loc)
        ctx.after = endLen > 0 ? ns.substring(with: NSRange(location: loc, length: endLen)) : ""
        return ctx
    }

    /// Full text of the currently focused field (used to learn from your corrections).
    static func focusedValue() -> (value: String, bundle: String)? {
        guard AXIsProcessTrusted() else { return nil }
        let sys = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(sys, 0.3)
        guard let f = attr(sys, kAXFocusedUIElementAttribute as String) else { return nil }
        let el = f as! AXUIElement
        AXUIElementSetMessagingTimeout(el, 0.3)
        if ((attr(el, kAXSubroleAttribute as String) as? String) ?? "") == "AXSecureTextField" { return nil }
        guard let v = attr(el, kAXValueAttribute as String) as? String else { return nil }
        return (v, NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
    }
}
