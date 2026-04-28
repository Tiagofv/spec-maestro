#!/usr/bin/env bash
#
# bd-preflight.test.sh — Unit tests for .maestro/scripts/bd-preflight.sh
#
# Exercises all five branches in plan §2.1 against mktemp -d seeded workspaces.
# Never touches the real .beads/ — refuses to run if invoked from inside a real
# maestro/altpayments tree.
#
# Usage: bash .maestro/tests/bd-preflight.test.sh
# Exit 0 iff all 5 tests pass.

set -euo pipefail

# ---------------------------------------------------------------------------
# Locate the script under test relative to this test file.
# ---------------------------------------------------------------------------
TEST_FILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAESTRO_DIR="$(cd "$TEST_FILE_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$MAESTRO_DIR/.." && pwd)"
PREFLIGHT_SRC="$MAESTRO_DIR/scripts/bd-preflight.sh"
CONFIG_SRC="$MAESTRO_DIR/config.yaml"

if [[ ! -f "$PREFLIGHT_SRC" ]]; then
  echo "fatal: bd-preflight.sh not found at $PREFLIGHT_SRC" >&2
  exit 2
fi
if [[ ! -f "$CONFIG_SRC" ]]; then
  echo "fatal: config.yaml not found at $CONFIG_SRC" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Safety guard — refuse to run if $PWD looks like the real AltPayments or
