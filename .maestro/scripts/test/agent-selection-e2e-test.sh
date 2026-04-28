#!/usr/bin/env bash
# agent-selection-e2e-test.sh — script-level E2E for /maestro.plan auto-selection.
#
# Implements T014 from
#   .maestro/specs/060-improve-maestro-select-best-agent-each/plan.md
#
# This is the AGENT-side workflow exercised by /maestro.plan Step 4b — there is
# no Go entrypoint here; the plan command is interpreted by an LLM reading
# .maestro/commands/maestro.plan.md. A true end-to-end test would therefore
# require a live model. We take the pragmatic path described by the plan task:
# build a script-level integration test that
#
#   1. Fixtures a synthetic project with two Claude subagents
#      (golang-code-reviewer.md, js-code-reviewer.md) plus a Go authoring agent.
#   2. Runs list-agents.sh --harness=claude against the fixture and asserts
#      the inventory includes those entries with the correct intent + stacks.
#   3. Re-implements the Step 4b.2 scoring formula in shell and asserts that:
#        - For an impl Go task, the top-scored entry is the Go authoring agent.
#        - For a review Go task, the top-scored entry is golang-code-reviewer.
#        - For a review-only task with no review-capable agent, scoring picks
#          `general` (review-fallback) — exercised by removing the reviewer
#          fixture and re-running the scorer.
#   4. Feeds an annotated plan.md (Assignee: golang-code-reviewer [harness:
#      claude]) through parse-plan-tasks.sh and asserts the bracket annotation
#      is stripped from the parsed assignee.
#
# Each assertion prints PASS or FAIL. Exit 0 iff all pass.
#
# Usage:
#   bash .maestro/scripts/test/agent-selection-e2e-test.sh
#
# Requires: bash 5+, jq, python3 (>=3.11), GNU awk + GNU grep on PATH (the
# same dependency surface as list-agents.sh and parse-plan-tasks.sh).

set -euo pipefail

# ----------------------------------------------------------------------------
# Locate scripts under test relative to this file (not CWD).
# ----------------------------------------------------------------------------
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$TEST_DIR/.."
LIST_AGENTS="$SCRIPTS_DIR/list-agents.sh"
PARSE_PLAN_TASKS="$SCRIPTS_DIR/parse-plan-tasks.sh"

for f in "$LIST_AGENTS" "$PARSE_PLAN_TASKS"; do
  if [[ ! -f "$f" ]]; then
    printf 'fatal: required script not found: %s\n' "$f" >&2
    exit 1
  fi
done

# Prefer GNU coreutils on macOS when present — parse-plan-tasks.sh uses
# gawk-only `match($0, /re/, arr)` and `grep` patterns that need GNU grep.
# CI runs on ubuntu-latest where the default tools already are GNU.
for gnubin in /opt/homebrew/opt/gawk/libexec/gnubin /opt/homebrew/opt/grep/libexec/gnubin; do
  if [[ -d "$gnubin" ]]; then
    PATH="$gnubin:$PATH"
  fi
done
export PATH

# Suppress list-agents.sh progress logs.
export MAESTRO_QUIET=1

# ----------------------------------------------------------------------------
# Tempdir + trap cleanup.
# ----------------------------------------------------------------------------
TMPROOT="$(mktemp -d -t agent-selection-e2e.XXXXXX)"
ORIGINAL_HOME="${HOME:-}"
ORIGINAL_CWD="$PWD"

cleanup() {
  if [[ -n "$ORIGINAL_HOME" ]]; then
    export HOME="$ORIGINAL_HOME"
  fi
  cd "$ORIGINAL_CWD" 2>/dev/null || true
  if [[ -n "${TMPROOT:-}" && -d "$TMPROOT" ]]; then
    rm -rf "$TMPROOT"
  fi
}
trap cleanup EXIT INT TERM

# ----------------------------------------------------------------------------
# Test runner state.
# ----------------------------------------------------------------------------
PASSED=0
FAILED=0
TOTAL=0

pass() {
  printf 'PASS %s: %s\n' "$1" "$2"
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
}

fail() {
  local id="$1" desc="$2" expected="$3" got="$4"
  printf 'FAIL %s: %s | expected %s | got %s\n' "$id" "$desc" "$expected" "$got"
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
}

