# Headless bot runtimes and the `bots` adapter

## What
A `BotsAdapter: AgentAdapter` (`AdapterID "bots"`, capabilities `[.focus, .prompt, .steps, .thinking, .errors]`) that reports every bot from `BotStore` and runs each one as a supervised headless process through a `BotRuntime` protocol, with two implementations: `ClaudeRuntime` and `CodexRuntime`. Where the process runs is decided by a `ProcessLauncher`: `HostLauncher` (your Mac, `computer = "host"`) or `VMLauncher` (inside the bot's Linux VM, nchi-c72bcc; the default).

## Why
Part of nchi-a4f8e6. This replaces "an agent is a terminal" with "Nocchi owns the process".

## Runtimes
**Claude** (one long-lived process per awake bot):
`claude -p --input-format stream-json --output-format stream-json --verbose --permission-mode bypassPermissions --model <model> --append-system-prompt <persona> --mcp-config <nocchi-mcp.json>`, plus `--session-id <new uuid>` the first time or `--resume <sessionID>` afterwards. cwd = the bot's folder (the same path inside a VM). Each message is written to stdin as a stream-json user message. Nocchi reads the events (system/init, assistant, tool_use, result) from stdout.

**Codex**: `codex app-server` over JSON-RPC stdio. `initialize`, then `thread/start` (model, instructions = persona, approval policy never, full-access sandbox, MCP config) or `thread/resume {threadId}`, then `turn/start` per message. Nocchi reads the item/turn notifications.

Both runtimes only see a `LaunchedProcess` (stdin, stdout, stderr, exit status, terminate), so they work the same on the host and in a VM.

## Launchers
- `HostLauncher`: Foundation `Process` with the login shell's environment, in its own process group.
- `VMLauncher` (implemented in nchi-c72bcc): asks `VMManager` to wake the bot's computer, then starts the command through `nocchi-guest` over vsock with stdio streamed back. Harness credentials are passed in the environment (`CLAUDE_CODE_OAUTH_TOKEN`; Codex `auth.json` copied in by nchi-c72bcc).
- Session and thread state for a VM bot live inside the VM's disk (`~/.claude`, `~/.codex`), so `--resume` and `thread/resume` work there. The IDs are still saved in the bot's state file on the host.

## Mapping to AgentStatus
- No process: asleep (`.idle` with no recent change, so the face dozes; or add a dedicated `asleep` status if the reducer needs one)
- Computer waking or process starting: `.starting` (step: "waking its computer" while a VM restores or boots)
- Waiting for a free VM slot: `.starting` with step "waiting for a computer"
- Turn running, no tool: `.thinking`; tool use: `.working`, with a `.step` per tool call
- Turn ended: `.done`
- `ask_user` pending (nchi-5a9c2c): `.blocked`
- Process crashed or non-zero exit: `.error(message)`

## Acceptance criteria
- Messaging an asleep Claude bot starts the process, sends the message, shows thinking/working/done, and saves the session ID.
- After quitting and relaunching Nocchi, messaging the same bot resumes its conversation (it remembers earlier context). The same holds for Codex with the thread ID. True for host bots and VM bots.
- A bot idle for 15 minutes (configurable) has its process stopped and goes back to asleep; a VM bot's computer is suspended too (nchi-c72bcc). The next message resumes it.
- Quitting Nocchi stops all bot processes; none are left orphaned (process group, or a check that the parent is alive; VMs are stopped by nchi-c72bcc).
- A crashing harness shows `.error` with stderr's last line, and the next message retries.
- A message sent while a turn is running is queued (Claude stream-json accepts queued input; Codex: wait for the turn to finish, or use `turn/steer` if available).
- The contract tests (`AgentAdapterContract`) pass with a fake runtime and a fake launcher.
- An integration test against the real `claude`/`codex` on the host, skipped when not installed, like the Herdr tests.

## Flow
1. `ProcessLauncher` and `LaunchedProcess` protocols; `HostLauncher`.
2. `BotRuntime` protocol: `start(identity, state, launcher)`, `send(text)`, `interrupt()`, `stop()`, and `events: AsyncStream<RuntimeEvent>`.
3. `ClaudeRuntime`: line-delimited JSON reader over `LaunchedProcess`.
4. `CodexRuntime`: a JSON-RPC client (reuse the JSON-RPC handling in `HerdrConnection`/`HcClient` where it fits).
5. `BotsAdapter`: combines BotStore, the launchers and the runtimes, handles the idle timeout, writes state. Picks the launcher from the bot's `computer`.
6. Wire it up in `AppDelegate` with a Sources › Bots setting (on by default).
7. Host harness binaries: `claude` and `codex` on the login shell's PATH. A GUI app doesn't inherit the PATH, so look it up once via `zsh -lc 'command -v claude'`. In a VM they're at fixed paths in the base image.
8. Expose per-harness model suggestions (Claude: opus/sonnet/haiku; Codex: app-server `model/list` where available) for the new-bot form.

Build this with `HostLauncher` first (`computer = "host"`), so the runtimes can be tested before the VMs exist; `VMLauncher` arrives with nchi-c72bcc.

## Decisions
- One long-lived process per awake bot, not one process per message: no startup cost per message, and the stream-json/app-server protocols are built for it.
- Full permissions: `bypassPermissions` / never-approve plus full access. The developer decided this. By default this reaches only the bot's VM.
- The launcher is separate from the runtime, so the harness code is the same on the host and in a VM.
- Host process environment: the login shell's environment, so tools see the user's PATH, tokens, etc.

## Edge cases
- HIGH: an orphaned host process keeps running with full access after Nocchi crashes. Must be handled: a process group plus a watchdog, or a stdin-closed means exit check. (VM processes die with the VM.)
- MEDIUM: the Codex app-server schema is unstable. Pin a minimum Codex version (also in the base image) and add a schema drift test based on `codex app-server generate-json-schema`.
- MEDIUM: a long-running turn while Nocchi quits. Interrupt, then wait up to 5 s, then kill.
- LOW: the harness isn't installed (host). The bot shows `.error("claude not found")`.

## Resolved (2026-11-13)
- Idle timeout: 15 minutes by default.
- Model choice: a list of suggestions per harness plus free text.
- Where bots run: their own Linux VM by default, the host by opt-in (nchi-c72bcc).
