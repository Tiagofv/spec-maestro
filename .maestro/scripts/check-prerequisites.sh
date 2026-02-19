#!/usr/bin/env bash
# Check that required pipeline stages are complete before proceeding
# Usage: check-prerequisites.sh <stage> [feature-dir]
# Stages: clarify (needs spec), plan (needs spec), tasks (needs plan), implement (needs tasks)
# Outputs JSON: {"ok":true} or {"ok":false,"error":"...","suggestion":"..."}

set -euo pipefail

STAGE="${1:?Usage: check-prerequisites.sh <stage>}"
FEATURE_DIR="${2:-.maestro/specs/$(ls -1 .maestro/specs 2>/dev/null | tail -1)}"

check_file_exists() {
  local file="$1"
  local name="$2"
  if [[ ! -f "$file" ]]; then
    echo "{\"ok\":false,\"error\":\"$name not found\",\"suggestion\":\"Run the previous pipeline stage first\"}"
    exit 1
  fi
}

case "$STAGE" in
  clarify|plan)
    check_file_exists "$FEATURE_DIR/spec.md" "Specification"
    ;;
  tasks)
    check_file_exists "$FEATURE_DIR/plan.md" "Implementation plan"
    ;;
  implement|review|pm-validate)
    # Check bd has tasks for this feature
    if ! command -v bd &>/dev/null; then
      echo "{\"ok\":false,\"error\":\"bd CLI not found\",\"suggestion\":\"Install bd: go install github.com/...\"}"
      exit 1
    fi
    ;;
  *)
    echo "{\"ok\":false,\"error\":\"Unknown stage: $STAGE\",\"suggestion\":\"Valid stages: clarify, plan, tasks, implement\"}"
    exit 1
    ;;
esac

echo "{\"ok\":true}"
