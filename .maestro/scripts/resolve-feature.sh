#!/usr/bin/env bash
# resolve-feature.sh — resolve which feature a command should act on, in one place.
#
# Six commands (specify/clarify/research/plan/tasks/implement) each repeated the same
# ~14-line "Resolving the feature ID (AI inference)" block. This script centralizes the
# DETERMINISTIC part of that inference and emits JSON; the command only has to surface the
# result (and, on a conflict, ask the user).
#
# Usage:
#   resolve-feature.sh [explicit_id_or_number]
#
# Resolution order:
#   1. Explicit arg — a feature id (070-slug) or bare number (070) → matched to a spec dir.
#   2. Recent state activity — most-recently-updated non-complete .maestro/state/*.json.
#   3. Current git branch — feat/NNN-... or NNN-... .
#   Empty feature dirs (spec.md missing or 0 bytes) are excluded from inference.
#
# Output (JSON, stdout):
#   {"feature_id":"...","spec_dir":".maestro/specs/...","branch":"feat/...",
#    "source":"explicit|state|branch|none","conflict":false,"conflict_with":null}
#   - source=none → no signals; the caller decides (specify: new feature; others: ask).
#   - conflict=true → state recency and branch disagree; the caller must ask which to use.
#
# Read-only. Requires jq.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo '{"error":"jq required"}'; exit 2; }

BASE="${MAESTRO_MAIN_REPO:-.}"
SPECS="$BASE/.maestro/specs"
STATE="$BASE/.maestro/state"
ARG="${1:-}"

emit() { # feature_id spec_dir branch source conflict conflict_with
  jq -n --arg id "$1" --arg dir "$2" --arg br "$3" --arg src "$4" \
        --argjson conf "${5:-false}" --arg cw "${6:-}" \
    '{feature_id:$id, spec_dir:$dir, branch:$br, source:$src, conflict:$conf,
      conflict_with:(if $cw=="" then null else $cw end)}'
}

# a feature dir is usable only if it has a non-empty spec.md
has_spec() { [ -s "$SPECS/$1/spec.md" ]; }
slug_to_branch() { echo "feat/${1#[0-9]*-}"; }   # feat/<slug> from NNN-slug

# --- 1. explicit ------------------------------------------------------------
if [ -n "$ARG" ]; then
  if [ -d "$SPECS/$ARG" ]; then
    emit "$ARG" "$SPECS/$ARG" "$(slug_to_branch "$ARG")" explicit; exit 0
  fi
  # bare number → first dir whose name starts with that (zero-padded) number
  num="$(printf '%03d' "$((10#$ARG))" 2>/dev/null || echo "$ARG")"
  match="$(ls -d "$SPECS/${num}-"*/ 2>/dev/null | head -1)"
  if [ -n "$match" ]; then
    fid="$(basename "$match")"; emit "$fid" "$SPECS/$fid" "$(slug_to_branch "$fid")" explicit; exit 0
  fi
  emit "$ARG" "$SPECS/$ARG" "$(slug_to_branch "$ARG")" explicit; exit 0
fi

# --- 2. recent state activity (most-recent non-complete) --------------------
state_fid=""
if [ -d "$STATE" ]; then
  # sort state files by updated_at desc, skip complete/cancelled, take first with a spec
  while IFS=$'\t' read -r _ fid; do
    [ -n "$fid" ] || continue
    has_spec "$fid" && { state_fid="$fid"; break; }
  done < <(
    for f in "$STATE"/*.json; do
      [ -f "$f" ] || continue
      st="$(jq -r '.stage // ""' "$f" 2>/dev/null)"
      if [ "$st" = "complete" ] || [ "$st" = "cancelled" ]; then continue; fi
      ua="$(jq -r '.updated_at // ""' "$f" 2>/dev/null)"
      printf '%s\t%s\n' "$ua" "$(basename "$f" .json)"
    done | sort -r
  )
fi

# --- 3. current git branch --------------------------------------------------
branch_fid=""
cur_branch="$(git -C "$BASE" branch --show-current 2>/dev/null || echo "")"
case "$cur_branch" in
  feat/*) cand="${cur_branch#feat/}";;
  *) cand="$cur_branch";;
esac
if printf '%s' "$cand" | grep -qE '^[0-9]+-'; then
  # feat/NNN-slug → use the id directly
  has_spec "$cand" && branch_fid="$cand"
elif printf '%s' "$cand" | grep -qE '^[0-9]+$'; then
  # feat/NNN → first spec dir with that number
  m="$(ls -d "$SPECS/$(printf '%03d' "$((10#$cand))")-"*/ 2>/dev/null | head -1)"
  [ -n "$m" ] && branch_fid="$(basename "$m")"
elif [ -n "$cand" ]; then
  # feat/<slug> (the real create-feature.sh form, no number) → spec dir whose
  # slug part (after NNN-) equals the branch slug.
  for d in "$SPECS"/[0-9]*-*/; do
    [ -d "$d" ] || continue
    fid="$(basename "$d")"
    if [ "${fid#[0-9]*-}" = "$cand" ] && has_spec "$fid"; then branch_fid="$fid"; break; fi
  done
fi

# --- decide -----------------------------------------------------------------
if [ -n "$state_fid" ] && [ -n "$branch_fid" ] && [ "$state_fid" != "$branch_fid" ]; then
  emit "$state_fid" "$SPECS/$state_fid" "$(slug_to_branch "$state_fid")" state true "$branch_fid"; exit 0
fi
if [ -n "$state_fid" ]; then
  emit "$state_fid" "$SPECS/$state_fid" "$(slug_to_branch "$state_fid")" state; exit 0
fi
if [ -n "$branch_fid" ]; then
  emit "$branch_fid" "$SPECS/$branch_fid" "$(slug_to_branch "$branch_fid")" branch; exit 0
fi
emit "" "" "" none
