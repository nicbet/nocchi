# Nocchi MCP server

## What
An MCP server inside Nocchi that every bot gets through its harness's MCP config. It provides computer-use tools that work the same for Claude and Codex, plus Nocchi-specific tools. Computer-use calls go to the bot's computer: its VM (the default, nchi-c72bcc) or your Mac (`computer = "host"`, opt-in).

## Why
Part of nchi-a4f8e6. Claude Code's computer use doesn't work with `-p` (headless), and Codex's is a feature of the Codex desktop app. One server in Nocchi gives both harnesses the same tools, and Nocchi decides which screen they act on.

## Transport
The harness starts a tiny stdio shim, `nocchi mcp --bot <slug>`, which connects to the server in Nocchi:
- Host bots: the shim is the Nocchi binary in a CLI mode, connecting over a Unix socket in Application Support.
- VM bots: the shim is part of `nocchi-guest` in the VM, connecting over vsock.
Either way, each connection knows which bot it is, and no network port is opened.

## Tools
- `screenshot(display?, window?)`: PNG scaled down, with its coordinate mapping
- `click(x, y, button?, count?)`, `type(text)`, `key(combo)`, `scroll(x, y, dx, dy)`, `drag(...)`
- `open_app(name)`, `list_windows()`, `focus_window(id)`
- `ask_user(question, choices?)`: shows the question in the notch, the bot goes `.blocked`, and the call returns the answer
- `set_mood(mood)`: the bot changes its own face for a moment

## Backends for computer use
- **VM** (default): forwarded to `nocchi-guest` in the bot's VM: an X11 screenshot of the VM's display; input with xdotool; `open_app` launches a `.desktop` entry or a command; windows via `wmctrl`.
- **Host** (`computer = "host"`): ScreenCaptureKit and CGEvent with Nocchi's Accessibility and Screen Recording permissions; `open_app`/windows via NSWorkspace and AX (reuse `WindowRaiser`). Screenshots exclude Nocchi's own panel.

## Screen lock (per computer)
A lock per computer: per VM, and one for the host. Own VMs have only one bot, so the lock only matters for named shared computers and the host. The first input call takes the lock for that bot until its turn ends. Another bot's input call fails straight away with "screen in use by <name>".
- Host: while a bot holds the lock the notch shows its face with a "driving" accent. Esc (a global key monitor) or a click on the notch takes control back and fails the bot's next input call with "user took control".
- VM: taking control in the Screen tab (nchi-c72bcc/nchi-58bfcf) does the same for that VM.

## Acceptance criteria
- A Claude bot and a Codex bot, each on its own VM, can take a screenshot and click a button in an app in their VM, at the same time.
- A `computer = "host"` bot can do the same on your Mac, and only one host bot drives at once.
- Esc stops a host bot within one action; "take control" stops a VM bot within one action.
- Without Accessibility or Screen Recording granted, host tools return a clear error, and Nocchi shows a one-time prompt to grant them. VM bots don't need these permissions.
- `ask_user` round-trips through the notch UI (the UI itself is part of nchi-58bfcf, so stub it until then).

## Decisions
- Our own MCP server, not the harness's built-in computer use (unavailable headless).
- One server, two backends, chosen by the bot's computer; the tools look the same to the model.
- Stdio shim over a Unix socket (host) or vsock (VM), not HTTP on localhost: no open port, and the bot's identity comes from the shim's argument.
- Fail fast when the screen is in use, rather than waiting.

## Edge cases
- HIGH (host): Reduce Motion / Peek: the "driving" indicator must stay visible even with peeks turned off.
- MEDIUM: multiple displays on the host. `screenshot` takes a display index; coordinates are per display. VMs have one display.
- MEDIUM: VM display resolution: fix it (e.g. 1440×900) so screenshots and coordinates stay stable; the viewer scales.
- LOW: the user moves the mouse while a host bot drives. Not treated as taking control; only Esc or a notch click.

## Resolved (2026-11-13)
- Transport: the stdio shim (Unix socket on the host, vsock in a VM). No network port.
- Screen in use by another bot: fail straight away with "screen in use by <name>".
- Computer use acts on the bot's own VM by default; the host only with `computer = "host"`.
