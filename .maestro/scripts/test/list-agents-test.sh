#!/usr/bin/env bash
# list-agents-test.sh — fixture-based test harness for list-agents.sh.
#
# Implements the 10 required test cases (T-1 through T-10) from the
# contract section "Test contract" in:
#   .maestro/specs/060-improve-maestro-select-best-agent-each/
#     contracts/list-agents-script.md
#
# Each test runs in its own clean subdirectory of an isolated tempdir,
# with HOME also pointed inside the tempdir so the real user's
# ~/.claude, ~/.codex, ~/.config/opencode are NEVER read or written.
#
# Usage:
#   bash .maestro/scripts/test/list-agents-test.sh
#
# Exit codes:
#   0 — all tests passed
#   1 — at least one test failed
#
# Requires: bash 5+, jq, python3 (>=3.11) — same as list-agents.sh.

set -euo pipefail

# ----------------------------------------------------------------------------
# Locate the script under test using BASH_SOURCE so the test is robust
# regardless of CWD.
# ----------------------------------------------------------------------------
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_UNDER_TEST="$TEST_DIR/../list-agents.sh"

if [[ ! -f "$SCRIPT_UNDER_TEST" ]]; then
  printf 'fatal: list-agents.sh not found at %s\n' "$SCRIPT_UNDER_TEST" >&2
  exit 1
fi

# Suppress progress logs from the script under test — keep test output clean.
export MAESTRO_QUIET=1

# ----------------------------------------------------------------------------
# Tempdir + trap cleanup.
# ----------------------------------------------------------------------------
TMPROOT="$(mktemp -d -t list-agents-test.XXXXXX)"
ORIGINAL_HOME="${HOME:-}"
ORIGINAL_CWD="$PWD"

