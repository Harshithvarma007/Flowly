import SwiftUI
import Combine
import AVFoundation

enum Page: String, CaseIterable, Identifiable {
    case home = "Home", dictionary = "Dictionary", snippets = "Snippets", style = "AI & Style", model = "Model", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self { case .home: return "house"; case .dictionary: return "character.book.closed"; case .snippets: return "text.badge.plus"
        case .style: return "sparkles"; case .model: return "cpu"; case .settings: return "gearshape" }
    }
}

struct RootView: View {
    @AppStorage("onboardingDone") var done = false
    @State var page: Page = Page(rawValue: ProcessInfo.processInfo.environment["FLOWLY_PAGE"] ?? "") ?? .home
    var body: some View {
        Group {
            if !done { OnboardingView(finish: { withAnimation(.easeInOut(duration: 0.3)) { done = true } }) }
            else {
                HStack(spacing: 0) {
                    Sidebar(page: $page)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            switch page {
                            case .home: HomeView()
                            case .dictionary: DictionaryView()
                            case .snippets: SnippetsView()
                            case .style: AIView()
                            case .model: ModelView()
                            case .settings: GeneralView()
                            }
                        }.padding(.horizontal, 36).padding(.top, 44).padding(.bottom, 36).frame(maxWidth: 760).frame(maxWidth: .infinity)
                    }.background(T.bg)
                }
            }
        }.frame(minWidth: 900, minHeight: 640).background(T.bg).ignoresSafeArea()
    }
}

struct Sidebar: View {
    @Binding var page: Page
    @ObservedObject var t = Controller.shared.transcriber
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) { Logo(size: 30); Text("Flowly").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(T.ink) }
                .padding(.leading, 12).padding(.top, 42).padding(.bottom, 22)
            ForEach(Page.allCases.filter { $0 != .settings }) { p in NavItem(p: p, selected: page == p) { page = p } }
            Spacer()
            NavItem(p: .settings, selected: page == .settings) { page = .settings }
            HStack(spacing: 8) {
                if t.ready { Circle().fill(T.green).frame(width: 7, height: 7); Text("On-device · ready").font(.system(size: 11.5)).foregroundStyle(T.sub) }
                else { ProgressView().controlSize(.mini); Text(t.progress > 0 && t.progress < 1 ? "Downloading \(Int(t.progress * 100))%" : "Loading model…").font(.system(size: 11.5)).foregroundStyle(T.sub) }
            }.padding(.horizontal, 12).padding(.vertical, 10)
        }.padding(.horizontal, 12).padding(.bottom, 10).frame(width: 220).background(T.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(T.stroke).frame(width: 1) }
    }
}
struct NavItem: View {
    let p: Page, selected: Bool, action: () -> Void
    @State var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: p.icon).font(.system(size: 14, weight: .medium)).frame(width: 20).foregroundStyle(selected ? T.accent : T.sub)
                Text(p.rawValue).font(.system(size: 13.5, weight: selected ? .semibold : .medium)).foregroundStyle(selected ? T.ink : T.sub)
                Spacer()
            }.padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? T.card : (hover ? T.hover : .clear))
                    .shadow(color: .black.opacity(selected ? 0.06 : 0), radius: 3, y: 1))
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}

