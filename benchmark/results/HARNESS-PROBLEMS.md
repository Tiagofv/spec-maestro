# Maestro harness problems — found by developing a feature through the pipeline

Evidence from driving Case 01 (Go CLI task tracker — a trivial 4-command feature) through
the real maestro pipeline. The point isn't artifact correctness (the artifacts are fine) —
it's the **friction, ceremony, and context cost of the harness itself**.

Severity: 🔴 breaks/misleads · 🟡 clunky/wasteful · 🟢 papercut.

---

## 🔴 1. State JSON is hand-maintained by the model → it lies

Every one of the 10 commands tells the agent to **hand-write `.maestro/state/<feature>.json`**.
A model writing state has no clock and no view of git, so the file drifts from reality:

- **Fabricated timestamps.** Case 01's state has `created_at: …T00:00:00Z`,
  `…00:01:00Z`, `…00:02:00Z` — invented sequential times. `analyze`'s "metrics"
  (durations, velocity) are therefore meaningless.
- **Records a branch that doesn't exist.** State has `branch: feat/…`,
  `worktree_branch: feat/…` while `git branch` shows only `main` and
  `worktree_created: false`. The state asserts work that never happened.
- **Inconsistent counts.** `clarification_count: 0` even though clarify resolved 4.

**Fix:** make state script-owned. An `update-state.sh <feature> <stage> <action>` using real
`date` and `git` would remove the per-command "write this JSON" instructions (context saved
in 10 files) and make timestamps/branch real.

## 🔴 2. `implement` silently relocates work to a worktree → split-brain

The headline clunk. `specify`/`clarify`/`plan`/`tasks` all run on `main`: they write the
spec, plan, state, and bd issues there. Then `implement` (Step 1b) **defaults
`worktree_required=true`** and silently runs `worktree-create.sh`, which makes
`.worktrees/<slug>/` on a `feat/<slug>` branch and writes **all the code there**. Observed in
Case 01:

- main tree: still on `main`, `main.go` is the empty 3-line stub.
- `.worktrees/add-…/`: on `feat/add-…`, the real 588-line implementation (builds + vets +
  tests **green** — code quality is good!).
- The worktree's feature commits are **not visible from `main`** (`git log` on main shows only
  setup commits). bd (shared, on main) marks the tasks closed.

Net: the spec, plan, bd dashboard, and your `git HEAD` all say "done" while your actual
checkout (`main`) contains nothing. The feature is stranded in a hidden subdirectory on
another branch. For a solo dev running a quick feature this indirection is surprising and
easy to miss — you finish `implement`, look at your files, and see an empty stub.

Compounding: `create-feature.sh` *claims* (and the state file records) a branch at `specify`
time that doesn't exist until `implement`; `commit.md` assumes "commits will be made on the
worktree branch."

**Fix (decision needed):** make the worktree opt-in (default `worktree_required=false` for
single-agent runs), or surface it loudly ("your code is in .worktrees/<slug> on feat/<slug>")
and have `list`/state reflect *where the code actually is*. The worktree default makes sense
for parallel agents, not for the common solo flow.

## 🟡 3. Command files are huge and reloaded every invocation

Commands+skills ≈ **21.8K words / ~29K tokens**. `research.md` 4.2K · `implement.md` 3.4K
(656 lines, 7 steps, 4a–4f + 5a–5f substeps) · `plan.md` 2.4K. Each is loaded in full every
time the command runs — most of it conditional ceremony (worktree provisioning, signal-conflict
resolution, parallelism assessment) that doesn't apply to a simple run.

**Fix:** split each heavy command into a short **directive** (the happy path) + a **deferred
reference** section the agent only opens when a branch/edge actually occurs. Isolated-process
execution (see the benchmark runner) also caps the blast radius to one command per stage.

## 🟡 4. "Find the Feature" inference is duplicated across 7 commands

