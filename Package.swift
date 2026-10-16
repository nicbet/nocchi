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
        .library(name: "NocchiMascot", targets: ["NocchiMascot"]),
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
        // The face: one per Mood, drawn with Core Graphics, live or as a still frame.
        .target(name: "NocchiMascot", dependencies: ["NocchiCore"]),
        // NotchKit and views.
        .target(name: "NocchiUI", dependencies: ["NocchiCore", "NocchiMascot"]),

        .testTarget(name: "NocchiCoreTests", dependencies: ["NocchiCore"]),
        .testTarget(name: "NocchiHerdrTests", dependencies: ["NocchiHerdr", "NocchiTerminals"]),
        .testTarget(name: "NocchiMascotTests", dependencies: ["NocchiMascot"]),
        .testTarget(name: "NocchiUITests", dependencies: ["NocchiUI"]),
        .testTarget(name: "NocchiClaudeTests", dependencies: ["NocchiClaude"]),
        .testTarget(name: "NocchiTerminalsTests", dependencies: ["NocchiTerminals"]),
    ]
)
