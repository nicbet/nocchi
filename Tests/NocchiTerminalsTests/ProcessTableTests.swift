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
