# Spec: expose each agent's terminal window

## What
Additive public API so AgentSpaces can map agents → CGWindowID:
1. `NocchiCore.AgentHost { pid: pid_t; windowHints: [String] }` (Hashable, Sendable) and `AgentInfo.host: AgentHost?` (init param, default nil).
2. `NocchiTerminals.WindowRaiser.windowID(in pid: pid_t, matching hints: [String]) -> CGWindowID?` and the batch `windowIDs(in pid: pid_t, matching hints: [[String]]) -> [CGWindowID?]` (one result per hints list, same order), both `nonisolated` so callers can run them off the main thread.

## Why
AgentSpaces assigns windows to workspaces by CGWindowID; guessing from cwd is wrong when several windows share a folder. Nocchi already computes the terminal pid and title hints for "open".

## How
- **Claude:** `ClaudeSessionTracker.applyRegistry` gains `titles: [String: String] = [:]` (session → latest `ai-title`). Where the pid's host is known, `info.host = AgentHost(pid: host, windowHints: [title, folder])` — the same hints `perform(.open)` uses. Changes ride the existing `guard info != agents[id]` → `.upserted`. The adapter reads titles via `ClaudeActivity.latestTitle`, cached per session and re-read at most every 5 s (it lists `~/.claude/projects` and tails the file, too costly every 1 s poll).
- **Herdr:** `HerdrTracker` keeps `hostPID: Int32?`; `setHost(_:)` re-derives `host` for all agents and returns upserts; `update`/`apply`/`tabRenamed` refresh `host` from `windowHints(for:)` so new tab titles / workspace labels / moves propagate. The adapter looks the pid up (`TerminalApps.preferred(HerdrTerminal.hostApps())`) on each reconcile (connect, every 30 s, after structural events) only when `locatesHost` is set.
- **Resolver:** factor `raise`'s candidate collection into a private `candidates(in:)`; `raise` and `windowIDs` both use it via the pure `bestCandidate(_:hints:)` (on a generic `Candidate<Element>`, so tests cover tab vs window without AX). `windowIDs` walks the app's windows and tabs once, sets `AXUIElementSetMessagingTimeout(app, 0.25)`, and returns `_AXUIElementGetWindow` of each list's matched window (the tab's window for a tab match); `windowID` calls it with one list. `windowIDs`, `windowID`, `isTrusted` and the AX helpers (`candidates`, `tabs`, `elements`, `string`) are `nonisolated`; `raise` stays main-actor. No actions, no attribute writes. The pure `bestCandidates(_:hints:)` (one per list) is the batch's matching and is tested.

## Acceptance criteria
- `swift test` passes; Nocchi's UI/behavior unchanged (host-only upserts don't push steps or change status/changedAt).
- Claude agents in a local terminal have `host` with pid + [title, folder]; nil inside tmux/SSH.
- Herdr agents have `host` when `locatesHost: true` and a local Herdr client exists.
- `windowIDs` returns one result per hints list in order; `windowID` returns the window ID for a matching window or the window containing a matching tab; nil when untrusted / no hints / no match.
- README + PLAN mention the API.

## Agent Decisions
- **Herdr host lookup is opt-in (`locatesHost: Bool = false`, on both inits).** It spawns `ps` every reconcile; keeping it off leaves Nocchi exactly as before. AgentSpaces must pass `HerdrAdapter(socketPath:…, locatesHost: true)`. Revisit: default it on if Nocchi itself wants it.
- **Claude titles cached 5 s.** Hints may lag a new tab title by ≤5 s. Revisit if AgentSpaces needs faster.
- **Herdr with several attached clients:** the host is the preferred one (last active), same as "open".
