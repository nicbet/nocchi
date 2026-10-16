# Walkthrough: library products + NocchiMascot

## Why
AgentSpaces reuses Nocchi's business logic through `.package(path: "../nocchi")`, and later through a git URL with a version tag. It needs agent state, terminal and window lookup, the live adapters, and the faces, but not the notch UI.

## Package shape
- **Library products:** `Package.swift` exports NocchiCore, NocchiTerminals, NocchiClaude, NocchiHerdr and NocchiMascot, one product per target. The modules were already mostly `public` because the app target crosses module boundaries.
- **The one gap outside the faces:** `ProcessTable.Entry` had no public init, so an outside package couldn't build a fake process table. It now has `public init(pid:ppid:tty:args:)`.
- **NocchiMascot** is the only real refactor. `Sources/NocchiUI/Mascot/*` moved into its own target, which depends only on NocchiCore (for `Mood`). It holds FaceParams, FaceMotion, FaceRenderer, FaceNSView, FaceView, FacePalette/RGBA, MoodGallery and the face environment values. NocchiUI depends on it, and each NocchiUI file imports it explicitly (no `@_exported`).
- **Tests:** the face, palette and motion tests moved to `NocchiMascotTests`.

## Non-obvious decisions
- **Reduce Motion is split in two.** FaceView reads `\.nocchiReducesMotion`, which used to be declared in NocchiUI's `NocchiSettings.swift`.
  - The declaration moved to `NocchiMascot/FaceEnvironment.swift`, and a public `facesReduceMotion(_:)` modifier lets other apps set it.
  - The resolver that combines the system setting with NocchiSettings stays in NocchiUI, so the mascot knows nothing about Nocchi's settings.
- **`MoodGalleryWindow` stays in NocchiUI** (`NotchKit/MoodGalleryWindow.swift`), because it resolves reduced motion through NocchiSettings. The `MoodGallery` view itself is in NocchiMascot. As a result, the app target doesn't need to depend on NocchiMascot.
- **The face API:**
  - **FaceParams:** public with an init whose defaults match the old values. It is `Sendable` and `Equatable`.
  - **FaceMotion:** public, with `mood` publicly readable and privately settable.
  - **Still internal:** accessory colours (`FacePalette.eye`, `ring`, …) stay internal until someone needs them.

## Gotchas for consumers
- SwiftPM names a path dependency after its directory, so the folder must be called `nocchi`. An `.xpo/worktrees/...` folder needs a symlink.
- To render faces offscreen with `ImageRenderer`, use `.facesRenderStill().facesReduceMotion(true)`.

## Verified
- 140 tests pass and `make snapshot` renders.
- A scratchpad consumer depending on all five products builds and runs. It covers AgentStore with MockAdapter, AgentReducer, both adapters, ProcessTable, TerminalApps.host, WindowRaiser and every face.