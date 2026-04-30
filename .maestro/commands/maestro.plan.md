---
description: >
  Generate a technical implementation plan from the feature specification.
  Creates architecture, component design, data model, API contracts, phases, and testing strategy.
argument-hint: [feature-id] (optional, defaults to most recent)
---

# maestro.plan

Generate an implementation plan for the feature.

## Step 1: Prerequisites Check

Run the prerequisite check:

```bash
bash .maestro/scripts/check-prerequisites.sh plan
```

If it fails, show the error and suggestion, then stop.

## Step 2: Find the Specification

If `$ARGUMENTS` contains a feature ID, use it. Otherwise, find the most recent feature in `.maestro/specs/`.

Read:

- The spec file: `.maestro/specs/{feature_id}/spec.md`
- The constitution: `.maestro/constitution.md` (if exists)
- The state: `.maestro/state/{feature_id}.json`

## Step 3: Validate Spec Readiness

Check for unresolved `[NEEDS CLARIFICATION]` markers:

- If found, warn the user and suggest running `/maestro.clarify` first
- Offer to proceed anyway with assumptions noted

## Step 3b: Validate Research Readiness

Read research metadata from `.maestro/state/{feature_id}.json` using additive, backward-compatible rules:

- Treat missing research fields as legacy state (`research_ready=false`)
- Use `research_artifacts` and `research_artifact_pointers` (if present) as source paths for research outputs
- Never fail only because research metadata fields are missing

Resolve and read synthesis before planning:

1. Resolve synthesis path in this order:
   - `research_artifact_pointers.synthesis` (if present)
   - matching entry in `research_artifacts` for `research/synthesis.md` (if present)
   - default `.maestro/specs/{feature_id}/research/synthesis.md`
2. If synthesis exists, read it and extract:
   - readiness verdict (`ready` or `not_ready`)
   - minimum quality signals:
     - recommendation entries with Decision, Rationale, Alternatives, Confidence
     - ambiguity classification (blocker vs non-blocker)
     - at least 3 external approach comparisons with trade-offs
     - preferred direction
     - explicit missing minimum items when verdict is `not_ready`
3. If synthesis is missing/unreadable or required signals are missing, treat research as incomplete (`planning_research_ready=false`) without hard failure.

Planning readiness gate behavior:

1. Consider research ready only when all are true:
   - `research_ready=true` in state
   - synthesis verdict is `ready`
   - synthesis minimum quality signals are present
2. Otherwise require this exact acknowledgement phrase before proceeding:

`I acknowledge proceeding without complete research`

If the phrase is missing or incorrect, stop and instruct the user to run `/maestro.research {feature_id}`.

## Step 3c: Load Research Findings

If research is linked to the feature (check `research_ids` array in state):

### 3c.1: Read Linked Research

For each research_id in `research_ids`:

1. Read `.maestro/state/research/{research_id}.json`
2. Get the research file path
3. Read the full research document
4. Extract key findings, recommendations, and risks

### 3c.2: Build Research Context

Compile research findings for planning context:

```markdown
## Research-Informed Context

### Technology Recommendations

{From research findings}

### Pattern Guidance

{Applicable patterns from research}

### Identified Risks

{Risks and mitigations from research}

### Best Practices to Apply

{Practices from research}
```

### 3c.3: Apply Research to Planning

Use research findings to inform plan decisions:

**Architecture Decisions:**

- Reference research technology recommendations
- Consider pattern guidance from research
- Include research-identified risks in risk section

**Component Design:**

- Apply patterns discovered in research
- Follow best practices identified
- Avoid pitfalls documented

**Risk Assessment:**

- Include all risks from research
- Add mitigations based on research recommendations

**Example Integration:**

```markdown
### Key Design Decisions

| Decision        | Options Considered          | Chosen     | Rationale                                                                    |
| --------------- | --------------------------- | ---------- | ---------------------------------------------------------------------------- |
| Database choice | PostgreSQL, MongoDB, SQLite | PostgreSQL | Per research 20250312-db-comparison: better for time-series, proven at scale |
```

## Step 4: Read the Plan Template

Read `.maestro/templates/plan-template.md`.