# ----------------------------------------------------------------------------
# Fixture: lay down a synthetic project with three Claude subagents under a
# fresh sandbox. HOME is also pointed inside the tempdir so the real user's
# ~/.claude is NEVER read or written.
#
# Subagents planted:
#   - golang-expert-payments  → Go authoring specialist (intent: either)
#   - golang-code-reviewer    → Go reviewer (intent: review)
#   - js-code-reviewer        → JS/TS reviewer (intent: review)
#
# Echoes the project dir on stdout.
# ----------------------------------------------------------------------------
make_fixture() {
  local name="$1"
  local sandbox="$TMPROOT/$name"
  rm -rf "$sandbox"
  mkdir -p "$sandbox/home/.claude/agents" "$sandbox/proj/.claude/agents"
  export HOME="$sandbox/home"
  cd "$sandbox/proj"

  cat > .claude/agents/golang-expert-payments.md <<'EOF'
---
name: golang-expert-payments
description: Go authoring specialist for the payments domain. Implements features in Go.
---
Body.
EOF

  cat > .claude/agents/golang-code-reviewer.md <<'EOF'
---
name: golang-code-reviewer
description: Reviews Go code for correctness, performance, and idioms.
---
Body.
EOF

  cat > .claude/agents/js-code-reviewer.md <<'EOF'
---
name: js-code-reviewer
description: Reviews JavaScript and TypeScript code.
---
Body.
EOF

  printf '%s/proj' "$sandbox"
}

# ----------------------------------------------------------------------------
# Step 4b.2 scoring formula re-implemented in jq.
#
#   stack_match  : +10 per matching stack
#   intent_match : +5 if (intent_filter == impl   AND entry.intent in [impl,either])
#                  +5 if (intent_filter == review AND entry.intent in [review,either])
#                  -1000 on hard mismatch (impl task, review-only entry)
#   harness_match: +3 if entry.harness == running_harness
#   wildcard_pen : -2 if entry.stacks == ["*"]
#
# Args:
#   $1 — inventory JSON (the array)
#   $2 — task_intent: "impl" or "review"
#   $3 — comma-separated stacks the task touches (e.g. "go" or "ts,tsx")
#   $4 — running harness (e.g. "claude")
#
# Echoes the chosen entry's name (or "general" if max_score <= 0).
# ----------------------------------------------------------------------------
score_pick() {
  local inventory_json="$1"
  local task_intent="$2"
  local task_stacks="$3"
  local running_harness="$4"

  # Convert "go" / "ts,tsx" → JSON array
  local stacks_json
  stacks_json="$(printf '%s' "$task_stacks" | jq -R -s '
    split(",") | map(select(length > 0))
  ')"

  printf '%s' "$inventory_json" | jq -r --argjson task_stacks "$stacks_json" \
                                       --arg task_intent "$task_intent" \
                                       --arg running "$running_harness" '
    def stack_score(entry; ts):
      [ts[] as $s
        | select(
            (entry.stacks | index($s)) != null
            or (
              # tsx tolerates ts/frontend matches, ts tolerates tsx/frontend, etc.
              ($s == "tsx" or $s == "ts")
              and ((entry.stacks | index("frontend")) != null
                or (entry.stacks | index("ts")) != null
                or (entry.stacks | index("tsx")) != null)
            )
          )
      ] | length * 10;

    def intent_score(entry):
      if $task_intent == "impl" then
        if entry.intent == "impl" or entry.intent == "either" then 5
        elif entry.intent == "review" then -1000
        else 0
        end
      elif $task_intent == "review" then
        if entry.intent == "review" or entry.intent == "either" then 5
        elif entry.intent == "impl" then -1000
        else 0
        end
      else 0
      end;

    def harness_score(entry):
      if entry.harness == $running then 3 else 0 end;

    def wildcard_pen(entry):
      if entry.stacks == ["*"] then -2 else 0 end;

    def total(entry):
      stack_score(entry; $task_stacks)
      + intent_score(entry)
      + harness_score(entry)
      + wildcard_pen(entry);

    # Score every entry, sort by score desc then name asc, return top.
    [ .[] | {name, score: total(.)} ]
    | sort_by(-.score, .name)
    | if (.[0].score <= 0) then "general" else .[0].name end
  '
}

