import Foundation
import AppKit
import ApplicationServices

enum Inserter {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags; e?.post(tap: .cghidEventTap)
        }
    }

    private static func snapshot() -> [[(NSPasteboard.PasteboardType, Data)]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in item.types.compactMap { t in item.data(forType: t).map { (t, $0) } } }
    }
    private static func restore(_ snap: [[(NSPasteboard.PasteboardType, Data)]]) {
        let pb = NSPasteboard.general; pb.clearContents()
        let items = snap.map { entries -> NSPasteboardItem in
            let i = NSPasteboardItem(); for (t, d) in entries { i.setData(d, forType: t) }; return i
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }

    /// Pastes text into the focused app via ⌘V, then restores the user's clipboard.
    nonisolated(unsafe) static var sink: ((String) -> Void)?   // test hook: capture instead of pasting

    @MainActor static func insert(_ text: String, pressEnter: Bool = false) async {
        if let sink { sink(text); return }
        let pb = NSPasteboard.general
        let snap = Prefs.restoreClipboard ? snapshot() : []
        pb.clearContents(); pb.setString(text, forType: .string)
        guard trusted else { return } // text stays on clipboard so the user can paste manually
        try? await Task.sleep(nanoseconds: 60_000_000)
        key(9, flags: .maskCommand)
        if pressEnter { try? await Task.sleep(nanoseconds: 150_000_000); key(36) }
        if Prefs.restoreClipboard {
            try? await Task.sleep(nanoseconds: 500_000_000)
            restore(snap)
        }
    }

    /// Copies the current selection (⌘C) and returns it, restoring the clipboard.
    @MainActor static func selectedText() async -> String {
        guard trusted else { return "" }
        let pb = NSPasteboard.general
        let snap = snapshot(); let before = pb.changeCount
        key(8, flags: .maskCommand)
        for _ in 0..<12 { try? await Task.sleep(nanoseconds: 25_000_000); if pb.changeCount != before { break } }
        let s = pb.changeCount != before ? (pb.string(forType: .string) ?? "") : ""
        restore(snap)
        return s
    }

    static func frontApp() -> (name: String, bundle: String) {
        let a = NSWorkspace.shared.frontmostApplication
        return (a?.localizedName ?? "", a?.bundleIdentifier ?? "")
    }
}
