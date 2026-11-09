# README: the Herdr app source

## What
Update README.md for nchi-169460: the Herdr app (herdr-core `hc` + herdr-app) is the main Herdr source, and the TUI is optional.

## Why
The README still describes only the Herdr TUI (0.9.1+), its session/socket settings and `make live` against it.

## How
- Intro: "anything else Herdr runs" stays; no version there.
- Requirements: the Herdr app (herdr-core 0.1.19+) for Codex and the rest, for writing to agents and starting them; the Herdr TUI (0.9.1+) still works as a separate source, off by default.
- Features: notes say "(Herdr)" for both; folder drop: new tab in the folder's space, else a new space.
- Settings: Sources row; `herdrSession`/`herdrSocketPath` marked as TUI-only.
- Dev deps: `hc` for the herdr-core integration tests, `herdr` for the TUI's.
- Development: `make test` note, `make live` default plus `SOURCE=`.
- Library products: add `NocchiHerdrCore` (`HerdrCoreAdapter`).

## Acceptance criteria
- [ ] Every Herdr mention in the README is correct for both sources.
- [ ] Docs only; `swift build` not needed.
