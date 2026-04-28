#!/usr/bin/env bash
# list-agents.sh — enumerate harness-installed agents/skills as a JSON inventory.
#
# Purpose:
#   Walks the filesystem (project + user scope) for Claude Code, OpenCode, and
#   Codex agents/skills, parses their metadata, and emits a single deterministic
#   JSON array of AgentInventoryEntry records on stdout. Consumed by
#   /maestro.plan Step 4b to score and pick the best Assignee per task.
#
# Contract:
#   .maestro/specs/060-improve-maestro-select-best-agent-each/contracts/list-agents-script.md
# Data model:
#   .maestro/specs/060-improve-maestro-select-best-agent-each/data-model.md
#
# Status: T001 SCAFFOLD ONLY.
#   This file lands the CLI surface, harness detection, dispatcher, and stub
#   per-runtime list_* functions that all return `[]`. The real walks land in
#   later tasks:
#     T002 — list_claude   (.claude/agents, .claude/skills, builtins)
#     T003 — list_opencode (.opencode/agents, .opencode/skills)
#     T004 — list_codex    (.codex/agents *.toml, .agents/skills, ~/.codex/config.toml filter)
#     T005 — shared inference helpers (infer_stacks, infer_intent) + sort/dedupe
#
# Inputs (CLI):
#   --harness=auto|claude|opencode|codex|all   default: auto
#   --format=json                              default: json (only json supported in v1)
#
# Outputs:
#   stdout — JSON array of AgentInventoryEntry objects (empty array `[]` if none)
#   stderr — human-readable progress lines; suppressed when MAESTRO_QUIET=1
#
# Exit codes:
#   0  success (including empty inventory)
#   1  fatal error (unreadable config, missing python3, malformed TOML)
#   2  invalid CLI flag
#
# Dependencies:
#   - bash 5+
#   - jq                  (JSON assembly + concatenation)
#   - python3 (>=3.11)    (TOML parsing for Codex agents — used in T004)
#
# Harness detection:
#   detect_harness() probes `which claude|opencode|codex` and the presence of
#   project-local dirs (.claude/, .opencode/, .codex/). When a downstream wants
#   to FORCE a harness, the env vars CLAUDE_CODE / OPENCODE / CODEX_RUNTIME are
#   reserved for that purpose; v1 only consults `which` + dir presence and
#   leaves the env-var hook to a future task. Preference order on multi-match
#   matches KnownAgentDirs ordering: claude > opencode > codex.

set -euo pipefail

# ----------------------------------------------------------------------------
# Defaults
# ----------------------------------------------------------------------------
HARNESS="auto"
FORMAT="json"

# ----------------------------------------------------------------------------
# Logging helper — stderr only, suppressed when MAESTRO_QUIET=1.
# Reserved for future "discovered N agents in <dir>" lines emitted by T002–T004.
# ----------------------------------------------------------------------------
log() {
  if [[ "${MAESTRO_QUIET:-0}" != "1" ]]; then
    printf '%s\n' "$*" >&2
  fi
}

# ----------------------------------------------------------------------------
# CLI parsing — getopt-style loop accepting `--key=value` form only.
# Unknown flags exit 2 with stderr message per contract.
#
# Gated under `_parse_args` so the script remains source-able for inline
# testing (sourcing should NOT consume the parent shell's positional args nor
# exit on unknown flags). Invoked from `main` at the bottom only when the
# script is executed directly (BASH_SOURCE[0] == $0).
# ----------------------------------------------------------------------------
_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --harness=*)
        HARNESS="${1#--harness=}"
        shift
        ;;
      --format=*)
        FORMAT="${1#--format=}"
        shift
        ;;
      -h|--help)
        cat <<'EOF'
Usage: list-agents.sh [--harness=auto|claude|opencode|codex|all] [--format=json]

Enumerates installed agents/skills across known harnesses (Claude Code,
OpenCode, Codex) and prints a JSON array of AgentInventoryEntry records.

Options:
  --harness=NAME   Restrict enumeration. `auto` (default) detects the running
                   harness; `all` enumerates all three.
  --format=json    Output format. Only `json` is supported in v1.

Env:
  MAESTRO_QUIET=1  Suppress stderr progress lines.

Exit:
  0  success
  1  fatal error
  2  invalid CLI flag
EOF
        exit 0
        ;;
      *)
        printf 'unknown flag: %s\n' "$1" >&2
        exit 2
        ;;
    esac
  done

  # Validate --harness value.
  case "$HARNESS" in
    auto|claude|opencode|codex|all) ;;
    *)
      printf 'unknown flag: --harness=%s\n' "$HARNESS" >&2
      exit 2
      ;;
  esac

  # Validate --format value (only json in v1).
  if [[ "$FORMAT" != "json" ]]; then
    printf 'unknown flag: --format=%s\n' "$FORMAT" >&2
    exit 2
  fi
}

