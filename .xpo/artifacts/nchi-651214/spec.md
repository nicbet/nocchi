# Library products + NocchiMascot

## What
Export NocchiCore, NocchiTerminals, NocchiClaude, NocchiHerdr and a new NocchiMascot as `.library` products, so AgentSpaces can depend on `.package(path: "../nocchi")`.

## How
- `Package.swift`: add the library products. New target `NocchiMascot` (depends on NocchiCore). NocchiUI depends on NocchiMascot. New test target `NocchiMascotTests`.
- Move `Sources/NocchiUI/Mascot/*` to `Sources/NocchiMascot/`. Move `FaceMotionTests` and `FaceParamsTests` to `Tests/NocchiMascotTests/`.
- Add `import NocchiMascot` where needed (NocchiUI views, NotchKit, Settings).
- Make the face types and members that consumers outside the module need `public`. Add a public `ProcessTable.Entry.init`.
- Check the public surface with a throwaway consumer package in the scratchpad that uses all five products.

## Acceptance criteria
- `swift build` and `swift test` pass.
- A consumer package builds against all five products through a path dependency.
- NocchiMascot does not pull in NotchKit or the rest of NocchiUI.
- The app behaves the same (`make snapshot` renders).

## Decisions
- No `@_exported import`. Each file imports what it uses.
- `MoodGalleryWindow` stays in NocchiUI, in `NotchKit/MoodGalleryWindow.swift`, because it reads `NocchiSettings` to decide on reduced motion. The `MoodGallery` view moves to NocchiMascot.
- The `nocchiReducesMotion` environment value moves into NocchiMascot, since FaceView reads it. A public `facesReduceMotion(_:)` modifier lets other apps set it. The resolver that reads the system setting and NocchiSettings stays in NocchiUI.
- The app target doesn't depend on NocchiMascot directly, because it only uses `MoodGalleryWindow`.
- SwiftPM names a path package after its directory, so AgentSpaces must point at a directory called `nocchi`.