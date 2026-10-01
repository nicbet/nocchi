import AppKit
import NocchiCore
import SwiftUI

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

    /// Delay before opening on hover, so passing through the menu bar doesn't open it.
    private let expandDelay: Duration = .milliseconds(90)
    /// Grace period before closing, so small overshoots don't collapse it.
    private let collapseDelay: Duration = .milliseconds(350)

    public init(store: AgentStore) {
        let screen = NotchGeometry.preferredScreen()
        model = NotchModel(geometry: screen.map(NotchGeometry.init(screen:)) ?? NotchGeometry.make(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            safeAreaTop: 0, topLeftArea: nil, topRightArea: nil, menuBarHeight: 24
        ), store: store)
        let host = NSHostingView(rootView: NotchView(model: model).resolvesReduceMotion())
        host.sizingOptions = []
        panel.contentView = host
    }

    /// How long the launch greeting stays open.
    private let greetingDuration: Duration = .seconds(3)

    public func start(greeting: Bool = true) {
        layout()
        panel.orderFrontRegardless()
        if greeting { greet() }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.screensChanged() }
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
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        hoverPoll?.cancel()
        pendingModeChange?.cancel()
        panel.orderOut(nil)
    }

    /// Opens the notch with the greeting, then collapses (unless the pointer is over it).
    public func greet() {
        model.isGreeting = true
        setMode(.expanded)
        Task { [weak self] in
            try? await Task.sleep(for: self?.greetingDuration ?? .seconds(3))
            guard let self else { return }
            model.isGreeting = false
            if !model.isHovering && !model.isPinned { setMode(.collapsed) }
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

    private func screensChanged() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
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
        model.isHovering = inside
        scheduleModeChange()
    }

    private func scheduleModeChange() {
        pendingModeChange?.cancel()
        let target: NotchMode = (model.isHovering || model.isPinned) ? .expanded : .collapsed
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