# ----------------------------------------------------------------------------
# detect_harness — echo the name of the harness we're running under.
#
# Strategy (v1):
#   1. Check `which` for each known binary.
#   2. Check for project-local dir presence (.claude/, .opencode/, .codex/).
#   3. If exactly one hit: echo it.
#   4. If multiple hits: prefer claude > opencode > codex (matches
#      KnownAgentDirs ordering in cmd/maestro-cli/pkg/agents/detect.go).
#   5. If no hits: echo `unknown` (caller routes to all stubs).
#
# Reserved for future use (NOT consulted in v1):
#   $CLAUDE_CODE, $OPENCODE, $CODEX_RUNTIME — downstream callers may set these
#   to force a harness. T00x (TBD) will wire them in if needed.
# ----------------------------------------------------------------------------
detect_harness() {
  local has_claude=0 has_opencode=0 has_codex=0

  command -v claude   >/dev/null 2>&1 && has_claude=1
  command -v opencode >/dev/null 2>&1 && has_opencode=1
  command -v codex    >/dev/null 2>&1 && has_codex=1

  [[ -d ".claude"   ]] && has_claude=1
  [[ -d ".opencode" ]] && has_opencode=1
  [[ -d ".codex"    ]] && has_codex=1

  # Preference order: claude > opencode > codex.
  if   [[ $has_claude   -eq 1 ]]; then echo "claude"
  elif [[ $has_opencode -eq 1 ]]; then echo "opencode"
  elif [[ $has_codex    -eq 1 ]]; then echo "codex"
  else echo "unknown"
  fi
}

# ============================================================================
# Inference helpers — infer_stacks / infer_intent
#
# Pure bash functions that derive stack tags and intent from an agent's
# `name` + `description`. Used by list_claude/list_opencode/list_codex
# (T002–T004) when an agent's frontmatter does not declare them explicitly.
#
# Pattern reference:
#   .maestro/specs/060-improve-maestro-select-best-agent-each/research/pattern-catalog.md
#   — Pattern 6 (keyword-match heuristics for stack/intent inference)
#
# Pitfall reference:
#   .maestro/specs/060-improve-maestro-select-best-agent-each/research/pitfall-register.md
#   — P-13: substring matching on bare keywords causes false positives
#     (e.g. description "this agent is pretty good" matches `py`). All
#     keyword matching MUST use word boundaries.
#
# Word-boundary mechanism: `grep -wE` against a here-string. Chosen because:
#   1. POSIX-portable across macOS BSD and Linux GNU userland (the bash `=~`
#      `[[:<:]]`/`[[:>:]]` BSD bracket classes are NOT supported on GNU, and
#      `\b`/`\<`/`\>` is a GNU-ism not in BSD ERE).
#   2. `-w` treats `[A-Za-z0-9_]` boundaries the same way for both userlands.
#   3. No python dependency for this hot path; helpers stay pure-bash + grep.
#
# Both functions are pure: no side effects, no global state writes, idempotent.
# ============================================================================

# ----------------------------------------------------------------------------
# _word_match <haystack> <pipe-separated-alternatives>
# Returns 0 if any alternative matches `haystack` as a whole word; else 1.
# Internal helper — not part of the public surface.
# ----------------------------------------------------------------------------
_word_match() {
  local haystack="$1"
  local pattern="$2"
  # `grep -w` needs ERE alternation wrapped or it works as-is with -E; the
  # critical bit is `-w` which anchors each alternative on word boundaries.
  printf '%s' "$haystack" | grep -qwE -- "$pattern"
}