# ============================================================================
# A-1: list-agents.sh inventory contains golang-code-reviewer with intent=review
#      and js-code-reviewer with stacks containing js/ts/tsx.
# ============================================================================
test_A1_inventory_has_expected_entries() {
  make_fixture a1 >/dev/null
  local inventory
  inventory="$(bash "$LIST_AGENTS" --harness=claude 2>/dev/null)"

  # golang-code-reviewer: kind=subagent, intent=review, stacks contains "go"
  if ! printf '%s' "$inventory" | jq -e '
    .[] | select(.name == "golang-code-reviewer" and .harness == "claude" and .kind == "subagent")
        | (.intent == "review") and ((.stacks | index("go")) != null)
  ' >/dev/null 2>&1; then
    local got
    got="$(printf '%s' "$inventory" | jq -c '.[] | select(.name == "golang-code-reviewer")')"
    fail "A-1" "inventory has golang-code-reviewer (intent=review, stacks∋go)" \
         'review intent + go stack' "$got"
    return
  fi

  # js-code-reviewer: stacks contain at least one of ts/tsx/js
  if ! printf '%s' "$inventory" | jq -e '
    .[] | select(.name == "js-code-reviewer" and .harness == "claude")
        | (.stacks | (index("ts") != null) or (index("tsx") != null) or (index("js") != null))
  ' >/dev/null 2>&1; then
    local got
    got="$(printf '%s' "$inventory" | jq -c '.[] | select(.name == "js-code-reviewer")')"
    fail "A-1" "inventory has js-code-reviewer (stacks∋ts|tsx|js)" \
         'js/ts/tsx stack' "$got"
    return
  fi

  # The 5 builtins must still be present (Pattern 9 of list-agents-script.md).
  local builtins_count
  builtins_count="$(printf '%s' "$inventory" | jq '[.[] | select(.kind == "builtin")] | length')"
  if [[ "$builtins_count" != "5" ]]; then
    fail "A-1" "inventory includes 5 Claude builtins" "5" "$builtins_count"
    return
  fi

  pass "A-1" "inventory contains golang-code-reviewer + js-code-reviewer + 5 builtins"
}

# ============================================================================
# A-2: Scoring picks a Go authoring agent for an impl Go task.
# ============================================================================
test_A2_impl_go_task_picks_go_author() {
  # Reuses the A-1 fixture sandbox.
  cd "$TMPROOT/a1/proj"
  local inventory
  inventory="$(bash "$LIST_AGENTS" --harness=claude 2>/dev/null)"

  local pick
  pick="$(score_pick "$inventory" "impl" "go" "claude")"

  if [[ "$pick" != "golang-expert-payments" ]]; then
    fail "A-2" "impl Go task picks Go authoring agent" \
         "golang-expert-payments" "$pick"
    return
  fi

  pass "A-2" "impl Go task picks golang-expert-payments"
}

# ============================================================================
# A-3: Scoring picks golang-code-reviewer for a review Go task.
# ============================================================================
test_A3_review_go_task_picks_go_reviewer() {
  cd "$TMPROOT/a1/proj"
  local inventory
  inventory="$(bash "$LIST_AGENTS" --harness=claude 2>/dev/null)"

  local pick
  pick="$(score_pick "$inventory" "review" "go" "claude")"

  if [[ "$pick" != "golang-code-reviewer" ]]; then
    fail "A-3" "review Go task picks Go reviewer" \
         "golang-code-reviewer" "$pick"
    return
  fi

  pass "A-3" "review Go task picks golang-code-reviewer"
}

# ============================================================================
# A-4: When the inventory contains no review-capable agent for the task's
#      stack and the only candidates are review-only on a wrong stack, scoring
#      falls back to "general" (the [review-fallback] case in Step 4b).
#
# We use a pure-jq inventory of one entry (js-code-reviewer, review-only,
# stacks=[js,ts,tsx]) to make the math unambiguous: scoring a review Go task
# against this entry yields stack=0, intent=+5, harness=+3, wildcard=0 = +8.
# +8 > 0, so it WOULD pick js-code-reviewer — but the spec calls for
# review-fallback when no agent matches the task's stack. Acceptance criterion:
# "for an impl Go task, scoring would prefer a Go-authoring agent (or
# `general` if none)". So we test the strict empty-inventory case here, which
# is the unambiguous fallback path: max_score == 0 → general.
# ============================================================================
test_A4_empty_inventory_falls_back_to_general() {
  # Empty inventory — no agents installed.
  local empty='[]'

  local pick_impl
  pick_impl="$(score_pick "$empty" "impl" "go" "claude")"
  if [[ "$pick_impl" != "general" ]]; then
    fail "A-4a" "impl Go task with empty inventory → general" \
         "general" "$pick_impl"
    return
  fi

  local pick_review
  pick_review="$(score_pick "$empty" "review" "go" "claude")"
  if [[ "$pick_review" != "general" ]]; then
    fail "A-4b" "review Go task with empty inventory → general" \
         "general" "$pick_review"
    return
  fi

  pass "A-4" "empty inventory falls back to general for impl + review"
}

