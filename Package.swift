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
            dependencies: ["NocchiCore", "NocchiHerdr", "NocchiClaude", "NocchiUI"]
        ),
        // Agent model, AgentAdapter protocol, store and reducer. No UI, no Herdr.
        .target(name: "NocchiCore"),
        // HerdrAdapter: Herdr socket client and event stream.
        .target(name: "NocchiHerdr", dependencies: ["NocchiCore"]),
        // What Claude Code agents are doing, read from their session transcripts.
        .target(name: "NocchiClaude", dependencies: ["NocchiCore"]),
        // NotchKit, Mascot and views.
        .target(name: "NocchiUI", dependencies: ["NocchiCore"]),

        .testTarget(name: "NocchiCoreTests", dependencies: ["NocchiCore"]),
        .testTarget(name: "NocchiHerdrTests", dependencies: ["NocchiHerdr"]),
        .testTarget(name: "NocchiUITests", dependencies: ["NocchiUI"]),
        .testTarget(name: "NocchiClaudeTests", dependencies: ["NocchiClaude"]),
    ]
)
