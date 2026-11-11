import Foundation
import AppKit
import AVFoundation
import ServiceManagement

@MainActor
final class Controller: ObservableObject {
    static let shared = Controller()
    let recorder = AudioRecorder()
    let transcriber = Transcriber()
    let hud = HUD()
    let hotkeys = HotkeyManager()
    let store = Store.shared
    @Published var recording = false
    @Published var hotkeyActive = false
    @Published var lastText = ""
    @Published var lastRaw = ""
    var onRecordingChange: ((Bool) -> Void)?
    private var mode: DictationMode = .dictate
    private var ctxTask: Task<TextContext, Never>?
    private var liveTask: Task<Void, Never>?
    private var chain: Task<Void, Never>?   // dictations are processed strictly in order

    func boot() {
        transcriber.load(variant: Prefs.model)
        Task.detached { await LLM.prewarm() }
        recorder.onLevel = { [weak self] l in DispatchQueue.main.async { self?.hud.model.push(l) } }
        hotkeys.isActive = { [weak self] in self?.recording ?? false }
        hotkeys.onStart = { [weak self] m in self?.begin(m) }
        hotkeys.onStop = { [weak self] in self?.finish() }
        hotkeys.onCancel = { [weak self] in self?.cancel() }
        startHotkeys()
    }
    func startHotkeys() {
        if !Inserter.trusted { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary) }
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        hotkeyActive = hotkeys.start()
        if !hotkeyActive {
            Task { for _ in 0..<600 { try? await Task.sleep(nanoseconds: 2_000_000_000); if self.hotkeys.start() { self.hotkeyActive = true; break } } }
        }
    }

    private func beep(_ n: String) { if Prefs.sounds { NSSound(named: n)?.play() } }

    func begin(_ m: DictationMode) {
        guard !recording else { return }
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            hud.show(.message("Allow microphone access, then try again", error: true), autoHide: 3); hotkeys.reset(); return
        }
        mode = m
        ctxTask = Task.detached { ContextReader.capture() } // snapshot of where you're typing, read off the main thread (Accessibility can be slow in some apps)
        hud.model.live = ""
        do { try recorder.start() } catch { hud.show(.message(error.localizedDescription, error: true), autoHide: 3); hotkeys.reset(); return }
        recording = true; onRecordingChange?(true); beep("Tink")
        hud.show(.recording(command: m == .command, latched: false))
        startLive()
        Task { try? await Task.sleep(nanoseconds: 700_000_000); if self.recording { self.hud.model.phase = .recording(command: m == .command, latched: true) } }
    }

    /// Live preview: re-transcribes the most recent audio every moment while you speak and shows it in the HUD.
    private func startLive() {
        liveTask?.cancel()
        guard UserDefaults.standard.bool(forKey: "livePreview") else { return }
        liveTask = Task { [weak self] in
            var lastTotal = 0
            while let self, !Task.isCancelled, self.recording {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled, self.recording, self.transcriber.ready else { continue }
                let snap = self.recorder.snapshot(lastSeconds: 18)
                guard snap.total - lastTotal > 9600, AudioRecorder.rms(snap.samples) > 0.003 else { continue }
                lastTotal = snap.total
                if let t = await self.transcriber.transcribePartial(snap.samples, language: Prefs.language), !Task.isCancelled, self.recording,
                   !TextProcessor.isHallucination(t) {
                    let tail = t.count > 150 ? "…" + t.suffix(150) : t
                    self.hud.model.live = tail
                }
            }
        }
    }

    func cancel() {
        guard recording else { return }
        liveTask?.cancel()
        _ = recorder.stop(); recording = false; onRecordingChange?(false)
        hud.hide(); beep("Basso")
    }

    func finish() {
        guard recording else { return }
        liveTask?.cancel()
        let samples = recorder.stop(); recording = false; onRecordingChange?(false); beep("Pop")
        let duration = Double(samples.count) / AudioRecorder.rate
        guard duration >= 0.4, AudioRecorder.rms(samples) > 0.003 else { dlog("dropped: too short/quiet (\(String(format: "%.2f", duration))s rms=\(AudioRecorder.rms(samples)))"); hud.hide(); return }
        let m = mode, ctxT = ctxTask
        hud.show(.processing(m == .command ? "Thinking…" : "Transcribing…"))
        let previous = chain
        chain = Task {
            // Dictations run in order, but one stuck job can never block the next for more than a few seconds.
            _ = try? await raceTimeout(4) { await previous?.value }
            var c = TextContext(app: NSWorkspace.shared.frontmostApplication?.localizedName ?? "", bundle: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
            if let ctxT, let got = try? await raceTimeout(1.0, { await ctxT.value }) { c = got }
            await process(samples, duration: duration, mode: m, ctx: c)
        }
    }

    func process(_ samples: [Float], duration: Double, mode: DictationMode, ctx: TextContext) async {
        do {
            // Never drop a dictation just because the model is still warming up — wait for it.
            if !transcriber.ready {
                hud.show(.processing("Loading speech model…"))
                for _ in 0..<80 where !transcriber.ready { try? await Task.sleep(nanoseconds: 500_000_000) }
                guard transcriber.ready else { hud.show(.message("Speech model isn't ready — see Model page", error: true), autoHide: 4); return }
                hud.show(.processing("Transcribing…"))
            }
            let hintWords = store.hintWords + (UserDefaults.standard.bool(forKey: "useContext") ? ctx.visibleTerms : [])
            let raw: String
            do { raw = try await raceTimeout(90) { try await self.transcriber.transcribe(samples, language: Prefs.language, hints: hintWords) } }
            catch is TimeoutError { dlog("transcription hung; reloading model"); transcriber.recover(); hud.show(.message("Transcription stalled — reloading the speech model", error: true), autoHide: 4); return }
            if TextProcessor.isHallucination(raw) { dlog("dropped: looks like silence/hallucination: [\(raw)]"); hud.hide(); return }
            lastRaw = raw
            dlog("stage: transcribed \(raw.count) chars")
            let wordCount = raw.split(whereSeparator: { $0.isWhitespace }).count
            let engine = await LLM.resolve()
            dlog("engine=\(engine?.rawValue ?? "none") provider=\(Prefs.provider) polishOn=\(Prefs.polish) words=\(wordCount)")
            let willPolish = mode == .dictate && Prefs.polish && wordCount >= 4 && engine != nil
            var text = TextProcessor.process(raw, store: store, backtrack: !willPolish && mode == .dictate)
            if text.isEmpty { dlog("dropped: empty after cleanup"); hud.hide(); return }
            var aiFallback = false

            if mode == .command {
                guard engine != nil else { hud.show(.message("Command Mode needs an AI engine — see AI & Style", error: true), autoHide: 3.5); return }
                let sel = await Inserter.selectedText()
                hud.show(.processing(sel.isEmpty ? "Writing…" : "Rewriting…"))
                let app = (name: ctx.app, bundle: ctx.bundle)
                text = try await raceTimeout(40) { try await LLM.command(instruction: raw, selection: sel, app: app) }
            } else if willPolish {
                hud.show(.processing("Polishing…"))
                do {
                    let hints = store.hintWords
                    let input = text
                    if let p = try await raceTimeout(LLM.warm ? 9 : 28, { try await LLM.polish(input, ctx: ctx, hints: hints) }) { text = p } else { aiFallback = true; dlog("polish: output rejected, using basic cleanup") }
                } catch { dlog("polish failed (\(error.localizedDescription)); inserting basic cleanup"); aiFallback = true }
            } else if mode == .dictate && Prefs.polish && wordCount >= 4 && engine == nil { aiFallback = true }

            // Typing straight after a word or period with no space? Add one.
            if mode == .dictate, UserDefaults.standard.bool(forKey: "useContext"), let last = ctx.before.last, let first = text.first,
               !last.isWhitespace, !"([{\"'“‘/-".contains(last), !first.isWhitespace, !".,;:!?)]}".contains(first) { text = " " + text }

            lastText = text
            if Prefs.saveHistory {
                let words = text.split { $0.isWhitespace }.count
                store.addHistory(HistoryItem(text: text, raw: raw, app: ctx.app, duration: duration, words: words))
            }
            dlog("stage: inserting \(text.count) chars (aiFallback=\(aiFallback))")
            hud.hide()
            await Inserter.insert(text, pressEnter: Prefs.pressEnter && mode == .dictate)
            lastText = text
            dlog("stage: inserted")
            if !Inserter.trusted { hud.show(.message("Copied — grant Accessibility to auto-paste", error: true), autoHide: 3) }
            else if aiFallback { hud.show(.message("AI unavailable — used basic cleanup", error: true), autoHide: 2.5) }
            if mode == .dictate { Learner.watch(inserted: text.trimmingCharacters(in: .whitespaces), store: store, hud: hud, isRecording: { [weak self] in self?.recording ?? false }) }
        } catch {
            dlog("process error: \(error.localizedDescription)")
            hud.show(.message(error.localizedDescription, error: true), autoHide: 4)
        }
    }

    func pasteLast() {
        let t = lastText.isEmpty ? (store.history.first?.text ?? "") : lastText
        guard !t.isEmpty else { return }
        Task { try? await Task.sleep(nanoseconds: 250_000_000); await Inserter.insert(t) }
    }
    /// Re-insert what Whisper originally heard, without any AI changes.
    func pasteOriginal() {
        let t = lastRaw.isEmpty ? (store.history.first?.raw ?? "") : lastRaw
        guard !t.isEmpty else { return }
        Task { try? await Task.sleep(nanoseconds: 250_000_000); await Inserter.insert(t) }
    }

    func setLaunchAtLogin(_ on: Bool) { do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {} }
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
}
