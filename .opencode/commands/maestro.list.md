---
description: >
  List all features with status and suggested actions.
  Shows a dashboard of every feature in the project with stage, progress, and recommended next steps.
argument-hint: [--stage {specify|clarify|plan|tasks|implement|complete}]
---

# maestro.list

List all features in the project with their current stage, progress metrics, and suggested next actions.

## Step 1: Prerequisites Check

Verify the project is initialized:

1. Confirm `.maestro/` directory exists
2. Confirm `.maestro/specs/` directory exists
3. If not initialized, tell the user to run `/maestro.init` and stop

## Step 2: Parse Arguments

Extract optional filters from `$ARGUMENTS`:

| Flag      | Description              | Values                                                  |
| --------- | ------------------------ | ------------------------------------------------------- |
| `--stage` | Filter by feature stage  | `specify`, `clarify`, `plan`, `tasks`, `implement`, `complete` |

If `--stage` is provided, only features in that stage will be shown.

## Step 3: Run Discovery Script

Execute the list-features script to collect feature data:

```bash
bash .maestro/scripts/list-features.sh [--stage <stage>]
```

Capture the JSON array output. Each element contains:

- `feature_id` — directory name (e.g. `001-my-feature`)
- `numeric_id` — integer prefix for sorting
- `title` — feature name extracted from spec
- `stage` — current workflow stage
- `group` — `active` or `completed`
- `has_state` — whether a state file exists
- `user_stories` — count of user stories
- `task_count` — count of tasks
- `is_stalled` — boolean, true if no updates for 14+ days
- `days_since_update` — days since last state change
- `forked_from` — feature_id this was forked from (null if not a fork)
- `next_action` — suggested command to run
- `next_action_reason` — why that action is suggested

## Step 4: Handle Empty Results

If the JSON array is empty:

- **No filter applied:** Show onboarding message:

  ```
  No features found. Run /maestro.specify to create your first feature.
  ```

- **Filter applied:** Show filtered-empty message:

  ```
  No features found in stage "{stage}".

  Run /maestro.list to see all features, or /maestro.specify to create a new one.
  ```

Stop here if empty.

## Step 5: Stage Summary Header

Before the table, show a one-line summary counting features per stage:

```
Summary: 2 specify | 1 clarify | 3 plan | 0 tasks | 1 implement | 2 complete
```

Only include stages that have features (skip stages with 0 count). Example with sparse stages:

```
Summary: 2 specify | 3 plan | 1 implement
```

## Step 6: Format Output Table

Render a column-aligned table with these 6 columns:

```
Features (10 total)

ID    Name                          Stage        Stories  Tasks  Next Action
----  ----------------------------  -----------  -------  -----  --------------------------
010   ↳ from 005 Multi-currency v2  specify           0      0   /maestro.clarify
009   Payment reconciliation        plan              4      0   /maestro.tasks
008   Invoice templates             implement         6     12   (in progress)
007   Vendor onboarding             ⚠ STALLED (21d) specify  3   0   /maestro.clarify
005   Multi-currency support        clarify           5      0   /maestro.plan
004   Dashboard analytics           tasks             3      8   /maestro.implement
003   User notifications            ⚠ No state        0      0   /maestro.specify
──────────────────────────────────────────────────────────────────────────────
002   Batch payments                complete          4     10   /maestro.analyze
001   Basic invoicing               complete          3      6   /maestro.analyze
```

**Column Details:**

- **ID:** Numeric prefix from `feature_id` (e.g. `009`)
- **Name:** Feature title, truncated to 28 characters with `..` if longer. If the feature has a non-null `forked_from` field, prepend `↳ from {NNN} ` to the title, where NNN is the numeric ID prefix extracted from the `forked_from` feature_id (e.g., `005` from `005-multi-currency-support`). The truncation limit applies to the combined string including the fork prefix.
- **Stage:** Current stage; see Steps 8-9 for special indicators
- **Stories:** Count of user stories (`user_stories`)
- **Tasks:** Count of tasks (`task_count`)
- **Next Action:** The `next_action` value; show `(in progress)` if empty and stage is `implement`

## Step 7: Group Output

Separate active and completed features visually:

1. **Active features first** — sorted by `numeric_id` descending (newest first)
2. **Separator line** — a horizontal rule (`──────...`) spanning the table width
3. **Completed features** — sorted by `numeric_id` descending

If there are no completed features, omit the separator and completed section.
If there are no active features (all completed), omit the separator and show only completed.

## Step 8: Show Stalled Indicators

For features where `is_stalled` is `true`:

- Display `⚠ STALLED ({days}d)` next to the stage name in the Stage column
- Example: `⚠ STALLED (21d) specify`

This highlights features that haven't progressed in 14+ days and need attention.

## Step 9: Show Orphan Warnings

For features where `has_state` is `false`:

- Display `⚠ No state` in the Stage column instead of a stage name
- Set the Next Action to `/maestro.specify`

This identifies spec directories that were created manually without running the workflow.

## Step 10: Suggest Next Steps

After the table, recommend the most impactful action based on the feature landscape:

**Priority logic (first match wins):**

1. **Stalled features exist:** "⚠ {N} feature(s) stalled. Consider running the suggested next action to unblock progress."
2. **Orphan specs exist:** "⚠ {N} spec(s) without state. Run `/maestro.specify` on them to initialize tracking."
3. **Features in specify/clarify (early stages):** "💡 {N} feature(s) in early stages. Run `/maestro.clarify` or `/maestro.plan` to advance them."
4. **Features in plan/tasks (mid stages):** "🚀 {N} feature(s) ready for implementation. Run `/maestro.implement` to start building."
5. **All features complete:** "All features are complete. Run `/maestro.specify` to start a new feature, or `/maestro.analyze` to review outcomes."
6. **Default:** "Run the Next Action for any feature to advance your project."

```
───
Next steps: 🚀 2 feature(s) ready for implementation. Run /maestro.implement to start building.
```

---

**Remember:** This command is the project dashboard — the first thing a developer runs to orient themselves. Keep the output scannable, actionable, and focused on what to do next.
