import NocchiCore
import Observation

/// Short messages ("Atlas needs you") shown one at a time in the middle of the collapsed notch,
/// on screens where that space isn't a camera housing. Most urgent first; a newer state of the
/// same agent replaces its queued message.
@MainActor
@Observable
public final class Ticker {
    public struct Message: Hashable, Sendable {
        public var ref: AgentRef
        public var name: String
        public var mood: Mood

        public var text: String {
            switch mood {
            case .waiting: "\(name) needs you"
            case .error: "\(name) failed"
            case .done: "\(name) finished"
            default: name
            }
        }
    }

    public private(set) var current: Message?
    @ObservationIgnored private var queue: [Message] = []
    @ObservationIgnored private var advance: Task<Void, Never>?
    @ObservationIgnored let hold: Duration

    public init(hold: Duration = .seconds(4)) {
        self.hold = hold
    }

    public func announce(_ message: Message) {
        guard message != current else { return }
        queue.removeAll { $0.ref == message.ref }
        let rank = PeekTracker.rank(message.mood)
        let index = queue.firstIndex { PeekTracker.rank($0.mood) > rank } ?? queue.count
        queue.insert(message, at: index)
        if current == nil { next() }
    }

    public func stop() {
        advance?.cancel()
        queue.removeAll()
        current = nil
    }

    private func next() {
        current = queue.isEmpty ? nil : queue.removeFirst()
        guard current != nil else { return }
        advance = Task { [weak self, hold] in
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled else { return }
            self?.next()
        }
    }
}
