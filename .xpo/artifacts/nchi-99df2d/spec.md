# Bot identity store

## What
A `BotStore` (new module `NocchiBots`) that loads bot identities from `$XDG_CONFIG_HOME/nocchi/bots/*.toml` (default `~/.config/nocchi/bots/`) and their runtime state from `~/Library/Application Support/Nocchi/bots/<slug>.json`. It watches the directory, publishes the list of bots, and creates, updates and deletes bots for the UI.

## Why
Part of nchi-a4f8e6. Bots need an identity that outlives any process and Nocchi itself.

## Identity file
```toml
name     = "Reviewer"           # required, shown on the face/chip
harness  = "claude"             # claude | codex
model    = "opus"               # passed to the harness as-is
folder   = "~/Repositories/nocchi"
persona  = """You review diffs adversarially..."""
tint     = "teal"               # face accent
trust    = "full"               # only "full" for now
computer = "own"                # own (default) | "<name>" (shared VM) | host (drive the Mac, opt-in)
vm       = { cpus = 2, memory = "2G" }   # optional, for own/named VMs
mcp      = ["github"]           # optional, servers from mcp.toml (nchi-5dc8bf)
```
Slug = file name. The `AgentRef` is `bots/<slug>`, which stays stable across restarts and renames of `name`.

## State file
`{ "sessionID": "...", "threadID": "...", "lastActiveAt": "..." }`, written by the runtime (nchi-ae71db), never by hand. VM disks live separately under `Application Support/Nocchi/vm/` (nchi-c72bcc).

## Acceptance criteria
- With bot files present, launching Nocchi shows one asleep face per bot and starts no processes or VMs.
- Adding, editing or deleting a file updates the bots within about 1 s, with no restart.
- A malformed file doesn't crash anything: it's skipped and its error is shown, e.g. as a red "failed" face with the parse error. All other bots still load.
- `computer` defaults to `"own"`; `"host"` is accepted only when written explicitly; any other string is a named computer. `"own"` and `"host"` can't be used as names.
- `BotStore.create(identity)` writes a new file with a unique slug; `delete` removes the file and its state (and, through nchi-c72bcc, its VM disk).
- Unit tests: parsing, defaults, invalid files, slug collisions, `~` expansion, `computer` values.

## Flow
1. Add the TOMLKit Swift package dependency.
2. `BotIdentity` (Codable, including `Computer` enum: `.own`, `.named(String)`, `.host`, plus `VMResources`) and `BotState` types.
3. `BotStore` with a directory watcher (DispatchSource or FSEvents), publishing `[BotIdentity]`.
4. Write state atomically.

## Decisions
- TOML, not JSON: personas are multi-line prose, and TOML's `"""` strings keep them readable.
- Config and state kept apart, so dotfile sync never conflicts with session IDs.
- `computer` defaults to the bot's own VM; driving the host has to be asked for in the file.

## Edge cases
- MEDIUM: a file is renamed while the bot runs. Treat it as delete plus create: the old bot stops and the new one starts asleep with fresh state. Its VM disk is kept for a rename? Proposal: no, the new slug gets a fresh computer; a rename that should keep the computer goes through the UI, which moves the disk.
- LOW: the directory doesn't exist yet. Create it on the first `create`, and treat a missing directory as no bots.

## Resolved (2026-11-13)
- TOML, parsed with the TOMLKit Swift package (new dependency).
- `computer = own | <name> | host`, default `own`.
