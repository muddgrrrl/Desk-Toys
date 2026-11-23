import AppKit
import Carbon
import SwiftUI

// Select the property wrapper when the SDK also declares a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

private struct Prompt: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var body: String
    var pinned = false

    static let starters = [
        Prompt(title: "Keep going", body: "Continue the current task. Check what is still incomplete, then take the next step.", pinned: true),
        Prompt(title: "Show me the changes", body: "Summarize what changed, how you verified it, and anything still open."),
        Prompt(title: "Explain the trade-offs", body: "Compare the practical options and call out the assumptions that would change your recommendation.")
    ]
}

private final class PromptShelf: ObservableObject {
    @Published private(set) var prompts: [Prompt]
    @Published var error: String?
    let accessible: Bool
    private let file: URL

    init(file: URL) {
        self.file = file
        do {
            let data = try Data(contentsOf: file)
            prompts = try JSONDecoder().decode([Prompt].self, from: data)
            accessible = true
        } catch let problem as CocoaError where problem.code == .fileReadNoSuchFile {
            prompts = Prompt.starters
            accessible = true
        } catch {
            prompts = []
            accessible = false
            self.error = "The saved prompts could not be read. Your saved file is still in Application Support/Prompt Pocket."
        }
    }

    static func local() -> PromptShelf {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return PromptShelf(file: support.appendingPathComponent("Prompt Pocket/prompts.json"))
    }

    func matching(_ query: String) -> [Prompt] {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = prompts.filter { prompt in
            words.isEmpty || prompt.title.localizedStandardContains(words) || prompt.body.localizedStandardContains(words)
        }
        return matches.filter(\.pinned) + matches.filter { !$0.pinned }
    }

    @discardableResult
    func upsert(_ prompt: Prompt) -> Bool {
        var updated = prompts
        if let index = updated.firstIndex(where: { $0.id == prompt.id }) {
            updated[index] = prompt
        } else {
            updated.insert(prompt, at: 0)
        }
        return save(updated)
    }

    func remove(_ prompt: Prompt) {
        _ = save(prompts.filter { $0.id != prompt.id })
    }

    func togglePin(_ prompt: Prompt) {
        var updated = prompt
        updated.pinned.toggle()
        upsert(updated)
    }

    private func save(_ updated: [Prompt]) -> Bool {
        guard accessible else { return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(updated).write(to: file, options: .atomic)
            prompts = updated
            return true
        } catch {
            self.error = "The change could not be saved. Check that Prompt Pocket can write to your Application Support folder."
            return false
        }
    }
}

private struct PromptEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState var prompt: Prompt
    let isNew: Bool
    let save: (Prompt) -> Bool
    @ViewState private var failed = false

    private var trimmedTitle: String { prompt.title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var ready: Bool {
        !trimmedTitle.isEmpty && !prompt.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Prompt" : "Edit Prompt").font(.title2.bold())
            TextField("Title", text: $prompt.title)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $prompt.body)
                .font(.body)
                .frame(minHeight: 152)
                .accessibilityLabel("Prompt text")
                .border(DeskColor.gray.opacity(0.25))
            if failed {
                Text("Couldn’t save the prompt. Your edits are still here.")
                    .foregroundStyle(DeskColor.rose)
            }
            HStack {
                Toggle("Pin to top", isOn: $prompt.pinned)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    prompt.title = trimmedTitle
                    if save(prompt) { dismiss() } else { failed = true }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!ready)
            }
        }
        .deskWindow(accent: DeskColor.blue)
        .frame(width: 440)
    }
}

