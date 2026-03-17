# Competitive Analysis: maestro.list Command

**Research ID:** 031-competitive-analysis
**Date:** 2026-03-16
**Source Type:** codebase + external
**Domain:** Feature listing and project status commands

## Query

How do similar tools handle feature/task listing and status display, and what can we learn?

## Summary

Three external approaches were compared alongside maestro's own internal patterns. The most relevant comparison is with `bd ready` (the project's own issue tracker), GitHub's `gh issue list`, and linear-style project boards. The key insight is that maestro.list serves a unique niche — it's a workflow-aware feature tracker, not a generic issue list.

## Approaches Compared

### Approach 1: bd (beads) CLI — `bd ready` / `bd show`

**What it does:** Lists issues that are ready to work on (unblocked), shows individual issue details.

**Output format:**

```
ready issues:
  agent-maestro-abc.1  "Create list command"  (XS, backend)
  agent-maestro-abc.3  "Add filtering"        (S, backend)
```

**Strengths:**

- Simple, focused output — only shows actionable items
- Issue-level granularity (tasks, not features)
- Dependency-aware (only shows unblocked)

**Weaknesses:**

- No feature-level aggregation — you see individual tasks, not the feature they belong to
- No stage/workflow awareness — doesn't know about specify/clarify/plan pipeline
- No suggested next actions

**Lesson for maestro.list:** `bd` operates at the task level; `maestro.list` operates at the feature level. They're complementary, not competing. `maestro.list` should NOT replicate `bd ready` — instead it should show which features have tasks ready and link to `bd` for details.

### Approach 2: GitHub CLI — `gh issue list`

**What it does:** Lists issues/PRs with labels, milestones, and status filtering.

**Output format:**

```
Showing 5 of 23 open issues

#123  Add OAuth support      feature, auth     OPEN
#124  Fix login redirect     bug, auth         OPEN
#125  Update README          docs              OPEN
```

**Strengths:**

- Clean, scannable format
- Column alignment without heavy table borders
- Smart truncation
- Filter by label, milestone, assignee
- Count header shows filtered vs total

**Weaknesses:**

- No workflow stage awareness
- No suggested next actions
- Generic — doesn't understand project-specific workflows

**Lesson for maestro.list:** Adopt the "Showing X of Y" pattern for filtered views. Keep the output clean and scannable like `gh`. Avoid heavy table borders.

### Approach 3: Internal maestro.research.list

**What it does:** Lists research items with metadata, filtering, and summary statistics.

**Output format:**

```
Research Items (12 total)

ID                     Title                           Type       Created     Linked
--------------------   -----------------------------   --------   ----------  ------
20250311-oauth-patt..  OAuth implementation patterns   codebase   2025-03-11  2
```

**Strengths:**

- Already established in the codebase — users are familiar with this format
- Summary statistics at bottom
- Contextual next-step suggestions
- Filter arguments (`--type`, `--tag`)

**Weaknesses:**

- Fixed column widths may not adapt well to varying data
- No grouping or visual separation

**Lesson for maestro.list:** This is the primary template to follow. Extend it with:

- A stage column instead of type
- A "Next Action" column
- Grouping (active vs completed)
- Stalled indicator

### Approach 4: Linear-style Project Boards

**What it does:** Groups issues by status column (Backlog, In Progress, Done) with counts per column.

**Strengths:**

- Visual grouping by stage
- Immediate sense of bottlenecks (lots in "In Progress" = overloaded)
- Count per stage gives project health at a glance

**Weaknesses:**

- Requires horizontal space (multiple columns side-by-side)
- Not ideal for CLI text output

**Lesson for maestro.list:** Adopt the summary statistics concept — show counts per stage at the top or bottom. This gives instant project health awareness without needing a visual board:

```
Summary: 5 specify | 1 clarify | 2 plan | 2 tasks | 0 implement | 10 complete
```

## Comparison Matrix

| Criteria                | bd ready | gh issue list | maestro.research.list | Linear boards |
| ----------------------- | :------: | :-----------: | :-------------------: | :-----------: |
| Feature-level view      |    No    |    Partial    |          No           |      Yes      |
| Workflow awareness      |    No    |      No       |          No           |      Yes      |
| Next-action suggestions |    No    |      No       |          Yes          |      No       |
| Filtering               |    No    |      Yes      |          Yes          |      Yes      |
| Summary statistics      |    No    |  Yes (count)  |          Yes          |      Yes      |
| CLI-friendly            |   Yes    |      Yes      |          Yes          |      No       |
| Existing in codebase    |   Yes    |      N/A      |          Yes          |      N/A      |

## Recommendation

**Recommended Approach:** Hybrid of `maestro.research.list` format + Linear-style stage summary

**Rationale:**

1. `maestro.research.list` is the proven internal pattern — minimal learning curve for users
2. Adding stage-based summary statistics (like Linear boards) gives instant project health
3. The "Next Action" column is unique to maestro and its key differentiator
4. Grouping active vs completed (like `bd` showing only actionable items) reduces noise

**Unique value of maestro.list:** No existing tool combines feature-level granularity with workflow-stage awareness and contextual next-action suggestions. This is maestro's competitive advantage in this space.