## Step 4b: Inventory Discovery and Per-Task Agent Selection

Replace the previous static file-pattern-to-agent table with project-aware selection
driven by the harness's actual agent inventory.

### Step 4b.1: Discover the Inventory

Run the inventory script and capture its output:

```bash
bash .maestro/scripts/list-agents.sh --harness=auto > /tmp/maestro-agents-inventory.json
```

The output is a JSON array of `AgentInventoryEntry` records (see
`.maestro/specs/060-improve-maestro-select-best-agent-each/data-model.md`).

If the array is empty, every task in this plan will fall back to `general`. This is
correct behavior for a fresh project — emit a single `[no-match: empty-inventory]`
annotation at the top of the task list and proceed.

Determine the running harness:
- If exactly one of `which claude`, `which opencode`, `which codex` succeeds, that's the
  running harness.
- If multiple succeed, prefer in this order: `claude`, `opencode`, `codex` (matches
  spec-maestro's existing `KnownAgentDirs` order).
- If none succeed, the harness is `unknown` — selection still works against any matching
  entries, but the `[harness: ...]` annotation is omitted.

### Step 4b.2: Score Each Task Against the Inventory

For each task in the plan, compute a per-entry score:

| Component | Weight | How to compute |
| --------- | ------ | -------------- |
| Stack match | +10 per matching stack | Task touches `*.go` AND entry.stacks contains `"go"` → +10. Task touches `*.tsx` AND entry.stacks contains `"tsx"` or `"ts"` or `"frontend"` → +10. |
| Intent match | +5 if task is impl AND entry.intent in `["impl","either"]` | Or +5 if task is review AND entry.intent in `["review","either"]`. Mismatch (impl task, review-only entry) → -1000 (effectively excludes). |
| Harness match | +3 if entry.harness == running harness | Cross-harness entries get 0 here, so they're outscored by same-harness candidates but still selectable when no same-harness match exists. |
| Wildcard penalty | -2 if entry.stacks == `["*"]` | Generic agents like `general-purpose` are eligible but lose to specialists. |

Pick the entry with the **highest score**. If multiple entries tie at the top:
1. Prefer entries from the running harness.
2. Within the same harness, pick alphabetically by `name` and emit `[tie-broken]`.

If max score is **≤ 0**, set assignee to `general` and emit `[no-match: <reason>]`
where `<reason>` is the most specific cause:
- `harness-mismatch` — entries existed but none from the running harness.
- `no-stack-match` — entries existed but none matched the task's stacks.
- `no-intent-match` — only review-only entries existed for an impl task (or vice versa).
- `empty-inventory` — JSON array was empty.

### Step 4b.3: Emit Annotations

Every task's `Assignee:` field includes:
- The chosen name (or `general`).
- A `[harness: <name>]` annotation when the running harness was detected.
- One of: `[no-match: <reason>]`, `[tie-broken]`, `[review-fallback]`, or no annotation
  if a clean specialist match was found.

Annotations are space-separated, in brackets, after the assignee name. Example:

```
Assignee: golang-code-reviewer [harness: claude]
Assignee: general [harness: claude] [no-match: no-stack-match]
Assignee: general [harness: claude] [review-fallback]
```

### Step 4b.4: Review Tasks Are Selected Independently

Review tasks (label `review`, auto-paired with each impl task) are scored
independently against entries with `intent in ["review","either"]`. They do **not**
inherit the impl task's assignee. If no review-capable agent matches, the review task
falls back to `general` with `[review-fallback]` annotation — never to the impl
agent's name.

This change supersedes the previous rule in `maestro.tasks.md` Step 5.2 #3 (see
companion contract `maestro-tasks-step5-step6.md`).

### Step 4b.5: Regenerate Path

If this plan is being regenerated for a feature whose bd epic already exists, consult
each existing bd task's status before applying the new selection:
- bd task in `open` status → apply new selection.
- bd task in `in_progress`, `blocked`, or `closed` → preserve the existing assignee
  and emit `[divergence: was X, plan now suggests Y]` on the task line, where X is
  the preserved assignee and Y is what the new selection would have chosen.