// MARK: Home
struct StatCard: View {
    let icon: String, value: String, label: String, tint: Color
    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint).frame(width: 28, height: 28).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(T.ink).contentTransition(.numericText())
                Text(label).font(.system(size: 12)).foregroundStyle(T.sub)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct HomeView: View {
    @ObservedObject var s = Store.shared
    @ObservedObject var c = Controller.shared
    @ObservedObject var t = Controller.shared.transcriber
    @State var q = ""
    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }
    var groups: [(Date, [HistoryItem])] {
        let items = q.isEmpty ? s.history : s.history.filter { $0.text.localizedCaseInsensitiveContains(q) }
        return Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.date) }.sorted { $0.key > $1.key }
    }
    func title(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "Today" }; if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).month().day())
    }
    var body: some View {
        PageHeader(title: "\(greeting) 👋", subtitle: "Speak naturally — Flowly turns it into polished text, anywhere you type.")
        if !c.hotkeyActive {
            Card(padding: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "lock.shield").font(.system(size: 20)).foregroundStyle(T.amber)
                    VStack(alignment: .leading, spacing: 2) { Text("Hold key blocked: allow Accessibility & Input Monitoring").font(.system(size: 14, weight: .semibold)).foregroundStyle(T.ink)
                        Text("Needed to detect your hotkey and type into other apps. If Flowly is already listed, remove it with “−” and add it again.").font(.system(size: 12.5)).foregroundStyle(T.sub) }
                    Spacer()
                    Button("Open System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }.buttonStyle(PrimaryButton())
                }
            }.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(T.amber.opacity(0.5)))
        } else {
            Card(padding: 18) {
                HStack(spacing: 16) {
                    Logo(size: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) { Text("Hold").foregroundStyle(T.sub); KeyCap(label: Prefs.hotkey.cap); Text("and speak. Release to insert.").foregroundStyle(T.sub) }.font(.system(size: 14))
                        HStack(spacing: 6) { Text("Select text, hold").foregroundStyle(T.sub); KeyCap(label: Prefs.cmdHotkey.cap); Text("to rewrite with your voice.").foregroundStyle(T.sub) }.font(.system(size: 12.5))
                    }
                    Spacer()
                    if !t.ready { VStack(alignment: .trailing, spacing: 4) { ProgressView(value: t.progress > 0 && t.progress < 1 ? t.progress : nil).frame(width: 120).tint(T.accent); Text(t.status).font(.system(size: 11)).foregroundStyle(T.sub).lineLimit(1) } }
                    else { Badge(text: "Ready", color: T.green) }
                }
            }
        }
        HStack(spacing: 14) {
            StatCard(icon: "text.word.spacing", value: "\(s.wordsToday)", label: "words today", tint: T.accent)
            StatCard(icon: "sum", value: "\(s.totalWords)", label: "total words", tint: T.pink)
            StatCard(icon: "gauge.with.needle", value: s.avgWPM == 0 ? "–" : "\(s.avgWPM)", label: "avg words per minute", tint: T.green)
        }
        HStack {
            SectionLabel(text: "Recent dictations"); Spacer()
            HStack(spacing: 6) { Image(systemName: "magnifyingglass").foregroundStyle(T.sub).font(.system(size: 12)); TextField("Search", text: $q).textFieldStyle(.plain).font(.system(size: 13)).frame(width: 150) }
                .padding(.horizontal, 10).padding(.vertical, 6).background(T.card, in: Capsule()).overlay(Capsule().stroke(T.stroke))
        }
        if groups.isEmpty {
            Card { EmptyState(icon: "waveform", title: q.isEmpty ? "Nothing here yet" : "No matches", text: q.isEmpty ? "Your dictations will show up here. Click into any text field and hold \(Prefs.hotkey.cap) to try it." : "Try a different search.") }
        } else {
            ForEach(groups, id: \.0) { day, items in
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: title(day))
                    Card { VStack(spacing: 0) { ForEach(Array(items.enumerated()), id: \.element.id) { i, h in
                        HistoryRow(h: h) { s.history.removeAll { $0.id == h.id } }
                        if i < items.count - 1 { Rectangle().fill(T.stroke).frame(height: 1).padding(.leading, 90) } } } }
                }
            }
        }
    }
}

struct HistoryRow: View {
    let h: HistoryItem; let onDelete: () -> Void
    @State var hover = false
    @State var copied = false
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(h.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 12).monospacedDigit()).foregroundStyle(T.sub).frame(width: 58, alignment: .leading).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(h.text).font(.system(size: 14)).lineSpacing(3).foregroundStyle(T.ink).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if !h.app.isEmpty { Text("\(h.app) · \(h.words) words").font(.system(size: 11)).foregroundStyle(T.sub) }
            }
            HStack(spacing: 4) {
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(h.text, forType: .string); copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false } } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc").foregroundStyle(copied ? T.green : T.sub) }
                Button(action: onDelete) { Image(systemName: "trash").foregroundStyle(T.sub) }
            }.buttonStyle(.plain).font(.system(size: 12.5)).opacity(hover ? 1 : 0)
        }.padding(.horizontal, 18).padding(.vertical, 13).background(hover ? T.hover : .clear).onHover { hover = $0 }
    }
}

