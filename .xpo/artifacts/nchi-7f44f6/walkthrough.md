# Walkthrough: README for the Herdr app source

Docs only, following nchi-169460, which added `HerdrCoreAdapter` (the Herdr app: herdr-core `hc` plus herdr-app) alongside the TUI adapter.

- **Requirements:** the Herdr app is the main Herdr source (hc 0.1.19+, with herdr-app; starting agents needs its window). The TUI (0.9.1+) is a separate source, off by default since nchi-169460 changed `usesHerdr`'s default.
- **Features:** a dropped folder in the app opens a tab in the folder's space, else a new space named after it. This mirrors `HerdrCoreAdapter.start`.
- **Settings:**
  - The Sources row names all three sources and the dedup rule (Claude sessions inside an enabled Herdr appear once, as Herdr's).
  - `herdrSession`/`herdrSocketPath` only feed `HerdrAdapter`, so they're marked TUI-only.
- **Development:**
  - The integration tests need `hc` / `herdr` and use throwaway instances.
  - `make live` defaults to the app; `SOURCE=herdr-tui|claude` selects the others.
- **Library:** `NocchiHerdrCore` is listed. The `AgentInfo.host` note says only the TUI adapter fills it: the app adapter doesn't locate host windows.
