# A newly started agent becomes the main face

## What
After the Chat tab (or a dropped folder) starts an agent, that agent becomes the main face (the focus card), unless something needs you more urgently. Today it lands among the chips.

## Why
You just started it and want to see it work. Finding it among the chips takes a search.

## How
1. **Learn which agent was started:**
   - `AgentAdapter.perform` returns `AgentRef?`, the started agent for `.start` and nil otherwise. It's `@discardableResult`, so other call sites don't change. `AgentStore.perform` passes it through.
   - **Herdr:** `AgentRef(adapter: "herdr", localID: <pane from layout.apply>)`. The pane ID is Herdr's agent ID, so it matches the agent once Herdr reports it.
   - **Mock:** the ref it adds.
   - **Claude Code terminal tab:** nil. The session ID isn't known at launch. That fallback is to be replaced (Claude Desktop / Nocchi subprocess, to be filed), so no folder-matching heuristic.
2. **Select it:** after a successful start, `NotchModel.sendPrompt` (new chat) and `NotchController.startAgent(in:)` (folder drop) call `store.select(ref)`.
   - `store.select` works before Herdr has reported the agent: the reference is kept, and the agent becomes primary as soon as it appears.
3. **"Unless more urgent"** (decided with the user, 2026-10-02): **any** other agent that needs you wins over the new agent, including ones that were already waiting before you started it.
   - This is stricter than a chip click, where only what needs you *after* the click takes over. So a start selects with a flag: `store.select(ref, yieldsToAnyUrgent: true)`.
   - `AgentsState.primary` honours a yielding selection only while no other agent needs attention. Otherwise the usual urgency order picks the main face, and the new agent is part of that order if it asks something itself (e.g. the trust question).
   - When nothing else needs you any more, the new agent is the main face again (the selection stays).

## Acceptance criteria
- After a new chat through Herdr, the new agent is the main face once it appears (mock and Herdr paths).
- Any other agent that needs you (before or after the start) is the main face instead; once none does, the new agent is again.
- Chip clicks keep their current rule (only what needs you after the click takes over).
- The folder drop does the same.
- Tests:
  - store or state: a selection made before the agent appears takes effect when it does
  - integration: `perform(.start)` returns the pane `layout.apply` created
- `swift test` passes.

## Depends on
nchi-d952cb (the `layout.apply` start path, which knows the pane).
