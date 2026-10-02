import AppKit
import NocchiCore
import OSLog
import SwiftUI

let notchLog = Logger(subsystem: "com.github.nicbet.nocchi", category: "notch")

/// Owns the notch panel: positions it on the right screen, makes it click-through outside the
/// visible shape, and expands/collapses it on hover.
@MainActor
public final class NotchController {
    public let model: NotchModel
    private let panel = NotchPanel()

    private var globalMonitor: Any?
    private var hoverPoll: Task<Void, Never>?
    private var pendingModeChange: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var peekTracker = PeekTracker()
    private var peekEnd: Task<Void, Never>?
    private var bannerEnd: Task<Void, Never>?
    private var mouseDownMonitor: Any?
    private var dragPoll: Task<Void, Never>?
    private var dragChangeCount = 0
    private var dropReset: Task<Void, Never>?

    /// Delay before opening on hover, so passing through the menu bar doesn't open it.
    private let expandDelay: Duration = .milliseconds(90)
    /// Grace period before closing, so small overshoots don't collapse it.
    private let collapseDelay: Duration = .milliseconds(350)

    public init(store: AgentStore) {
        let screen = NotchGeometry.preferredScreen(named: NocchiSettings.shared.screenName)
        model = NotchModel(geometry: screen.map(NotchGeometry.init(screen:)) ?? NotchGeometry.make(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            safeAreaTop: 0, topLeftArea: nil, topRightArea: nil, menuBarHeight: 24
        ), store: store)
        let host = FirstClickHostingView(rootView: NotchView(model: model).acceptsFolderDrops(model).resolvesReduceMotion())
        host.sizingOptions = []
        panel.contentView = host
    }

    /// How long the launch greeting stays open: until its choreography has played out.
    private let greetingDuration: Duration = .seconds(GreetingTimeline.duration)