# ----------------------------------------------------------------------------
# infer_stacks <name> <description>
#
# Emits a compact JSON array of stack tags to stdout. Combines name +
# description into a lowercased haystack and matches against word-boundary
# keyword sets. Emits ["*"] (wildcard sentinel) when no specific stack
# matches — generic agents are usable on any task.
#
# Stack mapping (all word-boundary):
#   go    : go | golang
#   ts    : ts | typescript           (also emits tsx)
#   tsx   : tsx | react | frontend    (also emits ts)
#   js    : js | javascript
#   py    : py | python | pydantic | pytest
#   rust  : rust | cargo | tauri
#   sql   : sql | clickhouse | postgres | database
# ----------------------------------------------------------------------------
infer_stacks() {
  local name="${1:-}"
  local description="${2:-}"
  # Lowercase via tr (portable; bash 4 ${var,,} not available on macOS bash 3).
  local haystack
  haystack="$(printf '%s %s' "$name" "$description" | tr '[:upper:]' '[:lower:]')"

  local -a stacks=()

  if _word_match "$haystack" 'go|golang'; then
    stacks+=("go")
  fi

  # ts / tsx are coupled: typescript implies tsx-capable, react/tsx implies ts.
  local has_ts=0 has_tsx=0
  if _word_match "$haystack" 'ts|typescript'; then
    has_ts=1
    has_tsx=1
  fi
  if _word_match "$haystack" 'tsx|react|frontend'; then
    has_ts=1
    has_tsx=1
  fi
  [[ $has_ts  -eq 1 ]] && stacks+=("ts")
  [[ $has_tsx -eq 1 ]] && stacks+=("tsx")

  if _word_match "$haystack" 'js|javascript'; then
    stacks+=("js")
  fi

  if _word_match "$haystack" 'py|python|pydantic|pytest'; then
    stacks+=("py")
  fi

  if _word_match "$haystack" 'rust|cargo|tauri'; then
    stacks+=("rust")
  fi

  if _word_match "$haystack" 'sql|clickhouse|postgres|database'; then
    stacks+=("sql")
  fi

  if [[ ${#stacks[@]} -eq 0 ]]; then
    printf '["*"]'
    return 0
  fi

  # Build compact JSON array via jq, preserving order, deduping.
  # `--args` forwards each element as a string positional ($ARGS.positional).
  jq -cn --args '$ARGS.positional | unique_by(.) as $u | $ARGS.positional | map(select(. as $x | $u | index($x) != null)) | unique' "${stacks[@]}"
}

# ----------------------------------------------------------------------------
# infer_intent <name> <description> [mode_hint]
#
# Emits a single intent tag — one of "impl" | "review" | "either" — to stdout.
# Rules apply in order; first match wins.
#
#   1. mode_hint == "subagent"          → review
#   2. mode_hint == "primary"           → impl
#   3. name suffix "-reviewer" OR
#      name prefix  "review-"           → review
#   4. name contains "-reviewer-" segment OR
#      description contains phrase
#      "code review" or "reviewer"      → review
#   5. description or name contains
#      expert | developer | engineer |
#      author  | builder   | implementer → impl
#   6. default                          → either
# ----------------------------------------------------------------------------
infer_intent() {
  local name="${1:-}"
  local description="${2:-}"
  local mode_hint="${3:-}"

  # Rules 1 & 2 — explicit mode hint from harness frontmatter wins.
  case "$mode_hint" in
    subagent) printf '%s' "review"; return 0 ;;
    primary)  printf '%s' "impl";   return 0 ;;
  esac

  local name_lc desc_lc
  name_lc="$(printf '%s' "$name"        | tr '[:upper:]' '[:lower:]')"
  desc_lc="$(printf '%s' "$description" | tr '[:upper:]' '[:lower:]')"

  # Rule 3 — name suffix / prefix.
  if [[ "$name_lc" == *-reviewer ]] || [[ "$name_lc" == review-* ]]; then
    printf '%s' "review"
    return 0
  fi

  # Rule 4 — embedded reviewer segment or review phrasing in description.
  if [[ "$name_lc" == *-reviewer-* ]] \
     || [[ "$desc_lc" == *"code review"* ]] \
     || [[ "$desc_lc" == *"reviewer"* ]]; then
    printf '%s' "review"
    return 0
  fi

  # Rule 5 — implementation-coded vocabulary in name OR description.
  local impl_haystack="$name_lc $desc_lc"
  if _word_match "$impl_haystack" 'expert|developer|engineer|author|builder|implementer'; then
    printf '%s' "impl"
    return 0
  fi

  # Rule 6 — default.
  printf '%s' "either"
}

# ----------------------------------------------------------------------------
# Per-runtime stubs — replaced in T002–T004. Each must echo a JSON array.
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# _claude_parse_frontmatter <file>
#
# Read YAML frontmatter (between leading `---` lines) and emit two lines:
#   <name>
#   <description>
# A field that is missing yields an empty line. The description is normalized
# to its first sentence (split on `. `, max ~140 chars). Trailing whitespace
# and surrounding quotes are stripped.
#
# Implementation: awk for portability (works on macOS + Linux without python).
# Only `name:` and `description:` keys are recognized; any other keys are
# ignored. Multi-line YAML (block scalars) is NOT supported — Claude Code
# convention is single-line values, which is sufficient for v1.
#
# On YAML parse error (e.g. no frontmatter at all), emit two empty lines so
# callers can fall back to the filename stem.
# ----------------------------------------------------------------------------
_claude_parse_frontmatter() {
  local file="$1"
  awk '
    BEGIN { in_fm = 0; seen_open = 0; name = ""; desc = "" }
    /^---[[:space:]]*$/ {
      if (!seen_open) { seen_open = 1; in_fm = 1; next }
      else if (in_fm) { in_fm = 0; exit }
    }
    in_fm {
      # Match `key: value` with optional whitespace.
      if (match($0, /^[[:space:]]*name[[:space:]]*:[[:space:]]*/)) {
        v = substr($0, RLENGTH + 1)
        # Strip surrounding single/double quotes.
        sub(/^"/, "", v); sub(/"$/, "", v)
        sub(/^'\''/, "", v); sub(/'\''$/, "", v)
        # Strip trailing whitespace.
        sub(/[[:space:]]+$/, "", v)
        name = v
      } else if (match($0, /^[[:space:]]*description[[:space:]]*:[[:space:]]*/)) {
        v = substr($0, RLENGTH + 1)
        sub(/^"/, "", v); sub(/"$/, "", v)
        sub(/^'\''/, "", v); sub(/'\''$/, "", v)
        sub(/[[:space:]]+$/, "", v)
        desc = v
      }
    }
    END { print name; print desc }
  ' "$file" 2>/dev/null || { printf '\n\n'; return 0; }
}

# ----------------------------------------------------------------------------
# _first_sentence <text>
# Emit the first sentence of `text`, capped at ~140 chars. Splits on `. `.
# ----------------------------------------------------------------------------
_first_sentence() {
  local text="$1"
  # Take everything up to the first ". " (period + space).
  local first="${text%%. *}"
  # Cap at 140 chars.
  if [[ ${#first} -gt 140 ]]; then
    first="${first:0:140}"
  fi
  printf '%s' "$first"
}

# ----------------------------------------------------------------------------
# _claude_emit_entry <name> <description> <kind> <source>
# Emit a single AgentInventoryEntry JSON object to stdout (compact, one line).
# Calls infer_intent and infer_stacks (T002 helpers); for builtins the caller
# substitutes stacks=["*"] before invoking by passing kind="builtin".
# ----------------------------------------------------------------------------
_claude_emit_entry() {
  local name="$1"
  local description="$2"
  local kind="$3"
  local source_path="$4"

  local intent stacks_json desc_short
  intent="$(infer_intent "$name" "$description")"
  if [[ "$kind" == "builtin" ]]; then
    stacks_json='["*"]'
  else
    stacks_json="$(infer_stacks "$name" "$description")"
  fi
  desc_short="$(_first_sentence "$description")"

  jq -cn \
    --arg name "$name" \
    --arg harness "claude" \
    --arg kind "$kind" \
    --arg intent "$intent" \
    --argjson stacks "$stacks_json" \
    --arg source "$source_path" \
    --arg description "$desc_short" \
    '{name: $name, harness: $harness, kind: $kind, intent: $intent, stacks: $stacks, source: $source, description: $description}'
}

# ----------------------------------------------------------------------------
# list_claude — enumerate Claude Code subagents, skills, and built-ins.
#
# Walk order (project-priority, name-collision dedup):
#   1. ${CWD}/.claude/agents/*.md           kind=subagent  (project)
#   2. ${HOME}/.claude/agents/*.md          kind=subagent  (user — skipped on collision)
#   3. ${CWD}/.claude/skills/*/SKILL.md     kind=skill     (project)
#   4. ${HOME}/.claude/skills/*/SKILL.md    kind=skill     (user — skipped on collision)
# Then append five hard-coded built-ins (kind=builtin).
#
# Optional `claude agents` hint:
#   When the `claude` binary is on PATH, we attempt `claude agents` as a
#   non-authoritative HINT. Any parse failure or non-zero exit is silently
#   ignored — the directory walk above is the source of truth (P-2 mitigation).
#
# Determinism: entries are sorted by (kind, name) — `builtin` < `subagent` <
# `skill`, then alphabetical name — before emission, so repeated runs on an
# unchanged filesystem produce byte-identical output.
# ----------------------------------------------------------------------------
list_claude() {
  local cwd="${PWD}"
  local home="${HOME:-}"
  local -a entries=()
  # `seen_names` is a poor-man's set: we look it up via substring match on a
  # delimited string. Names cannot contain newlines so this is safe.
  local seen_names=$'\n'

  # Helper: append entry if name not yet seen. $1=name $2=desc $3=kind $4=source
  _add_entry_if_new() {
    local n="$1" d="$2" k="$3" s="$4"
    [[ -z "$n" ]] && return 0
    if [[ "$seen_names" == *$'\n'"$n"$'\n'* ]]; then
      return 0
    fi
    seen_names+="$n"$'\n'
    entries+=("$(_claude_emit_entry "$n" "$d" "$k" "$s")")
  }

  # Walk a single root directory for a given kind, matching files via `find`.
  # _walk_dir <kind> <root_dir> <leaf_glob> <maxdepth>
  #   kind="subagent": root=<.../agents>,    leaf="*.md",    maxdepth=1 (flat)
  #   kind="skill":    root=<.../skills>,    leaf="SKILL.md", maxdepth=2 (nested)
  # Sorted by `find ... | sort` for determinism. Missing roots are silently
  # skipped (treat-as-empty per contract failure-modes table).
  _walk_dir() {
    local kind="$1"
    local root="$2"
    local leaf="$3"
    local maxdepth="$4"
    [[ -d "$root" ]] || return 0
    local file
    while IFS= read -r file; do
      [[ -f "$file" ]] || continue
      local fm name desc
      fm="$(_claude_parse_frontmatter "$file")"
      name="$(printf '%s\n' "$fm" | sed -n '1p')"
      desc="$(printf '%s\n' "$fm" | sed -n '2p')"
      if [[ -z "$name" ]]; then
        # Fall back to filename stem (without .md, without SKILL).
        if [[ "$kind" == "skill" ]]; then
          # SKILL.md lives in skills/<dir>/SKILL.md → stem = parent dir name.
          name="$(basename "$(dirname "$file")")"
        else
          name="$(basename "$file" .md)"
        fi
      fi
      _add_entry_if_new "$name" "$desc" "$kind" "$file"
    done < <(find "$root" -maxdepth "$maxdepth" -name "$leaf" -type f 2>/dev/null | sort)
  }

  # Project-scope first (wins on collision), then user-scope.
  _walk_dir "subagent" "${cwd}/.claude/agents"  "*.md"     1
  if [[ -n "$home" && "$home" != "$cwd" ]]; then
    _walk_dir "subagent" "${home}/.claude/agents"  "*.md"     1
  fi
  _walk_dir "skill"    "${cwd}/.claude/skills"  "SKILL.md" 2
  if [[ -n "$home" && "$home" != "$cwd" ]]; then
    _walk_dir "skill"    "${home}/.claude/skills"  "SKILL.md" 2
  fi

  # Optional hint from `claude agents` — non-authoritative. Any parse failure
  # is silently ignored; the directory walk above remains the source of truth.
  # We only consume names here, not metadata, and we only ADD names not yet
  # seen — never override what we discovered on disk.
  if command -v claude >/dev/null 2>&1; then
    local hint_output
    if hint_output="$(claude agents 2>/dev/null)"; then
      # Best-effort: extract bare-word identifiers from each line. We do NOT
      # treat these as authoritative metadata; only as a name hint. If a name
      # is not already seen (and isn't a built-in), we skip it — without
      # frontmatter we can't infer stacks/intent reliably. Reserved for a
      # future task that wires `claude agents --json` if/when it exists.
      :
    fi
  fi

  # Hard-coded built-ins. P-7: `claude agents` does not list these but they
  # are always available in Claude Code, so we append unconditionally.
  _add_entry_if_new "Explore"           "Read-only research subagent"          "builtin" "builtin"
  _add_entry_if_new "Plan"              "Plan-mode research subagent"          "builtin" "builtin"
  _add_entry_if_new "general-purpose"   "General-purpose multi-step agent"     "builtin" "builtin"
  _add_entry_if_new "statusline-setup"  "Invoked when running /statusline"     "builtin" "builtin"
  _add_entry_if_new "Claude Code Guide" "Handles Claude Code questions"        "builtin" "builtin"

  # Emit a deterministic sorted JSON array.
  # Sort key: kind rank (builtin=0, subagent=1, skill=2), then name (alpha).
  if [[ ${#entries[@]} -eq 0 ]]; then
    printf '[]'
    return 0
  fi
  printf '%s\n' "${entries[@]}" \
    | jq -s '
        def kind_rank: if .kind == "builtin" then 0
                       elif .kind == "subagent" then 1
                       elif .kind == "skill" then 2
                       else 3 end;
        sort_by(kind_rank, .name)
      '
}

# ----------------------------------------------------------------------------
# _opencode_parse_mode <file>
#
# Extract just the `mode:` value from YAML frontmatter (between leading `---`
# lines). Returns one of "subagent" | "primary" | "all" | "" (empty when the
# field is missing or the file has no frontmatter).
#
# Why a separate extractor (vs. extending _claude_parse_frontmatter from T003):
#   _claude_parse_frontmatter has a fixed two-line output contract (name then
#   description) consumed by list_claude. Adding a third line would either
#   require changing every caller in T002/T003 or risk subtle parse drift.
#   A dedicated single-field extractor keeps T003's helper stable while still
#   reusing it for name/description below.
# ----------------------------------------------------------------------------
_opencode_parse_mode() {
  local file="$1"
  awk '
    BEGIN { in_fm = 0; seen_open = 0; mode = "" }
    /^---[[:space:]]*$/ {
      if (!seen_open) { seen_open = 1; in_fm = 1; next }
      else if (in_fm) { in_fm = 0; exit }
    }
    in_fm {
      if (match($0, /^[[:space:]]*mode[[:space:]]*:[[:space:]]*/)) {
        v = substr($0, RLENGTH + 1)
        sub(/^"/, "", v); sub(/"$/, "", v)
        sub(/^'\''/, "", v); sub(/'\''$/, "", v)
        sub(/[[:space:]]+$/, "", v)
        mode = v
      }
    }
    END { print mode }
  ' "$file" 2>/dev/null || { printf '\n'; return 0; }
}

# ----------------------------------------------------------------------------
# _opencode_emit_entry <name> <description> <kind> <source> <mode>
#
# Emit a single AgentInventoryEntry JSON object for an OpenCode agent/skill.
# Mirrors _claude_emit_entry but:
#   - harness="opencode"
#   - passes a mode_hint to infer_intent so that mode:subagent → "review",
#     mode:primary → "impl", and mode:all (or missing) falls through to
#     name/description heuristics.
# ----------------------------------------------------------------------------
_opencode_emit_entry() {
  local name="$1"
  local description="$2"
  local kind="$3"
  local source_path="$4"
  local mode="$5"

  # Translate OpenCode `mode` field → infer_intent mode_hint.
  # Only "subagent" and "primary" are meaningful hints; "all" (the OpenCode
  # default) and any unknown value fall through to heuristic inference.
  local mode_hint=""
  case "$mode" in
    subagent) mode_hint="subagent" ;;
    primary)  mode_hint="primary"  ;;
    *)        mode_hint=""         ;;
  esac

  local intent stacks_json desc_short
  intent="$(infer_intent "$name" "$description" "$mode_hint")"
  stacks_json="$(infer_stacks "$name" "$description")"
  desc_short="$(_first_sentence "$description")"

  jq -cn \
    --arg name "$name" \
    --arg harness "opencode" \
    --arg kind "$kind" \
    --arg intent "$intent" \
    --argjson stacks "$stacks_json" \
    --arg source "$source_path" \
    --arg description "$desc_short" \
    '{name: $name, harness: $harness, kind: $kind, intent: $intent, stacks: $stacks, source: $source, description: $description}'
}

# ----------------------------------------------------------------------------
# list_opencode — enumerate OpenCode subagents and skills.
#
# Walk order (project-priority, name-collision dedup):
#   1. ${CWD}/.opencode/agents/*.md          kind=subagent  (project, plural)
#   2. ${CWD}/.opencode/agent/*.md           kind=subagent  (project, singular back-compat)
#   3. ${HOME}/.config/opencode/agents/*.md  kind=subagent  (user)
#   4. ${CWD}/.opencode/skills/*/SKILL.md    kind=skill     (project)
#   5. ${HOME}/.config/opencode/skills/*/SKILL.md  kind=skill (user)
#
# YAML frontmatter parsing reuses the T003 helpers `_claude_parse_frontmatter`
# (name + description) and `_first_sentence`. The OpenCode-specific `mode:`
# field is read via the dedicated `_opencode_parse_mode` extractor and forwarded
# as a mode_hint to `infer_intent` (Pattern 6 — explicit mode wins over
# name/description heuristics).
#
# Determinism: entries are sorted by (kind, name) — `subagent` < `skill`,
# alphabetical within — so repeated runs on an unchanged filesystem produce
# byte-identical output.
# ----------------------------------------------------------------------------
list_opencode() {
  local cwd="${PWD}"
  local home="${HOME:-}"
  local -a entries=()
  # Poor-man's set: newline-delimited names, lookup via substring match. Names
  # cannot contain newlines so this is safe.
  local seen_names=$'\n'

  # Helper: append entry if name not yet seen. Project sources are walked
  # before user sources, so project always wins on collision.
  # $1=name $2=desc $3=kind $4=source $5=mode
  _add_oc_entry_if_new() {
    local n="$1" d="$2" k="$3" s="$4" m="$5"
    [[ -z "$n" ]] && return 0
    if [[ "$seen_names" == *$'\n'"$n"$'\n'* ]]; then
      return 0
    fi
    seen_names+="$n"$'\n'
    entries+=("$(_opencode_emit_entry "$n" "$d" "$k" "$s" "$m")")
  }

  # Walk a single root directory for a given kind.
  # _walk_oc_dir <kind> <root_dir> <leaf_glob> <maxdepth>
  #   kind="subagent": root=<.../agents> or <.../agent>, leaf="*.md", maxdepth=1
  #   kind="skill":    root=<.../skills>,                 leaf="SKILL.md", maxdepth=2
  # Sorted by `find ... | sort` for determinism. Missing roots are silently
  # skipped (treat-as-empty per contract failure-modes table).
  _walk_oc_dir() {
    local kind="$1"
    local root="$2"
    local leaf="$3"
    local maxdepth="$4"
    [[ -d "$root" ]] || return 0
    local file
    while IFS= read -r file; do
      [[ -f "$file" ]] || continue
      local fm name desc mode
      fm="$(_claude_parse_frontmatter "$file")"
      name="$(printf '%s\n' "$fm" | sed -n '1p')"
      desc="$(printf '%s\n' "$fm" | sed -n '2p')"
      mode="$(_opencode_parse_mode "$file")"
      if [[ -z "$name" ]]; then
        # Fall back to filename stem (without .md, without SKILL).
        if [[ "$kind" == "skill" ]]; then
          name="$(basename "$(dirname "$file")")"
        else
          name="$(basename "$file" .md)"
        fi
      fi
      _add_oc_entry_if_new "$name" "$desc" "$kind" "$file" "$mode"
    done < <(find "$root" -maxdepth "$maxdepth" -name "$leaf" -type f 2>/dev/null | sort)
  }

  # Project-scope (plural agents/ then singular agent/ for back-compat),
  # then user-scope under ~/.config/opencode/.
  _walk_oc_dir "subagent" "${cwd}/.opencode/agents" "*.md" 1
  _walk_oc_dir "subagent" "${cwd}/.opencode/agent"  "*.md" 1
  if [[ -n "$home" && "$home" != "$cwd" ]]; then
    _walk_oc_dir "subagent" "${home}/.config/opencode/agents" "*.md" 1
  fi
  _walk_oc_dir "skill" "${cwd}/.opencode/skills" "SKILL.md" 2
  if [[ -n "$home" && "$home" != "$cwd" ]]; then
    _walk_oc_dir "skill" "${home}/.config/opencode/skills" "SKILL.md" 2
  fi

  # Emit a deterministic sorted JSON array.
  # Sort key: kind rank (subagent=0, skill=1), then name (alpha).
  if [[ ${#entries[@]} -eq 0 ]]; then
    printf '[]'
    return 0
  fi
  printf '%s\n' "${entries[@]}" \
    | jq -s '
        def kind_rank: if .kind == "subagent" then 0
                       elif .kind == "skill" then 1
                       else 2 end;
        sort_by(kind_rank, .name)
      '
}

# ----------------------------------------------------------------------------
# _codex_check_python — verify python3 + tomllib are available.
#
# Codex subagent files are TOML, and TOML cannot be parsed reliably with awk
# (multi-line strings, arrays of tables, escapes). We require python3 >= 3.11
# so we can use the stdlib `tomllib` module (P-10 mitigation: avoids the
# external `tomlq` / `dasel` dependency).
#
# Returns 0 if usable, exits 1 otherwise.
# ----------------------------------------------------------------------------
_codex_check_python() {
  # If already resolved, skip.
  if [[ -n "${MAESTRO_PYTHON:-}" ]]; then
    return 0
  fi
  # Scan candidates: prefer the highest minor we can find with tomllib (>=3.11).
  # macOS ships /usr/bin/python3 = 3.9 (no tomllib); Homebrew typically installs
  # python3.11+ at /opt/homebrew/bin/python3.NN. Try common names.
  local candidate
  for candidate in python3.14 python3.13 python3.12 python3.11 python3; do
    if command -v "$candidate" >/dev/null 2>&1 && \
       "$candidate" -c 'import tomllib' >/dev/null 2>&1; then
      MAESTRO_PYTHON="$candidate"
      export MAESTRO_PYTHON
      return 0
    fi
  done
  printf 'python3 with tomllib (3.11+) required for Codex TOML parsing\n' >&2
  exit 1
}

# ----------------------------------------------------------------------------
# _codex_parse_toml <file>
#
# Parse a Codex subagent TOML file via python3+tomllib and emit two lines on
# stdout: <name>\n<description>. On parse failure, exit non-zero (caller logs
# and skips). Empty / missing fields produce empty lines so callers can fall
# back to the filename stem.
#
# We pass the path as argv[1] (NOT interpolated into the program text) to keep
# the heredoc safe against arbitrary path characters.
# ----------------------------------------------------------------------------
_codex_parse_toml() {
  local file="$1"
  "${MAESTRO_PYTHON:-python3}" - "$file" <<'PY'
import sys, tomllib
path = sys.argv[1]
try:
    with open(path, "rb") as f:
        data = tomllib.load(f)
except Exception as e:
    sys.stderr.write(f"codex: failed to parse {path}: {e}\n")
    sys.exit(2)
name = data.get("name", "") or ""
desc = data.get("description", "") or ""
# Single-line each — strip embedded newlines so awk-style line-pair consumers
# don't get confused.
print(str(name).replace("\n", " ").strip())
print(str(desc).replace("\n", " ").strip())
PY
}

# ----------------------------------------------------------------------------
# _codex_canonicalize <path>
#
# Emit a canonical absolute path (symlinks resolved). Used to make path
# comparisons in the skill enable filter robust against macOS-style symlinks
# (e.g. `/var → /private/var`) where `find` produces one form and the user's
# `~/.codex/config.toml` may contain the other. Falls back to the original
# path on any error (e.g. file removed mid-run).
# ----------------------------------------------------------------------------
_codex_canonicalize() {
  local p="$1"
  "${MAESTRO_PYTHON:-python3}" - "$p" <<'PY' 2>/dev/null || printf '%s' "$p"
import os, sys
p = sys.argv[1]
try:
    print(os.path.realpath(p))
except Exception:
    print(p)
PY
}

# ----------------------------------------------------------------------------
# _codex_disabled_skills — emit newline-delimited canonical absolute paths of
# skills explicitly marked `enabled = false` in ~/.codex/config.toml.
#
# Reads `[[skills.config]]` array-of-tables entries with `path` + `enabled`.
# Each disabled path is run through `os.path.realpath` so it round-trips with
# `find`-emitted paths regardless of symlink prefix differences (notably
# macOS `/var` vs `/private/var`).
#
# A malformed config is non-fatal: log to stderr (when MAESTRO_QUIET unset),
# emit nothing, and the caller proceeds with NO filtering (P-8 graceful
# degradation per contract failure-modes table).
# ----------------------------------------------------------------------------
_codex_disabled_skills() {
  local home="${HOME:-}"
  local cfg="${home}/.codex/config.toml"
  [[ -f "$cfg" ]] || return 0
  "${MAESTRO_PYTHON:-python3}" - "$cfg" <<'PY' 2> >(while IFS= read -r line; do
    if [[ "${MAESTRO_QUIET:-0}" != "1" ]]; then
      printf 'codex: %s\n' "$line" >&2
    fi
  done)
import os, sys, tomllib
path = sys.argv[1]
try:
    with open(path, "rb") as f:
        data = tomllib.load(f)
except Exception as e:
    sys.stderr.write(f"warning: ~/.codex/config.toml malformed ({e}); skipping skill filter\n")
    sys.exit(0)
skills = data.get("skills", {})
configs = skills.get("config", []) if isinstance(skills, dict) else []
if not isinstance(configs, list):
    sys.exit(0)
for entry in configs:
    if not isinstance(entry, dict):
        continue
    if entry.get("enabled") is False:
        p = entry.get("path", "")
        if p:
            try:
                print(os.path.realpath(p))
            except Exception:
                print(p)
PY
}

# ----------------------------------------------------------------------------
# _codex_emit_entry <name> <description> <kind> <source>
#
# Emit a single AgentInventoryEntry JSON object for a Codex agent/skill.
# Mirrors _claude_emit_entry but harness="codex". No mode_hint — Codex TOML
# subagents don't carry an explicit mode field; we let infer_intent fall
# through to name/description heuristics.
# ----------------------------------------------------------------------------
_codex_emit_entry() {
  local name="$1"
  local description="$2"
  local kind="$3"
  local source_path="$4"

  local intent stacks_json desc_short
  intent="$(infer_intent "$name" "$description")"
  stacks_json="$(infer_stacks "$name" "$description")"
  desc_short="$(_first_sentence "$description")"

  jq -cn \
    --arg name "$name" \
    --arg harness "codex" \
    --arg kind "$kind" \
    --arg intent "$intent" \
    --argjson stacks "$stacks_json" \
    --arg source "$source_path" \
    --arg description "$desc_short" \
    '{name: $name, harness: $harness, kind: $kind, intent: $intent, stacks: $stacks, source: $source, description: $description}'
}

# ----------------------------------------------------------------------------
# list_codex — enumerate Codex subagents (TOML) and skills (Markdown).
#
# Walk order (project-priority, name-collision dedup):
#   Subagents (TOML):
#     1. ${CWD}/.codex/agents/*.toml          kind=subagent (project)
#     2. ${HOME}/.codex/agents/*.toml         kind=subagent (user)
#   Skills (SKILL.md, multi-source per Codex docs — P-4 mitigation):
#     3. ${CWD}/.agents/skills/*/SKILL.md          kind=skill (project)
#     4. ${CWD}/../.agents/skills/*/SKILL.md       kind=skill (parent dir)
#     5. ${REPO_ROOT}/.agents/skills/*/SKILL.md    kind=skill (git toplevel)
#     6. ${HOME}/.agents/skills/*/SKILL.md         kind=skill (user)
#     7. /etc/codex/skills/*/SKILL.md              kind=skill (admin)
#
# Skill enable filter (P-8 mitigation):
#   Read ~/.codex/config.toml `[[skills.config]]` entries; any skill whose
#   absolute SKILL.md path matches an entry with `enabled = false` is
#   filtered OUT entirely (does not appear in output).
#
# TOML parse via python3 + tomllib (>= 3.11). _codex_check_python exits 1 if
# the runtime is unavailable (P-10 mitigation: stdlib only, no external CLI).
# Per-file parse failures are logged to stderr (suppressed when
# MAESTRO_QUIET=1) and the file is skipped, keeping the run going.
#
# Determinism: entries are sorted by (kind, name) — `subagent` < `skill`,
# alphabetical within — so repeated runs on an unchanged filesystem produce
# byte-identical output.
# ----------------------------------------------------------------------------
list_codex() {
  _codex_check_python

  local cwd="${PWD}"
  local home="${HOME:-}"
  local -a entries=()
  # Poor-man's set: newline-delimited names, lookup via substring match.
  local seen_names=$'\n'

  # Build set of disabled skill paths (newline-delimited; absolute paths only).
  local disabled
  disabled=$'\n'"$(_codex_disabled_skills)"$'\n'

  # Helper: append entry if name not yet seen. Project sources are walked
  # before user sources, so project always wins on collision. For skills we
  # also drop entries whose source path matches the disabled set.
  # $1=name $2=desc $3=kind $4=source
  _add_codex_entry_if_new() {
    local n="$1" d="$2" k="$3" s="$4"
    [[ -z "$n" ]] && return 0
    if [[ "$seen_names" == *$'\n'"$n"$'\n'* ]]; then
      return 0
    fi
    if [[ "$k" == "skill" ]]; then
      # P-8: filtered out by ~/.codex/config.toml. Canonicalize the source path
      # before matching since _codex_disabled_skills emits realpath-resolved
      # paths and `find` may return un-resolved forms (notably macOS
      # /var → /private/var). Match against either form to be safe.
      local s_canon
      s_canon="$(_codex_canonicalize "$s")"
      if [[ "$disabled" == *$'\n'"$s"$'\n'* || "$disabled" == *$'\n'"$s_canon"$'\n'* ]]; then
        return 0
      fi
    fi
    seen_names+="$n"$'\n'
    entries+=("$(_codex_emit_entry "$n" "$d" "$k" "$s")")
  }

  # ---- Walk TOML subagent dirs ----
  # _walk_codex_subagents <root>
  _walk_codex_subagents() {
    local root="$1"
    [[ -d "$root" ]] || return 0
    local file
    while IFS= read -r file; do
      [[ -f "$file" ]] || continue
      local parsed name desc
      if ! parsed="$(_codex_parse_toml "$file" 2>/dev/null)"; then
        log "codex: skipped malformed TOML: $file"
        continue
      fi
      name="$(printf '%s\n' "$parsed" | sed -n '1p')"
      desc="$(printf '%s\n' "$parsed" | sed -n '2p')"
      if [[ -z "$name" ]]; then
        name="$(basename "$file" .toml)"
      fi
      _add_codex_entry_if_new "$name" "$desc" "subagent" "$file"
    done < <(find "$root" -maxdepth 1 -name '*.toml' -type f 2>/dev/null | sort)
  }

  _walk_codex_subagents "${cwd}/.codex/agents"
  if [[ -n "$home" && "$home" != "$cwd" ]]; then
    _walk_codex_subagents "${home}/.codex/agents"
  fi

  # ---- Walk SKILL.md skill dirs (multi-source, P-4) ----
  # _walk_codex_skills <root>
  _walk_codex_skills() {
    local root="$1"
    [[ -d "$root" ]] || return 0
    local file
    while IFS= read -r file; do
      [[ -f "$file" ]] || continue
      local fm name desc
      fm="$(_claude_parse_frontmatter "$file")"
      name="$(printf '%s\n' "$fm" | sed -n '1p')"
      desc="$(printf '%s\n' "$fm" | sed -n '2p')"
      if [[ -z "$name" ]]; then
        name="$(basename "$(dirname "$file")")"
      fi
      _add_codex_entry_if_new "$name" "$desc" "skill" "$file"
    done < <(find "$root" -maxdepth 2 -name 'SKILL.md' -type f 2>/dev/null | sort)
  }

  _walk_codex_skills "${cwd}/.agents/skills"
  # Parent directory (one above CWD).
  local parent_skills
  parent_skills="$(cd "$cwd/.." 2>/dev/null && pwd -P)/.agents/skills"
  if [[ -n "$parent_skills" && "$parent_skills" != "${cwd}/.agents/skills" ]]; then
    _walk_codex_skills "$parent_skills"
  fi
  # Git toplevel (only when invoked inside a git working tree).
  local repo_root
  if repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$repo_root" ]]; then
    if [[ "$repo_root" != "$cwd" && "${repo_root}/.agents/skills" != "$parent_skills" ]]; then
      _walk_codex_skills "${repo_root}/.agents/skills"
    fi
  fi
  if [[ -n "$home" && "$home" != "$cwd" ]]; then
    _walk_codex_skills "${home}/.agents/skills"
  fi
  _walk_codex_skills "/etc/codex/skills"

  # Emit a deterministic sorted JSON array.
  # Sort key: kind rank (subagent=0, skill=1), then name (alpha).
  if [[ ${#entries[@]} -eq 0 ]]; then
    printf '[]'
    return 0
  fi
  printf '%s\n' "${entries[@]}" \
    | jq -s '
        def kind_rank: if .kind == "subagent" then 0
                       elif .kind == "skill" then 1
                       else 2 end;
        sort_by(kind_rank, .name)
      '
}

# ----------------------------------------------------------------------------
# Dispatcher — route to one or more list_* functions and concatenate via jq.
# `jq -s 'add // []'` slurps the input arrays, concatenates, and falls back to
# `[]` when the result would be null (i.e. zero array inputs).
# ----------------------------------------------------------------------------
run_all() {
  { list_claude; list_opencode; list_codex; } | jq -s 'add // []'
}

# ----------------------------------------------------------------------------
# main — entry point invoked only when the script is executed directly.
# When sourced (e.g. for inline testing of infer_stacks / infer_intent), this
# function is defined but NOT called, leaving the parent shell side-effect-free.
# ----------------------------------------------------------------------------
main() {
  _parse_args "$@"

  case "$HARNESS" in
    claude)
      list_claude   | jq -s 'add // []'
      ;;
    opencode)
      list_opencode | jq -s 'add // []'
      ;;
    codex)
      list_codex    | jq -s 'add // []'
      ;;
    all)
      run_all
      ;;
    auto)
      local detected
      detected="$(detect_harness)"
      case "$detected" in
        claude)   list_claude   | jq -s 'add // []' ;;
        opencode) list_opencode | jq -s 'add // []' ;;
        codex)    list_codex    | jq -s 'add // []' ;;
        unknown)  run_all ;;
      esac
      ;;
  esac
}

# Source-able guard: only execute when invoked directly, not when sourced.
# (BASH_SOURCE[0] equals $0 only when this file is the entry script.)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
