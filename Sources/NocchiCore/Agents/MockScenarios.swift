import Foundation

/// A scripted sequence of agent changes.
public struct MockScenario: Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var agents: [MockAgent]
    public var script: [MockStep]
    public var loops: Bool

    public init(name: String, agents: [MockAgent], script: [MockStep] = [], loops: Bool = false) {
        self.name = name
        self.agents = agents
        self.script = script
        self.loops = loops
    }

    public static let empty = MockScenario(name: "Empty", agents: [])

    /// Every built-in scenario, for the demo menu.
    public static let all: [MockScenario] = [.showcase, .calm, .quiet, .needsYou, .failure, .crowd]

    /// Five agents going through every state in a loop (about 45 s).
    public static let showcase = MockScenario(
        name: "Showcase",
        agents: [
            MockAgent("nocchi", name: "nocchi", status: .working, title: "Start working…", focused: true),
            MockAgent("research", name: "Research", status: .working, title: "Asking Research"),
            MockAgent("calendar", kind: .codex, name: "Calendar", status: .idle, title: "Sending to Calendar"),
            MockAgent("travel", kind: .pi, name: "Travel", status: .thinking, title: "Pinging Travel"),
            MockAgent("comms", name: "Comms", status: .idle, title: "Looping in Comms"),
        ],
        script: [
            MockStep(after: 2, .step("nocchi", "Prep workspace")),
            MockStep(after: 2, .status("calendar", .working, title: "Sending to Calendar")),
            MockStep(after: 2, .step("nocchi", "Copy final outputs")),
            MockStep(after: 2, .status("travel", .working, title: "Pinging Travel")),
            MockStep(after: 3, .finish("research")),
            MockStep(after: 3, .status("comms", .blocked, title: "Approve sending the email?")),
            MockStep(after: 4, .status("comms", .working, title: "Looping in Comms")),
            MockStep(after: 3, .finish("nocchi")),
            MockStep(after: 3, .status("calendar", .error("Calendar API returned 401"))),
            MockStep(after: 4, .status("research", .idle)),
            MockStep(after: 2, .status("calendar", .working, title: "Retrying Calendar")),
            MockStep(after: 3, .finish("travel")),
            MockStep(after: 2, .finish("comms", .idle)),
            MockStep(after: 3, .status("nocchi", .working, title: "Start working…")),
            MockStep(after: 1, .finish("calendar", .idle)),
            MockStep(after: 3, .status("research", .working, title: "Asking Research")),
            MockStep(after: 2, .status("travel", .thinking, title: "Pinging Travel")),
        ],
        loops: true
    )

    /// No agents at all.
    public static let quiet = MockScenario(name: "Quiet", agents: [])

    /// One agent at work, the rest idle: the cluster folds into a pill, and unfolds while one of
    /// them wakes up for a turn (about 20 s loop).
    public static let calm = MockScenario(
        name: "Calm",
        agents: [
            MockAgent("nocchi", name: "nocchi", status: .working, title: "Polishing the notch", focused: true),
            MockAgent("docs", name: "docs", status: .idle, title: "Updated README"),
            MockAgent("api", name: "api", status: .idle, title: "Ready"),
            MockAgent("web", kind: .codex, name: "web", status: .idle, title: "Ready"),
            MockAgent("infra", name: "infra", status: .idle, title: "Ready"),
        ],
        script: [
            MockStep(after: 6, .status("api", .working, title: "Bumping dependencies")),
            MockStep(after: 4, .finish("api", .idle)),
            MockStep(after: 10, .step("nocchi", "Polishing the notch")),
        ],
        loops: true
    )

    /// One agent waiting for approval while others work.
    public static let needsYou = MockScenario(
        name: "Needs You",
        agents: [
            MockAgent("deploy", name: "deploy", status: .blocked, title: "Run `make deploy`?"),
            MockAgent("api", name: "api", status: .working, title: "Refactoring handlers"),
            MockAgent("web", kind: .codex, name: "web", status: .working, title: "Fixing flaky test"),
        ]
    )

    /// One agent failed.
    public static let failure = MockScenario(
        name: "Failure",
        agents: [
            MockAgent("setup", name: "Helper Bot", status: .error("Couldn't identify the context right now. Upload your context folder and try again.")),
            MockAgent("docs", name: "docs", status: .idle),
        ]
    )

    /// More agents than fit the 2×2 cluster.
    public static let crowd = MockScenario(
        name: "Crowd",
        agents: (1...7).map { i in
            MockAgent("agent\(i)", kind: i % 3 == 0 ? .codex : .claude, name: "agent \(i)",
                      status: [.working, .idle, .thinking, .done, .working, .idle, .blocked][i - 1],
                      title: "Task \(i)")
        }
    )
}
