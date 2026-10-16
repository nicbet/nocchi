# Spec: `shell` is a finished turn with a background command

## What
In `ClaudeSessionTracker.status(_:after:)`, treat the registry's `shell` like `idle`. `shell` means the turn is over and a background command (`run_in_background`, e.g. a dev server) is still running.

## Why
Evidence from Claude Code 2.1.301: `busy → shell` happened at the moment of the transcript's `turn_duration` line. A foreground Bash call keeps `busy`. The current mapping (`shell` → working) leaves a finished agent "working" for as long as its background command lives.

## How
- `busy` → working (unchanged)
- `waiting` → blocked (unchanged)
- `idle` or `shell` after `busy` → done (a finished turn, with `.turnFinished` as before)
- `idle` or `shell` after anything else known → idle. This covers `shell → idle` (the background command ended) and `idle → shell`. The status at that point is already `done`/`idle`, but a reported `idle` would clear `done` early, so **`shell ↔ idle` changes nothing**: return nil.
- Concretely: `idle`/`shell` after `busy` → .done; after `waiting` → .idle; after `idle`/`shell` → nil (no change); first sighting → nil (unchanged).
- Update the doc comment and PLAN's M6 line.

## Acceptance criteria
- `idle, busy, shell` → done, celebrated once; `shell → idle` afterwards keeps it done (until seen).
- `busy, waiting, shell` → idle.
- `shell → busy` (a new turn, e.g. the background command finishing wakes Claude) → working.
- `swift test` passes.
