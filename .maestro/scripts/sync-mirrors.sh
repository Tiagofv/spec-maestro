#!/usr/bin/env bash
# sync-mirrors.sh — detect and (optionally) fix drift between the CANONICAL maestro
# sources in .maestro/ and the per-harness mirrors (.claude/, .opencode/, .codex/).
#
# Why: the same command/skill markdown lives in up to 5 places — .maestro/ (source of
# truth), the three harness mirrors that agents actually READ, and the embedded resources
# baked into the `maestro` binary. They drift silently ("different versions locally"),
# and editing .maestro/ has no effect until the mirror is refreshed.
#
# Usage:
#   sync-mirrors.sh                # --check (default): report drift, exit 1 if any
#   sync-mirrors.sh --check        # same
#   sync-mirrors.sh --fix          # reconcile .maestro/ -> mirrors (SAFE: see guards)
#   sync-mirrors.sh --fix --force  # also overwrite mirrors that are LARGER than source
#
# Direction: .maestro/ is the source of truth (per README). --fix copies source -> mirror.
# GUARD: --fix refuses to overwrite a mirror file that is substantially LARGER than its
# source (>1.25x lines) — that usually means the mirror holds content the source lost, i.e.
# real work that a blind copy would destroy. Such files are reported as NEEDS-REVIEW and
# left untouched unless --force is given. This is the common, dangerous drift case.
#
# Embedded resources (the binary) are refreshed separately: run `make generate` in
# cmd/maestro-cli, then reinstall. This script notes that but does not run Go tooling.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="${MAESTRO_MAIN_REPO:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
cd "$BASE" || { echo "sync-mirrors: cannot cd to $BASE" >&2; exit 2; }

MODE="check"; FORCE=0
for a in "$@"; do
  case "$a" in
    --check) MODE="check" ;;
    --fix)   MODE="fix" ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "sync-mirrors: unknown arg '$a'" >&2; exit 2 ;;
  esac
done

MIRRORS=(.claude .opencode .codex)
RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'
drift=0 review=0 synced=0

lines() { wc -l <"$1" 2>/dev/null | tr -d ' '; }

# Compare one canonical file against one mirror path. Echoes a status; mutates counters.
compare_one() {
  local src="$1" mir="$2" label="$3"
  if [ ! -f "$mir" ]; then
    drift=$((drift+1)); echo "  ${RED}MISSING${OFF}  $label  ${DIM}(absent in mirror)${OFF}"
    [ "$MODE" = "fix" ] && { mkdir -p "$(dirname "$mir")"; cp "$src" "$mir"; synced=$((synced+1)); echo "           ${GRN}-> created${OFF}"; }
    return
  fi
  cmp -s "$src" "$mir" && return 0   # in sync, silent
  drift=$((drift+1))
  local sl ml; sl=$(lines "$src"); ml=$(lines "$mir")
  if [ "$ml" -gt $(( sl * 5 / 4 )) ]; then
    review=$((review+1))
    echo "  ${YEL}REVIEW${OFF}   $label  ${DIM}source ${sl}L < mirror ${ml}L — mirror may hold lost content${OFF}"
    if [ "$MODE" = "fix" ] && [ "$FORCE" = 1 ]; then cp "$src" "$mir"; synced=$((synced+1)); echo "           ${GRN}-> overwritten (--force)${OFF}"; fi
  else
    echo "  ${RED}DRIFT${OFF}    $label  ${DIM}source ${sl}L vs mirror ${ml}L${OFF}"
    [ "$MODE" = "fix" ] && { cp "$src" "$mir"; synced=$((synced+1)); echo "           ${GRN}-> synced${OFF}"; }
  fi
}

echo "maestro mirror sync — mode=$MODE${FORCE:+ force=$FORCE}  base=$BASE"
echo

for m in "${MIRRORS[@]}"; do
  [ -d "$m" ] || continue
  echo "── $m ─────────────────────────────────"
  # commands
  for src in .maestro/commands/maestro.*.md; do
    [ -f "$src" ] || continue
    compare_one "$src" "$m/commands/$(basename "$src")" "commands/$(basename "$src")"
  done
  # skills (mirrors prefix with maestro-)
  if [ -d .maestro/skills ]; then
    for sdir in .maestro/skills/*/; do
      [ -d "$sdir" ] || continue
      s=$(basename "$sdir")
      compare_one "${sdir}SKILL.md" "$m/skills/maestro-$s/SKILL.md" "skills/maestro-$s/SKILL.md"
    done
  fi
  # mirror-only command files (extra — informational)
  for mf in "$m"/commands/maestro.*.md; do
    [ -f "$mf" ] || continue
    [ -f ".maestro/commands/$(basename "$mf")" ] || echo "  ${DIM}EXTRA    commands/$(basename "$mf") (in mirror, not in source)${OFF}"
  done
  echo
done

echo "──────────────────────────────────────────"
echo "drift: $drift   needs-review: $review   synced: $synced"
if [ "$MODE" = "check" ]; then
  [ "$drift" -gt 0 ] && echo "${YEL}Run 'sync-mirrors.sh --fix' to reconcile (REVIEW files need --force / manual merge).${OFF}"
  echo "${DIM}Embedded resources: run 'make generate' in cmd/maestro-cli + reinstall to refresh the binary.${OFF}"
  [ "$drift" -gt 0 ] && exit 1 || { echo "${GRN}All mirrors in sync.${OFF}"; exit 0; }
else
  [ "$review" -gt 0 ] && echo "${YEL}$review file(s) left untouched (mirror larger than source). Inspect, then rerun with --force or fix the source.${OFF}"
  echo "${DIM}Now run 'make generate' in cmd/maestro-cli + reinstall to refresh embedded resources.${OFF}"
fi
