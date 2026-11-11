import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var window: NSWindow?
    let c = Controller.shared

    func applicationDidFinishLaunching(_ n: Notification) {
        Prefs.register()
        if ProcessInfo.processInfo.environment["FLOWLY_LIGHT"] != nil { NSApp.appearance = NSAppearance(named: .aqua) }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIcon(false)
        rebuildMenu()
        c.onRecordingChange = { [weak self] r in self?.setIcon(r) }
        c.boot()
        if ProcessInfo.processInfo.environment["FLOWLY_HUD"] != nil { c.hud.model.live = "Hey Sarah, quick update on the project. So the backend is done, the front end is about eighty percent done, and we are still waiting on design for the settings page"; c.hud.show(.recording(command: false, latched: true)); Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.c.hud.model.push(Float.random(in: 0.1...0.9)) } }
        openSettings() // always show the window on launch so the app is never "invisible"
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.rebuildMenu() }
    }
    func setIcon(_ rec: Bool) {
        let img = NSImage(systemSymbolName: rec ? "waveform.circle.fill" : "waveform", accessibilityDescription: "Flowly")
        img?.isTemplate = !rec
        item.button?.image = rec ? img?.withSymbolConfiguration(.init(paletteColors: [.systemRed])) : img
    }
    func rebuildMenu() {
        let m = NSMenu()
        let status = c.transcriber.ready ? "Ready — hold \(Prefs.hotkey.label) to dictate" : c.transcriber.status
        let s = NSMenuItem(title: status, action: nil, keyEquivalent: ""); s.isEnabled = false; m.addItem(s)
        if !c.hotkeyActive { let w = NSMenuItem(title: "⚠︎ Grant Accessibility access…", action: #selector(grant), keyEquivalent: ""); w.target = self; m.addItem(w) }
        m.addItem(.separator())
        let p = NSMenuItem(title: "Paste last transcript", action: #selector(pasteLast), keyEquivalent: "v"); p.keyEquivalentModifierMask = [.command, .shift]; p.target = self; m.addItem(p)
        let po = NSMenuItem(title: "Paste original transcript (no AI)", action: #selector(pasteOriginal), keyEquivalent: ""); po.target = self; m.addItem(po)
        let o = NSMenuItem(title: "Home & Settings…", action: #selector(openSettings), keyEquivalent: ","); o.target = self; m.addItem(o)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit Flowly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = m
    }
    @objc func grant() { c.startHotkeys(); NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
    @objc func pasteLast() { c.pasteLast() }
    @objc func pasteOriginal() { c.pasteOriginal() }
    @objc func openSettings() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Flowly"; w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true; w.minSize = NSSize(width: 900, height: 640)
            w.contentView = NSHostingView(rootView: RootView()); w.center(); w.isReleasedWhenClosed = false
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in NSApp.setActivationPolicy(.accessory) }
            window = w
        }
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool { openSettings(); return true }
}

if let i = CommandLine.arguments.firstIndex(of: "--hudshot"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated {
        let m = HUDModel(); m.live = CommandLine.arguments.count > i + 2 ? CommandLine.arguments[i + 2] : ""
        m.phase = .recording(command: false, latched: true); m.levels = (0..<26).map { _ in Float.random(in: 0.1...0.9) }
        let r = ImageRenderer(content: HUDView(m: m).background(Color.gray.opacity(0.4))); r.scale = 2
        if let img = r.nsImage, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])); print("wrote")
        }
    }
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--e2e"), i + 1 < CommandLine.arguments.count {
    Prefs.register()
    Task { @MainActor in
        let c = Controller.shared
        c.transcriber.load(variant: Prefs.model)
        while !c.transcriber.ready { try? await Task.sleep(nanoseconds: 500_000_000) }
        let wav = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        var all = [Float](); wav.dropFirst(44).withUnsafeBytes { (b: UnsafeRawBufferPointer) in let p = b.bindMemory(to: Int16.self); all = (0..<p.count).map { Float(p[$0]) / 32768 } }
        var pasted: [String] = []
        Inserter.sink = { pasted.append($0) }
        let before = c.store.history.count
        // Simulate the live preview running while the user speaks, then the final pass starting right at key release.
        let live = Task { for _ in 0..<6 { _ = await c.transcriber.transcribePartial(Array(all.prefix(48000)), language: nil); try? await Task.sleep(nanoseconds: 200_000_000) } }
        try? await Task.sleep(nanoseconds: 300_000_000)
        let t0 = Date()
        let finalTask = Task { await c.process(all, duration: Double(all.count) / 16000, mode: .dictate, ctx: TextContext(app: "Test", bundle: "x", before: "")) }
        let result = await withTaskGroup(of: String.self) { g -> String in
            g.addTask { await finalTask.value; return "done" }
            g.addTask { try? await Task.sleep(nanoseconds: 60_000_000_000); return "TIMEOUT (hang)" }
            let r = await g.next()!; g.cancelAll(); return r
        }
        _ = await live.value
        print("process: \(result) in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
        print("pasted \(pasted.count) item(s): \(pasted.first ?? "<none>")")
        print("history +\(c.store.history.count - before)")
        exit(0)
    }
    RunLoop.main.run()
}
if let i = CommandLine.arguments.firstIndex(of: "--canceltest"), i + 1 < CommandLine.arguments.count {
    Prefs.register()
    Task { @MainActor in
        let c = Controller.shared
        c.transcriber.load(variant: Prefs.model)
        while !c.transcriber.ready { try? await Task.sleep(nanoseconds: 500_000_000) }
        let wav = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        var all = [Float](); wav.dropFirst(44).withUnsafeBytes { (b: UnsafeRawBufferPointer) in let p = b.bindMemory(to: Int16.self); all = (0..<p.count).map { Float(p[$0]) / 32768 } }
        for round in 1...6 {
            // Same pattern as the app: a live task loops partial passes, then gets cancelled at "key release" and the final pass starts at once.
            let live = Task { while !Task.isCancelled { _ = await c.transcriber.transcribePartial(all, language: nil) } }
            try? await Task.sleep(nanoseconds: UInt64.random(in: 100_000_000...900_000_000))
            live.cancel()
            let t0 = Date()
            let r: String = await withTaskGroup(of: String.self) { g in
                g.addTask { (try? await c.transcriber.transcribe(all, language: nil, hints: [])) ?? "<error>" }
                g.addTask { try? await Task.sleep(nanoseconds: 40_000_000_000); return "HANG (no result after 40s)" }
                let x = await g.next()!; g.cancelAll(); return x
            }
            print("round \(round): \(String(format: "%.1f", Date().timeIntervalSince(t0)))s -> \(r.prefix(60))")
            _ = await live.value
        }
        exit(0)
    }
    RunLoop.main.run()
}
if let i = CommandLine.arguments.firstIndex(of: "--e2e-gui"), i + 1 < CommandLine.arguments.count {
    Prefs.register()
    MainActor.assumeIsolated { _ = NSApplication.shared; NSApp.setActivationPolicy(.regular) }
    Task { @MainActor in
        let c = Controller.shared
        c.transcriber.load(variant: Prefs.model)
        let win = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 300)); tv.isRichText = false
        tv.string = "Thanks for your email. I looked at the proposal and"
        win.contentView = tv; win.title = "Flowly test field"; win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        win.makeFirstResponder(tv); tv.setSelectedRange(NSRange(location: tv.string.count, length: 0))
        while !c.transcriber.ready { try? await Task.sleep(nanoseconds: 500_000_000) }
        try? await Task.sleep(nanoseconds: 800_000_000)
        print("trusted=\(Inserter.trusted) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        let t0 = Date(); let ctx = ContextReader.capture()
        print("ContextReader.capture took \(String(format: "%.2f", Date().timeIntervalSince(t0)))s; app=\(ctx.app) before=[\(ctx.before.suffix(40))]")
        let wav = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        var all = [Float](); wav.dropFirst(44).withUnsafeBytes { (b: UnsafeRawBufferPointer) in let p = b.bindMemory(to: Int16.self); all = (0..<p.count).map { Float(p[$0]) / 32768 } }
        let before = c.store.history.count
        let t1 = Date()
        await c.process(all, duration: Double(all.count) / 16000, mode: .dictate, ctx: ctx)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        print("process+paste took \(String(format: "%.1f", Date().timeIntervalSince(t1)))s")
        print("FIELD NOW: [\(tv.string)]")
        print("history +\(c.store.history.count - before)")
        exit(0)
    }
    RunLoop.main.run()
}
if CommandLine.arguments.contains("--learntest") {
    Task { @MainActor in
        let store = Store.shared
        let cases: [(String, String)] = [
            ("Hey Harshit, can you send the report to Srinivas about the Kubernetes migration by Friday", "Hey Harshith, can you send the report to Srinivas about the Kubernetes migration by Friday"),
            ("I think we should ship the new pricing page tomorrow morning", "I believe we ought to ship the new pricing page tomorrow morning"),
            ("Let's sync with priyanka on the contract terms before the call", "Let's sync with Priyanka on the contract terms before the call"),
            ("The deployment finished and the dashboards look healthy today", "Notes: The deployment finished and the dashboards look healthy today. Unrelated text here."),
        ]
        for (ins, cur) in cases {
            let c = Learner.corrections(inserted: ins, current: cur)
            let ok = c.filter { Learner.isLearnable(from: $0.from, to: $0.to, store: store) }
            print("pairs=\(c.map { "\($0.from)->\($0.to)" })  learnable=\(ok.map { "\($0.from)->\($0.to)" })")
        }
        exit(0)
    }
    RunLoop.main.run()
}
if let i = CommandLine.arguments.firstIndex(of: "--eval"), i + 1 < CommandLine.arguments.count {
    Prefs.register()
    if i + 2 < CommandLine.arguments.count { UserDefaults.standard.set(CommandLine.arguments[i + 2], forKey: K.provider) }
    if i + 3 < CommandLine.arguments.count { UserDefaults.standard.set(CommandLine.arguments[i + 3], forKey: K.ollamaModel) }
    Task { @MainActor in await Eval.run(path: CommandLine.arguments[i + 1]); exit(0) }
    RunLoop.main.run()
}
if let i = CommandLine.arguments.firstIndex(of: "--polish"), i + 1 < CommandLine.arguments.count {
    Prefs.register()
    let text = CommandLine.arguments[i + 1]
    if i + 2 < CommandLine.arguments.count { UserDefaults.standard.set(CommandLine.arguments[i + 2], forKey: K.provider) }
    if i + 3 < CommandLine.arguments.count { UserDefaults.standard.set(CommandLine.arguments[i + 3], forKey: K.ollamaModel) }
    Task { @MainActor in
        let t0 = Date()
        let e = await LLM.resolve()
        let rule = TextProcessor.process(text, store: Store.shared, backtrack: e == nil)
        let out = (try? await LLM.polish(rule, ctx: TextContext(app: "Notes", bundle: "com.apple.Notes"), hints: [])) ?? nil
        print("ENGINE: \(e?.rawValue ?? "none")  (\(String(format: "%.2f", Date().timeIntervalSince(t0)))s)\nOUT:\n\(out ?? "<rejected/none>")")
        exit(0)
    }
    RunLoop.main.run()
}
if let i = CommandLine.arguments.firstIndex(of: "--selftest"), i + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[i + 1]
    Prefs.register()
    Task { @MainActor in
        let t = Transcriber()
        t.load(variant: Prefs.model)
        while !t.ready { if t.status.hasPrefix("Model error") { print(t.status); exit(1) }; try? await Task.sleep(nanoseconds: 1_000_000_000); print(t.status) }
        let wavData = try? Data(contentsOf: URL(fileURLWithPath: path))
        if let wavData, wavData.count > 44 + 96000 {
            let pcm = wavData.dropFirst(44); let n = 48000
            var f = [Float](); f.reserveCapacity(n)
            pcm.withUnsafeBytes { (b: UnsafeRawBufferPointer) in let p = b.bindMemory(to: Int16.self); for i in 0..<min(n, p.count) { f.append(Float(p[i]) / 32768) } }
            let tp = Date()
            let partial = await t.transcribePartial(f, language: nil)
            print("PARTIAL first 3s: \(partial ?? "nil")  (\(String(format: "%.2f", Date().timeIntervalSince(tp)))s)")
        }
        if let wavData, wavData.count > 44 {
            var all = [Float](); wavData.dropFirst(44).withUnsafeBytes { (b: UnsafeRawBufferPointer) in let p = b.bindMemory(to: Int16.self); all = (0..<p.count).map { Float(p[$0]) / 32768 } }
            let plain = try await t.transcribe(all, language: nil, hints: [])
            print("NO HINTS : [\(plain)]")
            for h in [["Whisper", "Flow", "Mac", "application"], ["Claude", "Slack", "Confluent"], ["Custom Whisper Flow Mac application"]] {
                let r = try await t.transcribe(all, language: nil, hints: h)
                print("HINTS \(h): [\(r)]")
            }
        }
        let t0 = Date()
        let raw = try await t.transcribeFile(path)
        print("RAW: \(raw)  (\(String(format: "%.2f", Date().timeIntervalSince(t0)))s)")
        let eng = await LLM.resolve()
        let rule = TextProcessor.process(raw, store: Store.shared, backtrack: eng == nil)
        print("RULES: \(rule)")
        let t1 = Date()
        let ai = (try? await LLM.polish(rule, ctx: TextContext(app: "Notes", bundle: "com.apple.Notes"), hints: [])) ?? nil
        print("FINAL (\(eng?.rawValue ?? "no engine"), \(String(format: "%.2f", Date().timeIntervalSince(t1)))s):\n\(ai ?? rule)")
        exit(0)
    }
    RunLoop.main.run()
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