# spec-maestro worktree tree. Tests must always work inside mktemp -d.
# This guards $PWD only; the test bodies themselves cd into temp dirs.
# ---------------------------------------------------------------------------
_safety_guard() {
  local pwd_resolved
  pwd_resolved="$(cd "$PWD" && pwd -P)"
  case "$pwd_resolved" in
    */AltPayments/.beads*|*/AltPayments/.beads/*)
      echo "refusing to run inside real AltPayments .beads tree: $pwd_resolved" >&2
      exit 2
      ;;
  esac
  # The script under test resolves PROJECT_ROOT relative to itself, so cwd at
  # invocation time only matters if we're inside a tree the script could
  # accidentally mutate. The real defence is in seed_workspace below, which
  # always copies scripts into a fresh mktemp -d and runs from there.
  :
}
_safety_guard

# ---------------------------------------------------------------------------
# Per-test workspace seeding. Each test gets a fresh mktemp -d that contains
# its own copy of .maestro/scripts/ and .maestro/config.yaml so the script
# resolves PROJECT_ROOT/.beads to the temp dir (never the real one).
# ---------------------------------------------------------------------------
seed_workspace() {
  local tmpd
  tmpd="$(mktemp -d)"
  mkdir -p "$tmpd/.maestro/scripts"
  cp "$PREFLIGHT_SRC" "$tmpd/.maestro/scripts/bd-preflight.sh"
  chmod +x "$tmpd/.maestro/scripts/bd-preflight.sh"
  cp "$CONFIG_SRC" "$tmpd/.maestro/config.yaml"
  printf '%s\n' "$tmpd"
}

# Hard refuse if a test would ever try to write into the real .beads/.
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

# ---------------------------------------------------------------------------
# Pinned drift recovery message — exact text emitted by bd-preflight.sh on
# exit 3. If bd-preflight.sh's message changes, this fixture must be updated
# in lockstep, and the test will fail loudly until it is.
# ---------------------------------------------------------------------------
EXPECTED_DRIFT_HEAD='✗ bd workspace prefix drift detected.'

read -r -d '' EXPECTED_DRIFT_BODY <<'EOF' || true
This usually means the workspace was set up before the stable prefix
convention was adopted. To migrate:

  1. bd rename-prefix altpay- --dry-run    # review the rename plan
  2. bd rename-prefix altpay-              # apply
  3. bd label propagate <prior_epic_id> feature:NNN   # back-fill label

See .maestro/templates/migration-runbook-template.md for the full one-time
runbook. /maestro.tasks will refuse to proceed until the prefix matches the
configured stable value.
EOF

# ---------------------------------------------------------------------------
# Test result collection
# ---------------------------------------------------------------------------
PASSED=()
FAILED=()

_pass() {
  PASSED+=("$1")
  echo "PASS: $1"
}
_fail() {
  FAILED+=("$1")
  echo "FAIL: $1 ($2)" >&2
}
_warn_skip() {
  # Counts as PASS for suite exit but flagged as WARN in output.
  PASSED+=("$1")
  echo "WARN: $1 ($2) — skipped"
}

# ---------------------------------------------------------------------------
# Branch 1: empty workspace, no .beads/ at all → exit 0, init message.
# ---------------------------------------------------------------------------
test_empty_workspace() {
  local name="test_empty_workspace"
  local tmpd
  tmpd="$(seed_workspace)"
  _assert_tmp_path "$tmpd"
  trap 'rm -rf "$tmpd"' RETURN

  local out rc
  out="$(cd "$tmpd" && bash "$tmpd/.maestro/scripts/bd-preflight.sh" 2>&1)" && rc=$? || rc=$?

  if [[ $rc -ne 0 ]]; then
    _fail "$name" "expected exit 0, got $rc; output: $out"
    return
  fi
  if ! grep -qF "bd workspace initialized with prefix altpay-" <<<"$out"; then
    _fail "$name" "expected stdout to contain 'bd workspace initialized with prefix altpay-'; got: $out"
    return
  fi
  _pass "$name"
}

# ---------------------------------------------------------------------------
# Branch 3: correct prefix → exit 0, "bd workspace OK ...".
# Note: bd init --prefix=altpay- strips the trailing hyphen (stores 'altpay'),
# which would *not* startsWith('altpay-'). We seed with altpay-001 to get a
# prefix that genuinely begins with the stable altpay- string.
# ---------------------------------------------------------------------------
test_correct_prefix() {
  local name="test_correct_prefix"
  local tmpd
  tmpd="$(seed_workspace)"
  _assert_tmp_path "$tmpd"
  trap 'rm -rf "$tmpd"' RETURN

  ( cd "$tmpd" && bd init --prefix="altpay-001" --non-interactive --skip-hooks --skip-agents -q ) >/dev/null 2>&1

  # Verify seed produced an altpay-prefixed workspace.
  local seeded_prefix
  seeded_prefix="$(cd "$tmpd" && bd config get issue_prefix 2>/dev/null | tr -d '[:space:]')"
  if [[ "$seeded_prefix" != altpay-* ]]; then
    _fail "$name" "seed step produced unexpected prefix '$seeded_prefix' (expected altpay-...)"
    return
  fi

  local out rc
  out="$(cd "$tmpd" && bash "$tmpd/.maestro/scripts/bd-preflight.sh" 2>&1)" && rc=$? || rc=$?

  if [[ $rc -ne 0 ]]; then
    _fail "$name" "expected exit 0, got $rc; output: $out"
    return
  fi
  local first_line
  first_line="$(printf '%s' "$out" | head -n1)"
  if [[ "$first_line" != "bd workspace OK"* ]]; then
    _fail "$name" "expected first stdout line to start with 'bd workspace OK'; got: $first_line"
    return
  fi
  _pass "$name"
}

# ---------------------------------------------------------------------------
# Branch 4: drifted prefix (bd_058) → exit 3 + literal recovery message.
# ---------------------------------------------------------------------------
test_drift() {
  local name="test_drift"
  local tmpd
  tmpd="$(seed_workspace)"
  _assert_tmp_path "$tmpd"
  trap 'rm -rf "$tmpd"' RETURN

  ( cd "$tmpd" && bd init --prefix="bd_058" --non-interactive --skip-hooks --skip-agents -q ) >/dev/null 2>&1

  local out rc
  out="$(cd "$tmpd" && bash "$tmpd/.maestro/scripts/bd-preflight.sh" 2>&1)" && rc=$? || rc=$?

  if [[ $rc -ne 3 ]]; then
    _fail "$name" "expected exit 3, got $rc; output: $out"
    return
  fi

  local first_line
  first_line="$(printf '%s' "$out" | head -n1)"
  if [[ "$first_line" != "$EXPECTED_DRIFT_HEAD" ]]; then
    _fail "$name" "expected first stdout line '$EXPECTED_DRIFT_HEAD'; got: $first_line"
    return
  fi

  # Pin the multi-line recovery body exactly via grep -F (literal substring).
  if ! grep -qF -- "$EXPECTED_DRIFT_BODY" <<<"$out"; then
    _fail "$name" "drift recovery body did not match pinned fixture"
    {
      echo "--- expected body (literal) ---"
      printf '%s\n' "$EXPECTED_DRIFT_BODY"
      echo "--- actual stdout ---"
      printf '%s\n' "$out"
      echo "--- end ---"
    } >&2
    return
  fi

  # Drift message must echo the actual current and expected prefixes.
  if ! grep -qF "Current:   bd_058" <<<"$out"; then
    _fail "$name" "drift message missing 'Current:   bd_058' line"
    return
  fi
  if ! grep -qF "Expected:  altpay-" <<<"$out"; then
    _fail "$name" "drift message missing 'Expected:  altpay-' line"
    return
  fi

  _pass "$name"
}

# ---------------------------------------------------------------------------
# Branch 5: empty issue_prefix on populated workspace → exit 4 + bootstrap
# recovery path. bd 1.0.3 refuses `bd config set issue_prefix ""`, so this
# state cannot be produced by a real bd init/bootstrap sequence; we install
# a PATH-shim that returns empty for `bd config get issue_prefix` and a
# plausible non-empty `bd list --all`. The shim also stubs the early
# `bd bootstrap --dry-run` call so it returns nothing (no needs_bootstrap).
# ---------------------------------------------------------------------------
test_missing_prefix_populated() {
  local name="test_missing_prefix_populated"
  local tmpd
  tmpd="$(seed_workspace)"
  _assert_tmp_path "$tmpd"
  trap 'rm -rf "$tmpd"' RETURN

  # Seed a populated .beads/ — has_embedded_db must return true so the script
  # falls through to the issue_prefix inspection branch (not branch 1).
  mkdir -p "$tmpd/.beads/embeddeddolt"
  # Touch issues.jsonl too, in a parallel-safe way (real bd creates this).
  : >"$tmpd/.beads/issues.jsonl"

  # Build a bd shim that:
  #   - returns "" for `bd config get issue_prefix`
  #   - returns a list with one issue line for `bd list --all`
  #   - returns nothing for `bd bootstrap --dry-run` (no needs_bootstrap)
  #   - exits 0 for everything else (best-effort)
  local shim_dir="$tmpd/shim"
  mkdir -p "$shim_dir"
  cat >"$shim_dir/bd" <<'SHIM'
#!/usr/bin/env bash
# Test shim for bd CLI. Implements only the subset bd-preflight.sh needs.
case "$1 $2 $3" in
  "config get issue_prefix")
    # Empty prefix — what we want to simulate.
    printf ''
    exit 0
    ;;
esac
case "$1 $2" in
  "bootstrap --dry-run")
    # Print nothing — script's grep for "^bootstrap plan:" finds no match,
    # so needs_bootstrap stays 0.
    exit 0
    ;;
  "list --all")
    # Issue lines must start with [a-zA-Z] to be counted by the script's
    # `grep -cE '^[a-zA-Z]'`.
    cat <<EOF
altpay-001-aaa  open  test issue
Total: 1 issues (1 open, 0 in progress)
EOF
    exit 0
    ;;
esac
# Default — no-op success.
exit 0
SHIM
  chmod +x "$shim_dir/bd"

  local out rc
  out="$(cd "$tmpd" && PATH="$shim_dir:/usr/bin:/bin" bash "$tmpd/.maestro/scripts/bd-preflight.sh" 2>&1)" && rc=$? || rc=$?

  if [[ $rc -ne 4 ]]; then
    _fail "$name" "expected exit 4, got $rc; output: $out"
    return
  fi
  if ! grep -qF "Recovery: bd bootstrap --yes" <<<"$out"; then
    _fail "$name" "expected stdout to point recovery at 'bd bootstrap --yes'; got: $out"
    return
  fi
  if ! grep -qF "✗ bd workspace has issues but no configured issue_prefix." <<<"$out"; then
    _fail "$name" "expected stdout to contain the missing-prefix-populated header"
    return
  fi
  _pass "$name"
}

# ---------------------------------------------------------------------------
# Branch 6 (in script): bd CLI not found on PATH → exit 2.
# ---------------------------------------------------------------------------
test_bd_not_on_path() {
  local name="test_bd_not_on_path"
  local tmpd
  tmpd="$(seed_workspace)"
  _assert_tmp_path "$tmpd"
  trap 'rm -rf "$tmpd"' RETURN

  # An empty PATH directory — bd is definitely not in there.
  local empty_dir="$tmpd/empty-bin"
  mkdir -p "$empty_dir"

  local out rc
  # Use a PATH that has standard utilities (so bash builtins/grep/awk work)
  # but not /opt/homebrew/bin or /usr/local/bin where bd typically lives.
  # We set PATH to /usr/bin:/bin only and additionally guard by sticking the
  # empty_dir in front. On the off chance a system has bd in /usr/bin (rare),
  # we'd still see it — but on a developer macOS laptop bd is in
  # /opt/homebrew/bin or /usr/local/bin, neither of which is on this PATH.
  out="$(cd "$tmpd" && PATH="$empty_dir:/usr/bin:/bin" bash "$tmpd/.maestro/scripts/bd-preflight.sh" 2>&1)" && rc=$? || rc=$?

  if [[ $rc -ne 2 ]]; then
    _fail "$name" "expected exit 2, got $rc; output: $out"
    return
  fi
  if ! grep -qF "bd CLI not found" <<<"$out"; then
    _fail "$name" "expected stderr to contain 'bd CLI not found'; got: $out"
    return
  fi
  _pass "$name"
}

# ---------------------------------------------------------------------------
# Suite runner
# ---------------------------------------------------------------------------
run_all() {
  test_empty_workspace
  test_correct_prefix
  test_drift
  test_missing_prefix_populated
  test_bd_not_on_path

  local total=$(( ${#PASSED[@]} + ${#FAILED[@]} ))
  if [[ ${#FAILED[@]} -eq 0 ]]; then
    echo "${#PASSED[@]}/$total tests passed"
    exit 0
  else
    local failed_csv=""
    local f
    for f in "${FAILED[@]}"; do
      failed_csv+="${failed_csv:+, }$f"
    done
    echo "${#PASSED[@]}/$total tests passed (failed: $failed_csv)"
    echo "failing tests: $failed_csv" >&2
    exit 1
  fi
}

# Only run when invoked as a script. Sourcing is a no-op.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_all
fi