private struct PocketControls: View {
    @ObservedObject var shelf: PromptShelf
    let shortcutReady: Bool
    @ViewState private var query = ""
    @ViewState private var editing: Prompt?
    @ViewState private var newPrompt = false
    @ViewState private var pendingDelete: Prompt?
    @ViewState private var copied: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DeskHeader(title: "Prompt Pocket", detail: "Copy the prompts you reach for most.", symbol: "text.quote", accent: DeskColor.blue)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(DeskColor.gray)
                TextField("Search prompts", text: $query)
                    .textFieldStyle(.plain)
                Button("New Prompt") {
                    newPrompt = true
                    editing = Prompt(title: "", body: "")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!shelf.accessible)
            }
            let items = shelf.matching(query)
            ScrollView {
                if items.isEmpty {
                    Text(shelf.accessible ? (query.isEmpty ? "Your pocket is empty." : "No matching prompts.") : "The saved prompts are unavailable.")
                        .foregroundStyle(DeskColor.gray)
                        .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { prompt in row(prompt) }
                    }
                }
            }
            .frame(height: 262)
            HStack {
                Text(shortcutReady ? "Control–Option–J opens the shelf" : "Open the shelf from the menu bar")
                Spacer()
                Text("\(items.count) \(items.count == 1 ? "prompt" : "prompts")")
            }
            .font(.callout)
            .foregroundStyle(DeskColor.gray)
        }
        .deskWindow(accent: DeskColor.blue)
        .frame(width: 540)
        .sheet(item: $editing) { prompt in
            PromptEditor(prompt: prompt, isNew: newPrompt, save: shelf.upsert)
        }
        .confirmationDialog("Delete this prompt?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { prompt in
            Button("Delete \(prompt.title)", role: .destructive) { shelf.remove(prompt) }
        }
        .alert("Prompt Pocket", isPresented: Binding(
            get: { shelf.error != nil }, set: { if !$0 { shelf.error = nil } }
        )) {
            Button("OK") { shelf.error = nil }
        } message: { Text(shelf.error ?? "") }
    }

    private func row(_ prompt: Prompt) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if prompt.pinned {
                        Image(systemName: "pin.fill").foregroundStyle(DeskColor.blue)
                            .accessibilityLabel("Pinned")
                    }
                    Text(prompt.title).fontWeight(.semibold).lineLimit(1)
                }
                Text(prompt.body).font(.callout).foregroundStyle(DeskColor.gray).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied == prompt.id ? "Copied" : "Copy") { copy(prompt) }
            Menu {
                Button("Edit…") {
                    newPrompt = false
                    editing = prompt
                }
                Button(prompt.pinned ? "Unpin" : "Pin") { shelf.togglePin(prompt) }
                Button("Delete…", role: .destructive) { pendingDelete = prompt }
            } label: {
                Image(systemName: "ellipsis.circle").accessibilityLabel("More actions for \(prompt.title)")
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(12)
        .background(DeskColor.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func copy(_ prompt: Prompt) {
        let clipboard = NSPasteboard.general
        clipboard.clearContents()
        if clipboard.setString(prompt.body, forType: .string) {
            copied = prompt.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                if copied == prompt.id { copied = nil }
            }
        } else {
            shelf.error = "Couldn’t write to the clipboard."
        }
    }
}

private final class PocketApp: DeskApp {
    private let shelf = PromptShelf.local()
    private var shortcut: DeskHotKey?

    init() { super.init(name: "Prompt Pocket", symbol: "text.quote") }

    override func start() {
        shortcut = DeskHotKey(code: UInt32(kVK_ANSI_J)) { [weak self] in self?.openWindow() }
    }

    override func makeContent() -> AnyView {
        AnyView(PocketControls(shelf: shelf, shortcutReady: shortcut?.registered == true))
    }

    override func populate(_ menu: NSMenu) {
        add("Open Prompt Shelf…", to: menu, action: #selector(openWindow), key: "o")
    }
}

@main
struct PromptPocket {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appendingPathComponent("prompts.json")
            let shelf = PromptShelf(file: file)
            precondition(shelf.accessible && shelf.matching("").count == 3)
            let example = Prompt(title: "Résumé", body: "Use bullets.")
            precondition(shelf.upsert(example) && shelf.matching("resume") == [example])
            shelf.togglePin(example)
            let reopened = PromptShelf(file: file)
            precondition(reopened.matching("").first?.id == example.id && reopened.matching("").first?.pinned == true)
            reopened.remove(example)
            precondition(PromptShelf(file: file).matching("Use bullets").isEmpty)
            let invalid = Data("unreadable".utf8)
            try! invalid.write(to: file)
            let corrupt = PromptShelf(file: file)
            precondition(!corrupt.accessible && !corrupt.upsert(example))
            precondition((try! Data(contentsOf: file)) == invalid)
            print("PASS: search, ordering, atomic persistence and corrupt-file handling")
            return
        }
        run(PocketApp())
    }
}
