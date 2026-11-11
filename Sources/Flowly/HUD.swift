import SwiftUI
import AppKit

@MainActor
final class HUDModel: ObservableObject {
    enum Phase { case recording(command: Bool, latched: Bool), processing(String), message(String, error: Bool) }
    @Published var phase: Phase = .processing("")
    @Published var levels: [Float] = Array(repeating: 0, count: 26)
    @Published var live = ""
    func push(_ l: Float) { levels.removeFirst(); levels.append(l) }
}

struct HUDView: View {
    @ObservedObject var m: HUDModel
    var body: some View {
        HStack(spacing: 10) {
            switch m.phase {
            case .recording(let cmd, let latched):
                VStack(alignment: .leading, spacing: 8) {
                    if !m.live.isEmpty {
                        Text(m.live).font(.system(size: 13)).foregroundStyle(.white.opacity(0.92)).lineLimit(3).multilineTextAlignment(.leading)
                            .frame(width: 440, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: cmd ? "wand.and.stars" : "mic.fill").foregroundStyle(cmd ? .purple : .red).font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 2.5) {
                            ForEach(0..<m.levels.count, id: \.self) { i in
                                Capsule().fill(LinearGradient(colors: [T.accent, T.pink], startPoint: .bottom, endPoint: .top)).frame(width: 3, height: 4 + CGFloat(m.levels[i]) * 22)
                            }
                        }.frame(height: 26).animation(.easeOut(duration: 0.08), value: m.levels)
                        if latched { Text("esc to cancel").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)) }
                    }
                }
            case .processing(let s):
                ProgressView().controlSize(.small).tint(.white)
                Text(s.isEmpty ? "Transcribing…" : s).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            case .message(let s, let err):
                Image(systemName: err ? "exclamationmark.triangle.fill" : "checkmark.circle.fill").foregroundStyle(err ? .orange : .green)
                Text(s).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0x141318).opacity(0.94)).overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.14))))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        .fixedSize()
        .frame(width: 580, height: 170, alignment: .bottom) // fixed canvas: pill can grow without being clipped
        .padding(.bottom, 14)
    }
}

@MainActor
final class HUD {
    let model = HUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    private func ensure() -> NSPanel {
        if let p = panel { return p }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 184), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]; p.ignoresMouseEvents = true
        let host = NSHostingView(rootView: HUDView(m: model)); host.frame = NSRect(x: 0, y: 0, width: 580, height: 184)
        p.contentView = host; panel = p; return p
    }
    func show(_ phase: HUDModel.Phase, autoHide: TimeInterval? = nil) {
        hideTask?.cancel()
        model.phase = phase
        if case .recording = phase {} else { model.live = "" }
        let p = ensure()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
        let f = screen.visibleFrame
        p.setFrameOrigin(NSPoint(x: f.midX - p.frame.width / 2, y: f.minY))
        p.orderFrontRegardless()
        if let t = autoHide { hideTask = Task { try? await Task.sleep(nanoseconds: UInt64(t * 1e9)); if !Task.isCancelled { hide() } } }
    }
    func hide() { hideTask?.cancel(); panel?.orderOut(nil) }
}
