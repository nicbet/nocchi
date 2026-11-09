import AppKit
import NocchiClaude
import NocchiCore
import NocchiHerdr
import NocchiHerdrCore
import NocchiUI

// Dev tool: `nocchi --render-iconset <dir>` writes the app icon in every size (see make-icon.sh).
if let flag = CommandLine.arguments.firstIndex(of: "--render-iconset") {
    let dir = URL(fileURLWithPath: CommandLine.arguments.dropFirst(flag + 1).first ?? "AppIcon.iconset")
    MainActor.assumeIsolated {
        do {
            try AppIcon.writeIconset(to: dir)
            print(dir.path)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("icon failed: \(error)\n".utf8))
            exit(1)
        }
    }
}

// Dev tool: `nocchi --snapshot <dir>` renders the notch to PNGs and exits. With `--live` it
// renders what the real Herdr app (herdr-core) reports instead of the preview scenarios;
// `--live --source herdr-tui` what the terminal Herdr reports; `--live --source claude` what
// Claude's own session registry reports.
if let flag = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let dir = CommandLine.arguments.dropFirst(flag + 1).first ?? "."
    let live = CommandLine.arguments.contains("--live")
    MainActor.assumeIsolated {
        let geometry = NotchGeometry.preferredScreen().map(NotchGeometry.init(screen:))
            ?? .make(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                     topLeftArea: CGRect(x: 0, y: 0, width: 663, height: 32),
                     topRightArea: CGRect(x: 0, y: 0, width: 663, height: 32), menuBarHeight: 32)
        func finish(_ write: () throws -> [URL]) -> Never {
            do {
                for url in try write() { print(url.path) }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
                exit(1)
            }
        }
        guard live else { finish { try NotchSnapshot.write(to: URL(fileURLWithPath: dir), geometry: geometry) } }
        let store = AgentStore()
        let settings = NocchiSettings.shared
        // `--source claude` sees Claude sessions natively (including Herdr's), to check the adapter.
        let source: AdapterID
        if CommandLine.arguments.contains("claude") {
            source = "claude"
            store.run(ClaudeAdapter(leavesHerdrToHerdr: false, leavesHerdrCoreToHerdr: false))
        } else if CommandLine.arguments.contains("herdr-tui") {
            source = "herdr"
            store.run(HerdrAdapter(socketPath: Herdr.socketPath(override: settings.herdrSocketPath, session: settings.herdrSession)))
        } else {
            source = "hc"
            store.run(HerdrCoreAdapter())
        }
        let activity = ClaudeActivityFeed(store: store)
        activity.start()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            activity.stop()
            // `--select <agent>` (a terminal like t7, or a TUI pane) renders that agent as the primary.
            if let flag = CommandLine.arguments.firstIndex(of: "--select"), CommandLine.arguments.indices.contains(flag + 1) {
                store.select(AgentRef(adapter: source, localID: CommandLine.arguments[flag + 1]))
            }
            for entry in store.state.agents.values.sorted(by: { $0.slot < $1.slot }) {
                print("\(entry.ref) \(entry.info.kind.displayName) \(entry.info.status) \(store.mood(of: entry)) \"\(entry.info.displayName)\" \(entry.steps.last ?? "") | msg: \(entry.lastMessage ?? "-")\(entry.info.isFocused ? " [focused]" : "")")
            }
            print(store.state.connections)
            finish { try NotchSnapshot.writeLive(store, to: URL(fileURLWithPath: dir), geometry: geometry) }
        }
    }
    RunLoop.main.run()  // keeps the main queue on the main thread, unlike dispatchMain()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
