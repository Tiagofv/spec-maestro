#!/usr/bin/env bash
# Helper functions for bd operations
# Source this file: source .maestro/scripts/bd-helpers.sh

# =============================================================================
# FORBIDDEN COMMANDS
# =============================================================================
# Never call any of these from this file or from any maestro command:
#
#   bd init --force            (deprecated alias for --reinit-local; bypasses
#                               local data-safety guard)
#   bd init --reinit-local     (re-initializes the local .beads/, can lose
#                               prior features' issues if the prefix changes)
#   bd init --discard-remote   (authorizes discarding configured remote's Dolt
#                               history; the most destructive option)
#
# Reason: each can silently destroy issues from prior features when the
# workspace already has data. Use bd-preflight.sh for setup/recovery — it uses
# bd bootstrap (non-destructive) and refuses to proceed on prefix drift.
#
# Entry point for setup/recovery:
#   bash "$(dirname "${BASH_SOURCE[0]}")/bd-preflight.sh"
# =============================================================================

set -euo pipefail

# Calling pattern: EPIC_ID=$(fn ...) — functions exit non-zero on failure, never return empty string.

command -v jq >/dev/null 2>&1 || { echo "bd-helpers.sh: jq not found; install via 'brew install jq' or 'apt-get install jq'" >&2; exit 1; }

# Check if bd is available
bd_check() {
  if ! command -v bd &>/dev/null; then
    echo "{\"error\":\"bd CLI not found\"}" >&2
    return 1
  fi
  return 0
}

# Run bd workspace pre-flight check.
# Exits 0 when the workspace is in a known-safe state.
# Exits non-zero with a named recovery path on drift / setup gaps.
# Usage: bd_preflight || { echo "preflight failed; see message above"; exit $?; }
bd_preflight() {
  bash "$(dirname "${BASH_SOURCE[0]}")/bd-preflight.sh"
}

# Create epic and return ID
# Usage: bd_create_epic "Title" "Description"
bd_create_epic() {
  local title="$1"
  local desc="${2:-}"
  local bd_output bd_stderr bd_exit
  local bd_stderr_file
  bd_stderr_file=$(mktemp)
  # Capture stdout and stderr separately; use || to capture non-zero exit without set -e aborting.
  bd_output=$(bd create --title="$title" --type=epic --priority=2 ${desc:+--description="$desc"} --json 2>"$bd_stderr_file") && bd_exit=0 || bd_exit=$?
  bd_stderr=$(cat "$bd_stderr_file")
  rm -f "$bd_stderr_file"
  # Surface any bd warning/diagnostic output even on success.
  if [[ -n "$bd_stderr" ]]; then
    printf '%s\n' "$bd_stderr" >&2
  fi
  if [[ $bd_exit -ne 0 ]]; then
    echo "bd create failed: $bd_stderr" >&2
    return $bd_exit
  fi
  local id
  id=$(printf '%s' "$bd_output" | jq -r '.id // empty')
  if [[ -z "$id" ]]; then
    echo "bd create succeeded but ID could not be parsed from output: ${bd_output:0:200}" >&2
    return 1
  fi
  printf '%s\n' "$id"
}

# Create task under epic
# Usage: bd_create_task "Title" "Description" "label" estimate_minutes epic_id assignee
bd_create_task() {
  local title="$1"
  local desc="$2"
  local label="$3"
  local estimate="$4"
  local epic_id="$5"
  local assignee="${6:-general}"
  local bd_output bd_stderr bd_exit
  local bd_stderr_file
  bd_stderr_file=$(mktemp)
  # Capture stdout and stderr separately; use || to capture non-zero exit without set -e aborting.
  bd_output=$(bd create \
    --title="$title" \
    --type=task \
    --priority=2 \
    --labels="$label" \
    --estimate="$estimate" \
    --assignee="$assignee" \
    --description="$desc" \
    --parent="$epic_id" \
    --json 2>"$bd_stderr_file") && bd_exit=0 || bd_exit=$?
  bd_stderr=$(cat "$bd_stderr_file")
  rm -f "$bd_stderr_file"
  # Surface any bd warning/diagnostic output even on success.
  if [[ -n "$bd_stderr" ]]; then
    printf '%s\n' "$bd_stderr" >&2
  fi
  if [[ $bd_exit -ne 0 ]]; then
    echo "bd create failed: $bd_stderr" >&2
    return $bd_exit
  fi
  local id
  id=$(printf '%s' "$bd_output" | jq -r '.id // empty')
  if [[ -z "$id" ]]; then
    echo "bd create succeeded but ID could not be parsed from output: ${bd_output:0:200}" >&2
    return 1
  fi
  printf '%s\n' "$id"
}

