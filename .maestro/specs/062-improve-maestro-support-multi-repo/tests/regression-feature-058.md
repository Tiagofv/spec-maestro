# Regression Test: Feature 058 Lazy-Migration
## Feature 062 — Multi-Repo Support in Maestro

**Purpose:** Verify that the `write_state_worktrees` lazy-migration introduced in feature 062 correctly upgrades the flat `worktree_*` keys in an existing feature-058 state file to the new `worktrees` map structure when any state-mutating maestro command is run.

---

## Pre-conditions

Both of the following must be true before executing this test:

1. The spec-maestro feature-062 branch has been merged to `main` in the `spec-maestro` repo.
2. `scripts/update-maestro.sh` has been run in the AltPayments install, pulling the updated maestro scripts into `/Users/tiagofvx/AltPayments/.maestro/`.

Confirm with:

```bash
# In AltPayments repo — verify scripts carry the multi-repo changes
grep -n "write_state_worktrees\|MAESTRO_BASE" /Users/tiagofvx/AltPayments/.maestro/scripts/bd-helpers.sh | head -20
```

---

## Baseline — Legacy State Shape (feature 058)

The state file at `/Users/tiagofvx/AltPayments/.maestro/state/058-partner-assistant-add-reminder-creation.json` currently uses the **flat** pre-062 schema. The worktree-related fields as of the regression baseline are:

```json
{
  "worktree_name": "partner-assistant-add-reminder-creation",
  "worktree_path": ".worktrees/partner-assistant-add-reminder-creation",
  "worktree_branch": "feat/partner-assistant-add-reminder-creation",
  "worktree_created": false
}
```

The `worktrees` map key and `repos` array are **absent** in the legacy file. This is the shape that must be migrated.

Full file for reference (relevant section only — no `worktrees` key, no `repos` key):

```json
{
  "feature_id": "058-partner-assistant-add-reminder-creation",
  "stage": "tasks",
  "branch": "feat/partner-assistant-add-reminder-creation",
  "worktree_name": "partner-assistant-add-reminder-creation",
  "worktree_path": ".worktrees/partner-assistant-add-reminder-creation",
  "worktree_branch": "feat/partner-assistant-add-reminder-creation",
  "worktree_created": false
}
```

---

## Test Step

Run the bd-helpers internal unit test, which exercises `write_state_worktrees` (including lazy-migration of existing state files) without requiring a full maestro command:

```bash
cd /Users/tiagofvx/AltPayments
bash .maestro/scripts/bd-helpers.sh --test
```

Expected output: the test suite completes without errors and prints a summary that includes the `write_state_worktrees` test case.

Alternatively, trigger a real state read+write by running any state-mutating maestro command against feature 058, for example:

```bash
# Minimal state-touching command — reads and rewrites state
cd /Users/tiagofvx/AltPayments
MAESTRO_FEATURE=058-partner-assistant-add-reminder-creation \
  bash .maestro/scripts/bd-helpers.sh --refresh-state
```

---

## Verification

After the test step, read the migrated state file:

```bash
cat /Users/tiagofvx/AltPayments/.maestro/state/058-partner-assistant-add-reminder-creation.json | python3 -m json.tool
```

Check for all three of the following:

### (a) `worktrees` map with key `"AltPayments"`

The file must contain a `worktrees` object whose key is the basename of `MAESTRO_BASE` (i.e., `"AltPayments"`):

```json
{
  "worktrees": {
    "AltPayments": {
      "name": "partner-assistant-add-reminder-creation",
      "path": ".worktrees/partner-assistant-add-reminder-creation",
      "branch": "feat/partner-assistant-add-reminder-creation",
      "created": false
    }
  }
}
```

### (b) Flat `worktree_*` keys absent

None of the following keys should be present at the top level after migration:

- `worktree_name`
- `worktree_path`
- `worktree_branch`
- `worktree_created`

Verify with:

```bash
python3 -c "
import json, sys
data = json.load(open('/Users/tiagofvx/AltPayments/.maestro/state/058-partner-assistant-add-reminder-creation.json'))
flat_keys = [k for k in data if k.startswith('worktree_')]
print('FAIL — flat keys still present:', flat_keys) if flat_keys else print('PASS — no flat worktree_* keys')
"
```

### (c) `repos` array contains `"AltPayments"`

The file must contain a `repos` array listing the repo names that have state for this feature:

```json
{
  "repos": ["AltPayments"]
}
```

Verify with:

```bash
python3 -c "
import json
data = json.load(open('/Users/tiagofvx/AltPayments/.maestro/state/058-partner-assistant-add-reminder-creation.json'))
repos = data.get('repos', [])
print('PASS — repos:', repos) if 'AltPayments' in repos else print('FAIL — AltPayments not in repos:', repos)
"
```

---

## Pass/Fail Criteria

- [ ] **PASS (a):** `worktrees` map exists in the state file with key `"AltPayments"` (the basename of `MAESTRO_BASE`) containing the worktree metadata.
- [ ] **PASS (b):** All `worktree_*` flat top-level keys (`worktree_name`, `worktree_path`, `worktree_branch`, `worktree_created`) are absent from the migrated state file.
- [ ] **PASS (c):** `repos` array is present and contains `"AltPayments"`.

All three checkboxes must be checked for this regression test to pass. Any single failure indicates the lazy-migration in `write_state_worktrees` did not execute correctly for feature 058.

---

## Notes

- This test is non-destructive: it only reads and rewrites the state file structure; no beads issues or git history are modified.
- If the test step produces an error about a missing `--test` flag, confirm the 062 scripts are present (`grep -n 'write_state_worktrees' .maestro/scripts/bd-helpers.sh`). If missing, re-run `scripts/update-maestro.sh`.
- The lazy-migration must be idempotent: running the test step a second time must produce the same result and must not duplicate entries in the `worktrees` map or `repos` array.
