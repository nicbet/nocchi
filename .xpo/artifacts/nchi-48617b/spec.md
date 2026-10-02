# Check a real Herdr start with a first message in a throwaway session (one-time)

## What
A **one-time** check, decided with the user on 2026-10-02 instead of a committed opt-in test. A real Claude Code agent is started through `HerdrAdapter.perform(.start(…, prompt:))`:
- in an isolated `nocchi-it-*` Herdr session
- in a fresh folder Claude has never seen
- answering Claude's trust question the way a user would

It checks that the agent then answers the message it was launched with. Afterwards everything it created is removed.

## Why
The committed integration test runs a fake agent script. It proves the argv, not that Claude holds an argv prompt through its trust question and then works on it, which was the point of nchi-0b5987.

## How
1. A temporary test file in this issue's worktree, run once, then deleted. Nothing is committed. It drives the real adapter code with an injected `agentCommand`: a wrapper script `exec claude --model haiku "$@"`, which is cheap.
2. Message: "Reply with exactly the word nocchi-ok and nothing else." No tools, so no permission prompts.
3. Expected:
   1. `perform` returns a ref.
   2. The adapter's events show it `blocked` (the trust question).
   3. Answer with `pane.send_keys`: move to "Yes, I trust this folder", then Enter, confirming the selection by reading the pane first.
   4. The ref goes `working` → `done`/`idle`, and the pane shows `nocchi-ok`.

## Cleanup
- the isolated Herdr session (which ends the agent)
- the temp folder
- its project entry in `~/.claude.json`: back up the file first, then remove only that one key
- its transcript folder under `~/.claude/projects/`
- the temporary test file

## Outcome
The result is recorded in the completion comment. Failures are filed as bugs linked here. No code changes.