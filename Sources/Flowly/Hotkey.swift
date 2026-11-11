import Foundation
import CoreGraphics
import AppKit

enum DictationMode { case dictate, command }

func dlog(_ m: String) {
    let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Flowly/debug.log")
    if let sz = (try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? Int, sz > 400_000 { try? FileManager.default.removeItem(at: u) }
    let line = "\(Date()) \(m)\n"
    if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() } else { try? line.write(to: u, atomically: true, encoding: .utf8) }
}

/// Global push-to-talk. Hold = talk while held. Quick tap = hands-free latch; tap again to finish. Esc cancels.
final class HotkeyManager {
    var onStart: ((DictationMode) -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var isActive: () -> Bool = { false }

    private var tap: CFMachPort?
    private enum State { case idle, holding(DictationMode, UInt64), latched(DictationMode) }
    private var state = State.idle
    private var swallowRelease = false
    private var otherKeyDuringPress = false

    @discardableResult
    func start() -> Bool {
        stop()
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let cb: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type, event)
        }
        dlog("start(): AXIsProcessTrusted=\(AXIsProcessTrusted()) listenAccess=\(CGPreflightListenEventAccess())")
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mask), callback: cb, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { dlog("tapCreate FAILED"); return false }
        dlog("tap created")
        tap = t
        let src = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }
    func stop() { if let t = tap { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t) }; tap = nil }
    var running: Bool { tap != nil }
    func reset() { state = .idle; swallowRelease = false }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }; return Unmanaged.passUnretained(event) }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown {
            if code == 53, isActive() { DispatchQueue.main.async { self.state = .idle; self.onCancel?() }; return nil } // Esc
            if case .holding = state { otherKeyDuringPress = true }
            return Unmanaged.passUnretained(event)
        }
        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
        dlog("flagsChanged code=\(code) flags=\(event.flags.rawValue)")
        let dictKey = Prefs.hotkey, cmdKey = Prefs.cmdHotkey
        let mode: DictationMode
        let key: HotKey
        if code == dictKey.keyCode { mode = .dictate; key = dictKey }
        else if code == cmdKey.keyCode { mode = .command; key = cmdKey }
        else { return Unmanaged.passUnretained(event) }
        let pressed = event.flags.contains(key.flag)
        let ts = event.timestamp
        DispatchQueue.main.async { self.transition(pressed: pressed, mode: mode, ts: ts) }
        return Unmanaged.passUnretained(event)
    }

    private func transition(pressed: Bool, mode: DictationMode, ts: UInt64) {
        switch (state, pressed) {
        case (.idle, true):
            otherKeyDuringPress = false
            state = .holding(mode, ts); onStart?(mode)
        case (.holding(let m, let t), false):
            let held = Double(ts &- t) / 1e9
            if otherKeyDuringPress && held < 0.5 { state = .idle; onCancel?(); return } // was a shortcut like ⌥+key
            if held < 0.35 { state = .latched(m) } else { state = .idle; onStop?() }
        case (.latched, true):
            state = .idle; swallowRelease = true; onStop?()
        case (.idle, false): swallowRelease = false
        default: break
        }
    }
}
