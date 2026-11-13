# User-defined MCP servers for bots

## What
A registry of MCP servers that Nocchi owns, `$XDG_CONFIG_HOME/nocchi/mcp.toml`, and a per-bot `mcp = [...]` field in the identity file. When a bot wakes, its runtime turns the bot's servers plus the built-in `nocchi` server into the harness's own MCP config, and the harness starts and talks to the servers itself (pass-through). Bots never see the user's global Claude or Codex MCP servers. For bots on a VM (the default, nchi-c72bcc), the harness and so the stdio servers run inside the VM.

## Why
Part of nchi-a4f8e6. The tools a bot has should be part of its identity, so it behaves the same whatever is in `~/.claude.json` or `~/.codex/config.toml` today. The developer chose pass-through (option 1) and strict mode on 2026-11-13.

## Config
```toml
# ~/.config/nocchi/mcp.toml
[servers.github]
command = "github-mcp-server"
args    = ["stdio"]
env     = { GITHUB_TOKEN = "keychain:nocchi/github" }
cwd     = "~/src"                 # optional
setup   = "npm i -g some-mcp"     # optional: run once in a bot's VM before first use

[servers.linear]
url     = "https://mcp.linear.app/mcp"
headers = { Authorization = "Bearer keychain:nocchi/linear" }
```
```toml
# bots/reviewer.toml
mcp = ["github", "linear"]
```
- A server has either `command` (stdio) or `url` (streamable HTTP), not both.
- `keychain:<service>/<account>` anywhere in an `env` or `headers` value is replaced at launch, on the host, with the generic password from the login Keychain. Plain values work too, but the import never writes secrets in plain text (see below).
- `nocchi` is a reserved name. The built-in server (nchi-5a9c2c) is always added and can't be overridden.

## Servers in a VM
- Stdio servers run inside the bot's VM, so their `command` must exist there. The base image includes node and python, so `npx`/`uvx` servers work. Anything else is installed by the server's optional `setup` command, run once per VM disk (and again after "reset computer"), with output shown in the transcript.
- Remote (`url`) servers work unchanged; the VM has internet through NAT.
- Secrets are resolved on the host and passed into the VM only in the generated config, which `nocchi-guest` writes with mode 0600 and deletes when the harness stops.
- Host bots (`computer = "host"`) run the servers on your Mac with the login shell's PATH.

## Acceptance criteria
- Claude bot: started with `--mcp-config <generated json> --strict-mcp-config`. Its system/init `mcp_servers` lists exactly the bot's servers plus `nocchi`.
- Codex bot: sees exactly the bot's servers plus `nocchi`, and none from any global `~/.codex/config.toml`.
- Works the same for a VM bot and a host bot.
- A server with `setup` runs it once in a fresh VM disk before the server is first used.
- Editing `mcp.toml` or a bot's `mcp` list takes effect the next time that bot wakes. An awake bot shows a "restart to apply" hint; no automatic restart in the middle of a turn.
- A bot naming an unknown server: the bot still starts without it, and the error is shown on the bot (in its transcript and as a warning on the chip).
- A missing Keychain item: that server is skipped with a clear error ("keychain item nocchi/github not found"), and the bot still starts.
- Import: Nocchi reads the servers in `~/.claude.json` (user-level `mcpServers`) and `~/.codex/config.toml` (`[mcp_servers.*]`) and shows a list to pick from. Picked servers are added to `mcp.toml`. Any env or header value that looks like a secret is moved into the Keychain and replaced with a `keychain:` reference. Name collisions get a suffix. Commands that are absolute host paths (e.g. `/opt/homebrew/bin/...`) are flagged "won't run in a bot's VM; add a setup command or use on host bots".
- Generated config files contain resolved secrets only in 0600 files that are deleted when the bot's process stops (host: per-bot directory in Application Support, also cleaned on next launch after a crash).
- Unit tests: parsing, validation (command xor url, reserved name), Keychain reference resolution (with a fake keychain), generated Claude JSON and Codex config, import from sample files.

## Flow
1. `MCPServerSpec` and `MCPRegistry` in `NocchiBots`, loaded and watched with `mcp.toml` alongside `BotStore` (nchi-99df2d). `mcp: [String]` is already in `BotIdentity`.
2. `SecretResolver`: Keychain `SecItemCopyMatching` for `keychain:` references; a protocol so tests can use a fake.
3. `ClaudeRuntime` (nchi-ae71db): write `{"mcpServers": {...}}` JSON through the launcher (host file, or into the VM via `nocchi-guest`) and pass `--mcp-config <file> --strict-mcp-config`.
4. `CodexRuntime`: strict isolation. On the host, start `codex app-server` with `CODEX_HOME` set to a per-bot directory holding a generated `config.toml` with only the bot's `mcp_servers`, plus a symlink or copy of `auth.json` from the real `~/.codex` so the bot stays signed in. In a VM, `~/.codex` is the bot's own, so the generated config is written there directly. If Codex accepts MCP servers per thread on `thread/start`, prefer that. Verify against the pinned Codex version.
5. `setup` commands: tracked per VM disk in a marker file inside the VM.
6. Import: `MCPImporter` reads both files and returns candidates. The UI is a sheet in Settings (and later the new-bot form, nchi-58bfcf).
7. New-bot form (nchi-58bfcf): a checklist of the registry's servers.

## Decisions
- Pass-through, not a gateway: much smaller, the same for both harnesses. The config's shape (named servers, references, per-bot lists) is what a later gateway would read, so moving to one later needs no file migration.
- Strict, with import instead of inheriting: a bot's tools are explicit and reproducible.
- Secrets come from Keychain references resolved on the host, never written to `mcp.toml` by the import; resolved values exist only in 0600 temporary files while the bot runs.
- One shared `mcp.toml` instead of one file per server: servers are short, and one file is easier to sync and hand-edit.
- Servers run where the harness runs (in the VM by default): they get the same containment as the bot.

## Edge cases
- HIGH: a separate `CODEX_HOME` on the host drops the user's Codex sign-in. Must share `auth.json` (symlink) or the bot can't authenticate.
- HIGH: secrets leaking via generated config files: 0600, deleted on stop, and also cleaned up on next launch (after a crash).
- MEDIUM: remote servers that only support OAuth. Out of scope for pass-through: the import marks them "needs sign-in, not supported yet" and doesn't add them. This is the main reason for a later gateway.
- MEDIUM: servers that only exist for macOS (e.g. ones that script Mac apps) can't run in a Linux VM. The import flags them; they work on host bots.
- LOW: the same server listed twice in a bot's `mcp`: deduplicate.

## Out of scope
- The gateway/proxy (option 2), per-bot tool allowlists, OAuth sign-in for remote servers. Each can be filed when needed.
