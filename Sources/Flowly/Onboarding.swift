import SwiftUI
import Combine
import AVFoundation

struct OnboardingView: View {
    let finish: () -> Void
    @State var step = Int(ProcessInfo.processInfo.environment["FLOWLY_STEP"] ?? "") ?? 0
    @State var tick = 0
    @State var tryText = ""
    @AppStorage(K.hotkey) var hotkey = HotKey.fn.rawValue
    @ObservedObject var t = Controller.shared.transcriber
    @ObservedObject var c = Controller.shared
    let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()
    var mic: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    var ax: Bool { Inserter.trusted }

    var body: some View {
        ZStack {
            T.bg
            Circle().fill(T.accent.opacity(0.10)).frame(width: 520).blur(radius: 90).offset(x: -260, y: -230)
            Circle().fill(T.pink.opacity(0.09)).frame(width: 480).blur(radius: 90).offset(x: 280, y: 250)
            VStack(spacing: 0) {
                Spacer(minLength: 30)
                Group {
                    switch step {
                    case 0: welcome
                    case 1: permissions
                    case 2: shortcut
                    default: tryIt
                    }
                }.frame(maxWidth: 520).transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                Spacer(minLength: 20)
                HStack(spacing: 7) { ForEach(0..<4) { i in Capsule().fill(i == step ? T.accent : T.sub.opacity(0.3)).frame(width: i == step ? 22 : 7, height: 7) } }.padding(.bottom, 28)
            }.padding(.horizontal, 40)
        }.onReceive(timer) { _ in tick += 1; if !c.hotkeyActive && ax { c.startHotkeys() } }
    }
    func go(_ n: Int) { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = n } }

    func heading(_ title: String, _ sub: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(T.ink).multilineTextAlignment(.center)
            Text(sub).font(.system(size: 15)).foregroundStyle(T.sub).multilineTextAlignment(.center).lineSpacing(3)
        }
    }

    var welcome: some View {
        VStack(spacing: 28) {
            Logo(size: 84).shadow(color: T.accent.opacity(0.35), radius: 24, y: 10)
            heading("Meet Flowly", "Talk instead of type. Hold a key, speak naturally, and polished text appears in any app — all processed privately on your Mac.")
            VStack(alignment: .leading, spacing: 12) {
                feature("lock.shield", "Private by default", "Speech recognition runs on-device. Audio never leaves your Mac.")
                feature("bolt.fill", "Fast and accurate", "Whisper large-v3 turbo, tuned for Apple Silicon.")
                feature("wand.and.stars", "Smart cleanup", "Fillers, false starts and “scratch that” handled for you.")
            }.padding(.top, 4)
            Button("Get started") { go(1) }.buttonStyle(PrimaryButton()).controlSize(.large).padding(.top, 6)
        }
    }
    func feature(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(T.accent).frame(width: 34, height: 34).background(T.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) { Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(T.ink); Text(text).font(.system(size: 12.5)).foregroundStyle(T.sub) }
        }
    }

    var permissions: some View {
        VStack(spacing: 26) {
            heading("Three quick permissions", "macOS needs your OK before Flowly can hear you and type for you.")
            Card { VStack(spacing: 0) {
                let _ = tick
                Row(title: "Microphone", subtitle: "Hear you while the hotkey is held", icon: "mic.fill") { PermStatus(ok: mic) { AVCaptureDevice.requestAccess(for: .audio) { _ in } } }
                Row(title: "Accessibility", subtitle: "Detect the hotkey and paste into other apps", icon: "hand.raised.fill") {
                    PermStatus(ok: ax) { c.startHotkeys(); NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) } }
                Row(title: "Input Monitoring", subtitle: "Lets macOS send your hold-to-talk key to Flowly", icon: "keyboard.fill", divider: false) {
                    PermStatus(ok: CGPreflightListenEventAccess()) { _ = CGRequestListenEventAccess(); NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!) } }
            } }
            Text("Switch Flowly on in each list. If it's already there from an older version, remove it with “−” and add it again.").font(.system(size: 12)).foregroundStyle(T.sub)
            HStack(spacing: 12) {
                Button("Back") { go(0) }.buttonStyle(SoftButton())
                Button(mic && ax && CGPreflightListenEventAccess() ? "Continue" : "Continue anyway") { go(2) }.buttonStyle(PrimaryButton())
            }
        }
    }

    var shortcut: some View {
        VStack(spacing: 26) {
            heading("Pick your shortcut", "Hold it to talk, release to insert. Tap quickly for hands-free mode.")
            HStack(spacing: 12) {
                ForEach([HotKey.fn, .rightOption, .rightCommand, .rightControl]) { k in
                    let sel = hotkey == k.rawValue
                    Button { hotkey = k.rawValue } label: {
                        VStack(spacing: 10) { KeyCap(label: k.cap).scaleEffect(1.15); Text(k.label.components(separatedBy: " ").first ?? "").font(.system(size: 11.5)).foregroundStyle(T.sub) }
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                    }.buttonStyle(.plain).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.card))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(sel ? T.accent : T.stroke, lineWidth: sel ? 2 : 1))
                }
            }
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) { if t.ready { Image(systemName: "checkmark.circle.fill").foregroundStyle(T.green) } else { ProgressView().controlSize(.small) }
                        Text(t.ready ? "Speech model ready" : t.status).font(.system(size: 13, weight: .medium)).foregroundStyle(T.ink) }
                    if !t.ready { ProgressView(value: t.progress > 0 && t.progress < 1 ? t.progress : nil).tint(T.accent)
                        Text("Downloading once (about \(ModelOption.all.first { $0.id == ModelOption.recommended }?.size ?? "")). You can keep going.").font(.system(size: 11.5)).foregroundStyle(T.sub) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                Button("Back") { go(1) }.buttonStyle(SoftButton())
                Button("Continue") { go(3) }.buttonStyle(PrimaryButton())
            }
        }
    }

    var tryIt: some View {
        VStack(spacing: 24) {
            heading("Try it out", "Click the box below, then hold \(HotKey(rawValue: hotkey)?.cap ?? "fn") and say something — like “Um, let's meet at three. Scratch that, make it four.”")
            ZStack(alignment: .topLeading) {
                TextEditor(text: $tryText).font(.system(size: 15)).scrollContentBackground(.hidden).padding(12).frame(height: 150)
                if tryText.isEmpty { Text("Your words will appear here…").font(.system(size: 15)).foregroundStyle(T.sub.opacity(0.7)).padding(.horizontal, 17).padding(.vertical, 20).allowsHitTesting(false) }
            }.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.card)).overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(T.accent.opacity(0.5), lineWidth: 1.5))
            if !c.hotkeyActive { Label("Hotkey not active yet — grant Accessibility on the previous step.", systemImage: "exclamationmark.triangle.fill").font(.system(size: 12.5)).foregroundStyle(T.amber) }
            HStack(spacing: 12) {
                Button("Back") { go(2) }.buttonStyle(SoftButton())
                Button(tryText.isEmpty ? "Skip for now" : "Finish") { finish() }.buttonStyle(PrimaryButton())
            }
        }
    }
}
