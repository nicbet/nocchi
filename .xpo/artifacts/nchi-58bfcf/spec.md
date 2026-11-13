# Bot UI

## What
The notch UI for bots: (1) a new-bot form, (2) writing to a bot through the existing composer, and (3) a per-bot panel with a **Transcript** tab (which also answers `ask_user` questions) and a **Screen** tab (watch the bot's computer and take control).

## Why
Part of nchi-a4f8e6. With no terminal, Nocchi is the only way to create, talk to, and see what a bot is doing, including on its own computer.

## New-bot form
Fields: name, harness (Claude | Codex segmented), model (picker of suggestions plus free text), persona (multi-line), folder (reuse the existing folder picker and `chatFolders`), tint (a row of swatches previewing the face), MCP servers (checklist from `mcp.toml`, nchi-5dc8bf), and computer: "Its own computer" (default), "Shared computer…" (pick or name one), or "This Mac". Choosing "This Mac" shows a one-line warning that the bot will control your screen and files with full permissions. Save calls `BotStore.create`, and the new bot appears asleep and becomes the primary. The composer's "new" target (today `ComposeTarget.newAgent`, which starts a Herdr agent) becomes "new bot" and opens this form. Dropping a folder on the notch creates a quick bot in that folder (default harness and model, its own computer, named after the folder) instead of starting a Herdr agent.

## Writing to a bot
A bot is a normal agent (`bots/<slug>`), so `ComposeTarget.agent(ref)` + `.prompt` already works. Unlike Herdr agents, clicking a bot's face never "opens" a terminal: it opens the bot's panel.

## Bot panel
A floating panel attached below the notch, with two tabs.
- **Transcript:** the bot's messages, its replies (markdown), and collapsed tool steps. Screenshots from computer-use calls appear as thumbnails. The composer sits at the bottom. A pending `ask_user` shows as a card with the choices or a text field. It's read from the runtime's event history, which is kept in memory per bot. On resume it shows the history from the harness's session file if cheap, else "earlier conversation not shown".
- **Screen** (VM bots): a live `VZVirtualMachineView` of the bot's VM (nchi-c72bcc), watch-only by default. **Take control** sends your input to the VM and pauses the bot's computer-use tools; **Give back** returns control. While the computer is asleep, the tab shows the last frame dimmed with "asleep". Host bots don't have this tab: their screen is yours.
- The chip and face show a small "on its computer" accent while a bot is using computer-use tools, and "driving your Mac" for host bots.

## Acceptance criteria
- Creating a bot from the form writes a valid identity file (including `computer` and `mcp`) and shows its face.
- Dropping a folder creates a quick bot there; no Herdr space or tab opens.
- Messaging a bot and watching the transcript stream the reply live.
- Answering an `ask_user` card unblocks the bot.
- The Screen tab shows a VM bot's desktop live; taking control lets you type in the VM, and the bot's next computer-use call fails with "user has control" until you give control back.
- Editing or deleting a bot from the UI (a context menu on its chip), including "Reset computer" for VM bots.
- `make snapshot` states for the form, the transcript, the ask card and the Screen tab (with a placeholder frame).

## Decisions
- Clicking a bot's face opens its panel, not a terminal (there is none).
- Panel floats below the notch, not inside the expanded notch: its 640×168 body is too small for a conversation or a screen.
- "New" means "new bot" for good; starting Herdr agents from the notch is removed.
- Driving the host is offered in the form but never the default, with a warning.

## Resolved (2026-11-13)
- Panel: a floating panel attached below the notch.
- The composer's "new" becomes "new bot" for good, replacing Herdr new-chat; a dropped folder creates a quick bot in that folder (see nchi-a4f8e6).
- Computers: own VM by default, shared named computers, "This Mac" by explicit choice (nchi-c72bcc).
