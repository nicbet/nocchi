# Spec Writing Guide

## Why specs exist

Without a spec, the agent rolls the dice at every design decision — picking the most probable
path from its training data, not the right one for this project. The spec collapses that space:
it makes branch points explicit so the user can steer instead of discovering unwanted choices
after the code is written. It also documents what will change, why, and how, so the user can
evaluate the proposed plan and course-correct before implementation begins.

A spec that merely restates the issue title has failed.

## Scaling the spec to the task

### Bug fix or small change (brief spec)

- What is the problem / what needs to change
- Why (root cause / motivation)
- How (the fix approach, noting any alternatives considered)
- Acceptance criteria (how to verify it worked)

### Feature or complex change (full spec)

- **What** — 2-3 sentence concrete description of what this delivers
- **Why** — motivation, link to parent epic/context
- **Acceptance Criteria** — observable, testable outcomes
- **Flow** — numbered implementation steps; name concrete files, functions, endpoints
- **Decisions** — choices made during design: "X, not Y" with rationale and alternatives
- **Edge Cases** — classified by risk:
  - HIGH (developer decides) — wrong default causes data loss, security holes, or broken UX
  - MEDIUM (agent proposes handling, developer confirms)
  - LOW (agent handles silently)
- **Assumptions** — what you are taking for granted; the user can correct these
- **Open Questions** — unresolved branch points needing answers before implementation
- **Agent Decisions** (non-interactive mode only) — choices the agent made on behalf of the user
  where the answer was not obvious. For each: the question, the choice made, the reasoning, and
  what to revisit if the choice was wrong. This section is the user's entry point for catching
  assumptions they would not have made.

## Key principles

- Draft concrete content. Never present blank templates or ask the user to fill in sections.
- Surface your assumptions explicitly — it is always easier for the user to react to a draft
  than to author from scratch.
- When you encounter open questions that would significantly change the implementation,
  stop and ask the user before proceeding.
- The spec is the source of truth for implementation. If you later discover it is wrong or
  incomplete, update the spec first, then change code.

<!-- xpo:skill 1.2.1 sha256:5a874c8b87af -->
