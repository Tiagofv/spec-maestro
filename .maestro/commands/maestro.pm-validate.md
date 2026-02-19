---
description: >
  Final validation gate for feature completion.
  Performs regression scan FIRST, then requirements validation.
  Escalates after 3 rounds of GAPS_FOUND. No limit for REGRESSION.
argument-hint: [feature-id]
---

# maestro.pm-validate

Validate feature completion.

## Step 1: Find the Feature

If `$ARGUMENTS` contains a feature ID, use it. Otherwise, find the most recent feature.

Read:

- The spec: `.maestro/specs/{feature_id}/spec.md`
- The state: `.maestro/state/{feature_id}.json`
- The config: `.maestro/config.yaml`

Get the epic ID from state.json and verify all review tasks are complete:

```bash
bd show {epic_id} --children --json
```

If any review tasks are still open, tell the user and stop.

## Step 2: Check Validation Round

Read the validation round from state.json (default: 1).

If round > 3 and verdict was GAPS_FOUND:

- Output: "PM validation failed after 3 rounds. Human intervention required."
- Stop

If verdict was REGRESSION:

- No round limit — regressions must be fixed

## Step 3: Spawn PM Validator

```
Task(
  subagent_type="pm-feature-validator",
  description="Validate: {feature_title}",
  prompt="Validate the feature: {feature_title}

  ## Spec
  {full spec content}

  ## Implementation Summary
  {list of tasks completed with close reasons}

  ## PHASE 1: REGRESSION SCAN (DO THIS FIRST)

  Run `git diff {base_branch}...HEAD` to get ALL files modified during this feature.

  For each modified file, scan the diff for REMOVED functionality:
  - Deleted switch cases, event handlers, or consumer registrations
  - Removed function definitions or method implementations
  - Dropped route/topic registrations
  - Narrowed logic (e.g., multi-entity handler replaced with single-entity)

  For each removal found, check whether ANY task in the epic explicitly required it.
  If a removal is not justified by any task description, it is a regression.

  If regressions are found, set verdict to REGRESSION regardless of whether the new
  feature's acceptance criteria are met. Regressions take priority over everything else.

  ## PHASE 2: REQUIREMENTS VALIDATION

  Check all acceptance criteria from the spec:

  {acceptance criteria from spec}

  For each criterion:
  1. Find evidence in the implemented code
  2. Verify the implementation matches the requirement
  3. Note any gaps or partial implementations

  ## OUTPUT

  Return ONLY this JSON. No markdown, no preamble:

  {
    \"verdict\": \"COMPLETE | GAPS_FOUND | BLOCKED | REGRESSION\",
    \"regressions\": [
      {
        \"file\": \"path/to/file\",
        \"removed\": \"What was removed\",
        \"impact\": \"Which existing feature this breaks\",
        \"justified\": false
      }
    ],
    \"requirements\": [
      {
        \"id\": \"REQ-1\",
        \"description\": \"Requirement text\",
        \"status\": \"MET | PARTIAL | NOT_MET | BLOCKED\",
        \"evidence\": \"What satisfies or is missing\",
        \"files\": [\"path/to/file\"]
      }
    ],
    \"follow_up_tasks\": [
      {
        \"title\": \"Task title\",
        \"description\": \"What needs to be done\",
        \"priority\": \"HIGH | MEDIUM | LOW\"
      }
    ],
    \"summary\": \"One sentence overall assessment\"
  }"
)
```

## Step 4: Handle Validator Response

Parse the JSON output.

**If REGRESSION (highest priority):**

```bash
bd close {pm_val_task_id} --reason "REGRESSION | files: {list} | impact: {feature}"
```

For each regression:

- Create a high-priority fix task to restore the functionality
- These fixes have no round limit — must be resolved

Create a new pm-validation task blocked by the fix tasks.

**If COMPLETE:**

```bash
bd close {pm_val_task_id} --reason "COMPLETE | requirements: {met}/{total} | regressions: 0"
```

Update state.json: set `stage` to `complete`.

**If GAPS_FOUND (round 1-2):**

```bash
bd close {pm_val_task_id} --reason "GAPS_FOUND | requirements: {met}/{total} | gaps: {list}"
```

Create fix tasks from follow_up_tasks array.
Increment validation round in state.json.
Create new pm-validation task for next round.

**If GAPS_FOUND (round 3):**
Output: "PM validation failed after 3 rounds. Human intervention required."
Close the task and stop orchestration.

**If BLOCKED:**
Show what's blocking and stop.

## Step 5: Report Results

Show the user:

1. Validation verdict
2. Regressions found (if any) — with impact
3. Requirements status (met/partial/not_met)
4. Follow-up tasks created (if any)
5. Current validation round

If COMPLETE:

- Congratulate! Feature is done.
- Suggest: "Run `/maestro.analyze` for post-epic learning."

---

**Regression scan is mandatory and happens FIRST.** A feature that meets all requirements but breaks existing functionality is NOT complete.
