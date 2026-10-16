# Spec: leave a Claude session to Herdr only when it is the pane's own agent

## What
Narrow `insideHerdr` in `ClaudeAdapter`'s `ProcessContext`. A `claude` process counts as Herdr's only if `herdr` is its nearest ancestor once login shells are skipped. "Any ancestor is `herdr`" is too broad.

## Why
Herdr lists a pane in `agents[]` only when the agent is the pane's foreground program: `claude` typed into the pane shell, or started by Nocchi the same way. When another program (`xpo`, an SDK server, a script) spawns `claude`, Herdr sees that program instead. ClaudeAdapter currently drops the session anyway, so it falls between the two adapters.

## How
1. Add a pure rule that takes `claude`'s ancestor chain (nearest first). Walk up while the entry is a shell (`zsh`, `bash`, `sh`, `fish`, `dash`, `ksh`, `tcsh`, `nu`; a leading `-` for login shells is stripped). The session is Herdr's if the first non-shell entry is `herdr`.
   - `claude → -zsh → herdr` → Herdr's (unchanged).
   - `claude → herdr` → Herdr's.
   - `claude → xpo → -zsh → herdr` → ClaudeAdapter's (the fix).
   - `claude → -zsh → login → ghostty` → ClaudeAdapter's (unchanged).
2. `ProcessContext.lookup` uses this rule. `ClaudeSessionTracker` doesn't change.
3. Put the rule somewhere tests can reach it, e.g. a static function on `ClaudeAdapter` that takes `[ProcessTable.Entry]`.

## Decisions
- **Process-chain rule, not matching against Herdr's snapshot.** Herdr's agents carry no pid. Matching would need cross-adapter wiring in `AgentStore` plus cwd/pane matching. cwd matching is ambiguous when two panes share a folder. The chain rule tracks how Herdr itself decides what is an agent.
- **Known gap:** a shell wrapper such as `bash -c claude` or a `claude` shell function still counts as Herdr's. That's correct, because Herdr also sees it as `claude`.

## Acceptance criteria
- [ ] `claude → xpo → -zsh → herdr` is not left to Herdr. ClaudeAdapter shows it.
- [ ] `claude → -zsh → herdr` is still left to Herdr, so it appears once.
- [ ] Unit tests cover both chains, plus `claude → herdr` and a chain with no Herdr.
- [ ] `swift test` passes.