// MARK: Dictionary & Snippets
struct DictionaryView: View {
    @ObservedObject var s = Store.shared
    var body: some View {
        HStack(alignment: .top) {
            PageHeader(title: "Dictionary", subtitle: "Teach Flowly your names, jargon and acronyms. Flowly also learns on its own: when you fix a word it typed, the correction shows up here as “Learned”.")
            Button { withAnimation { s.dictionary.insert(DictEntry(), at: 0) } } label: { Label("Add word", systemImage: "plus") }.buttonStyle(PrimaryButton())
        }
        if s.dictionary.isEmpty {
            Card { EmptyState(icon: "character.book.closed", title: "Your dictionary is empty", text: "Add names like “Kubernetes” or “Harshith”. Tip: set “heard as” to “harshit” to always fix that spelling.") }
        } else {
            Card { VStack(spacing: 0) {
                ForEach($s.dictionary) { $e in
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            TextField("Heard as (optional)", text: $e.spoken).textFieldStyle(FieldStyle())
                            Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.sub)
                            TextField("Written as", text: $e.written).textFieldStyle(FieldStyle())
                            if e.auto == true { Badge(text: "Learned", color: T.green) }
                            Button { withAnimation { s.dictionary.removeAll { $0.id == e.id } } } label: { Image(systemName: "trash").foregroundStyle(T.sub) }.buttonStyle(.plain)
                        }.padding(.horizontal, 16).padding(.vertical, 10)
                        if e.id != s.dictionary.last?.id { Rectangle().fill(T.stroke).frame(height: 1) }
                    }
                }
            } }
        }
    }
}

struct SnippetsView: View {
    @ObservedObject var s = Store.shared
    var body: some View {
        HStack(alignment: .top) {
            PageHeader(title: "Snippets", subtitle: "Say a short phrase, get the full text. Perfect for links, addresses, and replies you type all the time.")
            Button { withAnimation { s.snippets.insert(Snippet(), at: 0) } } label: { Label("Add snippet", systemImage: "plus") }.buttonStyle(PrimaryButton())
        }
        if s.snippets.isEmpty {
            Card { EmptyState(icon: "text.badge.plus", title: "No snippets yet", text: "Try “my calendar link” → your booking URL, or “sign off” → “Best regards, …”.") }
        } else {
            Card { VStack(spacing: 0) {
                ForEach($s.snippets) { $e in
                    VStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) { Text("When I say").font(.system(size: 11)).foregroundStyle(T.sub); TextField("my calendar link", text: $e.trigger).textFieldStyle(FieldStyle()) }.frame(width: 210)
                            VStack(alignment: .leading, spacing: 4) { Text("Type this").font(.system(size: 11)).foregroundStyle(T.sub); TextField("https://…", text: $e.text, axis: .vertical).lineLimit(1...6).textFieldStyle(FieldStyle()) }
                            Button { withAnimation { s.snippets.removeAll { $0.id == e.id } } } label: { Image(systemName: "trash").foregroundStyle(T.sub) }.buttonStyle(.plain).padding(.top, 22)
                        }.padding(.horizontal, 16).padding(.vertical, 12)
                        if e.id != s.snippets.last?.id { Rectangle().fill(T.stroke).frame(height: 1) }
                    }
                }
            } }
        }
    }
}

