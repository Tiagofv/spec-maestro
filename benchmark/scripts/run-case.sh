#!/usr/bin/env bash
# run-case.sh — drive a benchmark case through the maestro pipeline HEADLESSLY.
#
# Each stage runs as an isolated `claude -p` process: fresh context per stage,
# state shared on disk (.maestro/specs, bd db, git). This is the whole point —
# no single context holds the entire pipeline, so a full run costs a fraction of
# an interactive session.
#
# Usage:
#   benchmark/scripts/run-case.sh <case-id> [sandbox-dir]
#
# Env:
#   STAGES="specify clarify plan"   # which stages to run (default: cheap slice)
#   MAX_TURNS=40                      # per-stage turn cap
#   MODEL=sonnet                      # model alias for the headless runner
#
# Output (does NOT pollute the calling session's context):
#   <sandbox>/.bench/<stage>.json     raw claude result envelope
#   <sandbox>/.bench/<stage>.txt      stage result text
#   <sandbox>/.bench/report.tsv       stage  status  turns  cost_usd  dur_s  artifact
#   <sandbox>/.bench/PROBLEMS.md      one bullet per detected problem
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
die() { echo "error: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: run-case.sh <case-id> [sandbox-dir]"
CASE_ID="$(printf '%02d' "$((10#$1))")"
SANDBOX="${2:-}"
MAX_TURNS="${MAX_TURNS:-40}"
MODEL="${MODEL:-sonnet}"
STAGES="${STAGES:-specify clarify plan}"

# ---- feature text per case (kept generic — no proprietary code) --------------
specify_text() {
  case "$CASE_ID" in
    01) echo "Add a command-line task tracker. Users can add a task with a title, list all tasks, mark a task done by its id, and delete a task by its id. Tasks persist to a JSON file in the working directory. Each task has an id, title, done flag, and created timestamp." ;;
    02) echo "Add a URL shortener API. POST /shorten accepts a JSON body with a url field and returns a short code. GET /:code redirects (HTTP 302) to the original URL, or returns 404 if the code is unknown. Reject invalid URLs with 400. The short code should be short, URL-safe, and collision-free." ;;
    03) echo "Build a static site generator. It reads every .md file under content/, converts the Markdown to HTML, inserts the HTML into the {{content}} placeholder of templates/base.html, and writes the result to dist/<name>.html. Headings, paragraphs, bold, italic, and links must convert correctly. Running it twice produces identical output. Print the count of files generated." ;;
    04) echo "Add pagination to GET /notes on the existing notes API. Accept ?limit (default 20, max 100) and ?offset (default 0). Return { items, total, limit, offset }. Invalid params return 400. Existing POST /notes behavior and the existing tests must be unchanged." ;;
    05) echo "Add a rate limiter so callers don't get overwhelmed. It should limit how often something can happen and say no when there's too much." ;;
    06) echo "Add two endpoints to the API: GET /health returns {\"ok\":true}, and GET /items returns the list of items from the store. The store module gains an in-memory Items() []Item function the API calls. This work spans the api and store modules." ;;
    07) echo "Add a counter widget: a React component Counter.tsx that shows a number and an increment button, backed by a GET /count and POST /count/increment API in src/server. The component calls the API." ;;
    08) echo "Add Parse(data []byte) (Config, error) to safejson: parse JSON config into a Config struct, returning a useful error on malformed input. Also add MustParse(data []byte) Config for tests." ;;
    09) echo "Add formatWithCurrency(cents, code) that formats an amount with a currency symbol (USD->dollar, EUR->euro, GBP->pound), reusing the existing format. Unknown codes return an error value. Do not change existing format/round behavior or their tests." ;;
    10) echo "Add Slugify(s string) string: lowercase, replace runs of non-alphanumerics with a single hyphen, trim leading and trailing hyphens." ;;
  esac
}

# stage -> slash command prompt
stage_prompt() {
  case "$1" in
    specify) echo "/maestro.specify \"$(specify_text)\"" ;;
    clarify) echo "/maestro.clarify

Resolve every [NEEDS CLARIFICATION] marker. Pick the simplest reasonable answer for each and write it into the spec. Do not ask me — decide and proceed." ;;
    research) echo "/maestro.research" ;;
    plan) echo "/maestro.plan" ;;
    tasks) echo "/maestro.tasks" ;;
    implement) echo "/maestro.implement" ;;
    pm-validate) echo "/maestro.pm-validate" ;;
    analyze) echo "/maestro.analyze" ;;
    *) echo "/maestro.$1" ;;
  esac
}

# stage -> a glob that must exist in the spec dir after the stage (artifact check)
stage_artifact() {
  case "$1" in
    specify) echo "spec.md" ;;
    plan)    echo "plan.md" ;;
    research) echo "research/*.md" ;;
    *) echo "" ;;
  esac
}

# ---- scaffold if needed ------------------------------------------------------
[ -z "$SANDBOX" ] && SANDBOX="${TMPDIR:-/tmp}/maestro-bench-${CASE_ID}-run-$$"
if [ ! -d "$SANDBOX/.maestro" ]; then
  echo ">> Scaffolding sandbox: $SANDBOX"
  "$SCRIPT_DIR/setup-case.sh" "$CASE_ID" "$SANDBOX" >/dev/null || die "setup failed"
fi
[ -d "$SANDBOX/.maestro" ] || die "sandbox missing .maestro: $SANDBOX"
cd "$SANDBOX"
mkdir -p .bench
REPORT=".bench/report.tsv"
PROBLEMS=".bench/PROBLEMS.md"
: > "$REPORT"
: > "$PROBLEMS"
printf "stage\tstatus\tturns\tcost_usd\tdur_s\tartifact\n" >> "$REPORT"

