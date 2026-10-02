# Walkthrough: a newly started agent becomes the main face

## What and why
Starting an agent from the Chat tab or by dropping a folder used to leave it among the chips, so you had to find the agent you just started. Now it becomes the main face (the focus card), unless another agent needs you.

## Knowing which agent was started
`AgentAdapter.perform` now returns `AgentRef?`: the new agent for `.start`, nil for every other action. It's `@discardableResult`, so the many `try await adapter.perform(…)` call sites didn't change. `AgentStore.perform` passes the result through.

- **Herdr:** since nchi-d952cb, starting goes through `layout.apply`, whose response includes the new pane. A Herdr agent's ID is its pane, so `AgentRef(adapter: "herdr", localID: pane)` matches the agent as soon as Herdr reports it.
- **Mock:** returns the ref of the agent it adds.
- **Claude Code** (terminal-tab fallback): returns nil. The session ID only exists once Claude registers it, and this fallback is due to be replaced (Claude Desktop / Nocchi subprocess). So there's no folder-matching guesswork, and that path simply doesn't change the main face.

## Selecting it: a selection that yields
`store.select` already existed for chip clicks. It holds until something *new* (changed after the click) needs attention. For a started agent the user chose a stricter rule: **any** other agent that needs you wins, including ones already waiting before the start.

So a selection now carries `yieldsToAnyUrgent` (`AgentStore.selectionYields`), passed as `yields:` to `AgentsState.primary` and `others`. The only change in `primary` is the takeover condition: `changedAt > selectedAt` becomes `yields || changedAt > selectedAt`. Consequences:
- **Selecting before the agent exists works:** the reference is kept and wins once the agent appears. Herdr usually reports it a moment after `layout.apply` returns.
- **While another agent needs you,** the usual urgency order picks the main face; the selection isn't cleared. When nothing else needs you, the new agent is back.
- **If the new agent asks something itself** (Claude's trust question), it stays the main face, since that's where you answer.
- **Chip clicks pass no flag,** so they behave exactly as before.

Callers: `NotchModel.sendPrompt` (new chat) and `NotchController.startAgent(in:)` (folder drop).

## Tests
- `aStartedAgentGivesWayToAnyAgentThatNeedsYou` (reducer level):
  - the selection waits for the agent to appear
  - an already-waiting agent wins, where a chip click would hold
  - the started agent comes back after
  - it stays when it asks something itself
- `startReportsTheNewAgentAndSelectingItMakesItPrimary` (store with the mock adapter): the start returns the agent, which becomes primary; a blocked agent takes over and gives it back once idle.
- Herdr integration: each of the three starts returns a distinct `herdr` ref whose pane exists.