// MARK: AI
struct AIView: View {
    @AppStorage("useContext") var useContext = true
    @AppStorage("livePreview") var livePreview = true
    @AppStorage("autoLearn") var autoLearn = true
    @AppStorage(K.polish) var polish = true
    @AppStorage(K.provider) var provider = "auto"
    @AppStorage(K.llmModel) var llmModel = "claude-haiku-5-5"
    @AppStorage(K.ollamaModel) var ollamaModel = "qwen3.5:4b"
    @AppStorage(K.contextAware) var ctx = true
    @AppStorage("style") var style = "natural"
    @State var key = Keychain.get("anthropic") ?? ""
    @State var installed: [String] = []
    @State var active: Engine? = nil
    @State var testing = false
    @State var testOut = ""
    func sw(_ b: Binding<Bool>) -> some View { Toggle("", isOn: b).labelsHidden().toggleStyle(.switch).tint(T.accent) }
    func refresh() { Task { installed = await LLM.ollamaModels(); active = await LLM.resolve() } }
    var body: some View {
        PageHeader(title: "AI & Style", subtitle: "Flowly turns messy speech into clean, structured writing: fillers gone, self-corrections applied, lists and paragraphs formatted. It runs on a local model by default.").task { refresh() }
        Card(padding: 16) {
            HStack(spacing: 12) {
                Circle().fill(active != nil ? T.green : T.amber).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(active.map { "Active engine: \($0.label)" } ?? "No AI engine available").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(T.ink)
                    Text(active == nil ? "Install Ollama and run “ollama pull qwen3.5:4b”, or add a Claude API key below. Until then Flowly uses basic rule-based cleanup." : "Your dictation never leaves this Mac unless you choose Claude API.").font(.system(size: 12)).foregroundStyle(T.sub)
                }
                Spacer()
                Button("Refresh") { refresh() }.buttonStyle(SoftButton())
            }
        }
        Group2(title: "Cleanup") {
            Row(title: "AI cleanup & structure", subtitle: "Fixes grammar, applies self-corrections, formats lists and paragraphs, writes numbers and emails properly.", icon: "wand.and.stars") { sw($polish) }
            Row(title: "Writing style", icon: "textformat.size") {
                Picker("", selection: $style) { Text("Natural").tag("natural"); Text("Professional").tag("professional"); Text("Casual").tag("casual"); Text("Concise").tag("concise") }.labelsHidden().frame(width: 150) }
            Row(title: "Match tone to the app", subtitle: "Casual in Slack, polished in Mail, precise in Xcode.", icon: "app.badge", divider: false) { sw($ctx) }
        }
        Group2(title: "Smart features") {
            Row(title: "Live preview while you speak", subtitle: "Shows your words in the overlay as you talk.", icon: "text.bubble") { sw($livePreview) }
            Row(title: "Use cursor & screen context", subtitle: "Reads the text near your cursor (never password fields) so cleanup continues sentences correctly and spells names right. Local engines only.", icon: "text.cursor") { sw($useContext) }
            Row(title: "Learn from my corrections", subtitle: "When you fix a word Flowly typed, it's added to your dictionary.", icon: "graduationcap", divider: false) { sw($autoLearn) }
        }
        Group2(title: "Engine") {
            Row(title: "Use", subtitle: "Automatic prefers Ollama, then Apple Intelligence, then Claude.", icon: "server.rack", divider: provider == "ollama" || provider == "anthropic") {
                Picker("", selection: $provider) {
                    Text("Automatic").tag("auto"); Text("Ollama (local)").tag("ollama")
                    if LLM.appleAvailable { Text("Apple Intelligence").tag("apple") }
                    Text("Claude API").tag("anthropic")
                }.labelsHidden().frame(width: 190).onChange(of: provider) { _, _ in refresh() }
            }
            if provider == "ollama" || provider == "auto" {
                Row(title: "Ollama model", subtitle: installed.isEmpty ? "Ollama isn’t running or has no models." : "qwen3.5:4b gave the best cleanup in our tests.", icon: "cpu", divider: false) {
                    if installed.isEmpty { TextField("", text: $ollamaModel).textFieldStyle(FieldStyle()).frame(width: 200) }
                    else { Picker("", selection: $ollamaModel) { ForEach(installed, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 200) }
                }
            }
            if provider == "anthropic" {
                Row(title: "API key", subtitle: "Stored in your Keychain. Only text is sent, never audio.", icon: "key") { SecureField("sk-ant-…", text: $key).textFieldStyle(FieldStyle()).frame(width: 240).onChange(of: key) { _, v in Keychain.set("anthropic", v); refresh() } }
                Row(title: "Model", icon: "cpu", divider: false) { TextField("", text: $llmModel).textFieldStyle(FieldStyle()).frame(width: 240) }
            }
        }
        Group2(title: "Try it") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Runs a messy sample through your current engine.").font(.system(size: 12)).foregroundStyle(T.sub)
                HStack { Button(testing ? "Working…" : "Run sample") {
                    testing = true; testOut = ""
                    Task { let sample = "um so i wanted to follow up on the meeting we need to finalize three things first the budget second the hiring plan and third the launch date no wait the launch date is already set so just the budget and the hiring plan thanks"
                        let t0 = Date(); let r = try? await LLM.polish(sample, ctx: TextContext(), hints: [])
                        testOut = (r ?? nil) ?? "No engine available or the output was rejected."
                        testOut += "\n\n(\(String(format: "%.1f", Date().timeIntervalSince(t0)))s)"; testing = false }
                }.buttonStyle(PrimaryButton()).disabled(testing); Spacer() }
                if !testOut.isEmpty { Text(testOut).font(.system(size: 13)).foregroundStyle(T.ink).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(T.hover, in: RoundedRectangle(cornerRadius: 10)) }
            }.padding(16)
        }
        Card(padding: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "wand.and.stars").font(.system(size: 18)).foregroundStyle(T.gradient)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Command Mode").font(.system(size: 14, weight: .semibold)).foregroundStyle(T.ink)
                    Text("Select text, hold \(Prefs.cmdHotkey.cap), and say “make this friendlier” or “turn into bullet points”. With nothing selected, ask for new text: “write a short email declining the meeting”.")
                        .font(.system(size: 12.5)).foregroundStyle(T.sub).lineSpacing(2)
                }
            }
        }
    }
}

