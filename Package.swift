// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "nocchi",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "nocchi", targets: ["Nocchi"]),
        .library(name: "NocchiCore", targets: ["NocchiCore"]),
        .library(name: "NocchiTerminals", targets: ["NocchiTerminals"]),
        .library(name: "NocchiClaude", targets: ["NocchiClaude"]),
        .library(name: "NocchiHerdr", targets: ["NocchiHerdr"]),
        .library(name: "NocchiHerdrCore", targets: ["NocchiHerdrCore"]),
        .library(name: "NocchiMascot", targets: ["NocchiMascot"]),
    ],
    targets: [
        // App shell: lifecycle, notch panel, menu-bar item.
        .executableTarget(
            name: "Nocchi",
            dependencies: ["NocchiCore", "NocchiHerdr", "NocchiHerdrCore", "NocchiClaude", "NocchiTerminals", "NocchiUI"]
        ),
        // Agent model, AgentAdapter protocol, store and reducer. No UI, no Herdr.
        .target(name: "NocchiCore"),
        // Terminal apps hosting agents: process tree, bring to front, frontmost watching.
        .target(name: "NocchiTerminals"),
        // HerdrAdapter: the Herdr TUI's socket client and event stream.
        .target(name: "NocchiHerdr", dependencies: ["NocchiCore", "NocchiTerminals"]),
        // HerdrCoreAdapter: the Herdr GUI. Agents from herdr-core (`hc`), window actions through
        // herdr-app. Shares only the socket line reader with NocchiHerdr.
        .target(name: "NocchiHerdrCore", dependencies: ["NocchiCore", "NocchiTerminals", "NocchiHerdr"]),
        // What Claude Code agents are doing, read from their session transcripts.
        .target(name: "NocchiClaude", dependencies: ["NocchiCore", "NocchiTerminals"]),
        // The face: one per Mood, drawn with Core Graphics, live or as a still frame.
        .target(name: "NocchiMascot", dependencies: ["NocchiCore"]),
        // NotchKit and views.
        .target(name: "NocchiUI", dependencies: ["NocchiCore", "NocchiMascot"]),

        .testTarget(name: "NocchiCoreTests", dependencies: ["NocchiCore"]),
        .testTarget(name: "NocchiHerdrTests", dependencies: ["NocchiHerdr", "NocchiTerminals"]),
        .testTarget(name: "NocchiHerdrCoreTests", dependencies: ["NocchiHerdrCore", "NocchiHerdr"]),
        .testTarget(name: "NocchiMascotTests", dependencies: ["NocchiMascot"]),
        .testTarget(name: "NocchiUITests", dependencies: ["NocchiUI"]),
        .testTarget(name: "NocchiClaudeTests", dependencies: ["NocchiClaude"]),
        .testTarget(name: "NocchiTerminalsTests", dependencies: ["NocchiTerminals"]),
    ]
)
