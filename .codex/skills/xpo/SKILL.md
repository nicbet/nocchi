---
name: xpo
description: >-
  Issue-tracking workflow for a repository using xpo (Exponential).
  Use before planning, implementing, fixing, or completing any code
  change; when creating or updating issues, specs, or walkthroughs;
  or when the user mentions xpo, issues, epics, or the board.
metadata:
  author: exponential
  version: "3.1"
---

# xpo Development Workflow

Use the `xpo` MCP tools and follow this workflow when working on `xpo` issues:

### 1. Check existing work

Understand what's on the board before doing anything. Call `list` to see current issues; use the
`match` parameter to search for related work. Call `show` for full details on candidate issues.

Before creating a new issue, search to ensure no existing issue already covers the work.

### 2. Plan (Write great issues)

Decide what the issue title and description should be before filing it.

- **Features/design work:** propose the idea to the user. Discuss and iterate on the proposal. Only create an issue after the user approves.
- **Bugs reported by the user:** investigate and understand the bug before filing. If possible, reproduce it or identify the root cause, then file the issue.
- **Bugs found during implementation:** file immediately and link back to the originating issue. No approval needed.

See **Issue Creation** for labels, titles, descriptions, and parent linking.

### 3. Spec (Think Before You Build)

Before implementing, ensure the issue has an up-to-date spec. If none exists, write one using the
xpo MCP server's `spec` tool. See `references/spec-guide.md` for the full spec template and scaling rules.

**Check prior rationale** — if the issue modifies or extends behavior introduced by prior work,
use the `rationale` tool to search for related specs and walkthroughs before writing the spec.
This surfaces design decisions and constraints that should inform the new work. Skip this for
greenfield features or bug fixes in code with no deliberate design history.

The spec is a thinking tool — it collapses the design space so the user can steer decisions
instead of discovering unwanted choices after the code is written. Scale the depth to the task:
a bug fix gets a brief What/Why/How/AC spec; a feature gets the full template.

**Interactive mode** (user present — CLI, IDE plugin): after writing the spec, surface open questions
and uncertainties to the user and wait for answers before implementing. The spec is a conversation
artifact — the user should confirm or redirect before code is written.

**Non-interactive mode** (headless — xpo drive, piped prompts): implement from the spec without
waiting, BUT the spec must explicitly mark where you made judgment calls. For every open question,
document the question, the answer you chose, and your reasoning. Use a dedicated section:

- **Agent Decisions** — choices made on behalf of the user where the answer was not obvious.
  Format each as: the question, the choice made, the reasoning, and what to revisit if the
  choice was wrong.

**Do not proceed to step 4 until the spec exists and (in interactive mode) the user has confirmed it.**

### 4. Start

**Before starting, check these gates:**

- Only issues with PLANNED status are eligible. If the issue is in BACKLOG, ask the user before transitioning it.
- Check the issue's dependencies. If any `depends_on` or `blocked_by` targets are not DONE, stop and ask the user how to proceed. Do not start multiple issues in a dependency chain simultaneously.
- If the issue is already in DOING and assigned to someone else, stop and ask the user before taking it over.

Set the `assignee` field to yourself via `update` before calling `start`. Use the form
`<Agent Name> <agent@<host>.local>` — e.g. `Claude Code <agent@macbook.local>`.

Then call `start` with the issue ID **before touching any file**. This transitions the issue to DOING and creates an isolated git worktree or branch (depending on configuration).

All file reads, edits, builds, and test runs must happen inside the worktree path or branch returned by `start` — not the main checkout. To resume an issue already in DOING, call `start` with `force: true`.

### 5. Implement & Test

Follow the spec — its flow steps, decisions, and edge cases are your requirements.

- If you encounter a decision not covered by the spec, make a reasonable choice and note it when you write the completion comment in step 6. If the decision is significant (would surprise the user or constrain future work), stop and ask.
- If you realize the spec has a significant gap or is wrong, stop. Explain the issue, propose a spec update, and wait for approval.
- If you discover bugs or needed work outside the scope of this issue, file them as new issues and link back to the current one. Do not fix them silently or leave TODOs.

### 6. Handoff

Verify your work before handing off:

- Run the project's build and test commands. All tests must pass.
- Review your own changes against the spec — confirm all acceptance criteria are met.

Then add a brief completion comment using the `comment` tool, summarizing what changed and any decisions not in the original spec. Keep it lightweight — the walkthrough (step 8) is where the full explanation lives.

**Stop here and wait.** The user needs to review and test your changes before anything else happens. Do not write the walkthrough, commit, or merge until the user has explicitly approved.

