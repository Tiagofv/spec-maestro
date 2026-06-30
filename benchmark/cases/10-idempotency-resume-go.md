# Case 10 — Idempotency & resume (Go)

**Stack** Go · **Shape** re-running stages on purpose

Every other case runs each stage exactly once. This case **re-runs stages** to exercise the
guards that protect against double-work — code paths nothing else touches:
- `tasks` idempotency (Step 5): re-running `/maestro.tasks` on a feature that already has an
  epic must **not** create a second epic/duplicate tasks.
- `specify` refine mode: re-running `/maestro.specify` on an existing feature refines it,
  doesn't clobber.
- `implement` resume / worktree half-provisioned guard: re-entering implement must not
  re-provision or double-implement.

**Stresses:** `tasks` idempotency guard, `specify` refine path, `implement --resume` /
half-provisioned worktree guard, state `history` integrity across re-runs.

## Domain
A trivial Go string utility (`slugify`) — the feature is incidental; the point is re-running.

## Seed
`go.mod` (module `example.com/textutil`) + empty `textutil.go`.

## Specify (verbatim)
> Add `Slugify(s string) string`: lowercase, replace runs of non-alphanumerics with a
> single hyphen, trim leading/trailing hyphens.

## Run protocol
`init` → `specify` → **`specify` again** (refine: "also strip accents") → `clarify` →
`plan` → `tasks` → **`tasks` again** → `implement` → **`implement` again**.

## What good looks like
- **specify (2nd run)**: detects the existing feature, enters refine mode, folds in the new
  requirement, preserves prior content + clarification markers — does not create `002-…`.
- **tasks (2nd run)**: detects the existing `epic_id`, reports the existing epic, and
  **stops** — no duplicate epic, no duplicate tasks. State `history` shows the re-run.
- **implement (2nd run)**: with the feature already done, reports "all tasks closed" (or
  resumes cleanly); does not re-provision the worktree or redo closed tasks.

## Watch for
2nd `specify` creating a `-v2` / `002-` duplicate instead of refining · 2nd `tasks` creating
a second epic or duplicate tasks · `implement` re-running closed tasks or tripping the
half-provisioned guard on an already-provisioned worktree · `history` entries overwritten
instead of appended.
