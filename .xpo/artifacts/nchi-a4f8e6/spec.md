# Nocchi bots

## What
Persistent bots owned by Nocchi. A bot is an identity stored on disk: name, harness, model, persona, folder, face, MCP servers and **computer**. It runs headless, by default on its own Linux VM. It's restored when Nocchi launches, keeps its conversation across restarts, and can do anything on its computer, including computer use, through Nocchi's own MCP server.

## Why
Today "new agent" is really "new terminal". `HerdrCoreAdapter.start` runs `tab.new`/`space.new` in herdr-app, and the agent *is* that terminal (`AgentRef.localID` = terminal ID). So Nocchi has nothing that outlives the process, and every new agent opens a window. The developer wants easy, persistent bots in the style of GrokBot, living entirely in Nocchi, each with its own computer.

## Children and order
1. **nchi-99df2d**: identity store and lazy restore (the foundation)
2. **nchi-ae71db**: headless runtimes plus the `bots` adapter, with a launcher that's either the host or a VM (depends on 1)
3. **nchi-c72bcc**: bot computers: a Linux VM per bot (depends on 1; plugs into 2)
4. **nchi-5a9c2c**: Nocchi MCP server: computer use routed to the bot's computer, ask_user, set_mood
5. **nchi-5dc8bf**: user-defined MCP servers, given to bots (depends on 1; wired into 2)
6. **nchi-58bfcf**: UI: new-bot form, writing to a bot, transcript and Screen tab (depends on 2)
7. **nchi-42b3e7** (v2): macOS VMs as bot computers (depends on 3)

Suggested build order: 1 → 2 (with `computer = "host"` first, to get the runtimes working without VMs) → 3 → 4 → 5 → 6.

## Decisions
- **Headless only, no terminal escape hatch.** Nocchi is the only place to see a bot's work, so the transcript and Screen views are required.
- **Every bot has a computer; by default its own Linux VM** (`computer = "own"`). One VM per bot, cloned copy-on-write from a shared base image, running only while the bot is awake. `computer = "<name>"` shares a VM between bots. `computer = "host"` drives your Mac and is an explicit opt-in. macOS VMs come in v2.
- **Full trust by default, but on the bot's own computer.** Bots run without approvals or a sandbox (Claude `bypassPermissions`; Codex approvals off with full access). In a VM that reaches only the VM and the bot's shared folder. A per-bot `trust` field stays for later.
- **Computer use is Nocchi's, not the harness's.** Claude Code's computer use is unavailable in `-p` mode, and Codex's is a feature of the Codex desktop app. The Nocchi MCP server serves both harnesses and routes to the bot's computer: the VM (through the guest agent) or the host (CGEvent/ScreenCaptureKit).
- **A bot's MCP servers are part of its identity.** Pass-through and strict (nchi-5dc8bf).
- **Config in `~/.config/nocchi/`, state and VM disks in Application Support.**
- **Bots sit alongside today's agents.** Herdr and Claude Code agents are still watched as now. Bots are a third source (the `bots` adapter).

## Edge cases
- HIGH: prompt injection with full access. Mostly contained by the VM; the bot's shared folder and its own credentials are what it can still reach. For `computer = "host"` bots: the visible "driving" indicator, and Esc or a notch click to take control back.
- MEDIUM: harness CLI versions drift (the Codex app-server schema is marked unstable). Pin the minimum versions (also in the base image) and add a schema drift test, as already done for `hc`.

## Resolved (2026-11-13)
- **Today's "new agent" composer and drag-a-folder:** the composer's "new" opens the new-bot form; dropping a folder creates a quick bot there. Starting Herdr agents from the notch goes away; Herdr and Claude Code agents are still watched as before.
- **Folder:** each bot has a default folder in its identity; a message can point it elsewhere later.
- **User-defined MCP servers:** pass-through, strict, with import (nchi-5dc8bf). A gateway is deferred.
- **Computers:** Linux VM per bot in v1, macOS VM in v2, the host only by opt-in, named shared computers for bots that should share one.
