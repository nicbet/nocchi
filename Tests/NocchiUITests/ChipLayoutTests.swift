import Testing
@testable import NocchiUI

@Test func chipColumnsFollowTheOtherAgentsCount() {
    // Others (overflow chip included): 1–3 in one column, 4–6 in two.
    let shapes = (1...8).map { ChipLayout(count: $0) }.map { "\($0.columns)x\($0.rows)" }
    #expect(shapes == ["1x1", "1x2", "1x3", "2x2", "2x3", "2x3", "2x3", "2x3"])
}
