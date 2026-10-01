// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "nocchi",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "nocchi", targets: ["Nocchi"]),
    ],
    targets: [
        // App shell: lifecycle, notch panel, menu-bar item.
        .executableTarget(
            name: "Nocchi",
            dependencies: ["NocchiCore", "NocchiHerdr", "NocchiClaude", "NocchiTerminals", "NocchiUI"]
        ),
        // Agent model, AgentAdapter protocol, store and reducer. No UI, no Herdr.
        .target(name: "NocchiCore"),
        // Terminal apps hosting agents: process tree, bring to front, frontmost watching.
        .target(name: "NocchiTerminals"),
        // HerdrAdapter: Herdr socket client and event stream.
        .target(name: "NocchiHerdr", dependencies: ["NocchiCore", "NocchiTerminals"]),
        // What Claude Code agents are doing, read from their session transcripts.
        .target(name: "NocchiClaude", dependencies: ["NocchiCore", "NocchiTerminals"]),
        // NotchKit, Mascot and views.
        .target(name: "NocchiUI", dependencies: ["NocchiCore"]),

        .testTarget(name: "NocchiCoreTests", dependencies: ["NocchiCore"]),
        .testTarget(name: "NocchiHerdrTests", dependencies: ["NocchiHerdr", "NocchiTerminals"]),
        .testTarget(name: "NocchiUITests", dependencies: ["NocchiUI"]),
        .testTarget(name: "NocchiClaudeTests", dependencies: ["NocchiClaude"]),
        .testTarget(name: "NocchiTerminalsTests", dependencies: ["NocchiTerminals"]),
    ]
)
