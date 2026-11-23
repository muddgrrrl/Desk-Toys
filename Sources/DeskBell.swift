import AppKit
import Carbon
import SwiftUI

private enum BellTone: String, CaseIterable, Identifiable {
    case glass, pop, funk

    var id: Self { self }
    var title: String {
        switch self {
        case .glass: "Glass"
        case .pop: "Pop"
        case .funk: "Funk"
        }
    }
    var message: String {
        switch self {
        case .glass: "Ding!"
        case .pop: "Pop!"
        case .funk: "Ta-da!"
        }
    }
    var symbol: String {
        switch self {
        case .glass: "bell.fill"
        case .pop: "burst.fill"
        case .funk: "sparkles"
        }
    }
}

private final class BellSettings: ObservableObject {
    @Published var tone: BellTone {
        didSet { defaults.set(tone.rawValue, forKey: "tone") }
    }
    @Published var showFlash: Bool {
        didSet { defaults.set(showFlash, forKey: "showFlash") }
    }
    @Published var playSound: Bool {
        didSet { defaults.set(playSound, forKey: "playSound") }
    }
    @Published var hotKeyReady = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tone = BellTone(rawValue: defaults.string(forKey: "tone") ?? "") ?? .glass
        showFlash = defaults.object(forKey: "showFlash") as? Bool ?? true
        playSound = defaults.object(forKey: "playSound") as? Bool ?? true
    }
}

private struct BellControls: View {
    @ObservedObject var settings: BellSettings
    let ring: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DeskHeader(title: "Desk Bell", detail: "A little punctuation for your desktop.", symbol: "bell.fill", accent: DeskColor.rose)
            VStack(alignment: .leading, spacing: 14) {
                Picker("Tone", selection: $settings.tone) {
                    ForEach(BellTone.allCases) { tone in Text(tone.title).tag(tone) }
                }
                .pickerStyle(.segmented)
                Toggle("Play sound", isOn: $settings.playSound)
                Toggle("Show desktop flash", isOn: $settings.showFlash)
            }
            .padding(15)
            .background(DeskColor.card, in: RoundedRectangle(cornerRadius: 14))
            HStack {
                Text(settings.hotKeyReady ? "Control–Option–B" : "Shortcut unavailable")
                    .font(.callout).foregroundStyle(DeskColor.gray)
                Spacer()
                Button("Ring the bell", action: ring)
                    .buttonStyle(.borderedProminent)
                    .disabled(!settings.showFlash && !settings.playSound)
            }
        }
        .deskWindow(accent: DeskColor.rose)
        .frame(width: 420)
    }
}

private struct BellFlash: View {
    let tone: BellTone

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: tone.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(DeskColor.rose)
            Text(tone.message)
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 236, height: 76)
        .background(DeskColor.ink, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(DeskColor.rose.opacity(0.55), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private final class BellApp: DeskApp {
    private let settings = BellSettings()
    private var shortcut: DeskHotKey?
    private var flash: NSPanel?
    private var hideFlash: DispatchWorkItem?

    init() { super.init(name: "Desk Bell", symbol: "bell") }

    override func start() {
        let key = DeskHotKey(code: UInt32(kVK_ANSI_B)) { [weak self] in self?.ring() }
        settings.hotKeyReady = key.registered
        shortcut = key
    }

    override func makeContent() -> AnyView { AnyView(BellControls(settings: settings, ring: ring)) }

    override func populate(_ menu: NSMenu) {
        add("Ring the Bell", to: menu, action: #selector(ring), key: "r")
        add("Settings…", to: menu, action: #selector(openWindow), key: ",")
    }

    @objc private func ring() {
        let tone = settings.tone
        if settings.playSound { LocalSound.play(tone.title) }
        guard settings.showFlash else { return }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        hideFlash?.cancel()
        flash?.orderOut(nil)
        let visible = screen.visibleFrame
        let panel = NSPanel(
            contentRect: NSRect(x: visible.midX - 118, y: visible.maxY - 104, width: 236, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.contentView = NSHostingView(rootView: BellFlash(tone: tone))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.orderFrontRegardless()
        flash = panel
        let hide = DispatchWorkItem { [weak self, weak panel] in
            panel?.orderOut(nil)
            if self?.flash === panel { self?.flash = nil }
        }
        hideFlash = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: hide)
    }
}

@main
struct DeskBell {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            let name = "desk-bell-test-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let settings = BellSettings(defaults: defaults)
            precondition(settings.tone == .glass && settings.showFlash && settings.playSound)
            settings.tone = .funk
            settings.showFlash = false
            settings.playSound = false
            let restored = BellSettings(defaults: defaults)
            precondition(restored.tone == .funk && !restored.showFlash && !restored.playSound)
            precondition(BellTone.allCases.allSatisfy { NSSound(named: NSSound.Name($0.title)) != nil })
            print("PASS: sound assets and preferences")
            return
        }
        run(BellApp())
    }
}
