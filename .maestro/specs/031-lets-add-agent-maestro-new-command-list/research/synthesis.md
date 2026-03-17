# Research Synthesis: maestro.list Command

**Feature ID:** 031-lets-add-agent-maestro-new-command-list
**Date:** 2026-03-16
**Verdict:** ready

## Research Artifacts

1. **technology-options.md** — Evaluated 3 implementation approaches (Pure Markdown, Markdown + Script, Go CLI)
2. **pattern-catalog.md** — Cataloged 7 reusable patterns from the existing codebase
3. **pitfall-register.md** — Identified 7 pitfalls with mitigations
4. **competitive-analysis.md** — Compared 4 approaches (bd, gh, maestro.research.list, Linear boards)

## Key Decisions

### Decision 1: Implementation Architecture

**Decision:** Markdown command file + shell helper script
**Rationale:** Consistent with `maestro.research.list` and `maestro.tasks` patterns. Shell script handles deterministic data aggregation (scanning directories, parsing JSON, computing stalled status). Markdown command handles orchestration and output formatting.
**Alternatives:** Pure markdown (less reliable for JSON parsing), Go CLI subcommand (violates architecture separation)
**Confidence:** High

### Decision 2: Data Discovery Strategy

**Decision:** Scan `.maestro/specs/` for all feature directories, enrich with `.maestro/state/*.json` data where available
**Rationale:** Ensures orphan specs (spec exists, no state) are discovered. State files provide stage, metrics, and timestamps. Spec files provide human-readable title (line 1).
**Alternatives:** State-only discovery (misses orphan specs), spec-only discovery (misses state data)
**Confidence:** High

### Decision 3: Output Format

**Decision:** Column-aligned plain text table following `maestro.research.list` pattern, with stage summary header and active/completed grouping
**Rationale:** Proven internal format. Users are already familiar. Extending with stage column and next-action column serves the spec requirements.
**Alternatives:** Markdown table (harder to align in terminal), indented card format (less scannable for many items)
**Confidence:** High

### Decision 4: Stalled Detection Implementation

**Decision:** Use `jq` for date math (portable across macOS/Linux), fixed 14-day threshold
**Rationale:** The `date` command is not portable. `jq` has `now` and `strptime`/`mktime` for date operations. Already a project dependency.
**Alternatives:** Python one-liner (heavier dependency), OS-specific `date` commands (non-portable)
**Confidence:** High

### Decision 5: Feature Name Source

**Decision:** Read the first line of `spec.md` to extract `# Feature: {title}`. Fall back to reformatted slug if spec is missing.
**Rationale:** The title is always in the spec. Reading one line per feature is fast. No schema migration needed.
**Alternatives:** Store title in state file (requires migration), use slug only (less readable)
**Confidence:** Medium — reading spec files adds I/O but is acceptable for <100 features

## Ambiguity Classification

### Non-Blockers

- **Timestamp format variation** (3 formats observed) — `jq` handles all with fallback logic
- **State file schema evolution** — Defensive `jq` queries with defaults handle missing fields
- **Orphan spec cleanup** — Not this command's responsibility; just show with warning
- **Feature 013 malformed JSON** — Handle gracefully, show "?" for values

### No Blockers Identified

All ambiguities are classified as non-blockers. The implementation path is clear.

## External Approach Comparisons

| Approach                | Strengths for maestro.list                      | Weaknesses                       | Trade-offs                       |
| ----------------------- | ----------------------------------------------- | -------------------------------- | -------------------------------- |
| `bd ready`              | Dependency-aware filtering                      | Task-level only, no feature view | Complementary, not competing     |
| `gh issue list`         | Clean format, smart truncation, "X of Y" header | No workflow awareness            | Adopt format conventions         |
| `maestro.research.list` | Already in codebase, proven pattern             | No stage grouping                | Primary template to extend       |
| Linear boards           | Stage-based grouping, bottleneck visibility     | Not CLI-friendly                 | Adopt summary statistics concept |

## Preferred Direction

Build `maestro.list` as a **two-file implementation**:

1. **`.maestro/scripts/list-features.sh`** — Shell script that:
   - Scans `.maestro/specs/` for feature directories
   - Reads corresponding `.maestro/state/*.json` files
   - Reads spec titles from `spec.md` first line
   - Computes stalled status using `jq` date math
   - Supports `--stage` filter argument
   - Outputs structured JSON array

2. **`.maestro/commands/maestro.list.md`** — Command file that:
   - Calls `list-features.sh` to get feature data
   - Formats output as a column-aligned table
   - Adds stage summary header
   - Groups active features (sorted by ID descending) above completed features
   - Shows stalled warning indicators
   - Renders next-action suggestions per feature
   - Shows empty-project onboarding message if no features
   - Includes "Suggest Next Steps" section at the bottom

## Missing Items

None — all research areas are covered. The feature scope is well-defined, the implementation patterns are proven, and the pitfalls are identified with mitigations.

## Quality Signals Summary

- 4 research artifacts produced (technology-options, pattern-catalog, pitfall-register, competitive-analysis)
- 3 implementation options evaluated with trade-offs
- 4 external approaches compared
- 7 pitfalls identified with specific mitigations
- 5 key decisions documented with rationale, alternatives, and confidence levels
- All ambiguities classified as non-blockers
- Preferred direction is specific and actionable
