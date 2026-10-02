# Walkthrough: PLAN.md now records history; xpo holds the open work

## What changed
- **PLAN.md, top:** a note under the intro says open work is tracked in xpo (`nchi-…` IDs, rules in CLAUDE.md), and that this file records decisions, architecture and what each milestone delivered.
- **PLAN.md, Milestones:** renamed "Milestone history". Completed `[x]` items are untouched.
- **Open items became pointers:**
  - M7: performance check → `nchi-eaa8de`; showcase recorder → `nchi-c740b3`
  - M8 (iPhone companion): four checkboxes → one line pointing to epic `nchi-7fac9b`
  - Deferred section: removed; the face drag is epic `nchi-54ffe9`, which supersedes it
- **The dropped "Bots capsule" line** went from `- [ ] ~~…~~` to a plain italic bullet. It records a decision that was tried and dropped, not open work.
- **README.md:** the pointer to PLAN.md says "milestone history", and that open work is tracked with xpo.

## Why
- **One backlog, not two.** The open items had just been filed in xpo; keeping the checkboxes too would have let the two lists drift. CLAUDE.md requires every code change to go through an xpo issue, so PLAN.md checkboxes would have been a backlog nobody enforces.
- **Pointers instead of deleting the open items.** The section headings keep their context: someone reading M7 still sees that a performance pass and a recorder were part of "polish and ship". The issue IDs lead to the current detail.

## For future readers
- New work goes in xpo, not in PLAN.md.
- PLAN.md is updated when a decision or the architecture changes (decision table, adapter interface, Herdr protocol notes, status mapping), or to summarise what a finished body of work delivered.
- The milestones were left as history and not imported into xpo; their completed items and the "Tried and dropped" notes live only here and in git history.