## What
Dismissing the open chat with the pointer away from the notch (a click elsewhere, or Esc) should close the chat and collapse the notch in one motion, not two (composer shrinks back, then ~350 ms later the notch collapses).

## Why
The panel's `didResignKey` observer and the composer's Esc handler set `prompt = .none`. The overview animates the composer back into the focus card, then `promptChanged(.none)` calls `scheduleModeChange()`, which waits `collapseDelay` (350 ms) before collapsing because the pointer is outside.

## How
- `NotchModel.dismissComposer()` closes the field (`prompt = .none`) and then calls `onDismissComposer`. Both dismissals use it: the panel's `didResignKey` handler (a click elsewhere) and the composer's `.onExitCommand` (Esc).
- `NotchController.collapseIfAway()` is wired to `onDismissComposer`. It reads the pointer against `model.hitRect` directly (not `model.isHovering`, which may lag a click elsewhere). If the pointer is outside and nothing else holds the notch open (`!model.holdsOpen`: not pinned, no drop in progress, folder picker not up), it calls `setMode(.collapsed)` right away. `setMode` cancels the pending delayed change that `promptChanged(.none)` just scheduled.
- Otherwise today's behaviour applies (`scheduleModeChange()` via `promptChanged`).

Home (a click, so the pointer is over the notch) and a finished send are unchanged: they keep the shrink-back animation and the usual hover-based collapse.

## Acceptance criteria
- [ ] Chat open, click on another app/desktop with the pointer outside the notch → the notch collapses immediately, with the composer going out with it (single motion).
- [ ] Chat open, pointer outside the notch, Esc → same single-motion collapse, no stop at the main view.
- [ ] Chat open, pointer over the notch, Esc or Home → composer shrinks back into the cards, notch stays open.
- [ ] Folder picker open → the chat stays open (unchanged).
- [ ] Pinned (debug) → dismissing closes the chat but the notch stays expanded.
- [ ] `swift build` and `swift test` pass.
