#!/usr/bin/env bash
# bd-preflight.sh — pre-flight check for the bd workspace before /maestro.tasks
#   creates issues. Reads bd_stable_prefix from .maestro/config.yaml and walks a
#   five-branch decision tree: init / bootstrap / OK / drift-refuse / missing-prefix-refuse.
#   On drift or missing prefix, refuses to proceed and prints a named recovery
#   path (rename-prefix or bootstrap). NEVER calls destructive bd init flags;
#   recovery is always operator-initiated. Exit codes: 0 ok, 2 fatal (missing
#   bd or config), 3 prefix drift, 4 missing prefix on populated workspace.

set -euo pipefail

# Resolve config.yaml relative to this script so it works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../config.yaml"

# Branch 6 (fatal): bd CLI not on PATH.
if ! command -v bd >/dev/null 2>&1; then
  echo "bd CLI not found" >&2
  exit 2
fi

# Branch 7 (fatal): config missing or unreadable, or stable prefix key absent.
if [[ ! -r "$CONFIG" ]]; then
  echo "bd_stable_prefix not set in .maestro/config.yaml" >&2
  exit 2
fi

STABLE=$(grep -E '^bd_stable_prefix:' "$CONFIG" | awk '{print $2}')
if [[ -z "${STABLE:-}" ]]; then
  echo "bd_stable_prefix not set in .maestro/config.yaml" >&2
  exit 2
fi

# Workspace state lives one level above .maestro (the project root).
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BEADS_DIR="$PROJECT_ROOT/.beads"

has_embedded_db() {
  [[ -d "$BEADS_DIR/embeddeddolt" ]]
}

has_jsonl() {
  [[ -f "$BEADS_DIR/issues.jsonl" ]]
}

# ---------------------------------------------------------------------------
# Branch 1: no .beads or no embedded db AND no JSONL — fresh init.
# ---------------------------------------------------------------------------
if [[ ! -d "$BEADS_DIR" ]] || (! has_embedded_db && ! has_jsonl); then
  bd init --prefix="$STABLE" --non-interactive --skip-hooks --skip-agents -q
  echo "bd workspace initialized with prefix $STABLE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Branch 2: JSONL exists but no embedded db, OR bootstrap dry-run yields a
# non-empty plan (handles the worktree-without-its-own-db case).
# ---------------------------------------------------------------------------
needs_bootstrap=0
if has_jsonl && ! has_embedded_db; then
  needs_bootstrap=1
else
  # bd bootstrap --dry-run prints "Bootstrap plan: ..." when work is required.
  # On a fully-bootstrapped workspace it returns "no bootstrap needed" or similar.
  bootstrap_plan="$(bd bootstrap --dry-run 2>/dev/null || true)"
  if echo "$bootstrap_plan" | grep -qiE '^bootstrap plan:'; then
    needs_bootstrap=1
  fi
fi

if [[ $needs_bootstrap -eq 1 ]]; then
  bd bootstrap --yes
  echo "bd workspace bootstrapped"
  exit 0
fi

# ---------------------------------------------------------------------------
# Workspace has an embedded db. Inspect issue_prefix.
# ---------------------------------------------------------------------------
CURRENT_PREFIX="$(bd config get issue_prefix 2>/dev/null | tr -d '[:space:]' || true)"

# Branch 3: prefix is set and starts with the configured stable prefix.
if [[ -n "$CURRENT_PREFIX" && "$CURRENT_PREFIX" == "$STABLE"* ]]; then
  echo "bd workspace OK (prefix=$CURRENT_PREFIX)"
  exit 0
fi

# Branch 5: prefix empty, but workspace already has issues — bootstrap recovery.
if [[ -z "$CURRENT_PREFIX" ]]; then
  issue_count="$(bd list --all 2>/dev/null | grep -cE '^[a-zA-Z]' || true)"
  if [[ "${issue_count:-0}" -ge 1 ]]; then
    cat <<EOF
✗ bd workspace has issues but no configured issue_prefix.

This typically happens when the workspace was created by an older bd that
didn't set the prefix, or by a manual \`bd dolt init\` that bypassed bd's
own setup.

  Recovery: bd bootstrap --yes

bootstrap is non-destructive — it will validate the existing workspace
and set up missing config without touching issues. /maestro.tasks will
refuse to proceed until the prefix is set.
EOF
    exit 4
  fi
  # Empty prefix and empty workspace: treat as fresh init (branch 1 fallthrough).
  bd init --prefix="$STABLE" --non-interactive --skip-hooks --skip-agents -q
  echo "bd workspace initialized with prefix $STABLE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Branch 4: prefix is set but does not match the stable prefix — drift.
# ---------------------------------------------------------------------------
cat <<EOF
✗ bd workspace prefix drift detected.
  Current:   $CURRENT_PREFIX
  Expected:  $STABLE

This usually means the workspace was set up before the stable prefix
convention was adopted. To migrate:

  1. bd rename-prefix $STABLE --dry-run    # review the rename plan
  2. bd rename-prefix $STABLE              # apply
  3. bd label propagate <prior_epic_id> feature:NNN   # back-fill label

See .maestro/templates/migration-runbook-template.md for the full one-time
runbook. /maestro.tasks will refuse to proceed until the prefix matches the
configured stable value.
EOF
exit 3
