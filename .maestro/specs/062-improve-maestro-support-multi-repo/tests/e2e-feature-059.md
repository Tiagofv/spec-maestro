# E2E Validation: Feature 059 Against Multi-Repo Support (Feature 062)
## Feature 062 — Multi-Repo Support in Maestro

**Purpose:** Verify that `/maestro.implement` correctly provisions per-repo worktrees, routes tasks by repo label, enforces per-stack compile gates, pushes both branches, and never invokes `gh pr create` — using feature 059 (`059-partner-assistant-add-invoice-download`) as the real-world multi-repo test target.

---

## Pre-conditions

Both of the following must be true before executing this runbook:

1. The spec-maestro feature-062 branch has been merged to `main` in the `spec-maestro` repo.
2. `scripts/update-maestro.sh` has been run in the AltPayments install, pulling the updated maestro scripts into `/Users/tiagofvx/AltPayments/.maestro/`.

Confirm with:

```bash
# In AltPayments repo — verify scripts carry the multi-repo changes
grep -n "write_state_worktrees\|read_state_worktrees\|MAESTRO_BASE" \
  /Users/tiagofvx/AltPayments/.maestro/scripts/bd-helpers.sh | head -20
```

Expected: output includes `write_state_worktrees`, `read_state_worktrees`, and `MAESTRO_BASE` lines.

---

## Setup — Feature 059 State Shape (Test Target)

