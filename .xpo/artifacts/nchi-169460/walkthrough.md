# Walkthrough: Herdr GUI adapter (herdr-core + herdr-app)

## What and why
Herdr went from a TUI (`herdr`, one server with its own NDJSON API) to a GUI made of two independent programs:
- **herdr-core** (`hc`) runs the terminals and knows what each agent is doing.
- **herdr-app** is only the window: spaces, tabs, panes.

The old `HerdrAdapter` speaks the TUI protocol and sees none of the new agents. So there's a new module, `NocchiHerdrCore`, with a `HerdrCoreAdapter` (adapter id `hc`, shown as "Herdr"). The TUI adapter stays as "Herdr (TUI)".

## The two sockets
| | herdr-core | herdr-app |
|---|---|---|
| Path | `~/.local/state/herdr-core/default/default.sock` | `~/.config/herdr-app/herdr-app.sock` |
| Protocol | JSON-RPC 2.0, one message per line; errors carry a stable `error.data.kind` | one JSON line per connection: `{"ls":{}}`, `{"status":{}}`, `{"do":"cmd","args":{…}}`; failures are `{"error":"…"}` |
| Client | `HcClient` | `HerdrAppClient` |

Both reuse `HerdrConnection` (the blocking Unix-socket line reader from `NocchiHerdr`, now `package` access) instead of copying it. Both open a connection per request, like the TUI client. The event subscription keeps a dedicated connection read on its own thread (`HcEventStream`).

`hello` is sent first on every (re)connect. A core that speaks another API generation is reported as unavailable with a clear reason, rather than being half-understood.

## Where agents come from: `HcTracker`
`events.subscribe` returns every terminal (the snapshot), then every change in order: `created`, `status`, `turn`, `title`, `labels`, `foreground`, `lost`, `finished`, `removed` and `doc`. It also sends a `heartbeat` every 15 s, and `missed` when the subscriber fell behind.

`HcTracker` is pure and turns these into `AgentEvent`s:
- **An agent** is a *live* terminal whose program reports a status. Agents report through OSC 7501 (`ESC ] 7501 ; state=working:app=claude-code BEL`), and hc stores the result as `status`.
  - Plain shells have `status: null`, so they aren't agents.
  - When Claude exits back to its shell, `status` becomes null again and the agent is removed. If an agent starts again in the same terminal, it comes back.
  - The tracker keeps every live terminal, not just agents, so a shell that later starts an agent can be promoted.
- **Kind** comes from `status.app` (`claude-code` → `.claude` via `AgentKind(name:)`).
- **Unread `done`:** herdr-app writes the label `herdr.seen` (the turn the person has seen). `done` with `seen >= turn` is read, so it shows as `.idle`.
  - We confirmed on the real window that herdr-app only advances `seen` when the pane is actually visible. So unlike the TUI tracker, there's no frontmost-app overlay.
- **Ordering quirk:** hc sends the `status` that leaves `working` *before* the `turn` bump. Without care, a finished turn would compare against the old turn, look "seen", and flash idle before turning done. The tracker bumps the turn itself on that status change; the following `turn` event then sets the same absolute value.
- **Names** come from herdr-app's layout, which it stores *in hc* as the shared document `herdr-app`, so we don't need the window to be open.
  - Each terminal gets its space's name, else its tab's name unless that's just a number.
  - The doc is re-read whenever a `doc` event for `herdr-app` arrives.
- **Claude session ID:** hc doesn't know Claude's session, but it gives the foreground process ID. Claude's own registry has `~/.claude/sessions/<pid>.json` with `sessionId`.
  - The adapter injects that lookup into the tracker. With the session ID, `ClaudeActivityFeed` shows steps and messages, as it did with the TUI.
  - It's re-read on every change, because `/clear` starts a new session in the same process.

## The sync loop: `HerdrCoreAdapter.sync`
It has the same shape and resilience rules as the TUI adapter:
- connect (hello → subscribe → layout doc) → `.connection(.connected(version))` → snapshot → follow events
- reconnect backoff from 1 s up to 10 s
- agents only cleared after 3 failed attempts in a row, so an hc restart doesn't make faces flicker
- at launch, failure is reported right away

Specific to hc:
- `missed` re-subscribes immediately. It isn't a failure, so there's no backoff and it doesn't count as a miss.
- No traffic for 45 s (three missed heartbeats) means the line is dead, so it reconnects.

## Actions
- **prompt** → `terminal.send` (allowed a 20 s timeout, since hc only types once nobody has typed for about 3 s).
  - A known-blocked agent is refused locally.
  - The `blocked` / `not_found` / `finished` error kinds map to `AgentActionError`.
- **focus / open** → herdr-app `agent.focus {terminal}`. `open` then brings Herdr.app (`dev.herdr.app`) to the front through `TerminalApps.bringToFront`, which works around macOS 14 activation rules.
- **start:**
  - The space whose folder matches gets `tab.new` (tab named like the TUI did, via `HerdrAdapter.tabLabel`); otherwise `space.new` named after the folder, on this machine.
  - herdr-app delivers the first message as the agent's `task` once it's ready, so there's no retry dance as with the TUI.
  - The new terminal is found by diffing `ls` before and after (up to 10 s); if it isn't seen in time we return nil and the agent appears once hc reports it.
  - Without the window it fails with "Open Herdr to start agents", since an agent without a pane would be invisible.

## Wiring
- **Settings:** `usesHerdrCore` ("Herdr", default on). `usesHerdr` became "Herdr (TUI)" and now defaults to *off* when never set; a stored choice is kept.
- **Sources menu, status line and overview** show both. The TUI gets the outline split icon.
- **ClaudeAdapter** used to skip sessions whose ancestor chain contains `herdr`. `ProcessContext` now takes the set of process names to leave to Herdr: `herdr` (TUI) and/or `herdr-core` (the `hold` process that parents the app's terminals), depending on which sources are on. That keeps Claude sessions from showing twice.
- **`nocchi --snapshot --live`** (and `make live`) now uses hc. `--source herdr-tui` / `--source claude` (`make live SOURCE=…`) select the others, and `--select` uses the chosen adapter's IDs.

## Tests
- `HcTrackerTests`: fixtures copied from a real hc 0.1.19. They cover the snapshot filter, the no-flicker turn, blocked/error, removal and re-appearance, created terminals, the title rule, names from the layout, session lookup and notification decoding.
- `HerdrCoreIntegrationTests`: against a throwaway core (`IsolatedHerdrCore`).
  - It has its own `HC_SOCKET` under `/tmp/nocchi-it-*`, its own XDG state and config, and `HC_*` stripped. It's started, restarted and stopped with `hc server …`, so the operator's core is never touched.
  - Agents are a shell loop that echoes each line it's sent as an OSC 7501 report.
  - The adapter points at a herdr-app socket nobody listens on, so tests never move the real window.
  - Covered: the shared `AgentAdapterContract`, a full turn plus prompt plus the blocked refusal, and actions failing cleanly without a window.
- `HcSchemaDriftTests` / `HcSchema`: every `HcRequest` (and every request the adapter sent during integration tests) is checked against `hc schema` (OpenRPC) for method, parameter names, required parameters and string types.

## Known limits (v1)
- `isFocused` isn't set: herdr-app's `status.agent` didn't reliably mean "the focused pane".
- Remote machines and sub-agents are ignored.
- Chat and drop always start Claude, and which source starts agents follows the store's automatic rule. Follow-ups are filed for choosing the agent and destination, and for file/URL drops.
