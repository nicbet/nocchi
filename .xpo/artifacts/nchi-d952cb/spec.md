# Start Herdr agents as the pane's process, not by typing into a shell

Fixes three bugs found in nchi-020665 check 8:
- **nchi-d952cb:** the shell race ("claude" → "laude")
- **nchi-0b5987:** the first message is lost behind Claude's trust question
- **nchi-6b5dc7:** `agent_name_taken`, and no reuse of an open workspace

## What
`HerdrAdapter`'s `.start(kind:cwd:prompt:)` stops using `agent.start` (which types into the shell, needs a unique name, and makes the message a separate `agent.prompt`). It creates a pane whose process is the agent itself, with the message as an argument, through `layout.apply`.

## Why
Each bug comes from typing into a shell or from `agent.start`'s naming. Probed in an isolated Herdr 0.9.3 session (2026-10-02):
- `layout.apply` with a pane `command` passes argv exactly (spaces and quotes intact).
- The process gets the Herdr server's PATH, which finds `claude`.
- Herdr detects the agent (`agent: "claude"`, `blocked` while the trust question is up).
- Given a `workspace_id`, it adds a new tab to that workspace.
- Closing a workspace's last other pane keeps the workspace and its label.

## How
1. **Find the folder's workspace:** in a fresh `snapshot`, the first workspace with a pane whose `cwd` or `foreground_cwd` equals the folder (standardized path).
2. **Found:** `layout.apply {workspace_id, focus: false, root: {type: "pane", cwd, command}}`, which opens a new tab there.
3. **Not found:** `workspace.create {cwd, label: folder name, focus: false}`, then `layout.apply` into it, then `pane.close` the workspace's initial shell pane, so only the agent's tab remains. If `layout.apply` fails, close the created pane, as today.
4. **Command:** `["<agent>", <message>]`, run directly with no shell; no message argument when there's no prompt. When the agent exits, its pane closes, and so does the workspace if that was its last pane (decided 2026-10-02).
5. **Prompt as an argument** for `claude` and `codex`, whose CLIs take an initial prompt. For other kinds, start without it, then `agent.prompt` with the `agent_not_ready` retry (today's path).
6. **Tab name** (`tab_label`): the first words of the message, up to 24 characters, cut at a word boundary with "…" (e.g. "Book me an apartment…"). Without a message, the agent kind's name ("Claude"). Requested by the user, 2026-10-02.
7. **Removed:** `agent.start`, `agentName`, and the `agent_pane_busy` retry used only by it. `HerdrRequest.startAgent` stays only if something else uses it; otherwise it's removed.
8. **New `HerdrRequest` factory `applyLayout`,** checked against the schema like every request (SchemaDrift).

## Acceptance criteria
- A new chat in a folder with a Herdr workspace opens a new tab in that workspace; nothing else is created.
- A new chat in a folder without one creates a workspace labeled with the folder, containing only the agent's tab.
- Integration test in an isolated Herdr session, which starts no real agent: the agent executable is injectable, and the test uses a script that prints its arguments. It checks the reuse-or-create behavior and that the pane receives the message argv exactly.
- The agent's tab is named after the message.
- No `agent_name_taken`: two chats in the same folder both start.
- Shell startup files never run for the agent's pane (no shell).
- `swift test` passes.

## Out of scope
- Making the new agent the main face (nchi-7bb337).
- The non-Herdr owner (Claude Desktop / Nocchi subprocess, to be filed).

## Decisions (2026-10-02, with the user)
1. When the agent exits, its pane closes; no fallback to a shell.
2. A reused workspace always gets a new tab; an idle-looking shell is never taken over.
