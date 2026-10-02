# Walkthrough: on-screen check of the top bar and new chat

There's no code change. This issue was a hands-on check, run with the user, of the top bar and new chat (`86262a2`, `c0957e8`), the parts offscreen snapshots can't cover.

## Passed
- Tabs (Home / Chat / Esc), the draft surviving a click outside, the folder menu inside the non-activating panel, Choose… (the chat stays open behind the picker), the gear's menu at the pointer, and the source badges reacting to Sources.
- On an external display, the icons fit the 24 pt strip well.

## Found, filed separately
- **nchi-448189:** clicking outside closes in two steps (the composer shrinks, then the notch collapses).
- **nchi-0b5987:** in an untrusted folder, Claude's trust question blocks the first message.
- **nchi-d952cb:** `agent.start` types into a shell that is still starting up; oh-my-zsh's update question ate the `c` of `claude`.
- **nchi-6b5dc7:** `agent_name_taken` when the folder already has a Herdr agent; also, an open workspace isn't reused.

The last three share one fix, specced in nchi-d952cb: start the agent as the pane's own process through `layout.apply`, with the message as an argument. A probe in an isolated Herdr session confirmed:
- argv arrives intact
- `claude` is found on PATH
- Herdr detects the agent
- `layout.apply` adds a tab to an existing workspace

## Not tested
The terminal-tab fallback (check 9). The user would rather the fallback owner be the Claude Desktop app, then a Nocchi-owned subprocess; this still needs to be filed as its own feature.