// MARK: Model
struct ModelView: View {
    @AppStorage(K.model) var model = ModelOption.recommended
    @ObservedObject var t = Controller.shared.transcriber
    var body: some View {
        PageHeader(title: "Speech model", subtitle: "Runs 100% on your Mac — your voice never leaves it. Bigger models are more accurate but use more memory.")
        VStack(spacing: 10) {
            ForEach(ModelOption.all) { m in
                let sel = model == m.id
                Button { model = m.id; t.load(variant: m.id) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: sel ? "checkmark.circle.fill" : "circle").font(.system(size: 18)).foregroundStyle(sel ? T.accent : T.sub.opacity(0.5))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) { Text(m.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(T.ink); Text(m.size).font(.system(size: 12)).foregroundStyle(T.sub)
                                if m.id == ModelOption.recommended { Badge(text: "Recommended for this Mac", color: T.green) } }
                            Text(m.note).font(.system(size: 12.5)).foregroundStyle(T.sub)
                        }
                        Spacer()
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.card))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(sel ? T.accent : T.stroke, lineWidth: sel ? 1.8 : 1))
            }
        }
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { if t.ready { Image(systemName: "checkmark.circle.fill").foregroundStyle(T.green) } else { ProgressView().controlSize(.small) }
                    Text(t.status).font(.system(size: 13, weight: .medium)).foregroundStyle(T.ink) }
                if !t.ready && t.progress > 0 && t.progress < 1 { ProgressView(value: t.progress).tint(T.accent) }
                Text("Downloaded once and stored in ~/Library/Application Support/Flowly/Models.").font(.system(size: 11.5)).foregroundStyle(T.sub)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Settings
struct PermStatus: View {
    let ok: Bool, action: () -> Void
    var body: some View { if ok { Badge(text: "Granted", color: T.green) } else { Button("Grant access", action: action).buttonStyle(SoftButton()) } }
}

