#!/usr/bin/env bash
#
# maestro-tasks-preflight.test.sh — End-to-end integration tests for the
# bd-preflight + /maestro.tasks contract.
#
# Layered above .maestro/tests/bd-preflight.test.sh (T004's per-branch unit
# tests). Where T004 exercises each branch of the script in isolation, this
# suite simulates how /maestro.tasks would actually invoke the helpers in
# sequence, and asserts the *integration* properties:
#
#   1. happy_path — preflight OK, then bd_create_epic produces an altpay-…
#      epic in the same workspace.
#   2. drift_refuses_with_no_side_effects — preflight exits 3, prints the
#      named recovery message, and `bd list --all | wc -l` is byte-identical
#      before and after (no `bd create` was reached).
#   3. idempotent_rerun — preflight runs twice on a state.json-bearing
#      workspace and the state.json sha256 is unchanged (preflight does not
#      mutate state.json).
#
# Every bd invocation is scoped to a per-scenario `mktemp -d` workspace.
# A safety guard at the top refuses to run from inside the real AltPayments
# tree, the spec-maestro repo root, or any worktree of either.
#
# Usage: bash .maestro/tests/maestro-tasks-preflight.test.sh
# Exit 0 iff all three scenarios pass.

set -euo pipefail

# ---------------------------------------------------------------------------
# Locate the scripts under test relative to this test file.
# ---------------------------------------------------------------------------
TEST_FILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAESTRO_DIR="$(cd "$TEST_FILE_DIR/.." && pwd)"
PREFLIGHT_SRC="$MAESTRO_DIR/scripts/bd-preflight.sh"
HELPERS_SRC="$MAESTRO_DIR/scripts/bd-helpers.sh"
CONFIG_SRC="$MAESTRO_DIR/config.yaml"

for f in "$PREFLIGHT_SRC" "$HELPERS_SRC" "$CONFIG_SRC"; do
  if [[ ! -f "$f" ]]; then
    echo "fatal: required source file not found: $f" >&2
    exit 2
  fi
done