### 7. Revisions

When the user requests changes, update the spec to reflect the corrections **before** modifying
code. The spec must always match the final implementation. If the user's feedback changes the
approach, acceptance criteria, or decisions, those changes belong in the spec — not just in the
code diff. Without this step, the spec drifts from reality and future agents reading it will build
the wrong thing.

After applying the changes, go back to step 6.

### 8. Walkthrough

**Prerequisite:** the user has explicitly approved the changes. If the user has not responded since
your completion comment, you are NOT on this step — go back to step 6 (Handoff) and wait.

Write a walkthrough using the xpo MCP server's `walkthrough` tool. The walkthrough is the
**durable implementation record** — written from the perspective of a senior engineer explaining
the changes to a junior developer:

- What was built and why
- How the pieces fit together
- Key decisions and their rationale (including any that emerged during review)
- Anything non-obvious that a future reader would need to understand

Write the walkthrough **after** any user-requested corrections are applied, so it reflects the final state.

### 9. Complete

**Gate:** do not complete until ALL of the following are true:

1. The user has explicitly approved the changes
2. Tests pass
3. The walkthrough is written
4. All changes are committed on the issue's worktree or branch

If any are missing, go back to the missing step.

Then, in the issue's worktree (or on its branch):

1. If the project's instructions require a changelog entry, add it now.
2. Run `git status`. Delete or move scratch files that are not part of the change.
3. Commit everything: `git add -A && git commit -m "<issue-id>: <issue title>"`.
4. Call the xpo MCP server's `merge` tool. It squash-merges the branch into the default
   branch, records a MERGE event, closes the issue, and removes the worktree or branch.
   It refuses to run while the worktree has uncommitted or untracked files.

Committing on the issue's worktree or branch is your job. Merging is `merge`'s job: never run
`git merge`, `git rebase`, `git push`, or commit on the default branch yourself.

---

## Reference

### Status Graph

`BACKLOG → PLANNED → DOING → DONE; DOING ⇄ BLOCKED; any → CANCELED; any → DUPLICATE`

| Status      | Meaning                                           |
| ----------- | ------------------------------------------------- |
| `BACKLOG`   | Captured but not yet prioritised                  |
| `PLANNED`   | Prioritised and ready to be worked on             |
| `DOING`     | Actively being worked on                          |
| `BLOCKED`   | Waiting on something external                     |
| `DONE`      | Completed                                         |
| `CANCELED`  | Will not be done (obsolete, out of scope, etc.)   |
| `DUPLICATE` | Duplicate of another issue — link to the original |

### Issue Creation

- Always set a primary label (see **Issue Labels**). Add secondary labels for area/domain when useful.
- Descriptions and comments render as Markdown. Write literal newlines, not `\n` escape sequences.
- Markdown checklists (`- [ ] Title`) can sub-divide task steps.
- Keep titles under 100 characters.
- When a new issue belongs to an epic, set `parent` to the epic's ID.

### Issue Labels

Every issue MUST have exactly one **primary label** that classifies the type of work:

| Primary label | When to use                                         |
| ------------- | --------------------------------------------------- |
| `bug`         | Something is broken or behaving incorrectly         |
| `feature`     | A new capability that doesn't exist yet             |
| `task`        | A concrete piece of work (refactor, migration, etc) |
| `epic`        | A high-level goal that will be broken into subtasks |

An issue MAY also carry **secondary labels** for area or domain (e.g. `backend`, `frontend`, `ux`, `infra`).
Keep the set small — reuse existing labels before inventing new ones.

### Linking

Use the `link` tool to express relationships. Supported types: `blocks`, `blocked_by`,
`depends_on`, `dependency_of`, `duplicates`, `duplicated_by`, `relates_to`.
When a task spawns follow-up work, link the new issue back to the originating one.

### Backlog Review

When the user asks to review the board (not work an issue), this is a **read-only** operation:

1. Check DOING issues — what's actively underway and by whom
2. Check BLOCKED issues — what's stuck and what it's waiting on
3. Check PLANNED issues — what's ready to pick up, in priority order
4. Scan BACKLOG — anything notable worth planning

Flag stale DOING issues (no recent activity). Do NOT change any issue status during a review.

### Prioritisation

When choosing what to work on next (and dependency links do not resolve the order):

1. **Blockers** — issues blocking other work
2. **Bugs** — correctness problems in existing functionality
3. **Planned features** — by dependency order, then by story points (smaller first)

<!-- xpo:skill 1.2.1 sha256:7dd87a72d002 -->
