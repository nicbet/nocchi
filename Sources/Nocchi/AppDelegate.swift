import AppKit
import NocchiCore
import NocchiHerdr
import NocchiUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var notch: NotchController?
    private let gallery = MoodGalleryWindow()
    private let store = AgentStore()
    /// A demo scenario that replaces Herdr while it runs. `--demo <name>` starts with one.
    private var demo: MockScenario?
    private let connectionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--demo") {
            let name = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : MockScenario.showcase.name
            demo = MockScenario.all.first { $0.name == name } ?? .showcase
        }
        startSource()
        let notch = NotchController(store: store)
        notch.start()
        self.notch = notch
        statusItem = makeStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        notch?.stop()
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: Nocchi.name)

        let menu = NSMenu()
        let title = NSMenuItem(title: "\(Nocchi.name) \(Nocchi.version)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        connectionItem.isEnabled = false
        menu.addItem(connectionItem)
        menu.addItem(.separator())
        let ignoreReduceMotion = NSMenuItem(title: "Ignore Reduce Motion", action: #selector(toggleIgnoreReduceMotion(_:)), keyEquivalent: "")
        ignoreReduceMotion.target = self
        ignoreReduceMotion.state = NocchiSettings.shared.ignoresReduceMotion ? .on : .off
        ignoreReduceMotion.toolTip = "Animate nocchi fully even when Reduce Motion is on in System Settings."
        menu.addItem(ignoreReduceMotion)
        let autoPeek = NSMenuItem(title: "Peek When Agents Need You", action: #selector(toggleAutoPeek(_:)), keyEquivalent: "")
        autoPeek.target = self
        autoPeek.state = NocchiSettings.shared.autoPeek ? .on : .off
        autoPeek.toolTip = "Open the notch for a moment when an agent needs you, failed or finished."
        menu.addItem(autoPeek)
        menu.addItem(.separator())
        menu.addItem(demoMenuItem())
        menu.addItem(debugMenuItem())
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit \(Nocchi.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        item.menu = menu
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        connectionItem.title = connectionDescription
    }

    private var connectionDescription: String {
        if let demo { return "Demo: \(demo.name)" }
        switch store.state.connections["herdr"] {
        case .connected(let version): return "Herdr \(version ?? "") connected"
        case .unavailable(let reason): return reason
        case .connecting, nil: return "Connecting to Herdr…"
        }
    }

    // MARK: Source

    /// Herdr, unless a demo is running.
    private func startSource() {
        if let demo {
            store.stop("herdr")
            store.run(MockAdapter(scenario: demo))
        } else {
            store.stop("mock")
            let settings = NocchiSettings.shared
            let socket = Herdr.socketPath(override: settings.herdrSocketPath, session: settings.herdrSession)
            store.run(HerdrAdapter(socketPath: socket, revealsTerminal: true))
        }
    }

    @objc private func toggleAutoPeek(_ sender: NSMenuItem) {
        NocchiSettings.shared.autoPeek.toggle()
        sender.state = NocchiSettings.shared.autoPeek ? .on : .off
    }

    @objc private func toggleIgnoreReduceMotion(_ sender: NSMenuItem) {
        NocchiSettings.shared.ignoresReduceMotion.toggle()
        sender.state = NocchiSettings.shared.ignoresReduceMotion ? .on : .off
    }

    // MARK: Demo

    private func demoMenuItem() -> NSMenuItem {
        let menu = NSMenu()
        for scenario in MockScenario.all {
            let item = menu.addItem(withTitle: scenario.name, action: #selector(selectDemo(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = scenario.name
            item.state = scenario.name == demo?.name ? .on : .off
        }
        menu.addItem(.separator())
        let off = menu.addItem(withTitle: "Off (Herdr)", action: #selector(selectDemo(_:)), keyEquivalent: "")
        off.target = self
        off.state = demo == nil ? .on : .off

        let item = NSMenuItem(title: "Demo", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @objc private func selectDemo(_ sender: NSMenuItem) {
        demo = MockScenario.all.first { $0.name == sender.representedObject as? String }
        startSource()
        for item in sender.menu?.items ?? [] { item.state = item === sender ? .on : .off }
    }

    // MARK: Debug

    private func debugMenuItem() -> NSMenuItem {
        let menu = NSMenu()
        menu.addItem(withTitle: "Expand", action: #selector(debugExpand), keyEquivalent: "e").target = self
        menu.addItem(withTitle: "Collapse", action: #selector(debugCollapse), keyEquivalent: "c").target = self
        menu.addItem(withTitle: "Keep Expanded", action: #selector(debugTogglePinned(_:)), keyEquivalent: "p").target = self
        menu.addItem(withTitle: "Show Hit Area", action: #selector(debugToggleHitArea(_:)), keyEquivalent: "h").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Mood Gallery…", action: #selector(debugShowGallery), keyEquivalent: "g").target = self
        menu.addItem(withTitle: "Replay Greeting", action: #selector(debugGreet), keyEquivalent: "r").target = self

        let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @objc private func debugExpand() { notch?.setMode(.expanded) }
    @objc private func debugCollapse() { notch?.setMode(.collapsed) }

    @objc private func debugTogglePinned(_ sender: NSMenuItem) {
        guard let notch else { return }
        notch.setPinned(!notch.model.isPinned)
        sender.state = notch.model.isPinned ? .on : .off
    }

    @objc private func debugShowGallery() { gallery.show() }
    @objc private func debugGreet() { notch?.greet() }

    @objc private func debugToggleHitArea(_ sender: NSMenuItem) {
        guard let notch else { return }
        notch.model.showsHitArea.toggle()
        sender.state = notch.model.showsHitArea ? .on : .off
    }
}
