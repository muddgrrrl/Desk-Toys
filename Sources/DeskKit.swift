import AppKit
import Carbon
import SwiftUI

enum DeskColor {
    static let ink = Color(red: 0.075, green: 0.085, blue: 0.115)
    static let card = Color(red: 0.13, green: 0.145, blue: 0.19)
    static let gray = Color(red: 0.74, green: 0.76, blue: 0.81)
    static let rose = Color(red: 1, green: 0.62, blue: 0.71)
    static let lime = Color(red: 0.81, green: 0.91, blue: 0.58)
    static let blue = Color(red: 0.66, green: 0.79, blue: 1)
}

struct DeskHeader: View {
    let title: String
    let detail: String
    let symbol: String
    let accent: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 25, weight: .bold, design: .rounded))
                Text(detail).font(.callout).foregroundStyle(DeskColor.gray)
            }
            Spacer(minLength: 0)
        }
    }
}

extension View {
    func deskWindow(accent: Color) -> some View {
        self
            .padding(24)
            .foregroundStyle(.white)
            .background(DeskColor.ink)
            .preferredColorScheme(.dark)
            .tint(accent)
    }
}

class DeskApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem?
    private let menu = NSMenu()
    private let name: String
    private let symbol: String
    private var window: NSWindow?
    private let smokeTest: Bool

    init(name: String, symbol: String) {
        self.name = name
        self.symbol = symbol
        smokeTest = CommandLine.arguments.contains("--smoke-test")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let newItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        newItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: name)
        newItem.button?.imagePosition = .imageLeading
        newItem.button?.setAccessibilityLabel(name)
        newItem.button?.toolTip = name
        newItem.menu = menu
        menu.delegate = self
        item = newItem
        start()
        if smokeTest {
            openWindow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                guard window?.isVisible == true, item?.button?.image != nil else { exit(1) }
                print("PASS: \(name) menu bar item and window")
                NSApp.terminate(nil)
            }
        }
    }

    func start() {}
    func makeContent() -> AnyView { AnyView(EmptyView()) }
    func populate(_ menu: NSMenu) {}

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
    }

    func add(_ title: String, to menu: NSMenu, action: Selector, key: String = "") {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        menu.addItem(entry)
    }

    func setStatus(_ title: String, help: String) {
        guard let button = item?.button, button.toolTip != help else { return }
        button.title = title.isEmpty ? "" : " \(title)"
        button.toolTip = help
        button.setAccessibilityLabel(help)
    }

    @objc func openWindow() {
        if window == nil {
            let newWindow = NSWindow(contentViewController: NSHostingController(rootView: makeContent()))
            newWindow.title = name
            newWindow.styleMask = [.titled, .closable]
            newWindow.titlebarAppearsTransparent = true
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private var runningApp: DeskApp?

func run(_ delegate: DeskApp) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    runningApp = delegate
    app.delegate = runningApp
    app.run()
    runningApp = nil
}

final class DeskHotKey {
    private var key: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    var registered: Bool { key != nil && handler != nil }

    init(code: UInt32, action: @escaping () -> Void) {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let target = GetApplicationEventTarget()
        guard InstallEventHandler(target, { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<DeskHotKey>.fromOpaque(context).takeUnretainedValue().action()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler) == noErr else { return }

        let identifier = EventHotKeyID(signature: 0x44544F59, id: 1)
        RegisterEventHotKey(code, UInt32(controlKey | optionKey), identifier, target, 0, &key)
    }

    deinit {
        if let key { UnregisterEventHotKey(key) }
        if let handler { RemoveEventHandler(handler) }
    }
}

enum LocalSound {
    static func play(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}