# Add dependency between tasks
# Usage: bd_add_dep dependent_id blocker_id
bd_add_dep() {
  local dependent="$1"
  local blocker="$2"
  local dep_stderr_file dep_exit=0
  dep_stderr_file=$(mktemp)
  bd dep add "$dependent" "$blocker" 2>"$dep_stderr_file" || dep_exit=$?
  if [[ $dep_exit -ne 0 ]]; then
    local stderr_content
    stderr_content=$(cat "$dep_stderr_file")
    rm -f "$dep_stderr_file"
    # Duplicate edge is idempotent — not an error
    if echo "$stderr_content" | grep -qi "already exists\|duplicate"; then
      return 0
    fi
    echo "bd dep add failed: $stderr_content" >&2
    return $dep_exit
  fi
  rm -f "$dep_stderr_file"
  return 0
}

# Get ready tasks as JSON
bd_ready_json() {
  bd ready --json 2>/dev/null || echo "[]"
}

# Apply a feature:NNN label to an epic and propagate it to all children.
# Idempotent: bd label propagate skips children that already have the label.
# Usage: bd_apply_feature_label "$EPIC_ID" "061"
bd_apply_feature_label() {
  local epic_id="$1"
  local feature_num="$2"
  bd label propagate "$epic_id" "feature:$feature_num" 2>/dev/null || true
}

# Close task with structured reason
# Usage: bd_close task_id "VERDICT | key: value"
bd_close() {
  local task_id="$1"
  local reason="$2"
  bd close "$task_id" --reason "$reason" 2>/dev/null
}

# =============================================================================
# State-file readers (feature 062 — multi-repo support)
# =============================================================================
# Implements the reader contract documented in
#   .maestro/specs/062-improve-maestro-support-multi-repo/data-model.md §4.1
#
# State files at .maestro/state/{feature_id}.json may exist in two shapes:
#
#   1. NEW shape (post-062):
#        { "worktrees": { "<repo>": { "path", "branch", "created" }, ... } }
#
#   2. LEGACY shape (pre-062, single-repo only):
#        { "worktree_path": "...", "worktree_branch": "...",
#          "worktree_created": <bool>, "worktree_name": "..." }
#
# Readers MUST tolerate both shapes (§4.3 of data-model.md) until the lazy
# rewrite drains the in-flight feature set. Writers always emit the new shape
# (§4.2) — handled in a sibling task, not here.
# =============================================================================

# Source worktree-detect.sh once if MAESTRO_BASE is not already exported.
# The legacy-shape reader needs MAESTRO_BASE to synthesize a default repo key.
if [[ -z "${MAESTRO_BASE:-}" ]]; then
  # shellcheck source=worktree-detect.sh
  source "$(dirname "${BASH_SOURCE[0]}")/worktree-detect.sh" || true
fi

# _legacy_repo_key <state_file_path>
# Returns the default repo key for synthesizing a legacy-shape worktrees map.
# Order of preference per data-model.md §4.1:
#   1. state.legacy_repo (if present in the file — set during one-time
#      annotations).
#   2. basename(MAESTRO_BASE) — the project the user is working in.
#   3. "default" — last-resort fallback when MAESTRO_BASE is unset.
_legacy_repo_key() {
  local state_file="$1"
  local legacy_repo

  if [[ -f "$state_file" ]]; then
    legacy_repo="$(jq -r '.legacy_repo // empty' "$state_file" 2>/dev/null || echo "")"
    if [[ -n "$legacy_repo" ]]; then
      printf '%s' "$legacy_repo"
      return 0
    fi
  fi

  if [[ -n "${MAESTRO_BASE:-}" ]]; then
    printf '%s' "$(basename "$MAESTRO_BASE")"
    return 0
  fi

  printf '%s' "default"
}

