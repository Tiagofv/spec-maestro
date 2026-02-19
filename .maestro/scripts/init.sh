#!/usr/bin/env bash
# Initialize Maestro in a project
# Called by /maestro.init command
# Creates directory structure, registers commands and skills with AI agents

set -euo pipefail

PROJECT_ROOT="${1:-.}"
MAESTRO_DIR="$PROJECT_ROOT/.maestro"

echo "=== Initializing Maestro ===" >&2

# Create directory structure
mkdir -p "$MAESTRO_DIR"/{commands,templates,scripts,skills,cookbook,reference,specs,state,memory}

# Register commands and skills with each agent
for agent_prefix in ".claude" ".opencode"; do
  cmd_target="$PROJECT_ROOT/$agent_prefix/commands"
  skill_target="$PROJECT_ROOT/$agent_prefix/skills"

  # --- Commands ---
  mkdir -p "$cmd_target"
  for cmd in "$MAESTRO_DIR/commands"/maestro.*.md; do
    if [[ -f "$cmd" ]]; then
      cp "$cmd" "$cmd_target/" 2>/dev/null || true
      echo "Registered command: $(basename "$cmd") -> $agent_prefix/commands/" >&2
    fi
  done

  # --- Skills ---
  # Copy each skill directory (e.g. .maestro/skills/review/ -> .claude/skills/maestro-review/)
  # Prefix with "maestro-" to avoid collisions with agent-native skills
  for skill_dir in "$MAESTRO_DIR/skills"/*/; do
    if [[ -d "$skill_dir" ]]; then
      skill_name=$(basename "$skill_dir")
      dest="$skill_target/maestro-${skill_name}"
      mkdir -p "$dest"
      cp "$skill_dir"SKILL.md "$dest/SKILL.md" 2>/dev/null || true
      echo "Registered skill: $skill_name -> $agent_prefix/skills/maestro-${skill_name}/" >&2
    fi
  done
done

echo "=== Maestro initialized ===" >&2
echo "{\"ok\":true,\"maestro_dir\":\"$MAESTRO_DIR\"}"
