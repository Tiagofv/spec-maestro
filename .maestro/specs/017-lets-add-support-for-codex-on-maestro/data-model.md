# Data Model: Codex CLI Profile Support

## Overview

This feature does not introduce persistent database storage. The data model is runtime configuration represented by known profile directory names and their prompt metadata.

## Entities

### Entity: AgentProfileDirectory

- `dir_name` (string, required) - profile directory name at project root
- `display_name` (string, required) - human-readable integration name
- `description` (string, required) - prompt/UX description
- `optional` (boolean, required) - whether install is optional

### Initial Values for this feature

1. `.opencode` - OpenCode profile
2. `.claude` - Claude Code profile
3. `.codex` - Codex CLI profile

## Derived Views

- **Installed profiles:** subset of known profiles that exist on disk.
- **Missing profiles:** known profiles not present on disk.
- **Selectable profiles:** same as known profiles for init/update prompts.

## Invariants

- Known profile list is a single source of truth for init/update/doctor behavior.
- Prompt labels and selection parsing must align with known profile ordering.
- Missing optional profile directories never fail doctor checks.
