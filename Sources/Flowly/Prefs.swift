import Foundation
import AppKit

enum K {
    static let hotkey = "hotkey", cmdHotkey = "cmdHotkey", model = "model", language = "language"
    static let polish = "polish", provider = "provider", llmModel = "llmModel", ollamaModel = "ollamaModel"
    static let sounds = "sounds", mic = "mic", restoreClipboard = "restoreClipboard"
    static let removeFillers = "removeFillers", autoCap = "autoCap", contextAware = "contextAware"
    static let saveHistory = "saveHistory", pressEnter = "pressEnter"
}

enum HotKey: String, CaseIterable, Identifiable {
    case fn, rightOption, rightCommand, rightControl, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fn: return "Fn (🌐)"
        case .rightOption: return "Right Option ⌥"
        case .rightCommand: return "Right Command ⌘"
        case .rightControl: return "Right Control ⌃"
        case .none: return "Disabled"
        }
    }
    var keyCode: Int64 {
        switch self { case .fn: return 63; case .rightOption: return 61; case .rightCommand: return 54; case .rightControl: return 62; case .none: return -1 }
    }
    var flag: CGEventFlags {
        switch self { case .fn: return .maskSecondaryFn; case .rightOption: return .maskAlternate; case .rightCommand: return .maskCommand; case .rightControl: return .maskControl; case .none: return [] }
    }
}

struct ModelOption: Identifiable {
    let id: String, name: String, size: String, note: String
    static let all: [ModelOption] = [
        .init(id: "large-v3-v20240930_turbo_632MB", name: "Large v3 Turbo", size: "~630 MB", note: "Best speed/accuracy balance. Recommended for Macs with 16 GB+ RAM."),
        .init(id: "small_216MB", name: "Small", size: "~220 MB", note: "Good accuracy, light on memory. Great for 8 GB Macs."),
        .init(id: "base", name: "Base", size: "~140 MB", note: "Fastest, lowest accuracy."),
        .init(id: "large-v3-v20240930_626MB", name: "Large v3 (full)", size: "~630 MB", note: "Highest accuracy, slower than Turbo."),
    ]
    static var recommended: String {
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return gb >= 15 ? all[0].id : all[1].id
    }
}

let languages: [(code: String, name: String)] = [
    ("auto", "Auto-detect"), ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"),
    ("pt", "Portuguese"), ("nl", "Dutch"), ("hi", "Hindi"), ("te", "Telugu"), ("ta", "Tamil"), ("ja", "Japanese"),
    ("ko", "Korean"), ("zh", "Chinese"), ("ru", "Russian"), ("ar", "Arabic"), ("tr", "Turkish"), ("pl", "Polish"), ("sv", "Swedish"), ("uk", "Ukrainian"),
]

enum Prefs {
    static let d = UserDefaults.standard
    static func register() {
        d.register(defaults: [
            K.hotkey: HotKey.fn.rawValue, K.cmdHotkey: HotKey.rightOption.rawValue, K.model: ModelOption.recommended,
            K.language: "auto", K.polish: true, K.provider: "auto", "style": "natural", K.llmModel: "claude-haiku-5-5",
            K.ollamaModel: "qwen3.5:4b", K.sounds: true, K.mic: "", K.restoreClipboard: true,
            K.removeFillers: true, "useContext": true, "livePreview": true, "autoLearn": true, K.autoCap: true, K.contextAware: true, K.saveHistory: true, K.pressEnter: false,
        ])
    }
    static var hotkey: HotKey { HotKey(rawValue: d.string(forKey: K.hotkey) ?? "") ?? .fn }
    static var cmdHotkey: HotKey { HotKey(rawValue: d.string(forKey: K.cmdHotkey) ?? "") ?? .none }
    static var model: String { d.string(forKey: K.model) ?? ModelOption.recommended }
    static var language: String? { let l = d.string(forKey: K.language) ?? "auto"; return l == "auto" ? nil : l }
    static var polish: Bool { d.bool(forKey: K.polish) }
    static var sounds: Bool { d.bool(forKey: K.sounds) }
    static var restoreClipboard: Bool { d.bool(forKey: K.restoreClipboard) }
    static var removeFillers: Bool { d.bool(forKey: K.removeFillers) }
    static var autoCap: Bool { d.bool(forKey: K.autoCap) }
    static var contextAware: Bool { d.bool(forKey: K.contextAware) }
    static var saveHistory: Bool { d.bool(forKey: K.saveHistory) }
    static var pressEnter: Bool { d.bool(forKey: K.pressEnter) }
    static var provider: String { d.string(forKey: K.provider) ?? "auto" }
    static var llmModel: String { d.string(forKey: K.llmModel) ?? "claude-haiku-5-5" }
    static var ollamaModel: String { d.string(forKey: K.ollamaModel) ?? "qwen3.5:4b" }
    static var mic: String { d.string(forKey: K.mic) ?? "" }
}

enum Keychain {
    static let service = "com.flowly.app"
    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func set(_ account: String, _ value: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty else { return }
        var n = q; n[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(n as CFDictionary, nil)
    }
}