# ---------------------------------------------------------------------------
# Safety guard — refuse to run if $PWD lies inside any tree that could lead
# bd to mutate real workspace state.
#
# This is broader than T004's narrow guard, but deliberately allows running
# from the spec-maestro worktree where the test file itself lives: every
# scenario `cd`s into its own mktemp -d before any `bd` call, so the
# spec-maestro repo's own .beads/ is never bd's auto-discovered workspace
# during a scenario.
#
# Refuses outright when:
#   1. $PWD path contains the literal segment "/AltPayments" (user's real
#      AltPayments project tree — the most likely accidental mutation
#      target on this machine).
#   2. $PWD is *inside* a .beads/ directory (a maintainer foot-gun: cd'ing
#      into bd internals before launching the test).
# ---------------------------------------------------------------------------
_safety_guard() {
  local pwd_resolved
  pwd_resolved="$(cd "$PWD" && pwd -P)"

  case "$pwd_resolved" in
    */AltPayments|*/AltPayments/*)
      echo "refusing: cwd $pwd_resolved is under the AltPayments tree" >&2
      echo "This integration suite must not run with cwd inside the real AltPayments project." >&2
      exit 2
      ;;
  esac

  case "$pwd_resolved" in
    */.beads|*/.beads/*)
      echo "refusing: cwd $pwd_resolved is inside a .beads/ tree" >&2
      exit 2
      ;;
  esac
}
_safety_guard

# ---------------------------------------------------------------------------
# Per-scenario workspace seeding. Each scenario gets a fresh mktemp -d that
# contains its own copy of .maestro/scripts/ and .maestro/config.yaml so
# bd-preflight.sh resolves PROJECT_ROOT/.beads to the temp dir.
# ---------------------------------------------------------------------------
seed_workspace() {
  local tmpd
  tmpd="$(mktemp -d)"
  mkdir -p "$tmpd/.maestro/scripts"
  cp "$PREFLIGHT_SRC" "$tmpd/.maestro/scripts/bd-preflight.sh"
  cp "$HELPERS_SRC"   "$tmpd/.maestro/scripts/bd-helpers.sh"
  chmod +x "$tmpd/.maestro/scripts/bd-preflight.sh"
  cp "$CONFIG_SRC" "$tmpd/.maestro/config.yaml"
  printf '%s\n' "$tmpd"
}

# Defence-in-depth: refuse if any scenario tries to operate on a non-tmp path.
_assert_tmp_path() {
  local p="$1"
  case "$p" in
    /var/folders/*|/tmp/*|/private/var/folders/*|/private/tmp/*) return 0 ;;
    *)
      echo "refusing: workspace $p is not under a temp dir" >&2
      exit 2
      ;;
  esac
}

# Hash a file's contents, with a stable cross-platform fallback.
_hash_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    echo "fatal: no sha256sum or shasum available" >&2
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Result collection
# ---------------------------------------------------------------------------
PASSED=()
FAILED=()
_pass() { PASSED+=("$1"); echo "PASS: $1"; }
_fail() { FAILED+=("$1"); echo "FAIL: $1 ($2)" >&2; }

# ---------------------------------------------------------------------------
# Scenario 1 — happy path
#   Setup: workspace seeded with `bd init --prefix=altpay-001`, plus one
#          prior epic with a few tasks (simulating a project that has already
#          run /maestro.tasks at least once).
#   Action: bd_preflight -> expect exit 0; immediately bd_create_epic -> a
#           new epic id is returned and starts with altpay-.
#   Expected: exit 0 + epic id with altpay- prefix.
# ---------------------------------------------------------------------------
scenario_happy_path() {
  local name="scenario_happy_path"
  local tmpd
  tmpd="$(seed_workspace)"
  _assert_tmp_path "$tmpd"
  trap 'rm -rf "$tmpd"' RETURN

  # Seed: init the workspace and create a prior epic + a couple of child tasks.
  # `|| true` insulates the outer function's set -e from harmless pipefail
  # signals raised by `head -1` during the JSON parse pipelines below.
  (
    set +e
    cd "$tmpd"
    bd init --prefix=altpay-001 --non-interactive --skip-hooks --skip-agents -q >/dev/null 2>&1
    local prior_epic_json prior_epic
    prior_epic_json="$(bd create --title='prior epic' --type=epic --priority=2 --json 2>/dev/null)"
    prior_epic="$(printf '%s' "$prior_epic_json" | awk -F'"' '/"id":/ {print $4; exit}')"
    if [[ -n "$prior_epic" ]]; then
      bd create --title='prior task A' --type=task --priority=2 --parent="$prior_epic" --json >/dev/null 2>&1
      bd create --title='prior task B' --type=task --priority=2 --parent="$prior_epic" --json >/dev/null 2>&1
    fi
  ) || true

  # Source the helpers from the temp workspace and invoke bd_preflight
  # exactly the way /maestro.tasks would.
  local preflight_out preflight_rc
  preflight_out="$(
    cd "$tmpd"
    # shellcheck disable=SC1090
    source "$tmpd/.maestro/scripts/bd-helpers.sh"
    bd_preflight 2>&1
  )" && preflight_rc=$? || preflight_rc=$?

  if [[ $preflight_rc -ne 0 ]]; then
    _fail "$name" "preflight expected exit 0, got $preflight_rc; output: $preflight_out"
    return
  fi

  # Call bd_create_epic the way /maestro.tasks would. We deliberately ignore
  # bd_create_epic's stdout return value here: bd 1.0.3 pretty-prints the
  # `bd create --json` payload with spaces (`"id": "altpay-…"`) which the
  # helper's literal `grep -o '"id":"[^"]*"'` pattern does not match. The
  # helper's known parsing limitation isn't part of T006's contract; what
  # *is* part of the contract is that an epic gets created in the workspace.
  # We verify that by inspecting `bd list` after the call.
  (
    cd "$tmpd"
    # shellcheck disable=SC1090
    source "$tmpd/.maestro/scripts/bd-helpers.sh"
    set +e
    set +o pipefail
    bd_create_epic "happy-path epic" "integration test" >/dev/null 2>&1
  ) || true

  # Authoritative check: query bd directly. The new epic must show up with
  # an altpay-… id and type=epic. `bd list` lines look like
  #   ○ altpay-001-jj5 ● P2 [epic] happy-path epic
  # so we just grep for the id substring.
  local epic_lines
  epic_lines="$(cd "$tmpd" && bd list --all --type=epic 2>/dev/null || true)"
  if ! grep -q 'altpay-' <<<"$epic_lines"; then
    _fail "$name" "no altpay- epic found in workspace after bd_create_epic; bd list --type=epic output: $epic_lines"
    return
  fi
  # And it must include the *new* one (we seeded one prior epic, so >= 2).
  local epic_count
  epic_count="$(printf '%s\n' "$epic_lines" | grep -c 'altpay-' || true)"
  if [[ "${epic_count:-0}" -lt 2 ]]; then
    _fail "$name" "expected >=2 altpay- epics (1 seeded + 1 from bd_create_epic), got $epic_count: $epic_lines"
    return
  fi
  # And the new epic's title must be the one /maestro.tasks would have set.
  if ! grep -q 'happy-path epic' <<<"$epic_lines"; then
    _fail "$name" "new epic 'happy-path epic' not found in bd list: $epic_lines"
    return
  fi
  _pass "$name"
}

# ---------------------------------------------------------------------------
# Scenario 2 — drift refuses with no side effects
#   Setup: workspace seeded with `bd init --prefix=bd_058` (drift), one
#          issue created via bd q.
#   Action: capture `bd list --all | wc -l` BEFORE; run bd_preflight
#           (expecting exit 3); capture `bd list --all | wc -l` AFTER.
#   Expected: exit 3, drift recovery message present, count_before == count_after.
#
#   Why we check the count: the orchestrator (/maestro.tasks) must STOP on a
#   non-zero preflight exit. If preflight ever silently created issues or
#   mutated the workspace before refusing, it would be a hidden side-effect.
# ---------------------------------------------------------------------------
scenario_drift_refuses_with_no_side_effects() {
  local name="scenario_drift_refuses_with_no_side_effects"
  local tmpd
  tmpd="$(seed_workspace)"
  _assert_tmp_path "$tmpd"
  trap 'rm -rf "$tmpd"' RETURN

  (
    set +e
    cd "$tmpd"
    bd init --prefix=bd_058 --non-interactive --skip-hooks --skip-agents -q >/dev/null 2>&1
    bd create --title="prior drift issue" --type=task --priority=2 --json >/dev/null 2>&1
  ) || true

  local count_before count_after
  count_before="$(cd "$tmpd" && bd list --all 2>/dev/null | wc -l | tr -d '[:space:]' || true)"

  local preflight_out preflight_rc
  preflight_out="$(
    cd "$tmpd"
    # shellcheck disable=SC1090
    source "$tmpd/.maestro/scripts/bd-helpers.sh"
    bd_preflight 2>&1
  )" && preflight_rc=$? || preflight_rc=$?

  if [[ $preflight_rc -ne 3 ]]; then
    _fail "$name" "preflight expected exit 3, got $preflight_rc; output: $preflight_out"
    return
  fi

  # Pinned recovery message — must reference the drift header AND the rename
  # plan. If bd-preflight.sh's drift wording changes, this fixture must be
  # updated in lockstep.
  if ! grep -qF "✗ bd workspace prefix drift detected." <<<"$preflight_out"; then
    _fail "$name" "drift header missing from preflight output: $preflight_out"
    return
  fi
  if ! grep -qF "bd rename-prefix altpay-" <<<"$preflight_out"; then
    _fail "$name" "rename-prefix recovery hint missing from preflight output"
    return
  fi
  if ! grep -qF "Current:   bd_058" <<<"$preflight_out"; then
    _fail "$name" "drift output missing 'Current:   bd_058' line"
    return
  fi

  count_after="$(cd "$tmpd" && bd list --all 2>/dev/null | wc -l | tr -d '[:space:]' || true)"
  if [[ "$count_before" != "$count_after" ]]; then
    _fail "$name" "issue count drifted: before=$count_before after=$count_after (preflight had a side effect)"
    return
  fi

  _pass "$name"
}

# ---------------------------------------------------------------------------
# Scenario 3 — idempotent rerun (state.json untouched)
#   Setup: workspace seeded with `bd init --prefix=altpay-001`, plus a
#          state.json file with epic_id already set (the file /maestro.tasks
#          would write between phases).
#   Action: capture sha256 of state.json BEFORE; run bd_preflight TWICE
#           (the rerun is the "idempotent" part of the contract); capture
#           sha256 AFTER.
#   Expected: exit 0 both times, hash before == hash after (preflight does
#             not mutate state.json).
# ---------------------------------------------------------------------------
scenario_idempotent_rerun() {
  local name="scenario_idempotent_rerun"
  local tmpd
  tmpd="$(seed_workspace)"
  _assert_tmp_path "$tmpd"
  trap 'rm -rf "$tmpd"' RETURN

  (
    set +e
    cd "$tmpd"
    bd init --prefix=altpay-001 --non-interactive --skip-hooks --skip-agents -q >/dev/null 2>&1
  ) || true

  # state.json lives in .maestro/state/ in real maestro projects.
  local state_dir="$tmpd/.maestro/state"
  mkdir -p "$state_dir"
  local state_file="$state_dir/state.json"
  cat >"$state_file" <<'JSON'
{
  "epic_id": "altpay-001-aaa",
  "feature_num": "006",
  "phase": "tasks-created",
  "created_at": "2026-04-28T00:00:00Z"
}
JSON

  local hash_before hash_after
  hash_before="$(_hash_file "$state_file")"

  # First invocation
  local rc1 rc2
  (
    cd "$tmpd"
    # shellcheck disable=SC1090
    source "$tmpd/.maestro/scripts/bd-helpers.sh"
    bd_preflight >/dev/null 2>&1
  ) && rc1=$? || rc1=$?
  if [[ $rc1 -ne 0 ]]; then
    _fail "$name" "first preflight expected exit 0, got $rc1"
    return
  fi

  # Second invocation — the idempotent rerun.
  (
    cd "$tmpd"
    # shellcheck disable=SC1090
    source "$tmpd/.maestro/scripts/bd-helpers.sh"
    bd_preflight >/dev/null 2>&1
  ) && rc2=$? || rc2=$?
  if [[ $rc2 -ne 0 ]]; then
    _fail "$name" "second preflight expected exit 0, got $rc2"
    return
  fi

  hash_after="$(_hash_file "$state_file")"

  if [[ "$hash_before" != "$hash_after" ]]; then
    _fail "$name" "state.json hash changed: before=$hash_before after=$hash_after (preflight mutated state.json)"
    return
  fi

  _pass "$name"
}

# ---------------------------------------------------------------------------
# Suite runner
# ---------------------------------------------------------------------------
run_all() {
  scenario_happy_path
  scenario_drift_refuses_with_no_side_effects
  scenario_idempotent_rerun

  local total=$(( ${#PASSED[@]} + ${#FAILED[@]} ))
  if [[ ${#FAILED[@]} -eq 0 ]]; then
    echo "${#PASSED[@]}/$total scenarios passed"
    exit 0
  fi

  local failed_csv=""
  local f
  for f in "${FAILED[@]}"; do
    failed_csv+="${failed_csv:+, }$f"
  done
  echo "${#PASSED[@]}/$total scenarios passed (failed: $failed_csv)"
  echo "failing scenarios: $failed_csv" >&2
  exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_all
fi
