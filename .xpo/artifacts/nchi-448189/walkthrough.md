## What was built
If you dismiss the chat field while the pointer is away from the notch, the notch now collapses in one motion and the composer goes out with it. Dismissing means clicking another app or the desktop, or pressing Esc. Before this change it took two steps: the composer shrank back into the focus card, then `collapseDelay` (350 ms) later the notch collapsed.

## Why it happened
Closing the field sets `prompt = .none`. That has two effects:
1. The overview animates the composer back into the cards.
2. `NotchController.promptChanged(.none)` calls `scheduleModeChange()`. Because the pointer is outside, that schedules a collapse after the 350 ms grace period that normally absorbs small hover overshoots.

## How the pieces fit
- **`NotchModel.dismissComposer()`** is the single path for *user dismissals*. It only acts while composing, sets `prompt = .none`, then calls `onDismissComposer`. The callers are:
  - the panel's `didResignKey` observer (a click elsewhere), still skipped while the folder picker is up because the panel isn't key then;
  - the composer's `.onExitCommand` (Esc).
- **`NotchController.collapseIfAway()`** is wired to `onDismissComposer`. If the pointer is outside `model.hitRect` and nothing else holds the notch open (`holdsOpen`: pinned, a drop in progress, the folder picker), it calls `setMode(.collapsed)`. `setMode` cancels the delayed change that `promptChanged` just scheduled. The prompt change and the mode change land in the same run-loop turn, so SwiftUI animates them as one transition.

## Decisions
- **Pointer read directly, not `isHovering`.** `isHovering` is updated by mouse tracking and can lag behind a click elsewhere. `hitRect.contains(NSEvent.mouseLocation)` is always current.
- **Home and a finished send are deliberately excluded.** They still set `prompt = .none` directly. Home is a click on the notch, so the pointer is inside. After a send, the user should see the composer return to the cards and the new state. Both keep the shrink-back animation.
- **Esc was added during review.** The first version only handled a click elsewhere. The user asked for Esc with the pointer away to skip the main view too, which led to the shared `dismissComposer()` path.
- **Esc re-entrancy is harmless.** `promptChanged(.none)` calls `panel.resignKey()`, which fires `didResignKey`. By then `prompt` is already `.none`, so the guard in `dismissComposer()` returns early.
