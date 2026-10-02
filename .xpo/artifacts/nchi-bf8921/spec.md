# Slim PLAN.md down to decisions and architecture; point to xpo

## What
PLAN.md stops being the to-do list. It keeps the goals, platform decisions, architecture, Herdr protocol notes, status mapping, repository layout, and the milestone history. Open work lives only in xpo.

## Why
Open items now exist twice, in PLAN.md checkboxes and in xpo issues. Two lists drift apart. A rule in CLAUDE.md requires every change to go through an xpo issue, so PLAN.md checkboxes would be a second, unenforced backlog.

## How
1. **Top of PLAN.md:** a short note that open work is tracked in xpo (issue prefix `nchi`), and that this file records decisions, architecture and what each milestone delivered.
2. **"Milestones" → "Milestone history".** Completed `[x]` items stay as they are: they describe what shipped and why.
3. **Open items become pointers to their issue IDs:**
   - M7: "Performance budget check" → `nchi-eaa8de`; "Showcase recorder" → `nchi-c740b3`. The detailed text moves out, since the issues already carry it.
   - M8: the four checkboxes become one line: "Planned: see epic `nchi-7fac9b`".
   - Deferred section: removed; the face drag is epic `nchi-54ffe9`.
4. **The dropped "Bots capsule" line** (`- [ ] ~~…~~`) becomes a plain bullet under M5. It records a decision, not open work, so it shouldn't look like a checkbox.
5. **README.md:109:** "The design, architecture and milestone history are in PLAN.md; open work is tracked with xpo."

## Acceptance criteria
- `grep -n -- '- \[ \]' PLAN.md` finds nothing.
- Every removed open item has an xpo issue, referenced by ID where it used to be.
- Nothing in the decisions, architecture, protocol or status-mapping sections changes.
- The README pointer matches.

## Out of scope
Rewriting or condensing the architecture text, and moving the M0–M6 history into xpo.