import AppKit
import SwiftUI

private struct FocusSession: Codable, Equatable {
    var minutes = 25
    var deadline: Date?
    var pausedSeconds: TimeInterval?

    var duration: TimeInterval { TimeInterval(minutes * 60) }
    var active: Bool { deadline != nil || pausedSeconds != nil }

    func remaining(at now: Date) -> TimeInterval {
        let remaining = deadline?.timeIntervalSince(now) ?? pausedSeconds ?? duration
        return max(0, min(duration, remaining))
    }

    mutating func start(at now: Date) {
        guard !active else { return }
        deadline = now.addingTimeInterval(duration)
    }

    mutating func pause(at now: Date) {
        guard deadline != nil, remaining(at: now) > 0 else { return }
        pausedSeconds = remaining(at: now)
        deadline = nil
    }

    mutating func resume(at now: Date) {
        guard let pausedSeconds else { return }
        deadline = now.addingTimeInterval(pausedSeconds)
        self.pausedSeconds = nil
    }

    mutating func reset() {
        deadline = nil
        pausedSeconds = nil
    }

    mutating func finishIfDue(at now: Date) -> Bool {
        guard let deadline, now >= deadline else { return false }
        reset()
        return true
    }

    var valid: Bool {
        guard (1...180).contains(minutes) else { return false }
        guard let pausedSeconds else { return true }
        return deadline == nil && pausedSeconds.isFinite && pausedSeconds > 0 && pausedSeconds <= duration
    }
}

private final class FocusClock: ObservableObject {
    @Published private(set) var session: FocusSession
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var finished = false
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: "soundEnabled") }
    }
    private let defaults: UserDefaults
    private var heartbeat: Timer?
    var onTick: (() -> Void)?
    var onFinish: (() -> Void)?

    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        let restored = defaults.data(forKey: "session").flatMap { try? JSONDecoder().decode(FocusSession.self, from: $0) }
        let initial = restored.flatMap { $0.valid ? $0 : nil } ?? FocusSession()
        session = initial
        remaining = initial.remaining(at: now)
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
    }

    var timeText: String {
        let seconds = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var status: String {
        if finished { return "Session complete" }
        if session.deadline != nil { return "Focusing" }
        if session.pausedSeconds != nil { return "Paused" }
        return "Ready to focus"
    }

    func startHeartbeat() {
        guard heartbeat == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
        tick()
    }

    func tick(at now: Date = Date()) {
        var current = session
        if current.finishIfDue(at: now) {
            finished = true
            save(current)
            onFinish?()
        }
        let seconds = finished ? 0 : session.remaining(at: now)
        if remaining != seconds { remaining = seconds }
        onTick?()
    }

    func setMinutes(_ minutes: Int) {
        guard !session.active, (1...180).contains(minutes) else { return }
        finished = false
        var current = session
        current.minutes = minutes
        save(current)
        tick()
    }

    func toggle() {
        let now = Date()
        tick(at: now)
        var current = session
        if current.deadline != nil {
            current.pause(at: now)
        } else if current.pausedSeconds != nil {
            current.resume(at: now)
        } else {
            finished = false
            current.start(at: now)
        }
        save(current)
        tick(at: now)
    }

    func reset() {
        var current = session
        current.reset()
        finished = false
        save(current)
        tick()
    }

    private func save(_ current: FocusSession) {
        guard current != session else { return }
        session = current
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: "session")
        }
    }

    deinit { heartbeat?.invalidate() }
}

private struct FocusControls: View {
    @ObservedObject var clock: FocusClock
    let presets = [5, 15, 25, 45]