Use `bd show <id> --json` to read the existing status and assignee.

## Step 4c: Read and Store the Repos Set

Read the `**Repos:**` line from the spec header — this is the authoritative set of repositories for this feature. Store it as `repos_set`; every generated task in Step 5 must carry a matching `**Repo:**` field whose value is a member of this set.

Example header line: `**Repos:** svc-accounts-receivable, alt-front-end`

If the `**Repos:**` line is absent from the spec, stop and instruct the user to run `/maestro.specify` again (T017 added this field — its absence means the spec predates multi-repo support or was written incorrectly).

## Step 5: Generate the Plan

Fill in the template based on the spec and constitution.

**Rules for plan generation:**

1. **Architecture must be justified** — Every design decision should trace back to a requirement in the spec
2. **Be specific about files** — List actual file paths, not generic "create a service"
3. **Identify risks early** — Especially regression risks in modified components
4. **Phases should be deliverable** — Each phase produces something testable
5. **Testing is not optional** — Every component needs a testing strategy
6. **Assign agent per task** — For each task, run Step 4b's procedure (discovery + scoring). Set the matched agent as the task's assignee. If scoring fails, use `general` and emit a `[no-match: <reason>]` annotation. Always include a `[harness: <name>]` annotation when known.
7. **Split multi-agent tasks** — If a task touches files that score highest for *different* agents (e.g., a Go service file scoring for `golang-expert-payments` and a `.tsx` file scoring for `frontend-code` skill), split it into separate tasks — one per matched agent. Set dependencies between split tasks if they share interfaces.
8. **Show agent assignments** — In the plan output, every task must include an `Assignee` field showing which agent will implement it.
9. **Every task must carry a `**Repo:**` field** — Its value must be exactly one member of the `repos_set` captured in Step 4c. A task's `**Files to Modify:**` must not span multiple repos; if implementation naturally touches two repos, split it into two tasks (one per repo) and set dependencies between them.

If the spec is too vague to make architectural decisions, add items to "Open Questions" section and flag them.

## Step 5b: Validate the Plan Before Writing

Before writing the plan to disk, run the format validator:

```bash
bash .maestro/scripts/validate-plan-format.sh <plan-file-path>
```

Where `<plan-file-path>` is the path that Step 7 would write to (`.maestro/specs/{feature_id}/plan.md`). Write the plan to a temporary location first if needed, then validate, then move it into place only on success.

If the script exits nonzero, surface the full error output to the user and do **not** write (or keep) the plan file. Ask the user whether to fix the issues and retry, or abandon the plan generation.

## Step 6: Create Supporting Artifacts

If the plan includes:

- **API contracts** — Create `.maestro/specs/{feature_id}/contracts/` directory with contract files
- **Data model** — Create `.maestro/specs/{feature_id}/data-model.md` with detailed schema

## Step 7: Write the Plan

Write the completed plan to `.maestro/specs/{feature_id}/plan.md`.

## Step 8: Update State

Update `.maestro/state/{feature_id}.json`:

- Set `stage` to `plan`
- Add `plan_path` field
- Add `phases` count
- Add `components_new` and `components_modified` counts
- Preserve any existing research metadata fields (`research_path`, `research_artifacts`, `research_artifact_pointers`, `research_ready`, `research_parallel_agents_default`, `research_parallel_agents_max`, `research_parallel_agents_used`)
- If bypass path was used, set `research_bypass_acknowledged` to `true`
- Add history entry

State safety requirements:

- Additive only: never remove or rename existing fields
- Preserve history integrity: append entries only
- Keep compatibility with legacy state files that do not yet contain research fields

## Step 9: Report and Next Steps

Show the user:

1. Summary of the plan:
   - Number of phases
   - New components to create
   - Existing components to modify
   - Key risks identified
2. Any open questions that need resolution
3. Whether planning proceeded via research-ready path or bypass acknowledgement path
4. Research readiness evidence source (state metadata and synthesis path/verdict)
5. Suggest: "Review the plan, then run `/maestro.tasks` to break it into bd issues."

---

**Remember:** The plan is a technical blueprint. It should be detailed enough that a developer unfamiliar with the feature could implement it correctly.