The state file at `/Users/tiagofvx/AltPayments/.maestro/state/059-partner-assistant-add-invoice-download.json`
already uses the **feature-062 multi-repo schema** (it was completed after 062's schema was introduced).
Its authoritative shape at the time this runbook was written:

```json
{
  "feature_id": "059-partner-assistant-add-invoice-download",
  "stage": "complete",
  "multi_repo": true,
  "repos": ["svc-accounts-receivable", "alt-front-end"],
  "repo_worktrees": {
    "svc-accounts-receivable": {
      "path": "/Users/tiagofvx/AltPayments/svc-accounts-receivable/.worktrees/059-partner-assistant-add-invoice-download",
      "branch": "feat/059-partner-assistant-add-invoice-download",
      "linear": "AR-7421",
      "pr": "https://github.com/getalternative/svc-accounts-receivable/pull/182",
      "commits": 3
    },
    "alt-front-end": {
      "path": "/Users/tiagofvx/AltPayments/alt-front-end/.worktrees/059-partner-assistant-add-invoice-download",
      "branch": "feat/059-partner-assistant-add-invoice-download",
      "linear": "AR-7422",
      "pr": "https://github.com/getalternative/alt-front-end/pull/4131",
      "commits": 5
    }
  }
}
```

Key observations for this test:
- `multi_repo: true` — triggers the multi-repo code path in `/maestro.implement`.
- Two distinct repos: `svc-accounts-receivable` (Go) and `alt-front-end` (TypeScript/React).
- The state field is `repo_worktrees` (not `worktrees`) — verify that the 062 runtime reads this correctly via `read_state_worktrees`.

> **Caution — feature is `complete`:** Worktrees for 059 were torn down and PRs are open. A live `/maestro.implement` re-run on a completed feature would attempt to re-provision worktrees. **Do not run this against production 059 state without first cloning the state file to a test fixture.** See the dry-run approach in Step 1 below.

---

## Test Sequence

### Step 1a — Create a test fixture (clone state to avoid touching the live complete feature)

```bash
cp /Users/tiagofvx/AltPayments/.maestro/state/059-partner-assistant-add-invoice-download.json \
   /Users/tiagofvx/AltPayments/.maestro/state/059-e2e-test-fixture.json

# Reset stage to "tasks" so implement will run; clear completed_at
python3 -c "
import json, datetime
path = '/Users/tiagofvx/AltPayments/.maestro/state/059-e2e-test-fixture.json'
with open(path) as f: data = json.load(f)
data['feature_id'] = '059-e2e-test-fixture'
data['stage'] = 'tasks'
data.pop('completed_at', None)
# Mark worktrees as not yet created so provisioning runs
for repo in data.get('repo_worktrees', {}).values():
    repo['created'] = False
with open(path, 'w') as f: json.dump(data, f, indent=2)
print('fixture ready')
"
```

### Step 1b — Run `/maestro.implement` against the test fixture

> If running against the live 059 state (e.g., in a sandboxed environment), use `--resume` if worktrees are already partially provisioned.

```bash
# In AltPayments Claude Code session:
/maestro.implement 059-e2e-test-fixture
```

**Expected provisioning output (one line per repo, order may vary):**

```
Provisioning worktree: svc-accounts-receivable
  bash .maestro/scripts/worktree-create.sh --repo svc-accounts-receivable --feature 059-e2e-test-fixture
  → worktree created at /Users/tiagofvx/AltPayments/svc-accounts-receivable/.worktrees/059-e2e-test-fixture

Provisioning worktree: alt-front-end
  bash .maestro/scripts/worktree-create.sh --repo alt-front-end --feature 059-e2e-test-fixture
  → worktree created at /Users/tiagofvx/AltPayments/alt-front-end/.worktrees/059-e2e-test-fixture
```

**Verify worktrees exist in the right repo directories:**

```bash
ls /Users/tiagofvx/AltPayments/svc-accounts-receivable/.worktrees/059-e2e-test-fixture/
ls /Users/tiagofvx/AltPayments/alt-front-end/.worktrees/059-e2e-test-fixture/
```

Expected: each directory exists and contains the repo's source tree.

**Verify N=2 worktrees were created (one per repo):**

```bash
python3 -c "
import json
data = json.load(open('/Users/tiagofvx/AltPayments/.maestro/state/059-e2e-test-fixture.json'))
wt = data.get('repo_worktrees', data.get('worktrees', {}))
created = [r for r, v in wt.items() if v.get('created', False)]
print(f'PASS — {len(created)} worktrees created: {created}') if len(created) == 2 else print(f'FAIL — expected 2, got {len(created)}: {created}')
"
```

---

### Step 2 — Verify Go and TS tasks routed to their respective worktrees

When `/maestro.implement` processes a task, the orchestrator reads the task's `repo:*` bd label and resolves the worktree path from `state.repo_worktrees[repo].path` (or `state.worktrees[repo].path`).

**Observe routing log output during implement run:**

Expected lines (one per task, `repo:svc-accounts-receivable` for Go tasks, `repo:alt-front-end` for TS tasks):

```
Routing: bd_058-3c2.1 (…Go task title…) → golang-code-agent [label: backend, repo:svc-accounts-receivable]
  Working directory: /Users/tiagofvx/AltPayments/svc-accounts-receivable/.worktrees/059-e2e-test-fixture

Routing: bd_058-3c2.3 (…TS task title…) → js-code-agent [label: frontend, repo:alt-front-end]
  Working directory: /Users/tiagofvx/AltPayments/alt-front-end/.worktrees/059-e2e-test-fixture
```

**Verify no Go task is routed to `alt-front-end` and no TS task is routed to `svc-accounts-receivable`:** absence of cross-routing in the log is the check. If any task's repo label does not match a key in `repo_worktrees`, the orchestrator must print:

```
ERROR: Task {id} has no repo:* label. Cannot determine worktree.
```

and stop — verify this guard fires correctly if you introduce a label-less task.

---

### Step 3 — Verify compile gate runs correct stack per repo

The compile gate is invoked as:

```bash
bash .maestro/scripts/compile-gate.sh {worktree_path}
```

where `worktree_path` is the per-repo path resolved from state.

**For `svc-accounts-receivable` (Go stack):**

```bash
bash /Users/tiagofvx/AltPayments/.maestro/scripts/compile-gate.sh \
  /Users/tiagofvx/AltPayments/svc-accounts-receivable/.worktrees/059-e2e-test-fixture
```

Expected: compile-gate detects `go.mod` in the worktree and runs `go build ./...` (or the stack configured in `compile_gate.repos` for `svc-accounts-receivable`). Must exit 0.

**For `alt-front-end` (TypeScript/React stack):**

```bash
bash /Users/tiagofvx/AltPayments/.maestro/scripts/compile-gate.sh \
  /Users/tiagofvx/AltPayments/alt-front-end/.worktrees/059-e2e-test-fixture
```

Expected: compile-gate detects `package.json` / `tsconfig.json` and runs `tsc --noEmit` (or the stack configured in `compile_gate.repos` for `alt-front-end`). Must exit 0.

**Verify cross-stack gate is NOT triggered:** the Go compile gate must not run inside `alt-front-end` and vice versa. Inspect the gate's stdout for stack-detection lines, e.g.:

```
[compile-gate] repo: svc-accounts-receivable  stacks: go
[compile-gate] repo: alt-front-end            stacks: ts
```

---

### Step 4 — Verify both branches pushed at end

After all tasks close, the orchestrator runs:

```bash
# For each repo in state.repos:
git -C /Users/tiagofvx/AltPayments/svc-accounts-receivable/.worktrees/059-e2e-test-fixture \
    push origin feat/059-e2e-test-fixture

git -C /Users/tiagofvx/AltPayments/alt-front-end/.worktrees/059-e2e-test-fixture \
    push origin feat/059-e2e-test-fixture
```

**Verify both pushes succeed:**

```bash
git -C /Users/tiagofvx/AltPayments/svc-accounts-receivable \
    ls-remote --heads origin feat/059-e2e-test-fixture
git -C /Users/tiagofvx/AltPayments/alt-front-end \
    ls-remote --heads origin feat/059-e2e-test-fixture
```

Expected: each command returns exactly one ref line (the pushed branch). An empty result means the push did not happen.

---

### Step 5 — Verify no `gh pr create` was invoked

The implement command must NOT invoke `gh pr create` or the `linear-pr` skill. This is enforced by Decision 8.2 in the command spec.

**Verify by inspecting orchestrator output and Claude transcript for the run:** search for `gh pr create` or `linear-pr`:

```bash
# If the session transcript is captured in a log file, search it:
grep -i "gh pr create\|linear-pr\|pull_request\|pr create" /tmp/maestro-implement-run.log 2>/dev/null \
  && echo "FAIL — pr creation was invoked" || echo "PASS — no pr creation found"
```

Expected: no matches. If `gh pr create` appears in the log, the Decision 8.2 guard is broken.

---

### Step 6 — Run `list-feature-branches.sh` and verify output format

```bash
bash /Users/tiagofvx/AltPayments/.maestro/scripts/list-feature-branches.sh \
  --feature 059-e2e-test-fixture
```

**Expected output (one line per repo, `<repo>:<branch>` format, order may vary):**

```
svc-accounts-receivable:feat/059-e2e-test-fixture
alt-front-end:feat/059-e2e-test-fixture
```

Verify:
- Exactly 2 lines (one per repo).
- Each line matches the pattern `<repo-name>:<branch-name>` with no extra whitespace.
- Branch names match what was stored in `repo_worktrees[repo].branch`.

```bash
OUTPUT=$(bash /Users/tiagofvx/AltPayments/.maestro/scripts/list-feature-branches.sh \
           --feature 059-e2e-test-fixture)
LINE_COUNT=$(echo "$OUTPUT" | wc -l | tr -d ' ')
echo "$OUTPUT" | grep -E '^[^:]+:[^:]+$' | wc -l | tr -d ' ' | \
  xargs -I{} bash -c \
    "[ {} -eq $LINE_COUNT ] && echo 'PASS — all lines match <repo>:<branch>' || echo 'FAIL — malformed lines'"
echo "Line count: $LINE_COUNT (expected 2)"
```

---

## Pass/Fail Criteria

- [ ] **AC-1 (Multi-repo worktree provisioning):** `/maestro.implement` creates exactly one worktree per repo declared in `state.repos` (`svc-accounts-receivable` and `alt-front-end`), each in the correct repo's `.worktrees/` directory. Go tasks receive the `svc-accounts-receivable` worktree path; TS tasks receive the `alt-front-end` worktree path.

- [ ] **AC-2 (Per-repo compile gate and branch push):** The compile gate runs the correct stack (Go for `svc-accounts-receivable`, TypeScript for `alt-front-end`) and exits 0 for both. After all tasks close, both feature branches are pushed to their respective remotes. `gh pr create` is never invoked.

Both checkboxes must be checked for this e2e validation to pass.

---

## Notes and Caveats

- **Feature 059 is `complete`:** Worktrees were torn down and PRs are open. Running `/maestro.implement` on the live state without cloning to a fixture will attempt to re-provision worktrees on an already-complete feature, which may produce unexpected results. Always use the fixture approach (Step 1a) unless in a sandboxed environment.

- **`repo_worktrees` vs `worktrees` key:** Feature 059's state uses `repo_worktrees` (the pre-062 field name used during its implementation). The 062 runtime must read this via `read_state_worktrees`, which normalizes both field names. If the script only reads `worktrees`, Step 1b will fail with "no worktrees found" — this is a 062 bug to fix before marking AC-1 passed.

- **Fixture cleanup:** After the test run, remove the test fixture and clean up worktrees:
  ```bash
  bash /Users/tiagofvx/AltPayments/.maestro/scripts/worktree-cleanup.sh \
    --all --feature 059-e2e-test-fixture
  rm /Users/tiagofvx/AltPayments/.maestro/state/059-e2e-test-fixture.json
  ```

- **Epic ID:** Feature 059's tasks use the `bd_058-3c2` prefix (see `bd_prefix_caveat` in the state file). Ensure `bd ready` and `bd show` resolve these task IDs correctly in the current workspace before running implement.
