import NocchiCore
import Testing
@testable import NocchiUI

@Suite struct ClusterTests {
    @Test func foldsOnlyWhenSeveralOthersAreAllCalm() {
        #expect(Cluster.folds([.idle, .sleep]))
        #expect(Cluster.folds([.idle, .idle, .idle, .sleep, .idle]))
        #expect(!Cluster.folds([.idle]), "one face doesn't need a pill")
        #expect(!Cluster.folds([]))
        for busy in [Mood.working, .thinking, .waiting, .done, .error] {
            #expect(!Cluster.folds([.idle, busy, .sleep]), "\(busy) unfolds the cluster")
        }
    }
}