    private var primaryAction: String {
        if clock.session.deadline != nil { return "Pause" }
        if clock.session.active { return "Resume" }
        return "Start"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            DeskHeader(title: "Focus Fuse", detail: "Give one thing a little time.", symbol: "timer", accent: DeskColor.lime)
            ZStack {
                Circle().strokeBorder(DeskColor.card, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: clock.remaining / clock.session.duration)
                    .stroke(DeskColor.lime, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(4)
                VStack(spacing: 4) {
                    Text(clock.timeText)
                        .font(.system(size: 41, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(clock.status)
                        .font(.callout)
                        .foregroundStyle(DeskColor.gray)
                }
            }
            .frame(width: 172, height: 172)
            .frame(maxWidth: .infinity)
            HStack {
                ForEach(presets, id: \.self) { minutes in
                    Button("\(minutes) min") { clock.setMinutes(minutes) }
                        .frame(maxWidth: .infinity)
                        .tint(clock.session.minutes == minutes ? DeskColor.lime : DeskColor.gray)
                        .accessibilityAddTraits(clock.session.minutes == minutes ? .isSelected : [])
                }
            }
            .disabled(clock.session.active)
            HStack {
                Toggle("Finish sound", isOn: $clock.soundEnabled)
                Spacer()
                Button("Reset", action: clock.reset)
                    .disabled(!clock.session.active && !clock.finished)
                Button(primaryAction, action: clock.toggle)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .deskWindow(accent: DeskColor.lime)
        .frame(width: 408)
    }
}

private final class FuseApp: DeskApp {
    private let clock = FocusClock()

    init() { super.init(name: "Focus Fuse", symbol: "timer") }

    override func start() {
        clock.onFinish = { [weak self] in
            if self?.clock.soundEnabled == true { LocalSound.play("Hero") }
        }
        clock.onTick = { [weak self] in
            guard let self else { return }
            let active = clock.session.active || clock.finished
            setStatus(active ? clock.timeText : "", help: "Focus Fuse · \(clock.status) · \(clock.timeText)")
        }
        clock.startHeartbeat()
    }

    override func makeContent() -> AnyView { AnyView(FocusControls(clock: clock)) }

    override func populate(_ menu: NSMenu) {
        add("Open Timer…", to: menu, action: #selector(openWindow), key: "o")
        let title = clock.session.deadline != nil ? "Pause" : (clock.session.active ? "Resume" : "Start")
        add(title, to: menu, action: #selector(toggle))
        if clock.session.active || clock.finished {
            add("Reset", to: menu, action: #selector(reset))
        }
    }

    @objc private func toggle() { clock.toggle() }
    @objc private func reset() { clock.reset() }
}

@main
struct FocusFuse {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            let t = Date(timeIntervalSince1970: 1_000)
            var session = FocusSession(minutes: 5)
            session.start(at: t)
            precondition(session.remaining(at: t.addingTimeInterval(60)) == 240)
            session.pause(at: t.addingTimeInterval(60))
            precondition(session.remaining(at: t.addingTimeInterval(3_600)) == 240)
            session.resume(at: t.addingTimeInterval(3_600))
            let restored = try! JSONDecoder().decode(FocusSession.self, from: JSONEncoder().encode(session))
            precondition(restored == session && restored.valid)
            precondition(!session.finishIfDue(at: t.addingTimeInterval(3_839)))
            precondition(session.finishIfDue(at: t.addingTimeInterval(3_840)))
            precondition(!session.finishIfDue(at: t.addingTimeInterval(3_841)))
            precondition(!FocusSession(minutes: 0).valid && !FocusSession(pausedSeconds: -1).valid)
            let suite = "focus-fuse-test-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(try! JSONEncoder().encode(restored), forKey: "session")
            let clock = FocusClock(defaults: defaults, now: t.addingTimeInterval(3_839))
            var finishes = 0
            clock.onFinish = { finishes += 1 }
            clock.tick(at: t.addingTimeInterval(3_840))
            clock.tick(at: t.addingTimeInterval(3_850))
            precondition(finishes == 1 && clock.timeText == "00:00" && clock.finished)
            print("PASS: pause, resume, persisted deadlines and one-shot completion")
            return
        }
        run(FuseApp())
    }
}