struct GeneralView: View {
    @AppStorage(K.hotkey) var hotkey = HotKey.fn.rawValue
    @AppStorage(K.cmdHotkey) var cmd = HotKey.rightOption.rawValue
    @AppStorage(K.language) var lang = "auto"
    @AppStorage(K.mic) var mic = ""
    @AppStorage(K.sounds) var sounds = true
    @AppStorage(K.restoreClipboard) var restore = true
    @AppStorage(K.removeFillers) var fillers = true
    @AppStorage(K.autoCap) var cap = true
    @AppStorage(K.saveHistory) var hist = true
    @AppStorage(K.pressEnter) var enter = false
    @State var login = Controller.shared.launchAtLogin
    @State var devices = AudioDevices.inputs()
    @State var tick = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    func sw(_ b: Binding<Bool>) -> some View { Toggle("", isOn: b).labelsHidden().toggleStyle(.switch).tint(T.accent) }
    var body: some View {
        PageHeader(title: "Settings", subtitle: "Make Flowly work the way you do.")
        Group2(title: "Shortcuts") {
            Row(title: "Dictate", subtitle: "Hold to talk. Tap once for hands-free, tap again to finish. Esc cancels.", icon: "mic.fill") {
                HStack(spacing: 10) { KeyCap(label: (HotKey(rawValue: hotkey) ?? .fn).cap)
                    Picker("", selection: $hotkey) { ForEach(HotKey.allCases) { Text($0.label).tag($0.rawValue) } }.labelsHidden().frame(width: 150) }
            }
            Row(title: "Command Mode", subtitle: "Rewrite selected text, or write something new, with your voice.", icon: "wand.and.stars", divider: false) {
                HStack(spacing: 10) { KeyCap(label: (HotKey(rawValue: cmd) ?? .none).cap)
                    Picker("", selection: $cmd) { ForEach(HotKey.allCases) { Text($0.label).tag($0.rawValue) } }.labelsHidden().frame(width: 150) }
            }
        }
        Text("Tip: if Fn opens the emoji picker, set System Settings → Keyboard → “Press 🌐 key to” → Do Nothing.").font(.system(size: 12)).foregroundStyle(T.sub).padding(.leading, 4).padding(.top, -10)
        Group2(title: "Input") {
            Row(title: "Language", subtitle: "Auto-detect works for most speech; choose a language for the best accuracy.", icon: "globe") {
                Picker("", selection: $lang) { ForEach(languages, id: \.code) { Text($0.name).tag($0.code) } }.labelsHidden().frame(width: 170) }
            Row(title: "Microphone", icon: "mic.badge.plus", divider: false) {
                Picker("", selection: $mic) { Text("System default").tag(""); ForEach(devices) { Text($0.name).tag($0.uid) } }.labelsHidden().frame(width: 220) }
        }
        Group2(title: "Writing") {
            Row(title: "Remove filler words", subtitle: "Drops “um”, “uh” and stutters.", icon: "scissors") { sw($fillers) }
            Row(title: "Auto-capitalize", icon: "textformat") { sw($cap) }
            Row(title: "Press Return after inserting", subtitle: "Handy for chat apps and AI prompts.", icon: "return", divider: false) { sw($enter) }
        }
        Group2(title: "App") {
            Row(title: "Launch at login", icon: "power") { sw(Binding(get: { login }, set: { login = $0; Controller.shared.setLaunchAtLogin($0) })) }
            Row(title: "Sound cues", icon: "speaker.wave.2") { sw($sounds) }
            Row(title: "Restore clipboard after pasting", icon: "doc.on.clipboard") { sw($restore) }
            Row(title: "Keep history on this Mac", icon: "clock.arrow.circlepath", divider: false) { sw($hist) }
        }
        Group2(title: "Permissions") {
            let _ = tick
            Row(title: "Microphone", subtitle: "To hear you while the hotkey is held.", icon: "mic") { PermStatus(ok: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized) { AVCaptureDevice.requestAccess(for: .audio) { _ in } } }
            Row(title: "Accessibility", subtitle: "To detect the hotkey and type into other apps.", icon: "hand.raised") {
                PermStatus(ok: Inserter.trusted) { Controller.shared.startHotkeys(); NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) } }
            Row(title: "Input Monitoring", subtitle: "Lets macOS deliver your hold-to-talk key to Flowly.", icon: "keyboard", divider: false) {
                PermStatus(ok: CGPreflightListenEventAccess()) { _ = CGRequestListenEventAccess(); NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!) } }
        }.onReceive(timer) { _ in tick += 1 }
    }
}
