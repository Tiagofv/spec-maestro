#!/usr/bin/env bash
# Run compile gate based on stack from config.yaml
# Usage:
#   compile-gate.sh [worktree-path]              (legacy: positional worktree)
#   compile-gate.sh --repo <name> [worktree]     (062: dirname-keyed lookup)
#   compile-gate.sh                              (auto-derive repo name from MAESTRO_BASE)
# Exit 0 = pass, exit 1 = fail

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing — accept --repo flag plus optional positional worktree.
# ---------------------------------------------------------------------------
REPO_NAME=""
REPO_FLAG_USED=false
WORKTREE=""

while (( "$#" )); do
  case "$1" in
    --repo)
      if [[ $# -lt 2 ]]; then
        echo "FAIL: --repo requires an argument" >&2
        exit 1
      fi
      REPO_NAME="$2"
      REPO_FLAG_USED=true
      shift 2
      ;;
    --repo=*)
      REPO_NAME="${1#--repo=}"
      REPO_FLAG_USED=true
      shift
      ;;
    -h|--help)
      sed -n '2,5p' "$0" >&2
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "FAIL: unknown flag: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "$WORKTREE" ]]; then
        WORKTREE="$1"
      else
        echo "FAIL: unexpected extra argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

WORKTREE="${WORKTREE:-.}"
CONFIG=".maestro/config.yaml"

echo "=== Compile Gate: $WORKTREE ===" >&2

cd "$WORKTREE" || { echo "FAIL: Cannot cd to $WORKTREE" >&2; exit 1; }

# Parse stack from config
if [[ ! -f "$CONFIG" ]]; then
  echo "FAIL: Config not found at $CONFIG" >&2
  exit 1
fi

