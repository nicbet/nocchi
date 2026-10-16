# Walkthrough: expose each agent's terminal window

## What and why
AgentSpaces puts every window in a workspace by its `CGWindowID` and wants each agent in the workspace of the terminal window it runs in. Nocchi already worked this out privately to make "open" raise the exact window: the terminal app's pid plus title hints, which `WindowRaiser` matches against the app's windows and tabs. This change makes that public in two parts. Nocchi's own behavior is unchanged, apart from one deliberate fix (below).

## 1. `AgentInfo.host` (NocchiCore)
`AgentHost { pid: pid_t, windowHints: [String] }`, Hashable/Sendable, with no AppKit. `AgentInfo.host` defaults to nil in the initializer, so existing callers compile as before. A change to `host` goes through the same path as any other field: the trackers compare `AgentInfo` values and emit `.upserted`. The reducer only adds steps on a *title* change, so a host-only upsert changes nothing visible.

### Claude (`ClaudeSessionTracker`, `ClaudeAdapter`)
- The tracker already kept `hosts[session] = pid`. `applyRegistry` now also takes `titles` (session → latest `ai-title`) and sets `info.host = AgentHost(pid, [title, folder])`. These are the same hints `perform(.open)` builds (`windowHints(title:cwd:)`). Where the terminal is unknown (tmux, SSH), host stays nil.
- Finding the title means `ClaudeActivity.latestTitle`, which lists `~/.claude/projects` and tails the transcript. Doing that on every 1 s poll for every session would be wasteful, so the adapter's private `TitleCache` re-reads a session's title at most every 5 s. Hints can therefore lag a retitle by up to 5 s.

### Herdr (`HerdrTracker`, `HerdrAdapter`)
- The tracker didn't know the pid: "open" looked up Herdr's client terminal on demand. It now stores `hostPID`, and `setHost(_:)` re-derives every agent's host. `withHost` is applied wherever an agent can change (snapshot, status/title change, pane update, tab rename), so hints track new titles, tab names and workspaces. `windowHints(for:title:)` takes the title explicitly, so it can be computed for an `info` that hasn't been stored yet.
- **Fix along the way:** `paneUpdated` now records the pane's workspace. Without it, hints (and Nocchi's own "open") kept pointing at the old workspace after an agent moved.
- `HerdrAdapter(locatesHost:)` defaults to false. When on, every reconcile (connect, every 30 s, and after structural events) looks up `TerminalApps.preferred(HerdrTerminal.hostApps())`, the last-used client's terminal, the same one "open" picks. It's opt-in because it runs `ps`, which Nocchi doesn't need. AgentSpaces passes `true`.

## 2. The resolver (`WindowRaiser`, NocchiTerminals)
- `raise`'s candidate walk was pulled out into `candidates(in:)` (each window, then its tab-bar tabs) as generic `Candidate<Element>` values carrying `window`. A match on a tab therefore knows which window holds it. `bestCandidate` / `bestCandidates` wrap the existing `bestMatch`, so `raise` and the resolver share exactly the same matching. Because they're generic, tests run them on string stand-ins without Accessibility.
- `windowIDs(in:matching: [[String]]) -> [CGWindowID?]` walks the app once for several agents and returns one result per hints list, in order. `windowID(in:matching:)` calls it with a single list. It sets a 0.25 s `AXUIElementSetMessagingTimeout` on the app element so a hung terminal can't stall the caller, and gets the ID with the private `_AXUIElementGetWindow` (declared via `@_silgen_name`, as AgentSpaces does). It only reads: no actions, no attribute writes.
- **Review change:** the resolver, `isTrusted` and the AX helpers are `nonisolated`, so AgentSpaces can poll from a background task. `raise` stays on the main actor. `runsOffTheMainActor` checks this at compile time.

## Tests
- `WindowRaiserTests`: tab → its window, window → itself, earliest hint wins, no match / empty / one-letter hints → nil, batch with mixed matches and nils, callable from a detached task.
- `ClaudeSessionTrackerTests`: host = pid + [title, folder]; a new title is an upsert without a status change; no host when the terminal is unknown.
- `HerdrTrackerTests`: host appears on `setHost`, follows tab renames and titles, survives snapshots, no news for the same host, cleared with nil.

## Not verified live
`windowID` against real windows: the test process isn't Accessibility-trusted.
