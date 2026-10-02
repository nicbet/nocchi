# Try the top bar and new chat on screen

## What
A hands-on check of the top bar and new chat (commits `86262a2`, `c0957e8`), run together with the user. The user clicks; Claude watches the logs and reads state with `make live`.

Offscreen snapshots can't cover any of this: menus, the folder picker, which window has the keyboard, the terminal fallback.

## Why
Each step below runs code that has only been compiled and snapshotted, not driven. A non-activating panel is where SwiftUI menus and keyboard focus usually go wrong.

## Checks
1. **Tabs:** hover to open. Home is selected. Chat opens the new-chat field with the cursor in it, and Home closes it again. Escape also closes it.
2. **Draft survives:** type something, click outside the notch (the field closes), reopen Chat: the text is still there.
3. **Folder menu:** click the folder chip. A menu with recent and agent folders opens inside the notch; picking one updates the chip, which shows `parent/folder`.
4. **Choose…:** the folder picker opens; the notch stays open with the chat while it's up; picking a folder updates the chip; afterwards typing goes to the field again.
5. **Gear:** opens the settings menu at the pointer; the notch doesn't collapse under it in a way that breaks the menu.
6. **Source badges:** Herdr and Claude Code show green dots. Turning Herdr off in Sources turns its badge red or makes it disappear.
7. **Send through Herdr (optional, uses Claude):** send a tiny message in a scratch folder. A Herdr workspace appears, the agent starts and receives the message. The draft clears and the folder moves to the top of the recent list.
8. **Fallback (optional, uses Claude):** with Herdr turned off under Sources, send: a terminal tab opens in the folder running `claude "<message>"`, and the Claude Code source shows it.
9. **External display:** icons fit the 24 pt strip without touching the top edge awkwardly.

## Outcome
- Each failure is filed as a `bug` linked to this issue (fix now if small, with the user's OK).
- This issue's completion comment records what passed.
- No code changes in this issue itself.