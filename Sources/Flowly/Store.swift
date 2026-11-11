import Foundation

struct DictEntry: Codable, Identifiable, Hashable { var id = UUID(); var spoken = ""; var written = ""; var auto: Bool? = nil }
struct Snippet: Codable, Identifiable, Hashable { var id = UUID(); var trigger = ""; var text = "" }
struct HistoryItem: Codable, Identifiable, Hashable {
    var id = UUID(); var date = Date(); var text = ""; var raw = ""; var app = ""; var duration: Double = 0; var words = 0
}
private struct Blob: Codable { var dictionary: [DictEntry] = []; var snippets: [Snippet] = []; var history: [HistoryItem] = [] }

@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    @Published var dictionary: [DictEntry] = [] { didSet { save() } }
    @Published var snippets: [Snippet] = [] { didSet { save() } }
    @Published var history: [HistoryItem] = [] { didSet { save() } }

    static var supportDir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Flowly")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private var url: URL { Store.supportDir.appendingPathComponent("store.json") }
    private var loading = true

    init() {
        if let d = try? Data(contentsOf: url), let b = try? JSONDecoder().decode(Blob.self, from: d) {
            dictionary = b.dictionary; snippets = b.snippets; history = b.history
        }
        loading = false
    }
    private func save() {
        guard !loading else { return }
        let b = Blob(dictionary: dictionary, snippets: snippets, history: Array(history.prefix(2000)))
        if let d = try? JSONEncoder().encode(b) { try? d.write(to: url, options: .atomic) }
    }
    func addHistory(_ h: HistoryItem) { history.insert(h, at: 0) }

    var totalWords: Int { history.reduce(0) { $0 + $1.words } }
    var wordsToday: Int { history.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.words } }
    var avgWPM: Int {
        let secs = history.reduce(0) { $0 + $1.duration }
        return secs > 5 ? Int(Double(totalWords) / (secs / 60)) : 0
    }
    var hintWords: [String] { dictionary.map { $0.written }.filter { !$0.isEmpty } }
}
