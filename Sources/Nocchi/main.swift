import AppKit
import NocchiClaude
import NocchiCodex
import NocchiCore
import NocchiHerdr
import NocchiUI

// Dev tool: `nocchi --render-sounds <dir>` writes nocchi's voice as WAVs to listen to.
if let flag = CommandLine.arguments.firstIndex(of: "--render-sounds") {
    let dir = URL(fileURLWithPath: CommandLine.arguments.dropFirst(flag + 1).first ?? ".")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for voice in NocchiVoice.allCases {
        let url = dir.appending(path: "\(voice.rawValue).wav")
        try? voice.wav().write(to: url)
        print(url.path)
    }
    for candidate in NocchiVoice.candidates {
        let url = dir.appending(path: "candidates/\(candidate.name).wav")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? NocchiVoice.wavData(candidate.samples).write(to: url)
    }
    exit(0)
}

// Dev tool: `nocchi --snapshot <dir>` renders the notch to PNGs and exits. With `--live` it
// renders what the real Herdr reports instead of the preview scenarios; `--live --source claude`
// renders what Claude's own session registry reports.
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
        if CommandLine.arguments.contains("claude") {
            store.run(ClaudeAdapter(leavesHerdrToHerdr: false))
        } else if CommandLine.arguments.contains("codex") {
            store.run(CodexAdapter(leavesHerdrToHerdr: false))
        } else {
            store.run(HerdrAdapter(socketPath: Herdr.socketPath(override: settings.herdrSocketPath, session: settings.herdrSession)))
        }
        let activity = ClaudeActivityFeed(store: store)
        activity.start()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            activity.stop()
            // `--select <pane>` renders that agent as the primary.
            if let flag = CommandLine.arguments.firstIndex(of: "--select"), CommandLine.arguments.indices.contains(flag + 1) {
                store.select(AgentRef(adapter: "herdr", localID: CommandLine.arguments[flag + 1]))
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
