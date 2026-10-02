# Walkthrough: Herdr agents start as the pane's own process

## The problem
Three failures from the on-screen check (nchi-020665) all came from how new agents were started in Herdr: `workspace.create`, then `agent.start`, then `agent.prompt`.

- **`agent.start` types the agent command into the pane's shell.** Herdr thinks the pane is ready while zsh is still running its startup files. Oh-my-zsh's "update? [Y/n]" read the `c` of `claude`, and the shell ran `laude`. (nchi-d952cb)
- **The first message was a separate `agent.prompt`.** In a folder Claude hasn't trusted, Claude first asks "do you trust this folder?". The agent is blocked, the prompt is refused for 15 s, and Nocchi reported a failure for an agent that was actually running. (nchi-0b5987)
- **`agent.start` needs a unique agent name.** Nocchi named agents after the folder, so a second agent in a folder failed with `agent_name_taken`. It also always made a new workspace, even when one was open in that folder. (nchi-6b5dc7)

## The fix: `layout.apply` with a command
Herdr's `layout.apply` builds a tab from a layout tree; a pane node can carry `command` (argv) and `cwd`. A pane started this way runs the agent directly: no shell, nothing typed. Herdr still detects it as a `claude` agent, the same as with `agent.start`. This was probed by hand in an isolated session before building on it.

`HerdrAdapter.start(kind:cwd:prompt:)` now:
1. **Looks for a workspace already open in the folder** via `pane.list`, matching `cwd` or `foreground_cwd`. Paths go through `canonical` (symlinks resolved), because Herdr reports `/tmp` as `/private/tmp`.
2. **If one exists**, `layout.apply` with that `workspace_id` adds a **new tab** to it. Decided with the user: never take over an idle-looking shell.
3. **Otherwise** it calls `workspace.create` (labelled with the folder), then `layout.apply`, then closes the workspace's initial shell pane. The result is a workspace holding only the agent's tab. If `layout.apply` fails, the shell pane is closed too, so no empty workspace is left behind.
4. **The message is an argument** (`["claude", message]`) for `claude` and `codex`. Claude holds it through the trust question and starts on it once you answer. Meanwhile Herdr reports the agent `blocked`, so the face shows "needs you". Other kinds still get `agent.prompt` with the `agent_not_ready` retry.
5. **The tab is named after the message:** `tabLabel` takes the first words up to 24 characters, cut at a word, with "…". Without a message it's the kind's name. Requested by the user.

When the agent exits, its pane closes, and its workspace too if that was the last pane. Decided with the user; we don't wrap the agent in a shell.

## What went away
`agent.start`, `HerdrRequest.startAgent`, `agentName` (Herdr's name rules) and the `agent_pane_busy` retry. `herdrKind` became `HerdrAdapter.command(for:)`. It's injectable via `init(agentCommand:)`, so tests can run a script instead of a real agent.

## Tests
- `tabsAreNamedAfterTheMessage`: word cut, whitespace collapse, hard cut of one long word, kind name fallback.
- `startsAgentsInTheirFoldersWorkspace` (isolated Herdr, a fake agent script that prints its arguments):
  - an open workspace gets two new tabs (two starts in one folder: no name clash)
  - a fresh folder gets a workspace labelled with it, holding only the agent's tab
  - tab names
  - the message arrives as exactly one argument, with quotes, double spaces and `$HOME` intact
- New requests (`listPanes`, `applyLayout`) are in `HerdrRequest.all`, so the schema drift test checks them against the installed Herdr.

## Notes for later
- `layout.apply` and `workspace.create` aren't idempotent, so PLAN.md's "No resends" rule now names them.
- Making the new agent the main face is nchi-7bb337. `layout.apply` returns the pane, so `start` can report which agent it created.