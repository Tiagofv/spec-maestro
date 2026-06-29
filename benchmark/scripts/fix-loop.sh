#!/usr/bin/env bash
# fix-loop.sh — re-run ONE maestro stage in a sandbox and diff status/turns/cost
# against the previous run of that stage. Closes the local fix loop: edit a command
# in this repo's .maestro/, re-sync into the sandbox, re-run just the stage, confirm.
#
# Usage:
#   benchmark/scripts/fix-loop.sh <case-id> <stage> [sandbox-dir]
#
# Behaviour:
#   - snapshots the prior .bench/<stage>.json (if any) as <stage>.prev.json
#   - re-copies this repo's .maestro/commands + skills into the sandbox (so your edits
#     take effect) WITHOUT wiping specs/state/bd (the pipeline state is preserved)
#   - re-runs the single stage via run-case.sh (STAGES=<stage>)
#   - prints before/after status, turns, cost
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
die() { echo "error: $*" >&2; exit 1; }

[ $# -ge 2 ] || die "usage: fix-loop.sh <case-id> <stage> [sandbox-dir]"
CASE_ID="$(printf '%02d' "$((10#$1))")"
STAGE="$2"
SANDBOX="${3:-${TMPDIR:-/tmp}/maestro-bench-${CASE_ID}-run}"
[ -d "$SANDBOX/.maestro" ] || die "no sandbox at $SANDBOX (run run-case.sh first)"

prev=".bench/${STAGE}.json"
if [ -f "$SANDBOX/$prev" ]; then cp "$SANDBOX/$prev" "$SANDBOX/.bench/${STAGE}.prev.json"; fi

# re-sync edited maestro assets (commands/skills/templates) into the sandbox; keep state
echo ">> Re-syncing .maestro/{commands,skills,templates,scripts,cookbook,reference} from repo"
for d in commands skills templates scripts cookbook reference; do
  [ -d "$REPO_ROOT/.maestro/$d" ] && rm -rf "$SANDBOX/.maestro/$d" && cp -R "$REPO_ROOT/.maestro/$d" "$SANDBOX/.maestro/$d"
done
[ -d "$REPO_ROOT/.claude/commands" ] && rm -rf "$SANDBOX/.claude/commands" && cp -R "$REPO_ROOT/.claude/commands" "$SANDBOX/.claude/commands"

STAGES="$STAGE" "$SCRIPT_DIR/run-case.sh" "$CASE_ID" "$SANDBOX"

echo
echo "===== BEFORE vs AFTER ($STAGE) ====="
read_envelope() { # $1 = json file
  if [ -f "$1" ]; then
    jq -r '"status_err=\(.is_error)  turns=\(.num_turns)  cost=$\(.total_cost_usd)"' "$1" 2>/dev/null
  else echo "(no prior run)"; fi
}
echo "before: $(read_envelope "$SANDBOX/.bench/${STAGE}.prev.json")"
echo "after : $(read_envelope "$SANDBOX/.bench/${STAGE}.json")"
