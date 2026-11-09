# Herdr GUI adapter (herdr-core + herdr-app)

## What
A new agent source for the GUI Herdr. Herdr now has two independent pieces:

| | herdr-core (`hc` 0.1.19) | herdr-app (0.1.14) |
|---|---|---|
| Owns | terminals, agent status, turns, labels, the app's layout doc | the window: spaces, tabs, panes, focus |
| Socket | `~/.local/state/herdr-core/default/default.sock` (`HC_SOCKET`, `HC_SESSION` pick others) | `~/.config/herdr-app/herdr-app.sock` (`HERDR_APP_HOME`) |
| Protocol | JSON-RPC 2.0, one message per line; `hello` → `generation: 1`; OpenRPC via `hc schema` | one JSON line per connection: `{"ls":{}}`, `{"status":{}}`, `{"do":"<cmd>","args":{…}}`; errors `{"error":"…"}` |

The TUI adapter (`NocchiHerdr`, `herdr` 0.9) stays as its own source.

## Why
The user switched to the GUI. The TUI socket no longer has their agents, so Nocchi shows nothing from Herdr.

## How
1. **New target `NocchiHerdrCore`** (depends on NocchiCore, NocchiTerminals). Adapter id `hc`, display name "Herdr".
   - Line framing: `NocchiHerdrCore` depends on `NocchiHerdr` and reuses `HerdrConnection` (made `package`) and `JSONValue`. No copy of the socket code.
   - `HcClient`: a persistent connection for requests (JSON-RPC ids, `error.data.kind`), plus a dedicated connection for `events.subscribe`. Sends `hello` first and refuses a `generation` other than 1 (`unavailable("herdr-core speaks generation N; nocchi supports 1")`).
   - `HcRequest` factories only (for the drift test): `hello`, `subscribe`, `send(terminal,text)`, `docGet("herdr-app")`.
2. **Agents (`HcTracker`, pure, fixture-tested):**
   - An agent is a **live** terminal whose `status` is non-null (a program that reported OSC 7501). `status: null` (agent exited back to the shell) or `state: finished` / `removed` → gone.
   - Kind from `status.app` (`claude-code` → `.claude`, via `AgentKind(name:)`).
   - Status: `idle`/`working`/`blocked`/`done` map directly; `error` → `.error(msg)`; unknown words keep the previous status.
   - **Unread:** herdr-app writes the label `herdr.seen` (the turn the person saw). `done` with `seen >= turn` → `.idle`; `done` with `seen < turn` → `.done`. A `labels` event can clear it.
   - `working → done|idle` emits `.turnFinished`.
   - Title from `title` (non-empty keeps previous), cwd from `foreground.cwd` else `cwd`.
   - Name: the space's name from the `herdr-app` doc (`spaces[].tabs[].root` → terminal), else a non-numeric tab name, else nil (→ folder). Doc is read at snapshot and on each `doc` event named `herdr-app`.
   - Claude session ID (for steps and messages in `ClaudeActivityFeed`): from Claude's registry `~/.claude/sessions/<foreground pid>.json` (`sessionId`), re-read on each change (`/clear` starts a new session in the same process).
   - `isFocused` is not set in v1: herdr-app's `status.agent` didn't clearly mean "the focused pane" (it named t11 while another pane was focused).
