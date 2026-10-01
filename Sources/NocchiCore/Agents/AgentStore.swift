import Foundation
import Observation

/// Runs adapters and keeps the current `AgentsState` for the UI.
@MainActor
@Observable
public final class AgentStore {
    public private(set) var state = AgentsState()
    /// Moods depend on time (sleep, celebrations), so the store ticks `now` forward.
    public private(set) var now = Date()

    @ObservationIgnored private var runs: [AdapterID: (adapter: AgentAdapter, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var clock: Task<Void, Never>?

    public init() {}

    /// Chosen in nocchi (a chip click). Shown as the primary face unless something is urgent.
    /// Local on purpose: selecting doesn't switch panes in the terminal.
    public private(set) var selected: AgentRef?

    public var primary: AgentEntry? { state.primary(at: now, preferring: selected) }
    public var others: [AgentEntry] { state.others(at: now, preferring: selected) }

    public func select(_ ref: AgentRef?) {
        selected = ref
    }

    public func mood(of entry: AgentEntry) -> Mood { entry.mood(at: now) }

    /// See `AgentsState.others(at:fitting:)`.
    public func others(fitting spots: Int) -> (shown: [AgentEntry], hidden: [AgentEntry]) {
        state.others(at: now, fitting: spots, preferring: selected)
    }

    /// The mood that tints a "+N" summary of `hidden` agents.
    public func summaryMood(of hidden: [AgentEntry]) -> Mood? {
        state.mostUrgent(hidden, at: now).map(mood(of:))
    }

    /// Starts consuming `adapter`'s events. Replaces a running adapter with the same ID.
    public func run(_ adapter: AgentAdapter) {
        stop(adapter.id)
        let id = adapter.id
        let task = Task { [weak self] in
            for await event in adapter.events() {
                guard !Task.isCancelled else { break }
                self?.apply(event, from: id)
            }
        }
        runs[id] = (adapter, task)
        startClock()
    }

    /// Stops an adapter and forgets its agents.
    public func stop(_ id: AdapterID) {
        runs[id]?.task.cancel()
        runs[id] = nil
        for ref in state.agents.keys where ref.adapter == id { state.agents[ref] = nil }
        state.connections[id] = nil
    }

    public func perform(_ action: AgentAction) async throws {
        let adapterID: AdapterID = switch action {
        case .focus(let ref), .open(let ref), .prompt(let ref, _): ref.adapter
        case .start: runs.first { $0.value.adapter.capabilities.contains(.start) }?.key ?? "none"
        }
        guard let adapter = runs[adapterID]?.adapter else { throw AgentActionError.failed("No adapter \(adapterID)") }
        try await adapter.perform(action)
    }

    /// Whether any running adapter can start new agents.
    public var canStartAgents: Bool {
        runs.values.contains { $0.adapter.capabilities.contains(.start) }
    }

    public func capabilities(of ref: AgentRef) -> AdapterCapabilities {
        runs[ref.adapter]?.adapter.capabilities ?? []
    }

    /// Applies one event. Normally fed by `run(_:)`; public for previews and snapshots.
    public func apply(_ event: AgentEvent, from adapter: AdapterID) {
        now = Date()
        AgentReducer.reduce(&state, event, from: adapter, now: now)
    }

    private func startClock() {
        guard clock == nil else { return }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.now = Date()
            }
        }
    }
}
