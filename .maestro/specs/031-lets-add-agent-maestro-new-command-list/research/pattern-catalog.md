# Pattern Catalog: maestro.list Command

**Research ID:** 031-pattern-catalog
**Date:** 2026-03-16
**Source Type:** codebase
**Domain:** Existing patterns for list/status commands

## Query

What existing patterns in the maestro codebase can be reused for the `maestro.list` command?

## Summary

Three established patterns directly inform the implementation: the command definition pattern (frontmatter + steps), the list output pattern (`maestro.research.list`), and the state discovery pattern (directory scanning + JSON parsing). The next-action suggestion pattern is used by every command and provides a template for contextual recommendations.

## Findings

### Pattern 1: Command Definition Structure

**Source:** All 13 files in `.maestro/commands/`

Every command follows this exact structure:

```yaml
---
description: >
  Short description of what the command does.
argument-hint: [optional-args] [--flags]
---
```

```markdown
# maestro.{name}

Brief summary line.

## Step 1: {Title}

...

## Step N: Report and Next Steps
```

**Reuse for maestro.list:**

- Frontmatter: `description: "List all features with status, metrics, and suggested next actions."`, `argument-hint: [--stage {specify|clarify|plan|tasks|implement|complete}]`
- Follow numbered step pattern
- End with "Report and Next Steps" section

### Pattern 2: List Output Formatting (maestro.research.list)

**Source:** `.maestro/commands/maestro.research.list.md`

The closest existing command. Its output format:

```
Research Items ({count} total)

ID                     Title                           Type       Created     Linked
--------------------   -----------------------------   --------   ----------  ------
20250311-oauth-patt..  OAuth implementation patterns   codebase   2025-03-11  2
```

**Key design decisions to reuse:**

- Count header: `Features ({count} total)`
- Column-aligned table with dashed separator
- Truncation of long values with `..`
- Summary statistics at bottom
- Filter argument handling (`--type`, `--tag`)

**Adaptation for maestro.list:**

```
Features (19 total, 10 active, 9 completed)

ID    Name                           Stage      Stories  Tasks  Next Action
----  -----------------------------  ---------  -------  -----  ----------------------
031   Feature Dashboard Command      clarify    4        -      /maestro.plan
019   Improve Task Creation          complete   7        7      -
```

### Pattern 3: State File Discovery

**Source:** `.maestro/commands/maestro.implement.md`, `.maestro/commands/maestro.clarify.md`

Two discovery patterns exist:

**A. Spec-based (used by clarify, plan):**

- List directories in `.maestro/specs/` sorted by name
- Highest NNN number = most recent
- Simple alphabetic sort works because of zero-padded numbers

**B. State-based (used by implement):**

- List all `.maestro/state/*.json` files
- Parse each, sort by `updated_at` descending
- Most recently updated = active feature

**For maestro.list:** Use both — discover from specs directory for completeness, enrich with state file data where available. This handles the "orphan spec" case (spec exists, no state file).

### Pattern 4: Next-Action Suggestion Logic

**Source:** Every command's final step

The pattern for determining the next action based on stage:

| Stage       | Condition                   | Suggested Command                           |
| ----------- | --------------------------- | ------------------------------------------- |
| `specify`   | `clarification_count > 0`   | `/maestro.clarify`                          |
| `specify`   | `clarification_count == 0`  | `/maestro.plan`                             |
| `clarify`   | Markers remain              | `/maestro.clarify`                          |
| `clarify`   | All resolved                | `/maestro.plan`                             |
| `plan`      | Plan exists                 | `/maestro.tasks`                            |
| `tasks`     | Epic created                | `/maestro.implement`                        |
| `implement` | In progress                 | (monitoring)                                |
| `complete`  | Done                        | `/maestro.analyze`                          |
| Any         | `updated_at >= 14 days ago` | Stalled warning                             |
| (no state)  | Spec only                   | `/maestro.specify` (re-run to create state) |

### Pattern 5: Shell Helper Script Structure

**Source:** `research-state.sh`, `create-tasks.sh`, `parse-plan-tasks.sh`

Shell helper scripts follow this pattern:

```bash
#!/bin/bash
set -euo pipefail

# Subcommand dispatch
case "${1:-}" in
  list) do_list "$@" ;;
  create) do_create "$@" ;;
  *) echo "Usage: $0 {list|create}" >&2; exit 1 ;;
esac
```

Key conventions:

- Use `jq` for JSON parsing
- Output JSON for structured data, plain text for human-readable
- Exit codes: 0 = success, 1 = error
- Errors to stderr, data to stdout
- `set -euo pipefail` at top

### Pattern 6: Stalled Detection

**Source:** Feature 031 spec + state file schema

No existing implementation, but the data is available:

- Every state file has `updated_at` (ISO 8601 or date string)
- Three timestamp formats observed: `2026-02-19T10:24:00Z`, `2026-02-19T00:00:00.000Z`, `2026-02-19`
- Shell detection: `$(date -d "$updated_at" +%s)` vs `$(date +%s)` with 14-day threshold (1209600 seconds)
- macOS uses `date -j -f` instead of `date -d`; use `date` with portable parsing or `jq` for date math

### Pattern 7: Feature ID Extraction from Directory Names

**Source:** `create-feature.sh`, `check-prerequisites.sh`

Feature IDs follow the format `NNN-slug-words`:

- `NNN` is zero-padded 3-digit number (001, 002, ..., 031)
- The numeric prefix enables natural sort ordering
- Extract number: `echo "$feature_id" | grep -o '^[0-9]\+'`
- Sort descending by number for "newest first" ordering

## Related Patterns

- **Unicode status indicators:** `✓` (complete), `✗` (failed), `⚠` (warning/stalled) — used throughout Go CLI and command outputs
- **Progress tracking:** `├─`, `└─` tree drawing — used in `maestro.implement` progress output
- **Markdown table rendering:** Used in `maestro.tasks` for task listings — the AI agent renders markdown tables naturally