3. **Sync loop** like `HerdrAdapter`: `hello` → subscribe → `.connection(.connected(version))` → snapshot from the subscribe result → apply events in order. On `missed`, re-subscribe at once (a fresh snapshot, no backoff, not counted as a failure). No heartbeat for 45 s → reconnect. Backoff 1 → 10 s; clear agents after 3 misses (same rules as today).
4. **Actions** (capabilities `.focus, .prompt, .start, .errors`):
   - `.prompt` → `terminal.send {terminal, text}`. Refuse locally when `.blocked`; map `blocked` / `not_found` / `finished` kinds to `AgentActionError`.
   - `.focus` → herdr-app `do agent.focus {terminal}`. `.open` → same, then bring Herdr.app to the front (`NSRunningApplication` by bundle/name, via `TerminalApps.bringToFront`). App not running → `.failed("Herdr's window isn't open")`.
   - `.start` → herdr-app: the space whose `folder` equals cwd (canonical) gets `tab.new {space, folder, argv:[cmd], task, name}`; else `space.new {name: folder name, folder, argv, task}`. The new terminal is found by diffing `ls` before/after (unless the reply names it). Window not running → `.failed("Open Herdr to start agents")` (v1; an hc-only start would leave the agent without a pane).
5. **Settings & wiring:** `usesHerdrCore` (default **true**), shown as "Herdr"; existing toggle renamed "Herdr (TUI)" and defaults to **false** for new installs (stored values kept). `--live` defaults to hc; `--source herdr-tui` keeps the old one. Status menu line: "Herdr <version>" / "Connecting to Herdr…".
6. **No duplicates with ClaudeAdapter:** the ancestor walk also recognizes `herdr-core` (the `hold` process). Replace `leavesHerdrToHerdr: Bool` with which hosts to leave: `[.herdrTUI, .herdrCore]` per enabled sources.
7. **Tests:**
   - `HcTrackerTests` with fixtures captured from the real core (subscribe result, `status`/`labels`/`title`/`foreground`/`removed`/`missed` events).
   - Contract + integration against an isolated core (`HC_SOCKET=/tmp/nocchi-it-<rand>/hc.sock`, own `XDG_STATE_HOME`/`XDG_CONFIG_HOME`, `HC_*` stripped; `hc server start|restart|stop`), agents simulated by a shell loop printing each line it's sent as OSC 7501 (`ESC ] 7501 ; state=working:app=fake BEL`). The adapter under test points at a herdr-app socket nobody listens on. Skipped when `hc` isn't installed.
   - `make live` renders from hc; `make live SOURCE=herdr-tui|claude` for the others.
   - Schema drift: every `HcRequest` validated against `hc schema`.

## Acceptance criteria
- [x] With Herdr.app + hc running, every agent terminal shows in the notch with the right kind, status, name and title; exiting the agent removes it.
- [x] A finished turn shows `done` until seen in Herdr (`herdr.seen`), then `idle`.
- [x] Prompt from the Composer reaches the agent; a blocked agent refuses with a clear message.
- [x] Clicking an agent focuses its pane in Herdr.app and raises the window.
- [x] Starting an agent from Chat/drop opens a tab (or space) in the folder with the message as its task, and it becomes the main face.
- [x] Killing/restarting hc: agents survive short hiccups, reconnect, re-snapshot.
- [x] Claude sessions in hc terminals are not shown twice.
- [x] TUI adapter still works when enabled.
- [x] `swift test` passes; contract, tracker and schema drift tests cover the new adapter.

## Decisions
- Separate adapter, not a mode of `HerdrAdapter`: the protocols share nothing but line framing.
- hc is the source of truth for agents; herdr-app only for window actions, focus and names (from hc's doc, so names work even with the window closed).
- Unread comes from herdr-app's `herdr.seen` label rather than nocchi's own frontmost tracking.

- herdr-core sends `status` (leaving working) *before* the `turn` bump; the tracker bumps the turn itself on that status so a finished turn doesn't flash as seen.

## Verified on the real window (2026-11-09)
- Click → `agent.focus` switched to the right pane and Herdr came to the front.
- Folder drop → `space.new` named after the folder; Chat → `tab.new` in the folder's existing space.
- herdr-app sets `herdr.seen` only when the pane is actually visible: with the pane hidden and another app in front, `done` held until the click, then `idle`. No frontmost overlay needed.

## Out of scope
Remote machines (`hc machine`), sub-agents (`sub_agents`), framed/attach streams.