`clarify`, `research`, `plan`, `tasks`, `implement`, `pm-validate`, `specify` each re-implement
feature inference (state recency vs branch vs explicit id, conflict handling, "surface before
acting"). Same logic, 7 copies — a maintenance hazard and repeated context.

**Fix:** one `resolve-feature.sh` emitting `{feature_id, spec_dir, branch}`; commands call it
instead of restating the rules.

## 🟡 5. Templates force bloated artifacts for tiny features

`plan-template.md` (266 lines) produced a **346-line plan** for a 4-command CLI;
`spec-template.md` (121) → **181-line spec**. ~500 lines of scaffolding around ~20 lines of
real decisions. Reading these back in later stages re-pays the cost.

**Fix:** size-aware templates (an XS feature shouldn't emit Architecture/Data-Flow/API-Contract
sections it doesn't need), or collapse empty sections.

## 🟡 6. `implement` is expensive and slow for trivial work

The `implement` loop spawns an implementation subagent **and** a review subagent per task. For
Case 01 (5 impl tasks) that's ~10 subagent spawns. Cost/time: **$2.46 and ~11 min for one
stage** — 3× the entire specify+clarify+plan+tasks front half ($0.85+$0.62) combined, for a
~250-line CLI. Much of the per-task ceremony (worktree assertion, convention-memory scan,
routing, separate review spawn) is fixed overhead regardless of task size.

**Fix:** allow batching tiny tasks into one agent; make the inline review skip-or-fast-track
for LOW-risk diffs (the routing cookbook already classifies risk — use it to *skip* a full
review subagent, not just size it).

## 🟡 7. bd coupling is heavy

`tasks`/`implement` lean on bd for everything; `bd-preflight.sh` is a "five-branch decision
tree" (init / bootstrap / ok / drift-refuse / missing-prefix-refuse). It auto-inits (correct
`bench-` prefix, clean 12-issue DAG ✅), but the whole pipeline hard-depends on a second tool
whose failure modes the agent must reason about, and bd state (on main) drifts from where the
code actually is (in the worktree — see #2).

---

## Pipeline run log (Case 01, sonnet, headless)

| stage | turns | cost | wall | notes |
|-------|:-----:|:----:|:----:|-------|
| specify | 8 | $0.20 | 75s | good spec; greedy slug (fixed) |
| clarify | 13 | $0.28 | 77s | 4/4 resolved + written back — cleanest stage |
| plan | 14 | $0.37 | 165s | correct but 346 lines |
| tasks | 24 | $0.62 | 208s | clean 12-issue DAG; bd auto-init ✅ |
| implement | 49* | $2.46 | 651s | built all 5 tasks in a worktree, green gate; *halted at PM-VAL by API **credit limit**, not a maestro bug |
| pm-validate | — | — | — | not reached (credit) |
| commit | — | — | — | not reached (credit) |
| analyze | — | — | — | not reached (credit) |

**Front half (specify→tasks): $1.47 / ~9 min.** Implement alone: $2.46 / 11 min.
Full pipeline would be ~$4–5 / ~25 min headless for a trivial feature.

> Run caveat: the implement "error" was `Credit balance is too low` — the API account ran dry
> mid-run. The harness didn't crash. Re-run pm-validate/commit/analyze after topping up to
> observe those three (esp. whether `commit` copes with the split-brain and whether `analyze`
> reports real or fabricated-timestamp metrics).

---

## What to fix first (impact × ease)

1. **#2 worktree split-brain** — highest confusion; default worktrees off for solo runs or
   surface location loudly. *(decision)*
2. **#1 script-owned state** — kills fabricated timestamps + the lying branch field; removes
   "write this JSON" from 10 command files. *(clear win)*
3. **#3/#4 slim + de-duplicate commands** — directive + deferred-reference split; one
   `resolve-feature.sh`. Directly cuts the "too many words / context" pain. *(clear win)*
4. **#6 cheaper implement** — skip full review subagent for LOW-risk diffs; batch tiny tasks.
5. **#5 size-aware templates** — stop emitting unused sections for XS features.

Already fixed during this run: greedy slug (#earlier), benchmark overlay-tests-stale-resources.