echo ">> Case $CASE_ID headless run | model=$MODEL max_turns=$MAX_TURNS"
echo ">> Sandbox: $SANDBOX"
echo ">> Stages: $STAGES"

prob() { echo "- **$1**: $2" >> "$PROBLEMS"; }

# static checks that don't need a model — cheap, run against current disk state.
# DETECT_ONLY=1 runs ONLY these (no claude calls), to re-check a sandbox for free.
static_checks() {
  base=$(awk -F: '/^[[:space:]]+base_branch:/{gsub(/[" ]/,"",$2); print $2; exit}' .maestro/config.yaml 2>/dev/null)
  [ -z "${base:-}" ] && base="main"
  branch=$(git branch --show-current 2>/dev/null || echo "")
  specdir=$(ls -dt .maestro/specs/*/ 2>/dev/null | head -1 || echo "")
  if [ -n "$specdir" ] && [ "$branch" = "$base" ]; then
    prob "branch" "after specify the repo is still on base branch '$base' (no feature branch) so downstream commit/PR-diff compares base-to-base. The plain (non-worktree) flow never creates the branch that specify.md says it creates."
  fi
  if [ -n "$specdir" ]; then
    slug=$(basename "$specdir" | sed -E 's/^[0-9]+-//')
    segs=$(printf '%s' "$slug" | tr '-' '\n' | grep -c .)
    if printf '%s' "$slug" | grep -qiE '(^|-)(the|a|an|users|can|and|with|to|for|of)(-|$)' || [ "${segs:-0}" -gt 6 ]; then
      prob "slug" "feature dir slug '$slug' looks greedy (raw description words / stop-words, ${segs} segments). A concise slug reads better and shortens branch names."
    fi
  fi
}

if [ "${DETECT_ONLY:-0}" = "1" ]; then
  echo ">> DETECT_ONLY: static checks against existing sandbox (no model calls)"
  static_checks
  if [ -s "$PROBLEMS" ]; then echo "===== PROBLEMS ====="; cat "$PROBLEMS"; else echo "no problems detected"; fi
  exit 0
fi

for stage in $STAGES; do
  prompt="$(stage_prompt "$stage")"
  out=".bench/${stage}.json"
  echo ">> [$stage] running..."
  start=$(date +%s)
  # Auth: default to the claude.ai SUBSCRIPTION (unset ANTHROPIC_API_KEY/AUTH_TOKEN for the
  # child) so runs count against the plan quota, not metered API dollars. The API key
  # otherwise takes precedence and bills credits ("Credit balance is too low"). Opt back in
  # to API billing with USE_API_KEY=1.
  if [ "${USE_API_KEY:-0}" = "1" ]; then
    AUTH_ENV=(env)
  else
    AUTH_ENV=(env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN)
  fi
  # isolated headless process; json envelope carries cost/turns
  "${AUTH_ENV[@]}" claude -p "$prompt" \
    --output-format json \
    --model "$MODEL" \
    --max-turns "$MAX_TURNS" \
    --dangerously-skip-permissions \
    > "$out" 2> ".bench/${stage}.stderr" || true
  end=$(date +%s); dur=$((end-start))

  # parse envelope (claude -p json: {is_error, num_turns, total_cost_usd, result, ...})
  is_error=$(jq -r '.is_error // empty' "$out" 2>/dev/null)
  turns=$(jq -r '.num_turns // empty' "$out" 2>/dev/null)
  cost=$(jq -r '.total_cost_usd // empty' "$out" 2>/dev/null)
  jq -r '.result // empty' "$out" 2>/dev/null > ".bench/${stage}.txt"

  # locate newest spec dir for artifact checks
  specdir=$(ls -dt .maestro/specs/*/ 2>/dev/null | head -1)
  art_glob="$(stage_artifact "$stage")"
  art_ok="n/a"
  if [ -n "$art_glob" ] && [ -n "$specdir" ]; then
    # shellcheck disable=SC2086
    if ls $specdir$art_glob >/dev/null 2>&1; then art_ok="present"; else art_ok="MISSING"; fi
  fi

  status="ok"
  [ "$is_error" = "true" ] && status="error"
  [ -z "$turns" ] && status="error"
  [ "$turns" = "$MAX_TURNS" ] && status="turn-cap"
  [ "$art_ok" = "MISSING" ] && status="no-artifact"

  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$stage" "$status" "${turns:-?}" "${cost:-?}" "$dur" "$art_ok" >> "$REPORT"
  echo "   -> status=$status turns=${turns:-?} cost=\$${cost:-?} ${dur}s artifact=$art_ok"

  case "$status" in
    error)       prob "$stage" "headless run errored or produced no envelope (see .bench/${stage}.stderr)"; break ;;
    turn-cap)    prob "$stage" "hit MAX_TURNS=$MAX_TURNS without finishing — command may be too long / agent looping" ;;
    no-artifact) prob "$stage" "expected artifact '$art_glob' not created in $specdir" ;;
  esac
done

static_checks   # branch + slug checks the per-stage artifact check can't see

echo
echo "===== REPORT ====="
column -t -s $'\t' "$REPORT"
echo
if [ -s "$PROBLEMS" ]; then echo "===== PROBLEMS ====="; cat "$PROBLEMS"; else echo "no problems detected"; fi
echo
echo "artifacts: $SANDBOX/.bench/   sandbox: $SANDBOX"