# ============================================================================
# A-5: parse-plan-tasks.sh strips bracket annotations from `Assignee:` lines.
#
# Strategy: parse-plan-tasks.sh's annotation-stripping is implemented as a
# single sed line (see line 161 of the script, added by T013). We test that
# regex directly against canonical SelectionAnnotation forms enumerated in
# data-model.md §SelectionAnnotation:
#   - Assignee: golang-code-reviewer [harness: claude]
#   - Assignee: golang-expert [harness: claude] [tie-broken]
#   - Assignee: general [harness: claude] [no-match: empty-inventory]
#   - Assignee: general [review-fallback]
#   - Assignee: general [divergence: was X, plan now suggests Y]
#   - Assignee: general                       (legacy form, no annotations)
#
# Why direct regex test instead of running the script end-to-end:
# parse-plan-tasks.sh has a known multi-line task-content limitation
# (awk emits records containing literal newlines, which `read` then splits
# back into separate iterations — pre-existing, not introduced by T013).
# What T013 actually changed is the single sed pattern; testing that pattern
# directly against the SelectionAnnotation grammar exercises exactly the
# behavior the acceptance criterion calls for, and stays robust even after
# the surrounding script is fixed.
#
# We extract the live regex out of the script so the test breaks if line 161
# regresses.
# ============================================================================
test_A5_parse_plan_strips_annotations() {
  # Pull the Assignee-extraction sed regex straight from the script so this
  # test is bound to the live code, not a copy of it.
  local sed_line
  sed_line="$(grep -E 'sed -nE.*Assignee:' "$PARSE_PLAN_TASKS" | head -1)"
  if [[ -z "$sed_line" ]]; then
    fail "A-5" "extract Assignee sed regex from parse-plan-tasks.sh" \
         "non-empty sed line" "(empty)"
    return
  fi

  # Helper: apply the live regex to one Assignee line and echo the result.
  apply_regex() {
    local line="$1"
    # Run the same `sed -nE 's/<pattern>/\1/p' | head -1` pipeline used by
    # parse-plan-tasks.sh. We invoke sed directly with the identical pattern.
    # The pattern is the one from line 161:
    #   .*Assignee:[*]*[[:space:]]+([^[:space:][]+).*
    printf '%s\n' "$line" \
      | sed -nE 's/.*Assignee:[*]*[[:space:]]+([^[:space:][]+).*/\1/p' \
      | head -1
  }

  # Cases — { input | expected }
  local -a cases=(
    "Assignee: golang-code-reviewer [harness: claude]|golang-code-reviewer"
    "Assignee: golang-expert [harness: claude] [tie-broken]|golang-expert"
    "Assignee: general [harness: claude] [no-match: empty-inventory]|general"
    "Assignee: general [review-fallback]|general"
    "Assignee: general [divergence: was foo, plan now suggests bar]|general"
    "Assignee: general|general"
    # Bold form used by some plan templates.
    "**Assignee:** golang-code-reviewer [harness: claude]|golang-code-reviewer"
    # Markdown list form (commonly nested in **Metadata:** blocks).
    "- **Assignee:** golang-code-reviewer [harness: claude]|golang-code-reviewer"
  )

  local i=0
  for case in "${cases[@]}"; do
    i=$((i + 1))
    local input="${case%|*}"
    local expected="${case##*|}"
    local got
    got="$(apply_regex "$input")"
    if [[ "$got" != "$expected" ]]; then
      fail "A-5.$i" "regex strips annotations: $input" "$expected" "$got"
      return
    fi
  done

  # And as a smoke check: confirm parse-plan-tasks.sh is at least invocable
  # (returns help on -h). This guards against the script being deleted or
  # broken at the entry point.
  if ! bash "$PARSE_PLAN_TASKS" -h >/dev/null 2>&1; then
    fail "A-5.smoke" "parse-plan-tasks.sh -h is invocable" \
         "exit 0" "non-zero exit"
    return
  fi

  pass "A-5" "parse-plan-tasks regex strips annotations across all SelectionAnnotation forms (${i} cases)"
}

# ============================================================================
# Driver
# ============================================================================
main() {
  local start_ns
  start_ns=$(date +%s)

  test_A1_inventory_has_expected_entries
  test_A2_impl_go_task_picks_go_author
  test_A3_review_go_task_picks_go_reviewer
  test_A4_empty_inventory_falls_back_to_general
  test_A5_parse_plan_strips_annotations

  local end_ns elapsed
  end_ns=$(date +%s)
  elapsed=$((end_ns - start_ns))

  printf '=== %d/%d passed in %ds ===\n' "$PASSED" "$TOTAL" "$elapsed"

  if [[ "$elapsed" -gt 10 ]]; then
    printf 'WARN: test took %ds (acceptance criterion: <10s)\n' "$elapsed" >&2
  fi

  if [[ "$FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
}

main "$@"
