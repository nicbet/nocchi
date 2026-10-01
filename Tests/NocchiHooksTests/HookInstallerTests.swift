import Foundation
import Testing
@testable import NocchiHooks

@Suite struct HookInstallerTests {
    let command = "'/Users/me/Library/Application Support/nocchi/bin/nocchi-hook' claude"
    /// Herdr's own hook, as installed on this machine: it must survive.
    let herdr: [String: Any] = ["hooks": ["SessionStart": [["hooks": [["type": "command", "command": "bash '/Users/me/.codex/herdr-agent-state.sh' session", "timeout": 10]]]]],
                                "model": "opus"]

    func commands(_ settings: [String: Any], _ event: String) -> [String] {
        ((settings["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? [])
            .flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    @Test func installsBesideOtherHooksAndIsIdempotent() {
        let once = HookInstaller.installing(.claude, command: command, into: herdr)
        let twice = HookInstaller.installing(.claude, command: command, into: once)
        #expect(HookInstaller.isInstalled(in: twice))
        #expect(commands(twice, "SessionStart").count == 2, "Herdr's and ours, once")
        #expect(commands(twice, "PermissionRequest") == [command])
        #expect(twice["model"] as? String == "opus", "other settings untouched")
        let entry = ((twice["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]]
        #expect(entry?.first?["async"] as? Bool == true, "Claude never waits on nocchi")
    }

    @Test func removesExactlyOurs() {
        let installed = HookInstaller.installing(.claude, command: command, into: herdr)
        let removed = HookInstaller.removing(from: installed)
        #expect(!HookInstaller.isInstalled(in: removed))
        #expect(commands(removed, "SessionStart").count == 1)
        #expect(commands(removed, "Stop").isEmpty)
        #expect((removed["hooks"] as? [String: Any])?.keys.sorted() == ["SessionStart"], "emptied events are dropped")
        #expect(HookInstaller.removing(from: HookInstaller.installing(.claude, command: command, into: [:]))["hooks"] == nil)
    }

    @Test func codexEntriesAreSynchronousAndCoverItsEvents() {
        let settings = HookInstaller.installing(.codex, command: "'/x/nocchi-hook' codex", into: [:])
        #expect(commands(settings, "Interrupt") == ["'/x/nocchi-hook' codex"])
        #expect(commands(settings, "Notification").isEmpty)
        let entry = ((settings["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]]
        #expect(entry?.first?["async"] == nil)
    }

    @Test func enablesCodexHooksInConfig() {
        #expect(HookInstaller.enablingCodexHooks(in: "[features]\nhooks = true\njs_repl = false\n") == nil)
        #expect(HookInstaller.enablingCodexHooks(in: "model = \"x\"\n[features]\njs_repl = false\n")
            == "model = \"x\"\n[features]\nhooks = true\njs_repl = false\n")
        #expect(HookInstaller.enablingCodexHooks(in: "[features]\nhooks = false\n") == "[features]\nhooks = true\n")
        #expect(HookInstaller.enablingCodexHooks(in: "model = \"x\"\n") == "model = \"x\"\n\n[features]\nhooks = true\n")
        #expect(HookInstaller.enablingCodexHooks(in: "[other]\nhooks = false\n[features]\n")
            == "[other]\nhooks = false\n[features]\nhooks = true\n", "only the [features] section counts")
    }

    @Test func installsFilesWithBackups() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "nocchi-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let codex = home.appending(path: ".codex")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try #"{"hooks":{"SessionStart":[{"hooks":[{"command":"herdr","type":"command"}]}]}}"#
            .write(to: codex.appending(path: "hooks.json"), atomically: true, encoding: .utf8)
        try "[features]\njs_repl = false\n".write(to: codex.appending(path: "config.toml"), atomically: true, encoding: .utf8)
        let bundled = home.appending(path: "nocchi-hook-bundled")
        try Data("binary".utf8).write(to: bundled)

        let changed = try HookInstaller.install(.codex, bundledBinary: bundled, home: home)
        #expect(changed.map(\.lastPathComponent) == ["hooks.json", "config.toml"])
        #expect(HookInstaller.isInstalled(.codex, home: home))
        #expect(try String(contentsOf: codex.appending(path: "config.toml"), encoding: .utf8).contains("hooks = true"))
        #expect(FileManager.default.fileExists(atPath: HookInstaller.hookBinary(home: home).path))
        let backups = try FileManager.default.contentsOfDirectory(atPath: codex.path).filter { $0.contains(".nocchi-backup-") }
        #expect(backups.count == 2)

        try HookInstaller.uninstall(.codex, home: home)
        #expect(!HookInstaller.isInstalled(.codex, home: home))
        let left = try String(contentsOf: codex.appending(path: "hooks.json"), encoding: .utf8)
        #expect(left.contains("herdr"))
    }
}
