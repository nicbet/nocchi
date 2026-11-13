# Bot computers: a Linux VM per bot

## What
Every bot runs on a computer chosen by `computer` in its identity:
- `"own"` (default): its own Linux VM.
- `"<name>"`: a named Linux VM shared by every bot that sets the same name.
- `"host"`: your Mac. Explicit opt-in; this is the behaviour already specced for nchi-ae71db and nchi-5a9c2c.

Nocchi runs the VMs itself with Apple's Virtualization.framework. The bot's harness, its MCP servers and its computer-use actions all happen inside the VM. You can watch the VM's screen and take control in Nocchi.

## Why
Part of nchi-a4f8e6. Bots have full permissions and computer use. On your Mac that means a prompt injection can damage anything, only one bot can use the screen at a time, and bots compete with you for focus. A VM per bot contains the damage, lets bots use computers in parallel, and makes "the bot's own computer" part of its identity, like the products that give agents their own computer. Decided by the developer 2026-11-13: Linux VM in v1, macOS VM in v2 (nchi-42b3e7), driving the host only by opt-in, one VM per bot by default.

## Architecture
```
Nocchi (host)                                   VM (Linux arm64)
 BotsAdapter ── VMLauncher ── vsock ───────────── nocchi-guest (agent, systemd)
                                                    ├─ exec harness (claude -p / codex app-server), stdio over vsock
 Nocchi MCP server ◀── vsock ───────────────────── nocchi mcp shim (stdio MCP for the harness)
   computer tools ── vsock ─────────────────────▶ nocchi-guest: screenshot (X11), xdotool input
 Viewer: VZVirtualMachineView ◀── virtio-gpu ───── Xorg + Xfce on the VM's display
 bot folder ── virtiofs ────────────────────────▶ same absolute path in the VM
```

## Base image
- Debian arm64 (stable) with Xorg + Xfce, Chromium (Google Chrome has no Linux arm64 build), git, build tools, node and python, the `claude` and `codex` CLIs, xdotool, and `nocchi-guest`.
- Built by `scripts/build-vm-image.sh`: downloads a Debian cloud image, provisions it with cloud-init in a one-off VM, and writes `~/Library/Application Support/Nocchi/vm/base-<version>.img` (about 4–6 GB). Nocchi offers a "Set up bot computers" step the first time a bot with `computer = own` wakes, and runs the script with progress shown in the notch.
- Versioned: a new base image doesn't change existing bots' disks (they keep their clone); "reset computer" re-clones from the newest base.

## Per-bot disk
- `vm/bots/<slug>/disk.img`: an APFS `clonefile` of the base, so it only takes space for what changes. Created on first wake. Deleted with the bot. Named computers live under `vm/shared/<name>/`.
- Also per VM: the EFI variable store, the machine identifier, and the saved state file.

## Lifecycle
- **Wake** (a message to an asleep bot): restore the saved state if there is one (`restoreMachineStateFrom`, macOS 14+), else boot (EFI, about 5–10 s). Then wait for `nocchi-guest` to answer on vsock, then start the harness.
- **Sleep** (15 min idle, nchi-ae71db): stop the harness, pause, `saveMachineStateTo`, stop the VM.
- **Quit Nocchi:** save state for every running VM (with a time limit; force stop after that).
- **Limit:** at most N VMs running at once (setting, default 3). Waking one more sends the least recently used idle bot to sleep; if none is idle, the new one shows "waiting for a computer".
- **Resources per VM:** 2 vCPUs, 2 GB RAM by default; `vm = { cpus = 4, memory = "4G" }` in the identity overrides it.
- Network: NAT (`VZNATNetworkDeviceAttachment`), so the VM has internet but nothing on your LAN can reach it.

## Folder sharing
The bot's `folder` is shared read-write over virtiofs and mounted at the **same absolute path** in the VM. That way paths in the transcript, tool output and commit messages match your Mac. Only that folder is shared: no home directory, no `~/.ssh`.

## Harness sign-in inside the VM
- Claude: a long-lived token from `claude setup-token`, stored once in your Keychain (`keychain:nocchi/claude-oauth`) and passed as `CLAUDE_CODE_OAUTH_TOKEN` when the harness starts. An API key is also supported.
- Codex: `auth.json` copied into the VM's `~/.codex` on each wake from your Mac's `~/.codex` (or a Keychain item).
- A setup step in Settings: "Sign in bot computers" walks through both.

