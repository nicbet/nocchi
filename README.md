# Nocchi

A little face that lives in your Mac's notch and shows what your coding agents are doing. Claude
Code, Codex and anything else [Herdr](https://herdr.dev) runs get a face that works, thinks, waits
for you, celebrates when it's done and dozes off when idle. Collapsed, it hugs the notch; hover and
it springs open.

![The expanded notch: the primary agent's focus card and one chip per other agent](docs/notch-expanded.png)

![An agent that needs you: the notch opens on its own](docs/notch-alert-needs-you.png)

Concept, character and interaction design by AB Babaei (@ab.workss),
building on John Bai's original "bot in the notch" idea. Go check out their work.

## What it does

- **Collapsed:** the primary agent's face on the left of the notch, up to four others in a 2×2
  cluster on the right (a "+N" badge when there are more). No text: the faces do the talking.
- **Color means state:** idle white, thinking purple, working blue, needs you amber, done green,
  failed red, asleep gray.
- **Hover:** a focus card for the primary agent (its task, current step and previous step, or its
  last message), plus a chip for every other agent. Click a chip to make that agent the primary.
- **Peeks:** when an agent needs you, the notch opens by itself. A finished or failed turn shows a
  one-line banner under the notch instead. Turns that finish in the window you're looking at stay
  quiet.
- **Click the primary face** to jump to that agent's terminal window or tab. When it's idle, click
  it to write a message to it instead (Herdr agents).
- **Drop a folder on the notch** to start a new Claude agent there (Herdr).
- **A greeting** at launch: sparks, a wave hello, and a jump into the notch.

On screens without a notch, Nocchi draws one, and its middle shows short status messages ("deploy
needs you", "2 working · 1 needs you").

## Requirements

- macOS 15 (Sequoia) or later. Works with or without a hardware notch.
- At least one agent source:
  - **Claude Code:** nothing to set up. Nocchi reads Claude's own list of running sessions
    (`~/.claude/sessions`) and their transcripts, so sessions in any terminal or IDE show up.
  - **[Herdr](https://herdr.dev) 0.9.1 or later:** for Codex and every other agent Herdr
    recognizes, and for writing to agents and starting them from the notch.

## Building it yourself

There are no prebuilt downloads: build it from source. You don't need an Apple Developer account.
Dev dependencies:

- Xcode 16 or the Swift 6 toolchain, for `swift` and `codesign`
- Optional: [Herdr](https://herdr.dev), so `make test` also runs the Herdr integration tests

```sh
git clone https://github.com/nicbet/nocchi.git
cd nocchi
make signing-cert   # 1. once: create your local signing certificate (see below)
make install        # 2. build the release app and install it in /Applications
```

Then open Nocchi from `/Applications`. `make release` builds `build/Nocchi.app` without installing
it. Nocchi has no Dock icon; it lives in the notch and a menu-bar item. To start it with your Mac,
turn on **Launch at Login** in that menu.

### Signing certificate

Nocchi isn't signed with an Apple Developer ID. Without a certificate, the build signs it ad hoc,
and an ad-hoc signature is different for every build. macOS ties the Accessibility permission to
the signature, so after each rebuild Nocchi still shows as allowed in System Settings, but the
permission no longer applies. A self-signed certificate gives every build the same identity, and
the permission survives rebuilds.

`make signing-cert` runs [`scripts/create-signing-cert.sh`](scripts/create-signing-cert.sh), which:

1. creates a self-signed certificate named "Local App Signing" with `openssl`, valid for 10 years
   and limited to code signing,
2. imports it with its private key into your login keychain, and lets `codesign` use the key,
3. trusts it for code signing only (macOS asks for your password).

`make release`, `make app` and `make dev` (all through `scripts/bundle.sh`) check for the identity
with `security find-identity -v -p codesigning` and sign with it when it is there; otherwise they
sign ad hoc and say so. AI Bar and Cappucino use the same "Local App Signing" identity, so you only
create it once. To use a different name, set `SIGNING_IDENTITY` for both, e.g.
`SIGNING_IDENTITY="My Signing" make signing-cert release`. On the first signed build, macOS may
ask whether `codesign` may use the key: click **Always Allow**. If you granted Accessibility to an
ad-hoc build before, run `make reset-permissions` and grant it once more. To remove the
certificate, delete "Local App Signing" (certificate and key) in Keychain Access.

The app isn't notarized. A copy you build yourself opens normally. If you copy the app to another
Mac, Gatekeeper blocks it the first time: click **Open Anyway** in System Settings → Privacy &
Security, or run `xattr -dr com.apple.quarantine /Applications/Nocchi.app`.

### Optional: open the exact window

By default, opening an agent brings its terminal app to the front. To raise the exact window or tab
the agent runs in, choose **Open the Exact Window…** in the menu and grant Nocchi Accessibility
access in System Settings ▸ Privacy & Security ▸ Accessibility.

Run `make signing-cert` once before building. It creates a local code-signing certificate,
"Local App Signing", which every build is signed with, so macOS keeps the grant across rebuilds.
Without it the app is signed ad hoc, and macOS treats every rebuild as a new app: after updating,
run `make reset-permissions` and grant access again.

## Settings

All in the menu-bar item:

| Setting | What it does |
|---|---|
| Peek | **Everything** (open for "needs you", banner for finished or failed), **Only When Needed**, or **Never** |
| Play Sounds | A short sound when an agent needs you, failed or finished |
| Show Status Text | Messages in the middle of a drawn notch (screens without a hardware notch) |
| Sources | Herdr and Claude Code, each on or off |
| Screen | Which display shows the notch (Automatic picks the one with a notch) |
| Ignore Reduce Motion | Keep the animations when Reduce Motion is on (if you use it only for faster Spaces) |
| Launch at Login | Start Nocchi when you log in |

To watch a named Herdr session or a socket somewhere else:

```sh
defaults write com.github.nicbet.nocchi herdrSession <name>
defaults write com.github.nicbet.nocchi herdrSocketPath <path>
```

**Demo** in the menu plays scripted scenarios with mock agents, to see every state without running
any.

## Development

```sh
make            # list the tasks
make dev        # rebuild a debug app and relaunch it
make test       # all tests (Herdr integration tests run when herdr is installed)
make snapshot   # render the notch in every state to build/snapshots/*.png
make live       # render the notch from your real Herdr
```

`make snapshot` renders offscreen, so it needs no Screen Recording permission. The Debug menu has
the mood gallery, a greeting replay and controls to keep the notch open.

Other apps can use Nocchi's modules as library products (`NocchiCore`, `NocchiTerminals`,
`NocchiClaude`, `NocchiHerdr`, `NocchiMascot`). `AgentInfo.host` says which terminal app an agent
runs in and which titles find its window (`HerdrAdapter(locatesHost: true)` for Herdr agents), and
`WindowRaiser.windowID(in:matching:)` (or `windowIDs` for several agents in one app) turns that
into the window's `CGWindowID`, off the main thread and without raising it.

Open work is tracked with xpo.

## License

MIT. See [LICENSE](LICENSE).

## Trademarks

Claude and Claude Code are trademarks or registered trademarks of Anthropic, PBC. OpenAI and Codex
are trademarks or registered trademarks of OpenAI. Nocchi is an independent project and is not
affiliated with, endorsed by or sponsored by Anthropic or OpenAI.
