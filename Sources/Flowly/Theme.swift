import SwiftUI
import AppKit

extension Color {
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}

enum T {
    static let bg = Color(light: Color(hex: 0xFBF9F6), dark: Color(hex: 0x19181C))
    static let sidebar = Color(light: Color(hex: 0xF2EEE8), dark: Color(hex: 0x201F24))
    static let card = Color(light: .white, dark: Color(hex: 0x27262C))
    static let stroke = Color(light: Color.black.opacity(0.07), dark: Color.white.opacity(0.08))
    static let hover = Color(light: Color.black.opacity(0.035), dark: Color.white.opacity(0.05))
    static let ink = Color(light: Color(hex: 0x1D1B20), dark: Color(hex: 0xF3F1F5))
    static let sub = Color(light: Color(hex: 0x77737C), dark: Color(hex: 0x9F9BA6))
    static let accent = Color(hex: 0x6D5DF6)
    static let pink = Color(hex: 0xEE4D9D)
    static let green = Color(hex: 0x2FB67C)
    static let amber = Color(hex: 0xF0A23B)
    static let gradient = LinearGradient(colors: [accent, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct Card<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(T.stroke))
            .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
    }
}

struct PageHeader: View {
    let title: String, subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(T.ink)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(T.sub)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(T.sub).padding(.leading, 4) }
}

/// A group of rows in one card, divided by hairlines.
struct Group2<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            Card { VStack(spacing: 0) { content } }
        }
    }
}

struct Row<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var divider = true
    @ViewBuilder var control: Control
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundStyle(T.accent).frame(width: 28, height: 28)
                    .background(T.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(T.ink)
                    if let s = subtitle { Text(s).font(.system(size: 12)).foregroundStyle(T.sub).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 12)
                control
            }.padding(.horizontal, 16).padding(.vertical, 12)
            if divider { Rectangle().fill(T.stroke).frame(height: 1).padding(.leading, 16) }
        }
    }
}

struct KeyCap: View {
    let label: String
    var body: some View {
        Text(label).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(T.ink)
            .padding(.horizontal, 9).frame(minWidth: 28, minHeight: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(T.card))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(T.stroke.opacity(2)))
            .shadow(color: .black.opacity(0.12), radius: 0, y: 1.5)
    }
}
extension HotKey {
    var cap: String {
        switch self { case .fn: return "fn"; case .rightOption: return "⌥ right"; case .rightCommand: return "⌘ right"; case .rightControl: return "⌃ right"; case .none: return "—" }
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(T.gradient)).opacity(c.isPressed ? 0.85 : 1).scaleEffect(c.isPressed ? 0.98 : 1)
    }
}
struct SoftButton: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 12.5, weight: .medium)).foregroundStyle(T.ink).padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(T.hover.opacity(c.isPressed ? 2 : 1.4))).overlay(Capsule().stroke(T.stroke))
    }
}

struct Badge: View {
    let text: String; var color: Color = T.accent
    var body: some View { Text(text).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(color).padding(.horizontal, 7).padding(.vertical, 2.5).background(color.opacity(0.14), in: Capsule()) }
}

struct EmptyState: View {
    let icon: String, title: String, text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(T.gradient).frame(width: 56, height: 56).background(T.accent.opacity(0.1), in: Circle())
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(T.ink)
            Text(text).font(.system(size: 13)).foregroundStyle(T.sub).multilineTextAlignment(.center).frame(maxWidth: 340)
        }.frame(maxWidth: .infinity).padding(.vertical, 36)
    }
}

struct FieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).font(.system(size: 13.5)).padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(T.hover)).overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(T.stroke))
    }
}

struct Logo: View {
    var size: CGFloat = 30
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(T.gradient)
            HStack(spacing: size * 0.06) {
                ForEach([0.22, 0.45, 0.7, 0.45, 0.22], id: \.self) { h in Capsule().fill(.white).frame(width: size * 0.07, height: size * h) }
            }
        }.frame(width: size, height: size)
    }
}
