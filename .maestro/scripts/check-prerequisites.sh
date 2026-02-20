#!/usr/bin/env bash
# Check that required pipeline stages are complete before proceeding
# Usage: check-prerequisites.sh <stage> [feature-dir]
# Stages: clarify (needs spec), research (needs spec+state), plan (needs spec + research readiness validation), tasks (needs plan), implement (needs tasks)
# Outputs JSON: {"ok":true} or {"ok":false,"error":"...","suggestion":"..."}

set -euo pipefail

# Detect if running from inside a worktree and resolve main repo path
SCRIPT_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_SELF_DIR/worktree-detect.sh" ]]; then
  source "$SCRIPT_SELF_DIR/worktree-detect.sh" 2>/dev/null || true
fi

# If in a worktree, use the main repo path for lookups
MAESTRO_BASE="${MAESTRO_MAIN_REPO:-.}"

STAGE="${1:?Usage: check-prerequisites.sh <stage>}"
FEATURE_DIR="${2:-${MAESTRO_BASE}/.maestro/specs/$(ls -1 "${MAESTRO_BASE}/.maestro/specs" 2>/dev/null | tail -1)}"
FEATURE_ID="$(basename "$FEATURE_DIR")"
STATE_FILE="${MAESTRO_BASE}/.maestro/state/${FEATURE_ID}.json"

fail_with() {
  local error="$1"
  local suggestion="$2"
  echo "{\"ok\":false,\"error\":\"$error\",\"suggestion\":\"$suggestion\"}"
  exit 1
}

check_file_exists() {
  local file="$1"
  local name="$2"
  if [[ ! -f "$file" ]]; then
    fail_with "$name not found" "Run the previous pipeline stage first"
  fi
}

validate_plan_research_readiness() {
  # Backward compatibility: if state is missing or has no research fields,
  # allow planning to proceed with legacy behavior.
  if [[ ! -f "$STATE_FILE" ]]; then
    return 0
  fi

  local readiness_output
  readiness_output="$(python3 - "$STATE_FILE" "$MAESTRO_BASE" <<'PY'
import json
import os
import sys

state_path = sys.argv[1]
repo_base = os.path.abspath(sys.argv[2])

required_artifacts = [
    "technology-options.md",
    "pattern-catalog.md",
    "pitfall-register.md",
    "competitive-analysis.md",
    "synthesis.md",
]

try:
    with open(state_path, "r", encoding="utf-8") as f:
        state = json.load(f)
except Exception:
    print("error=State file is not valid JSON")
    print("suggestion=Fix the state file JSON or regenerate it with the previous stage command")
    sys.exit(2)

research_obj = state.get("research") if isinstance(state.get("research"), dict) else {}
has_research_fields = any(k.startswith("research_") for k in state.keys()) or bool(research_obj)

if not has_research_fields:
    print("has_research=false")
    sys.exit(0)

ready = state.get("research_ready")
if ready is None:
    ready = research_obj.get("ready")

if isinstance(ready, str):
    ready = ready.strip().lower() == "true"

if ready is not True:
    print("has_research=true")
    print("ready=false")
    sys.exit(0)

research_path = state.get("research_path")
if research_path is None:
    research_path = research_obj.get("path")

research_artifacts = state.get("research_artifacts")
if research_artifacts is None:
    research_artifacts = research_obj.get("artifacts")

if not isinstance(research_path, str) or not research_path.strip():
    print("error=Research is marked ready but research_path is missing")
    print("suggestion=Run /maestro.research to regenerate research metadata or set research_ready=false before planning")
    sys.exit(2)

research_path = research_path.strip()
resolved_research_path = research_path if os.path.isabs(research_path) else os.path.join(repo_base, research_path)

if not os.path.isdir(resolved_research_path):
    print("error=Research is marked ready but research directory is missing")
    print("suggestion=Run /maestro.research to regenerate missing artifacts and metadata")
    sys.exit(2)

if not isinstance(research_artifacts, list) or len(research_artifacts) == 0:
    print("error=Research is marked ready but research_artifacts is missing")
    print("suggestion=Run /maestro.research to regenerate artifact metadata")
    sys.exit(2)

listed_files = set()
missing_listed_files = []
for artifact in research_artifacts:
    if not isinstance(artifact, str) or not artifact.strip():
        continue
    artifact_path = artifact.strip()
    resolved = artifact_path if os.path.isabs(artifact_path) else os.path.join(repo_base, artifact_path)
    listed_files.add(os.path.basename(artifact_path))
    if not os.path.isfile(resolved):
        missing_listed_files.append(artifact_path)

missing_required = []
for filename in required_artifacts:
    if filename not in listed_files:
        missing_required.append(filename)
        continue
    required_path = os.path.join(resolved_research_path, filename)
    if not os.path.isfile(required_path):
        missing_required.append(filename)

if missing_required:
    print("error=Research is marked ready but required artifacts are missing: " + ", ".join(missing_required))
    print("suggestion=Run /maestro.research to regenerate missing artifacts or set research_ready=false to use the planning bypass")
    sys.exit(2)

if missing_listed_files:
    print("error=Research is marked ready but listed artifacts are missing: " + ", ".join(missing_listed_files))
    print("suggestion=Run /maestro.research to regenerate artifact files and metadata")
    sys.exit(2)

print("has_research=true")
print("ready=true")
PY
)" || true

if [[ -n "$readiness_output" ]]; then
    local output_error
    output_error="$(printf '%s\n' "$readiness_output" | awk -F= '/^error=/{sub(/^error=/, ""); print; exit}')"
    if [[ -n "$output_error" ]]; then
      local output_suggestion
      output_suggestion="$(printf '%s\n' "$readiness_output" | awk -F= '/^suggestion=/{sub(/^suggestion=/, ""); print; exit}')"
      if [[ -z "$output_suggestion" ]]; then
        output_suggestion="Run /maestro.research to regenerate research artifacts"
      fi
      fail_with "$output_error" "$output_suggestion"
    fi
  fi
}

case "$STAGE" in
  clarify)
    check_file_exists "$FEATURE_DIR/spec.md" "Specification"
    ;;
  research)
    check_file_exists "$FEATURE_DIR/spec.md" "Specification"
    check_file_exists "$STATE_FILE" "Feature state"
    ;;
  plan)
    check_file_exists "$FEATURE_DIR/spec.md" "Specification"
    validate_plan_research_readiness
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
    echo "{\"ok\":false,\"error\":\"Unknown stage: $STAGE\",\"suggestion\":\"Valid stages: clarify, research, plan, tasks, implement\"}"
    exit 1
    ;;
esac

echo "{\"ok\":true}"
