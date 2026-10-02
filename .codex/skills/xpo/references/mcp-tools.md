## MCP Tools Reference

The xpo MCP server exposes the tools listed below. Exact tool identifiers depend on your
agent harness (e.g. Claude Code surfaces them as `mcp__xpo__<tool>`; other harnesses
may use different naming conventions). The table uses the base tool names.

| Tool | Description |
|---|---|
| `list` | List or search issues; use `match` for free-text search |
| `show` | Read one issue with details, dependencies, and comments |
| `add` | Create a new issue |
| `update` | Update fields including status transitions (BACKLOG/PLANNED/DOING/BLOCKED/DONE) |
| `start` | Start working on an issue: transitions to DOING and creates a git worktree (or branch). Returns the worktree path |
| `merge` | Squash-merge an issue branch into the default branch, record a MERGE event, close the issue, and clean up the worktree. All changes must be committed on the worktree or branch first |
| `comment` | Add a markdown comment to an issue |
| `link` | Add a relationship between two issues |
| `history` | View the audit trail for an issue |
| `spec` | Read, write, or delete the design spec for an issue |
| `walkthrough` | Read, write, or delete the implementation walkthrough for an issue |
| `rationale` | Search across specs and walkthroughs for prior design decisions related to a topic |
| `artifact` | Manage generic artifacts attached to an issue |

<!-- xpo:skill 1.2.1 sha256:56f5bd6354e5 -->
