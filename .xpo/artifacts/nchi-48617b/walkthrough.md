# Walkthrough: one-time check with a real Claude agent

There's no code change. With the user, we decided to run this check once rather than commit an opt-in test, and to clean up afterwards.

## What was checked
The new-chat path since nchi-d952cb starts Claude as a Herdr pane's own process, with the message as an argument. The committed integration test uses a fake agent script, so it couldn't show what really mattered for nchi-0b5987: that Claude holds an argv prompt through its "do you trust this folder?" question and works on it afterwards.

A temporary test drove the real `HerdrAdapter.perform(.start(…, prompt:))`:
- in an isolated `nocchi-it-*` Herdr session
- in a fresh folder
- with the agent command injected as `exec claude --model haiku "$@"`, to keep it cheap

## Result (Claude Code v2.1.287, Haiku 4.5): passed in 8 s
1. `perform` returned the agent's ref (`herdr/w1:p2`).
2. Nocchi's adapter reported it `blocked` on the trust question, with the message not yet answered. The default option is "No, exit".
3. `pane.send_keys ["Down"]`, then `["Enter"]` trusted the folder.
4. Claude answered: `⏺ nocchi-ok`. Status went working → idle.

## Cleanup and why it was done this way
- **Session and temp folder:** removed by `IsolatedHerdr.stop()`.
- **The session's transcript folder** under `~/.claude/projects/` was checked to hold only this session, then deleted.
- **Trust entry:** accepting the question adds the folder as a trusted project in `~/.claude.json`. The file was backed up, then only that key was removed, with an atomic replace, since Claude rewrites the file often. A comparison with the backup showed the project list unchanged; only Claude's own launch counters differed.
- **The temporary test file** was deleted before closing.

## If you need this again
Recreate the test from the description above. The trust dialog's keys were Down then Enter. Match Claude's reply line (`⏺ …`), not just the word, because the prompt itself is shown in the pane too.