    public func start(greeting: Bool = true) {
        layout()
        panel.orderFrontRegardless()
        if greeting { greet() }
        observeMoods()
        model.onDropFolder = { [weak self] url in self?.startAgent(in: url) }
        model.onPromptChange = { [weak self] state in self?.promptChanged(state) }
        model.onChooseFolder = { [weak self] in self?.chooseFolder() }
        // A file drag can't be seen directly from outside the dragging app, so on every press we
        // watch the drag pasteboard until the button is released.
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchForFileDrag() }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.screensChanged() }
        // Clicking elsewhere while writing to an agent closes the field.
        observe(NotificationCenter.default, NSWindow.didResignKeyNotification, object: panel) { controller in
            if case .composing = controller.model.prompt, !controller.model.isChoosingFolder { controller.model.prompt = .none }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.model.screensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.model.screensAsleep = false }
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name, object: AnyObject? = nil,
        _ handler: @escaping @MainActor (NotchController) -> Void
    ) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { handler(self) } }
        }
        observers.append((center, token))
    }

    public func stop() {
        globalMonitor.map(NSEvent.removeMonitor)
        mouseDownMonitor.map(NSEvent.removeMonitor)
        dragPoll?.cancel()
        dropReset?.cancel()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        hoverPoll?.cancel()
        pendingModeChange?.cancel()
        peekEnd?.cancel()
        model.ticker.stop()
        panel.orderOut(nil)
    }

    // MARK: Peek

    /// Re-reads the moods whenever they change (the store's clock also ticks them each second).
    private func observeMoods() {
        let store = model.store
        let moods = withObservationTracking {
            Dictionary(uniqueKeysWithValues: store.state.agents.values.map { ($0.ref, store.mood(of: $0)) })
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeMoods() }
        }
        let entered = peekTracker.update(moods)
        let settings = NocchiSettings.shared
        let policy = PeekPolicy(level: settings.peekLevel,
                                statusTextAnnounces: !model.geometry.hasHardwareNotch && settings.showsStatusText)
        // Only what you haven't seen: a turn finishing right where you look just celebrates.
        let actions = policy.actions(for: entered) { ref in
            switch store.state.agents[ref]?.info.status {
            case .done, .blocked, .error: true
            default: false
            }
        }
        for action in actions {
            switch action {
            case .open(let peek): self.peek(peek)
            case .banner(let peek): showBanner(peek)
            }
        }
        // Sounds follow the peek level: everything unread, or only what opens the notch.
        let audible = settings.peekLevel == .everything
            ? entered.first { store.state.agents[$0.ref]?.needsAttention == true }
            : actions.lazy.compactMap { if case .open(let peek) = $0 { peek } else { nil } }.first
        if settings.playsSounds, !model.isGreeting, let audible { Self.sound(for: audible.mood)?.play() }
        for peek in entered {
            guard let entry = store.state.agents[peek.ref] else { continue }
            model.ticker.announce(Ticker.Message(ref: peek.ref, name: entry.info.displayName, mood: peek.mood))
        }
    }

    /// The mini peek: a line under the collapsed notch for about 3 s. Arrivals while it shows join
    /// it ("2 agents finished") and keep it up.
    private func showBanner(_ peek: PeekTracker.Peek) {
        guard !model.isGreeting, model.mode == .collapsed, let entry = model.store.state.agents[peek.ref] else { return }
        notchLog.info("banner: \(peek.ref.description, privacy: .public) \(String(describing: peek.mood), privacy: .public)")
        model.banner = model.banner?.adding(peek.ref, mood: peek.mood)
            ?? PeekBanner(ref: peek.ref, name: entry.info.displayName, mood: peek.mood)
        bannerEnd?.cancel()
        bannerEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.model.banner = nil
        }
    }

    private static func sound(for mood: Mood) -> NSSound? {
        switch mood {
        case .waiting: NSSound(named: "Ping")
        case .error: NSSound(named: "Basso")
        case .done: NSSound(named: "Glass")
        default: nil
        }
    }

    /// Opens the notch for a moment when an agent needs you, failed or finished. The expanded
    /// notch shows the alert for the most urgent agent. Hovering takes over from the timeout.
    private func peek(_ peek: PeekTracker.Peek) {
        guard !model.isGreeting, !model.holdsOpen, !model.isHovering else { return }
        notchLog.info("peek: \(peek.ref.description, privacy: .public) \(String(describing: peek.mood), privacy: .public)")
        if model.mode == .collapsed { model.isPeeking = true }
        model.banner = nil
        setMode(.expanded)
        peekEnd?.cancel()
        peekEnd = Task { [weak self] in
            try? await Task.sleep(for: peek.duration)
            guard !Task.isCancelled, let self else { return }
            if !model.isHovering && !model.holdsOpen && !model.isGreeting { setMode(.collapsed) }
        }
    }

    /// Opens the notch with the greeting, then collapses (unless the pointer is over it).
    public func greet() {
        model.isGreeting = true
        setMode(.expanded)
        Task { [weak self] in
            try? await Task.sleep(for: self?.greetingDuration ?? .seconds(3))
            guard let self else { return }
            model.isGreeting = false
            if !model.isHovering && !model.holdsOpen { setMode(.collapsed) }
        }
    }

    // MARK: Talk to an agent

    private func promptChanged(_ state: PromptState) {
        switch state {
        case .composing:
            panel.acceptsKeyboard = true
            panel.makeKey()
        case .none:
            panel.acceptsKeyboard = false
            panel.resignKey()
            scheduleModeChange()
        case .sending, .failed:
            break
        }
    }

    /// Picks the new chat's folder in an open panel; the chat stays open meanwhile.
    private func chooseFolder() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.canCreateDirectories = true
        picker.prompt = "Start Here"
        picker.message = "Where should the new agent work?"
        picker.directoryURL = model.newChatFolder
        model.isChoosingFolder = true
        // An accessory app's panel only takes keyboard input while the app is active.
        NSApp.activate()
        picker.begin { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                if response == .OK, let url = picker.url { self.model.newChatFolder = url }
                self.model.isChoosingFolder = false
                if case .composing = self.model.prompt {
                    self.panel.makeKey()
                } else {
                    self.scheduleModeChange()
                }
            }
        }
    }

    // MARK: Drop a folder

    /// Area around the notch where a file drag opens the drop zone.
    private var dropProximity: CGRect {
        model.geometry.rectHanging(model.shapeSize(for: .expanded)).insetBy(dx: -80, dy: -80)
    }

    private func watchForFileDrag() {
        guard dragPoll == nil, model.store.canStartAgents else { return }
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        dragPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 { return endFileDrag() }
                updateFileDrag()
            }
        }
    }

    private func updateFileDrag() {
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCount, pasteboard.types?.contains(.fileURL) == true else { return }
        let near = dropProximity.contains(NSEvent.mouseLocation)
        switch model.drop {
        case .none where near:
            model.drop = .offering(isTargeted: false)
            setMode(.expanded)
        case .offering where !near:
            model.drop = .none
            scheduleModeChange()
        default:
            break
        }
        trackMouse()
    }

    private func endFileDrag() {
        dragPoll?.cancel()
        dragPoll = nil
        // Released without dropping on the notch.
        if case .offering = model.drop {
            model.drop = .none
            scheduleModeChange()
        }
    }

    private func startAgent(in url: URL) {
        let folder = DropState.folder(for: url)
        notchLog.info("drop: start claude in \(folder.path, privacy: .public)")
        model.drop = .starting(folder: folder, since: Date())
        dropReset?.cancel()
        dropReset = Task { [weak self] in
            guard let store = self?.model.store else { return }
            let result: DropState
            do {
                if let started = try await store.perform(.start(kind: .claude, cwd: folder)) {
                    store.select(started, yieldsToAnyUrgent: true)
                }
                result = .started(folder: folder)
            } catch {
                result = .failed(folder: folder, message: Self.describe(error))
            }
            guard let self, !Task.isCancelled else { return }
            model.drop = result
            try? await Task.sleep(for: result == .started(folder: folder) ? .milliseconds(1500) : .seconds(5))
            guard !Task.isCancelled else { return }
            model.drop = .none
            scheduleModeChange()
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case AgentActionError.failed(let message): message
        case AgentActionError.unsupported: "This agent source can't start agents."
        default: "\(error)"
        }
    }

    // MARK: Debug controls

    public func setMode(_ mode: NotchMode) {
        pendingModeChange?.cancel()
        model.mode = mode
        trackMouse()
    }

    public func setPinned(_ pinned: Bool) {
        model.isPinned = pinned
        setMode(pinned ? .expanded : (model.isHovering ? .expanded : .collapsed))
    }

    // MARK: Layout

    /// Moves the notch to the preferred screen, e.g. after displays change or the setting does.
    public func screensChanged() {
        guard let screen = NotchGeometry.preferredScreen(named: NocchiSettings.shared.screenName) else { return }
        model.geometry = NotchGeometry(screen: screen)
        layout()
    }

    private func layout() {
        let size = model.panelSize
        let frame = model.geometry.rectHanging(size)
        panel.setFrame(frame, display: true)
    }

    // MARK: Hover

    /// Called on global mouse moves (while outside the panel) and by the poll (while inside).
    /// Global monitors don't see events that go to our own panel, so while the pointer is
    /// over the notch we poll its position until it leaves.
    private func trackMouse() {
        let point = NSEvent.mouseLocation
        // Grow 1 pt upward so the topmost row of pixels (y == screen maxY) counts as inside.
        var hit = model.hitRect
        hit.size.height += 1
        let inside = hit.contains(point)

        // Runs on every mouse move system-wide; only touch the window server when it changes.
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if inside { startHoverPoll() } else { stopHoverPoll() }

        guard inside != model.isHovering else { return }
        notchLog.debug("hover: \(inside, privacy: .public)")
        model.isHovering = inside
        scheduleModeChange()
    }

    private func scheduleModeChange() {
        pendingModeChange?.cancel()
        let target: NotchMode = (model.isHovering || model.holdsOpen) ? .expanded : .collapsed
        guard target != model.mode else { return }
        let delay = target == .expanded ? expandDelay : collapseDelay

        pendingModeChange = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            model.mode = target
            trackMouse()
        }
    }

    private func startHoverPoll() {
        guard hoverPoll == nil else { return }
        hoverPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                self?.trackMouse()
            }
        }
    }

    private func stopHoverPoll() {
        hoverPoll?.cancel()
        hoverPoll = nil
    }
}

/// The panel never becomes key, so without this the first click on a chip or button would only
/// "activate" the panel and do nothing.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
