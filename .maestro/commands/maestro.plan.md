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

## Step 4: Read the Plan Template

Read `.maestro/templates/plan-template.md`.

## Step 4b: File-Pattern-to-Agent Mapping

Use the following mapping table to assign agents to tasks based on file patterns:

| Pattern      | Agent   |
|--------------|---------|
| *.go         | general |
| *.ts,*.tsx   | general |
| *.py         | general |
| *            | general |

**Instructions:** When generating tasks, match each task's target files against this table. The first matching pattern determines the agent assignee for that task. Users can customize this table by editing it directly (e.g., changing `*.go` to `golang-expert-payments` for specialized Go development).

## Step 5: Generate the Plan

Fill in the template based on the spec and constitution.

**Rules for plan generation:**

1. **Architecture must be justified** — Every design decision should trace back to a requirement in the spec
2. **Be specific about files** — List actual file paths, not generic "create a service"
3. **Identify risks early** — Especially regression risks in modified components
4. **Phases should be deliverable** — Each phase produces something testable
5. **Testing is not optional** — Every component needs a testing strategy
6. **Assign agent per task** — For each task, match its target files against the File-Pattern-to-Agent Mapping table. Set the matched agent as the task's assignee. If no pattern matches, use `general`.
7. **Split multi-agent tasks** — If a task touches files matching different agent patterns (e.g., both `.go` and `.ts` files), split it into separate tasks — one per agent pattern. Set dependencies between split tasks if they share interfaces.
8. **Show agent assignments** — In the plan output, every task must include an `Assignee` field showing which agent will implement it.

If the spec is too vague to make architectural decisions, add items to "Open Questions" section and flag them.

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
- Add history entry

## Step 9: Report and Next Steps

Show the user:

1. Summary of the plan:
   - Number of phases
   - New components to create
   - Existing components to modify
   - Key risks identified
2. Any open questions that need resolution
3. Suggest: "Review the plan, then run `/maestro.tasks` to break it into bd issues."

---

**Remember:** The plan is a technical blueprint. It should be detailed enough that a developer unfamiliar with the feature could implement it correctly.
