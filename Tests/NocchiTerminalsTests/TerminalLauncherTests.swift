import Foundation
import Testing
@testable import NocchiTerminals

@Suite struct TerminalLauncherTests {
    @Test func quotesForTheShell() {
        #expect(TerminalLauncher.quote("plain") == "'plain'")
        #expect(TerminalLauncher.quote("it's $HOME `x`") == #"'it'\''s $HOME `x`'"#)
    }

    @Test func scriptRunsTheCommandInTheFolder() throws {
        let script = TerminalLauncher.script(["claude", "Book me an apartment; don't rm -rf"], in: URL(fileURLWithPath: "/tmp/my project"))
        #expect(script.hasPrefix("#!/bin/sh\n"))
        #expect(script.contains("cd '/tmp/my project' || exit 1"))
        #expect(script.contains(#"exec 'claude' 'Book me an apartment; don'\''t rm -rf'"#))
    }

    /// The quoted words reach the program unchanged.
    @Test func shellReadsTheWordsBack() throws {
        let words = ["it's", "$HOME", "a\nb", "\"q\"", "`x`"]
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "printf '%s\\0' " + words.map(TerminalLauncher.quote).joined(separator: " ")]
        let pipe = Pipe()
        shell.standardOutput = pipe
        try shell.run()
        shell.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(output.split(separator: "\0", omittingEmptySubsequences: false).dropLast().map(String.init) == words)
    }
}