## Viewer and taking control
- The bot's transcript panel (nchi-58bfcf) gets a **Screen** tab with a `VZVirtualMachineView` of the VM's display: native, no VNC.
- **Take control** sends your mouse and keyboard to the VM and pauses the bot's computer-use tools (they fail with "user has control"). **Give back** returns control. When you aren't controlling it, the view is watch-only.

## Acceptance criteria
- A new bot with no `computer` field wakes in its own VM; `uname` in its transcript shows Linux, and `pwd` shows the bot's folder at the same path as on the Mac.
- A file the bot writes in its folder appears on the Mac immediately, and vice versa.
- The bot can open Chromium, browse, take a screenshot and click in its own VM, while another bot does the same in another VM.
- Sleep then wake restores the VM (open windows still there) without a full boot, where save/restore is supported.
- Deleting a bot deletes its disk; "reset computer" re-clones from the base.
- `computer = "host"` bots behave as specced in nchi-ae71db/nchi-5a9c2c (no VM).
- Two bots with `computer = "lab"` share one VM; their computer-use calls take turns through the screen lock.
- Quitting Nocchi leaves no VM processes running.
- The app is signed with `com.apple.security.virtualization` (works with the local signing certificate; check `make install`).

## Flow
1. `NocchiVM` module: `VMSpec` (from the identity), `VMManager` (clone, configure, start/save/restore/stop, the running limit), and the `VZVirtualMachineConfiguration` (EFI, virtio-blk, virtio-net NAT, virtio-gpu, virtiofs, virtio-vsock, keyboard/pointer, entropy).
2. `nocchi-guest` (small Linux binary, e.g. Go or Rust, cross-compiled for arm64): exec with stdio over vsock, screenshot of the X display, xdotool input, health check. Built and copied in by the image script.
3. `scripts/build-vm-image.sh` plus the first-run "Set up bot computers" flow.
4. `ProcessLauncher` protocol (nchi-ae71db): `HostLauncher` (Foundation `Process`) and `VMLauncher` (exec via `nocchi-guest`). The runtimes don't care which.
5. Route the Nocchi MCP server's computer-use tools by the bot's computer: host (CGEvent/ScreenCaptureKit) or VM (`nocchi-guest`) (nchi-5a9c2c).
6. Entitlement plus `Info.plist`/Makefile changes.
7. Named computers (`computer = "<name>"`) last, once own VMs work.

## Decisions
- One VM per bot by default, from a shared base image with copy-on-write clones: isolation between bots and parallel computer use at little disk cost. A single shared VM is available on request with named computers.
- Virtualization.framework directly, not Apple's `container` tool or Docker: those have no display, and we need a GUI desktop plus `VZVirtualMachineView` for the viewer.
- The harness runs inside the VM, not on the host driving the VM: full permissions then only reach the VM.
- vsock for host↔guest traffic, not the network: no ports, works with NAT, and only Nocchi can reach it.
- Same absolute path for the shared folder.
- Debian + Xfce + Chromium: small, stable, and arm64-native.

## Edge cases
- HIGH: the harness token inside a VM a bot fully controls. The bot can read its own credentials. Accepted (it's the user's own account, the same as on the host), but the token is only passed in the environment, never written to the base image.
- HIGH: the shared folder is the one place the VM can damage your Mac (e.g. `rm -rf` in the project). The same exposure as any coding agent. Document it, and consider a read-only option later.
- MEDIUM: save/restore may not support every device configuration (e.g. virtiofs) on every macOS version. If it fails, fall back to a full boot. Verify on the first spike.
- MEDIUM: RAM. 3 VMs × 2 GB on a 16 GB Mac is fine; the limit setting is the guard. Show memory per VM in Settings.
- MEDIUM: the base image is large to download and build (a few GB). Show progress; resume after interruptions.
- LOW: Intel Macs. Not supported (arm64 guests only). Bots there need `computer = "host"`.

## Assumptions
- Apple Silicon and macOS 15+ (already Nocchi's minimum).
- `saveMachineStateTo`/`restoreMachineStateFrom` work for Linux guests with this device set. To be verified.