cleanup() {
  # Restore HOME first so the next process group sees a sane env.
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

# pass <id> <description>
pass() {
  local id="$1" desc="$2"
  printf 'PASS %s: %s\n' "$id" "$desc"
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
}

# fail <id> <description> <expected> <got>
fail() {
  local id="$1" desc="$2" expected="$3" got="$4"
  printf 'FAIL %s: %s | expected %s | got %s\n' "$id" "$desc" "$expected" "$got"
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
}

# ----------------------------------------------------------------------------
# Per-test sandbox: makes a fresh subdir of TMPROOT, points HOME at it
# (so ~/.claude etc. are isolated), and cd's the project root inside it.
# Echoes the project dir on stdout.
# ----------------------------------------------------------------------------
new_sandbox() {
  local name="$1"
  local sandbox="$TMPROOT/$name"
  rm -rf "$sandbox"
  mkdir -p "$sandbox/home" "$sandbox/proj"
  export HOME="$sandbox/home"
  cd "$sandbox/proj"
  printf '%s/proj' "$sandbox"
}

# ----------------------------------------------------------------------------
# Convenience: run the script under test with the given args from the
# current sandbox CWD. Captures stdout; stderr is dropped (we already
# set MAESTRO_QUIET=1, but be defensive).
# ----------------------------------------------------------------------------
run_script() {
  bash "$SCRIPT_UNDER_TEST" "$@" 2>/dev/null
}

# ============================================================================
# T-1: Empty inventory → []
#
# Use --harness=opencode (or codex) to exercise the truly-empty path:
# `claude` always emits 5 hard-coded builtins by design, so an "empty"
# claude inventory is never `[]`. The contract test case is about the
# general empty-walk semantics, which opencode/codex satisfy directly.
# ============================================================================
test_T1_empty_inventory() {
  new_sandbox t1 >/dev/null
  local out
  out="$(run_script --harness=opencode)"
  # Output must be a JSON array with length 0.
  if printf '%s' "$out" | jq -e 'type == "array" and length == 0' >/dev/null 2>&1; then
    pass "T-1" "empty inventory returns []"
  else
    fail "T-1" "empty inventory returns []" "[]" "$out"
  fi
}

# ============================================================================
# T-2: Single Claude project agent → 1 entry + 5 builtins
# ============================================================================
test_T2_single_claude_project_agent() {
  new_sandbox t2 >/dev/null
  mkdir -p .claude/agents
  cat > .claude/agents/golang-expert.md <<'EOF'
---
name: golang-expert
description: Go authoring specialist for payments domain.
---
Body content.
EOF

  local out
  out="$(run_script --harness=claude)"

  # Total entries: 1 subagent + 5 builtins = 6.
  local total
  total="$(printf '%s' "$out" | jq 'length')"
  if [[ "$total" != "6" ]]; then
    fail "T-2" "single Claude project agent yields 1 + 5 builtins" "length=6" "length=$total"
    return
  fi

  # The subagent must be present with kind=subagent.
  if ! printf '%s' "$out" | jq -e '
    map(select(.name == "golang-expert" and .kind == "subagent" and .harness == "claude")) | length == 1
  ' >/dev/null 2>&1; then
    fail "T-2" "single Claude project agent yields 1 + 5 builtins" "subagent golang-expert present" "$out"
    return
  fi

  # Exactly 5 builtins must be present.
  local builtins_count
  builtins_count="$(printf '%s' "$out" | jq '[.[] | select(.kind == "builtin")] | length')"
  if [[ "$builtins_count" != "5" ]]; then
    fail "T-2" "single Claude project agent yields 1 + 5 builtins" "5 builtins" "$builtins_count builtins"
    return
  fi

  pass "T-2" "single Claude project agent yields 1 + 5 builtins"
}

# ============================================================================
# T-3: Stack inference — Go agent → ["go"]; JS reviewer → contains ts/tsx/js
# ============================================================================
test_T3_stack_inference() {
  new_sandbox t3 >/dev/null
  mkdir -p .claude/agents
  cat > .claude/agents/golang-expert.md <<'EOF'
---
name: golang-expert
description: Go specialist.
---
EOF
  cat > .claude/agents/js-code-reviewer.md <<'EOF'
---
name: js-code-reviewer
description: Reviews JavaScript and TypeScript code.
---
EOF

  local out
  out="$(run_script --harness=claude)"

  # Go agent → stacks must equal exactly ["go"].
  if ! printf '%s' "$out" | jq -e '
    .[] | select(.name == "golang-expert") | .stacks == ["go"]
  ' >/dev/null 2>&1; then
    local got
    got="$(printf '%s' "$out" | jq -c '.[] | select(.name == "golang-expert") | .stacks')"
    fail "T-3" "stack inference: Go → [\"go\"]" '["go"]' "$got"
    return
  fi

  # JS reviewer → stacks must contain ts, tsx, and js.
  if ! printf '%s' "$out" | jq -e '
    .[] | select(.name == "js-code-reviewer") | .stacks
    | (index("ts") != null) and (index("tsx") != null) and (index("js") != null)
  ' >/dev/null 2>&1; then
    local got
    got="$(printf '%s' "$out" | jq -c '.[] | select(.name == "js-code-reviewer") | .stacks')"
    fail "T-3" "stack inference: JS reviewer → contains ts/tsx/js" 'contains ["ts","tsx","js"]' "$got"
    return
  fi

  pass "T-3" "stack inference: Go → [\"go\"]; JS reviewer → contains ts/tsx/js"
}

# ============================================================================
# T-4: Intent inference — name ending -reviewer → "review"
# ============================================================================
test_T4_intent_inference_reviewer() {
  new_sandbox t4 >/dev/null
  mkdir -p .claude/agents
  cat > .claude/agents/golang-code-reviewer.md <<'EOF'
---
name: golang-code-reviewer
description: Reviews Go code.
---
EOF

  local out
  out="$(run_script --harness=claude)"

  if ! printf '%s' "$out" | jq -e '
    .[] | select(.name == "golang-code-reviewer") | .intent == "review"
  ' >/dev/null 2>&1; then
    local got
    got="$(printf '%s' "$out" | jq -c '.[] | select(.name == "golang-code-reviewer") | .intent')"
    fail "T-4" "intent inference: name ending -reviewer → review" '"review"' "$got"
    return
  fi

  pass "T-4" "intent inference: name ending -reviewer → review"
}

# ============================================================================
# T-5: Codex TOML subagent → parsed name + description
# ============================================================================
test_T5_codex_toml_subagent() {
  new_sandbox t5 >/dev/null
  mkdir -p .codex/agents
  cat > .codex/agents/refactor-tomes.toml <<'EOF'
name = "refactor-tomes"
description = "Plans refactors before applying."
EOF

  local out
  out="$(run_script --harness=codex)"

  # The script's _first_sentence helper preserves the trailing period when
  # the description is a single sentence (no ". " split point). Match the
  # parsed-out form which keeps the terminating period.
  if ! printf '%s' "$out" | jq -e '
    .[] | select(.name == "refactor-tomes" and .harness == "codex" and .kind == "subagent")
        | .description == "Plans refactors before applying."
  ' >/dev/null 2>&1; then
    local got
    got="$(printf '%s' "$out" | jq -c '.[] | select(.name == "refactor-tomes")')"
    fail "T-5" "Codex TOML subagent → parsed name + description" \
         'name=refactor-tomes desc="Plans refactors before applying."' "$got"
    return
  fi

  pass "T-5" "Codex TOML subagent → parsed name + description"
}

# ============================================================================
# T-6: Codex skill at .agents/skills/foo/SKILL.md discovered
# ============================================================================
test_T6_codex_skill_discovered() {
  new_sandbox t6 >/dev/null
  mkdir -p .agents/skills/foo
  cat > .agents/skills/foo/SKILL.md <<'EOF'
---
name: foo
description: Foo helper skill.
---
Skill body.
EOF

  local out
  out="$(run_script --harness=codex)"

  if ! printf '%s' "$out" | jq -e '
    .[] | select(.name == "foo" and .harness == "codex" and .kind == "skill")
  ' >/dev/null 2>&1; then
    fail "T-6" "Codex skill at .agents/skills/foo/SKILL.md discovered" \
         "skill foo present (codex/skill)" "$out"
    return
  fi

  pass "T-6" "Codex skill at .agents/skills/foo/SKILL.md discovered"
}

# ============================================================================
# T-7: Codex skill disabled in ~/.codex/config.toml filtered out
# ============================================================================
test_T7_codex_disabled_skill_filtered() {
  new_sandbox t7 >/dev/null
  # Plant a skill on disk under HOME (so we can reference its absolute path
  # in ~/.codex/config.toml). We use HOME's .agents/skills dir which is one
  # of the configured Codex skill roots.
  mkdir -p "$HOME/.agents/skills/legacy-helper"
  cat > "$HOME/.agents/skills/legacy-helper/SKILL.md" <<'EOF'
---
name: legacy-helper
description: Old skill we are turning off.
---
EOF

  local skill_path="$HOME/.agents/skills/legacy-helper/SKILL.md"

  # Write ~/.codex/config.toml that disables the skill by absolute path.
  mkdir -p "$HOME/.codex"
  cat > "$HOME/.codex/config.toml" <<EOF
[[skills.config]]
path = "$skill_path"
enabled = false
EOF

  local out
  out="$(run_script --harness=codex)"

  # The skill must NOT appear.
  if printf '%s' "$out" | jq -e '
    map(select(.name == "legacy-helper")) | length > 0
  ' >/dev/null 2>&1; then
    fail "T-7" "disabled Codex skill filtered out" \
         "no entry named legacy-helper" "$out"
    return
  fi

  pass "T-7" "disabled Codex skill filtered out"
}

# ============================================================================
# T-8: OpenCode mode:subagent + name suggesting review → intent: "review"
# ============================================================================
test_T8_opencode_subagent_review() {
  new_sandbox t8 >/dev/null
  mkdir -p .opencode/agents
  # The contract says "intent: review when name suggests it". With
  # mode: subagent the mode_hint alone forces intent=review per Pattern 6
  # (rule 1 of infer_intent), and the name additionally suggests review.
  cat > .opencode/agents/ts-code-reviewer.md <<'EOF'
---
name: ts-code-reviewer
description: Reviews TypeScript code.
mode: subagent
---
Body.
EOF

  local out
  out="$(run_script --harness=opencode)"

  if ! printf '%s' "$out" | jq -e '
    .[] | select(.name == "ts-code-reviewer" and .harness == "opencode" and .kind == "subagent")
        | .intent == "review"
  ' >/dev/null 2>&1; then
    local got
    got="$(printf '%s' "$out" | jq -c '.[] | select(.name == "ts-code-reviewer")')"
    fail "T-8" "OpenCode mode:subagent → intent: review" '"review"' "$got"
    return
  fi

  pass "T-8" "OpenCode mode:subagent → intent: review"
}

# ============================================================================
# T-9: Determinism — two consecutive runs produce identical output
# ============================================================================
test_T9_determinism() {
  new_sandbox t9 >/dev/null
  # Plant a non-trivial mix so the sort path exercises actual data.
  mkdir -p .claude/agents .claude/skills/skill-a .opencode/agents
  cat > .claude/agents/golang-expert.md <<'EOF'
---
name: golang-expert
description: Go specialist.
---
EOF
  cat > .claude/agents/golang-code-reviewer.md <<'EOF'
---
name: golang-code-reviewer
description: Reviews Go code.
---
EOF
  cat > .claude/skills/skill-a/SKILL.md <<'EOF'
---
name: skill-a
description: A skill.
---
EOF
  cat > .opencode/agents/ts-code-reviewer.md <<'EOF'
---
name: ts-code-reviewer
description: Reviews TypeScript code.
mode: subagent
---
EOF

  local run1 run2
  run1="$(run_script --harness=all)"
  run2="$(run_script --harness=all)"

  if diff <(printf '%s' "$run1") <(printf '%s' "$run2") >/dev/null 2>&1; then
    pass "T-9" "determinism: two runs produce byte-identical output"
  else
    fail "T-9" "determinism: two runs produce byte-identical output" \
         "diff exits 0" "diff non-empty"
  fi
}

# ============================================================================
# T-10: Word-boundary inference — description "this agent is pretty good"
# does NOT falsely match `py` stack.
# ============================================================================
test_T10_word_boundary_no_false_py() {
  new_sandbox t10 >/dev/null
  mkdir -p .claude/agents
  cat > .claude/agents/generalist.md <<'EOF'
---
name: generalist
description: this agent is pretty good
---
EOF

  local out
  out="$(run_script --harness=claude)"

  # The generalist's stacks must NOT include "py".
  if printf '%s' "$out" | jq -e '
    .[] | select(.name == "generalist") | .stacks | index("py") != null
  ' >/dev/null 2>&1; then
    local got
    got="$(printf '%s' "$out" | jq -c '.[] | select(.name == "generalist") | .stacks')"
    fail "T-10" "word-boundary: \"pretty good\" does not match py" \
         'stacks without "py"' "$got"
    return
  fi

  pass "T-10" "word-boundary: \"pretty good\" does not match py"
}

# ============================================================================
# Driver
# ============================================================================
main() {
  test_T1_empty_inventory
  test_T2_single_claude_project_agent
  test_T3_stack_inference
  test_T4_intent_inference_reviewer
  test_T5_codex_toml_subagent
  test_T6_codex_skill_discovered
  test_T7_codex_disabled_skill_filtered
  test_T8_opencode_subagent_review
  test_T9_determinism
  test_T10_word_boundary_no_false_py

  printf '=== %d/%d passed ===\n' "$PASSED" "$TOTAL"

  if [[ "$FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
}

main "$@"
