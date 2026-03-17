# Pitfall Register: maestro.list Command

**Research ID:** 031-pitfall-register
**Date:** 2026-03-16
**Source Type:** codebase
**Domain:** Known issues and edge cases

## Query

What pitfalls and edge cases should be anticipated when implementing the `maestro.list` command?

## Summary

Five categories of pitfalls identified: state file inconsistencies, orphan artifacts, date parsing portability, JSON parsing failures, and scaling concerns. Most are mitigatable with defensive coding and explicit error handling.

## Pitfalls

### Pitfall 1: State File Schema Inconsistencies

**Severity:** Medium
**Likelihood:** Certain (observed in existing data)

The state file schema has evolved organically across 31 features. Key inconsistencies:

| Inconsistency                                   | Affected Features | Impact on maestro.list                                                       |
| ----------------------------------------------- | ----------------- | ---------------------------------------------------------------------------- |
| Missing worktree fields                         | 001-007           | Must treat as optional; default to "N/A"                                     |
| `tasks` field polymorphism (object vs array)    | 008 vs 018        | Use `task_count` number field instead; ignore `tasks` shape                  |
| `tasks_total`/`tasks_remaining` vs `task_count` | 017 vs others     | Check both field names; prefer `task_count`, fallback to `tasks_total`       |
| Missing `completed_at` on complete features     | 001, 006          | Don't rely on `completed_at` for completion check; use `stage == "complete"` |
| Timestamp format variation                      | All               | Parse all 3 formats: full ISO, millisecond ISO, date-only                    |
| Feature 013 malformed JSON                      | 013               | Must handle JSON parse errors gracefully                                     |

**Mitigation:** Use defensive `jq` queries with defaults: `jq -r '.task_count // .tasks_total // 0'`. Wrap JSON parsing in error handling. Show "?" for unparseable values instead of crashing.

### Pitfall 2: Orphan Spec Directories

**Severity:** Low
**Likelihood:** High (20+ test/duplicate spec dirs exist)

The `.maestro/specs/` directory contains 31 entries but `.maestro/state/` only has 20 state files. Many spec directories (020-030) appear to be test artifacts or duplicates with no matching state file.

**Examples:**

- `020-we-need-build-kanban-board-our-tauri-ui/` — duplicate of 001
- `024-quick-brown-fox-jumps-lazy-dog/` — test data
- `025-add-user-authentication/` — test data

**Mitigation:** Per the spec, show these with a warning: `⚠ No state`. The next action should suggest `/maestro.specify` to create proper state. Consider grouping these separately or filtering them by default.

### Pitfall 3: Date Parsing Portability (macOS vs Linux)

**Severity:** High
**Likelihood:** Certain (development on macOS, CI may be Linux)

The `date` command behaves differently:

| Operation       | Linux (GNU date)                     | macOS (BSD date)                                             |
| --------------- | ------------------------------------ | ------------------------------------------------------------ |
| Parse ISO 8601  | `date -d "2026-03-16T00:00:00Z" +%s` | `date -j -f "%Y-%m-%dT%H:%M:%SZ" "2026-03-16T00:00:00Z" +%s` |
| Parse date-only | `date -d "2026-03-16" +%s`           | `date -j -f "%Y-%m-%d" "2026-03-16" +%s`                     |
| Current time    | `date +%s`                           | `date +%s` (same)                                            |

**Mitigation Options:**

1. Use `jq` for date math: `jq` has `now` and `strptime`/`mktime` functions — portable across platforms
2. Use Python one-liner: `python3 -c "from datetime import datetime; ..."`
3. Detect OS and use appropriate `date` syntax

**Recommended:** Use `jq` for all date operations since it's already a project dependency.

### Pitfall 4: Large Number of Features

**Severity:** Low (now), Medium (future)
**Likelihood:** Low (currently 31 features; 20 with state)

At 31 features, output is manageable. At 100+ features, the unfiltered table becomes unwieldy.

**Mitigation:** The spec already defines filtering by stage. Additionally:

- Completed features at the bottom (per spec) naturally reduces visual noise
- Consider a default limit (e.g., show last 20 active features) with `--all` flag — but this is deferred per spec

### Pitfall 5: Feature Name Extraction

**Severity:** Low
**Likelihood:** Certain

State files don't store a human-readable feature name. The `feature_id` slug is the closest thing (e.g., `031-lets-add-agent-maestro-new-command-list`). The spec title is in `spec.md` but requires reading and parsing that file.

**Options:**

1. Use the spec `# Feature: {title}` line — requires reading each spec file (slow for many features)
2. Use the feature_id slug, reformatted — replace dashes with spaces, drop the NNN prefix
3. Store the title in the state file — requires a schema migration for existing features

**Recommended:** Read the spec title from `spec.md` line 1 (fast — just read first line). Fall back to reformatted slug if spec is missing.

### Pitfall 6: Concurrent State File Modifications

**Severity:** Low
**Likelihood:** Low

If `maestro.list` runs while another command is writing a state file, it could read a partially-written file.

**Mitigation:** This is read-only command. Use `jq` which reads the entire file atomically. If parsing fails, show a warning rather than crashing.

### Pitfall 7: Missing Research State vs Feature State

**Severity:** Low
**Likelihood:** Medium

The `maestro.list` command should list features, not research items. But some state files reference research metadata (`research_ready`, `research_artifacts`). The command should not confuse `.maestro/state/research/*.json` (research state files) with `.maestro/state/*.json` (feature state files).

**Mitigation:** Only scan `.maestro/state/*.json` (top-level), explicitly excluding the `research/` subdirectory. Use glob pattern `*.json` not `**/*.json`.
