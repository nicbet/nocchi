import Testing
@testable import NocchiTerminals

@Suite struct ProcessTableTests {
    let table = ProcessTable.parse("""
          1     0 ??       /sbin/launchd
       2418     1 ??       /Applications/Ghostty.app/Contents/MacOS/ghostty
       2420  2418 ttys003  /usr/bin/login -flp me /bin/zsh
       2422  2420 ttys003  -/opt/homebrew/bin/zsh
       3001  2422 ttys003  claude --resume abc
       3050  3001 ttys003  /bin/sh -c nocchi-hook claude
    garbage line
    """)

    @Test func parsesPidsTtysAndCommands() {
        #expect(table.entries.count == 6)
        #expect(table[3001]?.tty == "ttys003")
        #expect(table[2418]?.tty == nil)
        #expect(table[3001]?.command == "claude")
        #expect(table[2418]?.command == "ghostty")
        #expect(table[3050]?.args == "/bin/sh -c nocchi-hook claude")
    }

    @Test func ancestorsNearestFirst() {
        #expect(table.ancestors(of: 3050).map(\.pid) == [3001, 2422, 2420, 2418], "stops below launchd")
        #expect(table.ancestors(of: 9999).isEmpty)
    }
}

@Suite struct AppBundleTests {
    @Test func findsAppBundlesInCommandLines() {
        // iTerm: the shell's chain ends at a daemon under launchd, but login names the app.
        let table = ProcessTable.parse("""
            46336     1 ??       /Users/me/Library/Application Support/iTerm2/iTermServer-3.6.11 /Users/me/Library/Application Support/iTerm2/iterm2-daemon-1.socket
            62651 46336 ttys120  /usr/bin/login -fpl me /Applications/iTerm.app/Contents/MacOS/ShellLauncher --launch_shell
            62652 62651 ttys120  -zsh
            62700 62652 ttys120  claude
        """)
        let chain = [table[62700]!] + table.ancestors(of: 62700)
        #expect(ProcessTable.appBundles(in: chain) == ["/Applications/iTerm.app"])
    }

    @Test func noBundleNoGuess() {
        let table = ProcessTable.parse("""
            10     1 ttys001  tmux new -s work
            11    10 ttys002  claude
        """)
        #expect(ProcessTable.appBundles(in: [table[11]!] + table.ancestors(of: 11)).isEmpty)
    }
}