# read_state_worktrees <state_file_path>
# Prints the worktrees map as JSON to stdout. Tolerates legacy flat-triplet
# shape per data-model.md §4.1.
#
# Cases:
#   - NEW shape (state.worktrees present)       → return verbatim
#   - LEGACY shape (worktree_path + _branch)    → synthesize one-entry map
#   - Neither shape                              → return {} + warn on stderr
#
# Exits 2 (loudly) if jq is unavailable.
read_state_worktrees() {
  local state_file="$1"

  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR[read_state_worktrees]: jq not found in PATH; cannot parse state file" >&2
    return 2
  fi

  if [[ -z "$state_file" ]]; then
    echo "WARN[read_state_worktrees]: empty state_file argument; returning {}" >&2
    printf '{}'
    return 0
  fi

  if [[ ! -f "$state_file" ]]; then
    echo "WARN[read_state_worktrees]: state file not found: $state_file; returning {}" >&2
    printf '{}'
    return 0
  fi

  # Case 1: NEW shape — return state.worktrees verbatim if it's an object.
  local has_new_shape
  has_new_shape="$(jq -r 'if (.worktrees // null) | type == "object" then "yes" else "no" end' "$state_file" 2>/dev/null || echo "no")"
  if [[ "$has_new_shape" == "yes" ]]; then
    jq -c '.worktrees' "$state_file"
    return 0
  fi

  # Case 2: LEGACY shape — both worktree_path and worktree_branch must exist
  # as non-null strings. worktree_created defaults to false.
  local has_legacy_shape
  has_legacy_shape="$(jq -r '
    if ((.worktree_path // null) != null) and ((.worktree_branch // null) != null)
    then "yes" else "no" end
  ' "$state_file" 2>/dev/null || echo "no")"

  if [[ "$has_legacy_shape" == "yes" ]]; then
    local repo_key
    repo_key="$(_legacy_repo_key "$state_file")"
    jq -c --arg key "$repo_key" '
      {
        ($key): {
          path:    .worktree_path,
          branch:  .worktree_branch,
          created: (.worktree_created // false),
        }
      }
    ' "$state_file"
    return 0
  fi

  # Case 3: Neither shape present.
  echo "WARN[read_state_worktrees]: no worktrees map and no legacy worktree_* fields in $state_file; returning {}" >&2
  printf '{}'
  return 0
}

# =============================================================================
# Inline unit tests for the state-file readers above.
# Invocation:
#     bash .maestro/scripts/bd-helpers.sh test-readers
# Tests are intentionally minimal — they cover the three contract branches.
# =============================================================================

_test_read_state_worktrees() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  local pass=0 fail=0

  _assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
      echo "PASS: $label"
      pass=$((pass + 1))
    else
      echo "FAIL: $label"
      echo "  expected: $expected"
      echo "  actual:   $actual"
      fail=$((fail + 1))
    fi
  }

  # ---- Case 1: NEW shape — verbatim passthrough ----------------------------
  local new_file="$tmpdir/new.json"
  cat >"$new_file" <<'JSON'
{
  "feature_id": "test-new",
  "stage": "implement",
  "worktrees": {
    "spec-maestro": {
      "path": "/tmp/wt-a",
      "branch": "feat/x",
      "created": true
    }
  }
}
JSON
  local got_new expected_new
  got_new="$(read_state_worktrees "$new_file")"
  expected_new='{"spec-maestro":{"path":"/tmp/wt-a","branch":"feat/x","created":true}}'
  _assert_eq "new-shape returns worktrees verbatim" "$expected_new" "$got_new"

  # ---- Case 2: LEGACY shape — synthesized one-entry map --------------------
  local legacy_file="$tmpdir/legacy.json"
  cat >"$legacy_file" <<'JSON'
{
  "feature_id": "test-legacy",
  "stage": "tasks",
  "worktree_name": "test-legacy",
  "worktree_path": "/tmp/wt-legacy",
  "worktree_branch": "feat/legacy",
  "worktree_created": false
}
JSON
  # The default key is basename(MAESTRO_BASE) when legacy_repo is absent.
  local expected_key
  if [[ -n "${MAESTRO_BASE:-}" ]]; then
    expected_key="$(basename "$MAESTRO_BASE")"
  else
    expected_key="default"
  fi
  local got_legacy expected_legacy
  got_legacy="$(read_state_worktrees "$legacy_file")"
  expected_legacy="$(jq -cn --arg k "$expected_key" \
    '{($k): {path:"/tmp/wt-legacy", branch:"feat/legacy", created:false}}')"
  _assert_eq "legacy-shape synthesizes one-entry map keyed by basename(MAESTRO_BASE)" \
    "$expected_legacy" "$got_legacy"

  # Sub-case 2b: state.legacy_repo overrides the basename default.
  local legacy_anno_file="$tmpdir/legacy-anno.json"
  cat >"$legacy_anno_file" <<'JSON'
{
  "feature_id": "test-legacy-anno",
  "legacy_repo": "explicit-repo",
  "worktree_path": "/tmp/wt-anno",
  "worktree_branch": "feat/anno",
  "worktree_created": true
}
JSON
  local got_anno expected_anno
  got_anno="$(read_state_worktrees "$legacy_anno_file")"
  expected_anno='{"explicit-repo":{"path":"/tmp/wt-anno","branch":"feat/anno","created":true}}'
  _assert_eq "legacy-shape with state.legacy_repo uses that key" \
    "$expected_anno" "$got_anno"

  # ---- Case 3: NEITHER shape — empty map + warning -------------------------
  local empty_file="$tmpdir/empty.json"
  cat >"$empty_file" <<'JSON'
{
  "feature_id": "test-empty",
  "stage": "specify"
}
JSON
  local got_empty stderr_capture
  # Capture stderr to confirm the warning fires; stdout should be "{}".
  stderr_capture="$(read_state_worktrees "$empty_file" 2>&1 1>/dev/null || true)"
  got_empty="$(read_state_worktrees "$empty_file" 2>/dev/null)"
  _assert_eq "neither-shape returns empty map" "{}" "$got_empty"
  if [[ "$stderr_capture" == *"no worktrees map"* ]]; then
    echo "PASS: neither-shape prints warning to stderr"
    pass=$((pass + 1))
  else
    echo "FAIL: neither-shape prints warning to stderr"
    echo "  stderr was: $stderr_capture"
    fail=$((fail + 1))
  fi

  echo ""
  echo "_test_read_state_worktrees: $pass passed, $fail failed"
  if (( fail > 0 )); then
    return 1
  fi
  return 0
}

# =============================================================================
# State-file writer (feature 062 — multi-repo support)
# =============================================================================
# Implements the writer contract from
#   .maestro/specs/062-improve-maestro-support-multi-repo/data-model.md §4.2
#
# Any code writing state MUST emit the new shape:
#   1. If the in-memory state has worktree_path/worktree_branch/
#      worktree_created/worktree_name flat fields, fold them into a
#      `worktrees` map first (keyed by `_legacy_repo_key`).
#   2. Drop the flat fields from the dict before serializing.
#   3. Compute and write `repos` as Object.keys(worktrees) if it isn't
#      already present.
#   4. Serialize atomically (tmp file + mv).
#
# Idempotent: a state object already in the new shape round-trips unchanged
# (modulo `repos` normalization and an `updated_at` stamp).
# =============================================================================

# write_state_worktrees <state_file_path> <state_json>
# Always writes the new-shape state file: folds legacy flat-triplet keys into
# the worktrees map, drops the flat keys, ensures repos[] mirrors
# Object.keys(worktrees), and serializes atomically. Implements
# data-model.md §4.2 writer contract (feature 062).
write_state_worktrees() {
  local state_file="$1"
  local state_json="$2"

  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR[write_state_worktrees]: jq not found in PATH; cannot serialize state file" >&2
    return 2
  fi

  if [[ -z "$state_file" ]]; then
    echo "ERROR[write_state_worktrees]: empty state_file argument" >&2
    return 2
  fi

  if [[ -z "$state_json" ]]; then
    echo "ERROR[write_state_worktrees]: empty state_json argument" >&2
    return 2
  fi

  # Resolve the legacy repo key for the fold step. Pass the existing on-disk
  # file (if any) so that an existing `legacy_repo` annotation is honored —
  # this matches `read_state_worktrees`. If the on-disk file is absent, the
  # helper falls back to basename(MAESTRO_BASE) or "default".
  local repo_key
  repo_key="$(_legacy_repo_key "$state_file")"

  # Updated_at stamp is part of every state mutation.
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Build the new-shape JSON in one jq pipeline:
  #   1. If `worktrees` is missing but legacy flat fields are present, build
  #      a one-entry map keyed by $repo_key.
  #   2. If `worktrees` is missing AND no legacy fields are present, default
  #      to {} (caller is responsible for filling it later — we still produce
  #      a valid new-shape envelope).
  #   3. Drop the legacy flat keys.
  #   4. Set `repos` to keys(worktrees) when absent (or when present but
  #      empty/null — but only auto-fill when missing per §4.2).
  #   5. Stamp updated_at.
  #
  # `--argjson` would require pre-parsing; passing via stdin lets jq parse it
  # and surface clear errors on malformed input.
  local new_json
  if ! new_json="$(printf '%s' "$state_json" | jq \
      --arg key "$repo_key" \
      --arg now "$now" \
      '
      . as $s
      | (
          if (.worktrees // null) | type == "object" then
            .worktrees
          elif ((.worktree_path // null) != null) and ((.worktree_branch // null) != null) then
            {
              ($key): {
                path:    .worktree_path,
                branch:  .worktree_branch,
                created: (.worktree_created // false),
              }
            }
          else
            (.worktrees // {})
          end
        ) as $wts
      | .worktrees = $wts
      | (if (.repos // null) == null then .repos = ($wts | keys) else . end)
      | del(.worktree_path, .worktree_branch, .worktree_created, .worktree_name)
      | .updated_at = $now
      ' 2>&1)"; then
    echo "ERROR[write_state_worktrees]: jq failed to transform state: $new_json" >&2
    return 2
  fi

  # Atomic write: tmp file alongside target, then mv. Avoids leaving a
  # half-written state file if any step fails.
  local target_dir tmp_file
  target_dir="$(dirname "$state_file")"
  if [[ ! -d "$target_dir" ]]; then
    mkdir -p "$target_dir"
  fi
  tmp_file="$(mktemp "${target_dir}/.$(basename "$state_file").XXXXXX")"

  if ! printf '%s\n' "$new_json" >"$tmp_file"; then
    rm -f "$tmp_file"
    echo "ERROR[write_state_worktrees]: failed to write tmp file $tmp_file" >&2
    return 2
  fi

  if ! mv "$tmp_file" "$state_file"; then
    rm -f "$tmp_file"
    echo "ERROR[write_state_worktrees]: failed to mv tmp file over $state_file" >&2
    return 2
  fi

  return 0
}

# migrate_state_worktrees_in_place <state_file_path>
# Reads the file, applies the writer contract, writes back. Idempotent:
# running this twice produces the same shape on disk (modulo updated_at).
migrate_state_worktrees_in_place() {
  local state_file="$1"

  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR[migrate_state_worktrees_in_place]: jq not found in PATH" >&2
    return 2
  fi

  if [[ -z "$state_file" ]]; then
    echo "ERROR[migrate_state_worktrees_in_place]: empty state_file argument" >&2
    return 2
  fi

  if [[ ! -f "$state_file" ]]; then
    echo "ERROR[migrate_state_worktrees_in_place]: state file not found: $state_file" >&2
    return 2
  fi

  local current_json
  current_json="$(cat "$state_file")"
  write_state_worktrees "$state_file" "$current_json"
}

# =============================================================================
# Inline unit tests for the state-file writer above.
# Invocation:
#     bash .maestro/scripts/bd-helpers.sh test-writers
#     bash .maestro/scripts/bd-helpers.sh test-all     (runs readers + writers)
# =============================================================================

_test_write_state_worktrees() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  local pass=0 fail=0

  _assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
      echo "PASS: $label"
      pass=$((pass + 1))
    else
      echo "FAIL: $label"
      echo "  expected: $expected"
      echo "  actual:   $actual"
      fail=$((fail + 1))
    fi
  }

  local expected_default_key
  if [[ -n "${MAESTRO_BASE:-}" ]]; then
    expected_default_key="$(basename "$MAESTRO_BASE")"
  else
    expected_default_key="default"
  fi

  # ---- Case 1: writing legacy state produces new-shape file ----------------
  local legacy_in='{
    "feature_id": "test-legacy-write",
    "stage": "tasks",
    "worktree_name": "test-legacy-write",
    "worktree_path": "/tmp/wt-legacy-w",
    "worktree_branch": "feat/legacy-w",
    "worktree_created": true
  }'
  local legacy_target="$tmpdir/legacy-write.json"

  if write_state_worktrees "$legacy_target" "$legacy_in" >/dev/null 2>&1; then
    # Verify no flat keys remain.
    local has_flat
    has_flat="$(jq -r '
      [
        (.worktree_path // null),
        (.worktree_branch // null),
        (.worktree_created // null),
        (.worktree_name // null)
      ] | map(. != null) | any
    ' "$legacy_target")"
    _assert_eq "legacy-input: flat keys removed from on-disk file" "false" "$has_flat"

    # Verify the worktrees map was synthesized with the right key/values.
    local got_wts expected_wts
    got_wts="$(jq -c '.worktrees' "$legacy_target")"
    expected_wts="$(jq -cn --arg k "$expected_default_key" \
      '{($k): {path:"/tmp/wt-legacy-w", branch:"feat/legacy-w", created:true}}')"
    _assert_eq "legacy-input: worktrees map synthesized via _legacy_repo_key" \
      "$expected_wts" "$got_wts"

    # Verify repos[] auto-populated from keys(worktrees).
    local got_repos expected_repos
    got_repos="$(jq -c '.repos' "$legacy_target")"
    expected_repos="$(jq -cn --arg k "$expected_default_key" '[$k]')"
    _assert_eq "legacy-input: repos[] auto-populated from Object.keys(worktrees)" \
      "$expected_repos" "$got_repos"
  else
    echo "FAIL: write_state_worktrees on legacy input returned non-zero"
    fail=$((fail + 1))
  fi

  # ---- Case 2: writing new-shape input is idempotent (read→write→read) -----
  local new_in='{
    "feature_id": "test-new-write",
    "stage": "implement",
    "repos": ["spec-maestro"],
    "worktrees": {
      "spec-maestro": {
        "path": "/tmp/wt-new-w",
        "branch": "feat/new-w",
        "created": true
      }
    }
  }'
  local new_target="$tmpdir/new-write.json"

  if write_state_worktrees "$new_target" "$new_in" >/dev/null 2>&1; then
    # First read.
    local first_wts
    first_wts="$(read_state_worktrees "$new_target" 2>/dev/null)"

    # Write back what we just read (round-trip).
    local round_in round_target
    round_in="$(cat "$new_target")"
    round_target="$tmpdir/new-write-rt.json"
    write_state_worktrees "$round_target" "$round_in" >/dev/null 2>&1

    local round_wts
    round_wts="$(read_state_worktrees "$round_target" 2>/dev/null)"

    _assert_eq "new-input: round-trip read→write→read returns same map" \
      "$first_wts" "$round_wts"
  else
    echo "FAIL: write_state_worktrees on new-shape input returned non-zero"
    fail=$((fail + 1))
  fi

  # ---- Case 3: repos auto-populated when missing on input (new-shape) -----
  local norepos_in='{
    "feature_id": "test-no-repos",
    "stage": "implement",
    "worktrees": {
      "alpha": {"path":"/tmp/a","branch":"feat/a","created":true},
      "beta":  {"path":"/tmp/b","branch":"feat/b","created":true}
    }
  }'
  local norepos_target="$tmpdir/no-repos.json"
  write_state_worktrees "$norepos_target" "$norepos_in" >/dev/null 2>&1

  local got_norepos
  got_norepos="$(jq -c '.repos | sort' "$norepos_target")"
  _assert_eq "no-repos input: repos[] auto-populated from keys(worktrees)" \
    '["alpha","beta"]' "$got_norepos"

  # ---- Case 4: round-trip via migrate_state_worktrees_in_place ------------
  local rt_file="$tmpdir/legacy-rt.json"
  cat >"$rt_file" <<'JSON'
{
  "feature_id": "test-legacy-rt",
  "stage": "tasks",
  "worktree_name": "test-legacy-rt",
  "worktree_path": "/tmp/wt-rt",
  "worktree_branch": "feat/rt",
  "worktree_created": false
}
JSON

  migrate_state_worktrees_in_place "$rt_file" >/dev/null 2>&1

  # The file should now be in new shape — verify by checking that
  # read_state_worktrees does NOT hit the legacy synth branch (i.e. .worktrees
  # is a real object on disk).
  local rt_has_new_shape
  rt_has_new_shape="$(jq -r '(.worktrees // null) | type == "object"' "$rt_file")"
  _assert_eq "in-place migration: file has new-shape worktrees object" \
    "true" "$rt_has_new_shape"

  local rt_has_flat
  rt_has_flat="$(jq -r '
    [(.worktree_path // null), (.worktree_branch // null),
     (.worktree_created // null), (.worktree_name // null)]
    | map(. != null) | any
  ' "$rt_file")"
  _assert_eq "in-place migration: legacy flat keys gone from on-disk file" \
    "false" "$rt_has_flat"

  # And read_state_worktrees should return the synthesized one-entry map.
  local rt_wts expected_rt_wts
  rt_wts="$(read_state_worktrees "$rt_file" 2>/dev/null)"
  expected_rt_wts="$(jq -cn --arg k "$expected_default_key" \
    '{($k): {path:"/tmp/wt-rt", branch:"feat/rt", created:false}}')"
  _assert_eq "in-place migration: read_state_worktrees returns synthesized map" \
    "$expected_rt_wts" "$rt_wts"

  # ---- Case 5: idempotency — running migrate twice yields same shape ------
  migrate_state_worktrees_in_place "$rt_file" >/dev/null 2>&1
  local rt_wts_2
  rt_wts_2="$(read_state_worktrees "$rt_file" 2>/dev/null)"
  _assert_eq "in-place migration: idempotent (second run yields same map)" \
    "$rt_wts" "$rt_wts_2"

  echo ""
  echo "_test_write_state_worktrees: $pass passed, $fail failed"
  if (( fail > 0 )); then
    return 1
  fi
  return 0
}

# Test dispatcher — only runs when this file is invoked directly with one of
# the recognized test arguments. Sourcing the file (the normal usage) is
# unaffected.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    test-readers)
      _test_read_state_worktrees
      exit $?
      ;;
    test-writers)
      _test_write_state_worktrees
      exit $?
      ;;
    test-all)
      _test_read_state_worktrees
      r_status=$?
      echo ""
      _test_write_state_worktrees
      w_status=$?
      if (( r_status != 0 || w_status != 0 )); then
        exit 1
      fi
      exit 0
      ;;
  esac
fi