# Extract value from compile_gate block (avoid yq dependency)
get_compile_gate_value() {
  local key="$1"
  awk -v key="$key" '
    BEGIN { in_compile_gate=0 }
    /^compile_gate:[[:space:]]*$/ { in_compile_gate=1; next }
    in_compile_gate && /^[^[:space:]]/ { in_compile_gate=0 }
    in_compile_gate && $0 ~ "^[[:space:]]+" key ":[[:space:]]*" {
      line=$0
      sub("^[[:space:]]+" key ":[[:space:]]*", "", line)
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line ~ /^".*"$/) {
        sub(/^"/, "", line)
        sub(/"$/, "", line)
      }
      print line
      exit
    }
  ' "$CONFIG"
}

# Extract stacks list from compile_gate block
get_stacks_list() {
  awk '
    BEGIN { in_compile_gate=0; in_stacks=0 }
    /^compile_gate:[[:space:]]*$/ { in_compile_gate=1; next }
    in_compile_gate && /^[^[:space:]]/ { in_compile_gate=0; in_stacks=0 }
    in_compile_gate && /^[[:space:]]+stacks:[[:space:]]*$/ { in_stacks=1; next }
    in_stacks && /^[[:space:]]+-[[:space:]]+/ {
      line=$0
      sub(/^[[:space:]]+-[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      print line
      next
    }
    in_stacks && /^[[:space:]]+[^-]/ { in_stacks=0 }
  ' "$CONFIG"
}

# Extract the compile_gate.repos map as "key<TAB>value" lines.
# Handles:
#   - Plain keys:           spec-maestro: go,ts
#   - Quoted (glob) keys:   "svc-*": go
#   - Inline values (after the colon).
#   - Strips inline `# ...` comments and surrounding whitespace.
# Skips comment-only lines and blank lines.
get_repos_map() {
  awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    BEGIN { in_compile_gate=0; in_repos=0; repos_indent=-1 }
    /^compile_gate:[[:space:]]*$/ { in_compile_gate=1; in_repos=0; next }
    in_compile_gate && /^[^[:space:]]/ { in_compile_gate=0; in_repos=0 }
    in_compile_gate && /^[[:space:]]+repos:[[:space:]]*$/ {
      in_repos=1
      # Capture the indent of `repos:` so we can detect siblings.
      match($0, /^[[:space:]]+/)
      repos_indent=RLENGTH
      next
    }
    in_repos {
      # Compute current line indent (or -1 for blank lines).
      cur_indent=-1
      if (match($0, /^[[:space:]]+[^[:space:]]/)) {
        cur_indent=RLENGTH-1
      } else if ($0 ~ /^[^[:space:]]/) {
        cur_indent=0
      }
      # Sibling key (same/lower indent than `repos:`) ends the block.
      if (cur_indent != -1 && cur_indent <= repos_indent) {
        in_repos=0
        next
      }
      # Strip inline comments only when not inside quotes (best-effort: keys
      # in this map are either plain identifiers or quoted globs, neither of
      # which contains a literal `#`, so a simple split works).
      line=$0
      # Remove inline comment starting with `#` preceded by whitespace.
      if (match(line, /[[:space:]]+#.*$/)) {
        line=substr(line, 1, RSTART-1)
      }
      # Trim trailing/leading whitespace.
      line=trim(line)
      if (line == "" ) next
      if (line ~ /^#/) next
      # Match `key: value` where key may be "quoted" or bare.
      if (match(line, /^"[^"]+"[[:space:]]*:/)) {
        keylen=RLENGTH
        key=substr(line, 2, RSTART+keylen-2-RSTART-1)  # strip surrounding quotes
        # Simpler: extract via gensub-like manual ops.
        key=line
        sub(/^"/, "", key)
        # Remove from first `":` onward, but key has the closing quote.
        match(key, /"[[:space:]]*:/)
        key=substr(key, 1, RSTART-1)
        rest=line
        sub(/^"[^"]+"[[:space:]]*:[[:space:]]*/, "", rest)
        value=trim(rest)
      } else if (match(line, /^[A-Za-z0-9_.\/-]+[[:space:]]*:/)) {
        keylen=RLENGTH
        key=substr(line, 1, keylen)
        sub(/[[:space:]]*:$/, "", key)
        rest=line
        sub(/^[A-Za-z0-9_.\/-]+[[:space:]]*:[[:space:]]*/, "", rest)
        value=trim(rest)
      } else {
        next
      }
      # Strip optional surrounding quotes around the value.
      if (value ~ /^".*"$/) {
        sub(/^"/, "", value); sub(/"$/, "", value)
      } else if (value ~ /^'\''.*'\''$/) {
        sub(/^'\''/, "", value); sub(/'\''$/, "", value)
      }
      printf "%s\t%s\n", key, value
    }
  ' "$CONFIG"
}

# Look up a repo name in compile_gate.repos. Tries literal key match first,
# then glob match against keys (so "svc-*" matches "svc-foo"). Prints the
# matched value (comma-separated stack list) on stdout if found, exit 0;
# prints nothing and exits nonzero otherwise.
lookup_repo_stacks() {
  local name="$1"
  local map
  map="$(get_repos_map)"
  if [[ -z "$map" ]]; then
    return 1
  fi

  # First pass: literal match.
  local line key value
  while IFS=$'\t' read -r key value; do
    [[ -z "$key" ]] && continue
    if [[ "$key" == "$name" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  done <<< "$map"

  # Second pass: glob match (use bash pattern matching).
  while IFS=$'\t' read -r key value; do
    [[ -z "$key" ]] && continue
    # Only treat keys containing wildcard characters as globs to avoid
    # accidental matches on plain keys we already tried literally.
    case "$key" in
      *'*'*|*'?'*|*'['*)
        # shellcheck disable=SC2053
        if [[ "$name" == $key ]]; then
          printf '%s\n' "$value"
          return 0
        fi
        ;;
    esac
  done <<< "$map"

  return 1
}

# Run a single stack's gate command, given its name. Returns 0 on pass.
run_stack_gate() {
  local stack="$1"
  # Normalize common aliases so the repos map can use friendlier names.
  local lookup="$stack"
  case "$lookup" in
    ts|typescript) lookup="node" ;;
  esac
  local cmd
  cmd="$(get_compile_gate_value "$lookup")"
  if [[ -z "$cmd" ]]; then
    # Try the original spelling too, in case the user defined it directly.
    cmd="$(get_compile_gate_value "$stack")"
  fi
  if [[ -z "$cmd" ]]; then
    echo "WARN: No command for stack: $stack" >&2
    return 1
  fi
  echo "=== Running stack: $stack ===" >&2
  echo "Running: $cmd" >&2
  # Run in a subshell so any `cd` inside the gate command does not leak into
  # subsequent stack invocations (the existing go gate cd's into cmd/maestro-cli).
  if ( eval "$cmd" ) 2>&1; then
    echo "=== Stack: $stack PASSED ===" >&2
    return 0
  else
    echo "=== Stack: $stack FAILED ===" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 062 path: compile_gate.repos lookup. Active when the map exists in config.
# ---------------------------------------------------------------------------
REPOS_MAP="$(get_repos_map || true)"
if [[ -n "$REPOS_MAP" ]]; then
  # If --repo not supplied, auto-derive from basename(MAESTRO_BASE).
  if [[ "$REPO_FLAG_USED" != "true" && -z "$REPO_NAME" ]]; then
    # Source worktree-detect.sh to get MAESTRO_BASE. Tolerate failure (e.g.
    # when run outside a recognized maestro install) by leaving REPO_NAME
    # empty and falling through to the named error below.
    SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$SCRIPT_DIR/worktree-detect.sh" ]]; then
      # shellcheck source=/dev/null
      # `set -e` would abort on any non-zero from the sourced script; allow it.
      set +e
      # shellcheck disable=SC1090
      source "$SCRIPT_DIR/worktree-detect.sh" >/dev/null 2>&1
      set -e
      if [[ -n "${MAESTRO_BASE:-}" ]]; then
        REPO_NAME="$(basename "$MAESTRO_BASE")"
        echo "=== Auto-derived repo name from MAESTRO_BASE: $REPO_NAME ===" >&2
      fi
    fi
  fi

  if [[ -z "$REPO_NAME" ]]; then
    echo "compile-gate: could not determine repo name — pass --repo <name> explicitly, or ensure worktree-detect.sh is accessible" >&2
    exit 1
  fi

  STACK_CSV=""
  if STACK_CSV="$(lookup_repo_stacks "$REPO_NAME")"; then
    :
  else
    echo "compile-gate: no entry in compile_gate.repos matches repo \"$REPO_NAME\" (literal or glob); refusing to guess" >&2
    exit 1
  fi

  echo "=== Repo \"$REPO_NAME\" -> stacks: $STACK_CSV ===" >&2

  overall_pass=true
  IFS=',' read -r -a stacks_arr <<< "$STACK_CSV"
  for stack_name in "${stacks_arr[@]}"; do
    # Strip whitespace.
    stack_name="${stack_name#"${stack_name%%[![:space:]]*}"}"
    stack_name="${stack_name%"${stack_name##*[![:space:]]}"}"
    [[ -z "$stack_name" ]] && continue
    if ! run_stack_gate "$stack_name"; then
      overall_pass=false
    fi
  done

  if [[ "$overall_pass" == "true" ]]; then
    echo "=== All stacks PASSED ===" >&2
    exit 0
  else
    echo "=== One or more stacks FAILED ===" >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Legacy path: compile_gate.repos absent → use stacks list or single stack.
# Preserves pre-062 behavior verbatim.
# ---------------------------------------------------------------------------
if [[ "$REPO_FLAG_USED" == "true" ]]; then
  echo "compile-gate: --repo \"$REPO_NAME\" supplied but compile_gate.repos is missing/empty in $CONFIG; refusing to guess" >&2
  exit 1
fi

# Try stacks list first
STACKS_LIST=$(get_stacks_list)

if [[ -n "$STACKS_LIST" ]]; then
  # Multi-stack mode
  overall_pass=true
  while IFS= read -r stack_name; do
    [[ -z "$stack_name" ]] && continue
    CMD=$(get_compile_gate_value "$stack_name")
    if [[ -z "$CMD" ]]; then
      echo "WARN: No command for stack: $stack_name" >&2
      continue
    fi
    echo "=== Running stack: $stack_name ===" >&2
    if eval "$CMD" 2>&1; then
      echo "=== Stack: $stack_name PASSED ===" >&2
    else
      echo "=== Stack: $stack_name FAILED ===" >&2
      overall_pass=false
    fi
  done <<< "$STACKS_LIST"

  if [[ "$overall_pass" == "true" ]]; then
    echo "=== All stacks PASSED ===" >&2
    exit 0
  else
    echo "=== One or more stacks FAILED ===" >&2
    exit 1
  fi
else
  # Single-stack fallback (existing behavior)
  STACK=$(get_compile_gate_value "stack" | tr -d "'")

  if [[ -z "$STACK" ]]; then
    echo "FAIL: No stack defined in config.yaml" >&2
    exit 1
  fi

  # Get command for this stack
  CMD=$(get_compile_gate_value "$STACK")

  if [[ -z "$CMD" ]]; then
    echo "FAIL: No compile_gate command for stack: $STACK" >&2
    exit 1
  fi

  echo "Running: $CMD" >&2
  if eval "$CMD" 2>&1; then
    echo "=== Compile gate PASSED ===" >&2
    exit 0
  else
    echo "=== Compile gate FAILED ===" >&2
    echo "Fix the errors above and re-run." >&2
    exit 1
  fi
fi
