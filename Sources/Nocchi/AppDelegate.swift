import AppKit
import NocchiClaude
import NocchiCodex
import NocchiCore
import NocchiHerdr
import NocchiHooks
import NocchiUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var notch: NotchController?
    private let gallery = MoodGalleryWindow()
    private let store = AgentStore()
    private lazy var claudeActivity = ClaudeActivityFeed(store: store)
    /// Where `nocchi-hook` delivers Claude Code and Codex hook calls, once hooks are installed.
    private let hookServer = HookServer()
    /// A demo scenario that replaces Herdr while it runs. `--demo <name>` starts with one.
    private var demo: MockScenario?
    private let connectionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--demo") {
            let name = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : MockScenario.showcase.name
            demo = MockScenario.all.first { $0.name == name } ?? .showcase
        }
        do { try hookServer.start() } catch { NSLog("nocchi: hook socket unavailable: \(error)") }
        refreshHookBinary()
        startSource()
        claudeActivity.start()
        let notch = NotchController(store: store)
        notch.start()
        self.notch = notch
        statusItem = makeStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        notch?.stop()
        hookServer.stop()
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
        menu.addItem(peekMenuItem())
        menu.addItem(toggle("Play Sounds", \.playsSounds, tip: "A short sound when an agent needs you, failed or finished."))
        menu.addItem(toggle("Show Status Text", \.showsStatusText,
                            tip: "On screens without a notch, show messages like “Nocchi finished” between the faces."))
        menu.addItem(.separator())
        menu.addItem(sourcesMenuItem())
        menu.addItem(hooksMenuItem)
        menu.addItem(screenMenuItem)
        menu.addItem(toggle("Ignore Reduce Motion", \.ignoresReduceMotion,
                            tip: "Animate nocchi fully even when Reduce Motion is on in System Settings."))
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
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
        for item in hooksMenuItem.submenu?.items ?? [] {
            if let agent = (item.representedObject as? String).flatMap(HookInstaller.Agent.init(rawValue:)) {
                item.state = HookInstaller.isInstalled(agent) ? .on : .off
            }
        }
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        rebuildScreenMenu()
    }

    // MARK: Settings

    private func toggle(_ title: String, _ setting: ReferenceWritableKeyPath<NocchiSettings, Bool>, tip: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(toggleSetting(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = setting
        item.state = NocchiSettings.shared[keyPath: setting] ? .on : .off
        item.toolTip = tip
        return item
    }

    /// Everything / Only When Needed / Never.
    private func peekMenuItem() -> NSMenuItem {
        let menu = NSMenu()
        for level in PeekLevel.allCases {
            let item = menu.addItem(withTitle: level.title, action: #selector(selectPeekLevel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = level.rawValue
            item.state = NocchiSettings.shared.peekLevel == level ? .on : .off
        }
        menu.items[0].toolTip = "Open the notch when an agent needs you; a one-line banner when one finishes or fails."
        menu.items[1].toolTip = "Open the notch only when an agent needs you."
        let item = NSMenuItem(title: "Peek", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @objc private func selectPeekLevel(_ sender: NSMenuItem) {
        guard let level = (sender.representedObject as? String).flatMap(PeekLevel.init(rawValue:)) else { return }
        NocchiSettings.shared.peekLevel = level
        for item in sender.menu?.items ?? [] { item.state = item === sender ? .on : .off }
    }

    @objc private func toggleSetting(_ sender: NSMenuItem) {
        guard let setting = sender.representedObject as? ReferenceWritableKeyPath<NocchiSettings, Bool> else { return }
        NocchiSettings.shared[keyPath: setting].toggle()
        sender.state = NocchiSettings.shared[keyPath: setting] ? .on : .off
    }

    private let screenMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "Screen", action: nil, keyEquivalent: "")
        item.submenu = NSMenu()
        return item
    }()

    /// Automatic, then every connected screen.
    private func rebuildScreenMenu() {
        guard let menu = screenMenuItem.submenu else { return }
        menu.removeAllItems()
        let chosen = NocchiSettings.shared.screenName
        let automatic = menu.addItem(withTitle: "Automatic", action: #selector(selectScreen(_:)), keyEquivalent: "")
        automatic.target = self
        automatic.state = chosen == nil ? .on : .off
        automatic.toolTip = "The screen with a notch, else the main screen."
        menu.addItem(.separator())
        for screen in NSScreen.screens {
            let item = menu.addItem(withTitle: screen.localizedName, action: #selector(selectScreen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = screen.localizedName
            item.state = chosen == screen.localizedName ? .on : .off
        }
    }

    @objc private func selectScreen(_ sender: NSMenuItem) {
        NocchiSettings.shared.screenName = sender.representedObject as? String
        notch?.screensChanged()
    }

    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change Launch at Login"
            alert.runModal()
        }
        sender.state = service.status == .enabled ? .on : .off
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    private var connectionDescription: String {
        if let demo { return "Demo: \(demo.name)" }
        let settings = NocchiSettings.shared
        var parts: [String] = []
        if settings.usesHerdr {
            switch store.state.connections["herdr"] {
            case .connected(let version): parts.append("Herdr \(version ?? "")")
            case .unavailable(let reason): parts.append(reason)
            case .connecting, nil: parts.append("Connecting to Herdr…")
            }
        }
        if settings.watchesClaude {
            let count = store.state.agents.keys.filter { $0.adapter == "claude" }.count
            parts.append(count == 0 ? "Claude Code" : "Claude Code (\(count) outside Herdr)")
        }
        if settings.watchesCodex {
            let count = store.state.agents.keys.filter { $0.adapter == "codex" }.count
            parts.append(count == 0 ? "Codex" : "Codex (\(count))")
        }
        return parts.isEmpty ? "No agent sources" : parts.joined(separator: " · ")
    }

    // MARK: Source

    /// The enabled sources, or the demo in their place.
    private func startSource() {
        let settings = NocchiSettings.shared
        if let demo {
            store.stop("herdr")
            store.stop("claude")
            store.stop("codex")
            store.run(MockAdapter(scenario: demo))
            return
        }
        store.stop("mock")
        if settings.usesHerdr {
            if !store.isRunning("herdr") {
                let socket = Herdr.socketPath(override: settings.herdrSocketPath, session: settings.herdrSession)
                store.run(HerdrAdapter(socketPath: socket, watchesTerminal: true))
            }
        } else {
            store.stop("herdr")
        }
        // Sessions in Herdr panes are Herdr's while Herdr is a source; otherwise Claude shows them.
        store.stop("claude")
        if settings.watchesClaude {
            store.run(ClaudeAdapter(hooks: hookServer, leavesHerdrToHerdr: settings.usesHerdr))
        }
        store.stop("codex")
        if settings.watchesCodex {
            store.run(CodexAdapter(hooks: hookServer, leavesHerdrToHerdr: settings.usesHerdr))
        }
    }

    private func sourcesMenuItem() -> NSMenuItem {
        let menu = NSMenu()
        for (title, setting, tip) in [
            ("Herdr", \NocchiSettings.usesHerdr, "Agents running in Herdr panes."),
            ("Claude Code", \NocchiSettings.watchesClaude, "Claude sessions anywhere else: a terminal tab, an IDE. Read from Claude's own session list; nothing to set up."),
            ("Codex", \NocchiSettings.watchesCodex, "Codex CLI sessions anywhere else. Read from their processes and session logs; nothing to set up."),
        ] {
            let item = menu.addItem(withTitle: title, action: #selector(toggleSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = setting
            item.state = NocchiSettings.shared[keyPath: setting] ? .on : .off
            item.toolTip = tip
        }
        let item = NSMenuItem(title: "Sources", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @objc private func toggleSource(_ sender: NSMenuItem) {
        guard let setting = sender.representedObject as? ReferenceWritableKeyPath<NocchiSettings, Bool> else { return }
        NocchiSettings.shared[keyPath: setting].toggle()
        sender.state = NocchiSettings.shared[keyPath: setting] ? .on : .off
        startSource()
    }

    // MARK: Hooks

    /// Claude Code and Codex hooks: optional. Claude works without them (its session list reports
    /// everything); Codex needs them for "needs you". Both get instant updates from them.
    private lazy var hooksMenuItem: NSMenuItem = {
        let menu = NSMenu()
        for agent in HookInstaller.Agent.allCases {
            let item = menu.addItem(withTitle: agent.title, action: #selector(toggleHooks(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = agent.rawValue
            item.toolTip = agent == .codex
                ? "Lets nocchi see when Codex asks for permission, and react instantly. Optional."
                : "Instant updates and failure reasons. Optional: nocchi already sees Claude sessions without hooks."
        }
        let item = NSMenuItem(title: "Hooks", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }()

    /// The `nocchi-hook` inside this app, to copy where hooks call it.
    private var bundledHook: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "nocchi-hook")
            ?? Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "nocchi-hook")
    }

    /// Keeps the installed hook binary in step with this version of the app.
    private func refreshHookBinary() {
        guard let bundledHook, HookInstaller.Agent.allCases.contains(where: { HookInstaller.isInstalled($0) }) else { return }
        try? HookInstaller.updateBinary(from: bundledHook, to: HookInstaller.hookBinary())
    }

    @objc private func toggleHooks(_ sender: NSMenuItem) {
        guard let agent = (sender.representedObject as? String).flatMap(HookInstaller.Agent.init(rawValue:)) else { return }
        let installed = HookInstaller.isInstalled(agent)
        let file = (agent.settingsFile().path as NSString).abbreviatingWithTildeInPath
        let alert = NSAlert()
        if installed {
            alert.messageText = "Remove nocchi's \(agent.title) hooks?"
            alert.informativeText = "nocchi removes only its own entries from \(file) (a backup is made first)."
            alert.addButton(withTitle: "Remove")
        } else {
            alert.messageText = "Install nocchi's \(agent.title) hooks?"
            var text = "nocchi adds its entries to \(file), next to any hooks you have (a backup is made first). "
            text += agent == .codex
                ? "It also turns on hooks in ~/.codex/config.toml. Codex may ask you to trust the new hook; restart running Codex sessions to pick it up."
                : "Restart running Claude sessions to pick them up."
            alert.informativeText = text
            alert.addButton(withTitle: "Install")
        }
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            if installed {
                try HookInstaller.uninstall(agent)
            } else {
                guard let bundledHook else { throw CocoaError(.fileNoSuchFile) }
                try HookInstaller.install(agent, bundledBinary: bundledHook)
            }
            sender.state = HookInstaller.isInstalled(agent) ? .on : .off
        } catch {
            let failure = NSAlert(error: error)
            failure.messageText = "Couldn't change the \(agent.title) hooks"
            failure.runModal()
        }
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
