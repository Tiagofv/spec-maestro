# Technology Options Research: Task Creation Script

**Feature ID:** 019-improve-maestroe-task-creation-on-beads-currently-
**Research Date:** 2026-02-23
**Author:** Maestro Research Agent
**Status:** Draft

---

## Executive Summary

This research explores options for two deferred questions in Feature 019:

1. **Idempotency Strategy:** What unique identifier to use for checking if tasks already exist
2. **Input Format:** What format to use for passing the task plan to the script

After evaluating Beads CLI capabilities, Linear API requirements, and existing Maestro patterns, we recommend:

- **Idempotency:** Use `title + parent epic` as the composite identifier
- **Input Format:** Use JSON format for programmatic reliability

---

## 1. Findings

### 1.1 Idempotency Strategy Options

#### Option A: Title + Parent Epic Composite Key

**Approach:** Check if a task with the same title exists under the same epic.

**Implementation:**

```bash
# Search for existing task by title under epic
bd list --parent $EPIC_ID --json | jq -r '.[].title' | grep -q "^${TASK_TITLE}$"
```

**Pros:**

- Human-readable and debuggable
- Aligns with existing Maestro task structure
- No additional metadata storage needed
- Works with existing Beads CLI

**Cons:**

- Title changes break idempotency
- Potential for collisions if titles aren't unique
- Case sensitivity and whitespace handling needed

**Evidence:**

- Current plan.md tasks use structured titles like "TDP-001-037: Write component tests"
- Beads supports `--parent` filter for listing child issues
- Title-based matching is standard in issue trackers

---

#### Option B: Beads Issue ID (External Reference)

**Approach:** Use Beads-generated IDs (e.g., "agent-maestro-s00.39") as the unique identifier.

**Implementation:**

```bash
# Store mapping in state or external file
# Check if task exists by ID
bd show $TASK_ID --json 2>/dev/null && echo "exists" || echo "new"
```

**Pros:**

- Guaranteed unique (Beads generates UUID-like IDs)
- Fast lookup (direct ID access)
- No ambiguity or collision risk

**Cons:**

- Requires storing ID mappings between runs
- IDs are not human-readable
- Breaks idempotency if state file is lost
- Adds complexity for dependency tracking

**Evidence:**

- Beads generates IDs like "agent-maestro-s00.39" automatically
- JSON output includes `id` field for each issue
- Requires state persistence between script runs

---

#### Option C: External Reference Field (--external-ref)

**Approach:** Use Beads' built-in `--external-ref` flag to store a custom identifier.

**Implementation:**

```bash
# Create with external reference
bd create --title "$TITLE" --external-ref "$FEATURE_ID-$TASK_NUM"

# Search by external reference
bd search --query "$FEATURE_ID-$TASK_NUM" --json
```

**Pros:**

- Native Beads support for custom IDs
- Clean separation from Beads internal IDs
- Can encode feature/task relationship

**Cons:**

- External refs are searchable but not directly queryable by value
- Requires maintaining external ref format convention
- Not all Beads operations support filtering by external-ref

**Evidence:**

- Beads CLI supports `--external-ref` flag on create
- External refs appear in JSON output as `external_ref` field
- Search includes external_ref in indexed fields

---

#### Option D: Custom ID Field in Description

**Approach:** Embed a custom task ID in the task description metadata.

**Implementation:**

```bash
# Store in description YAML frontmatter
---
task_id: "MST-001-001"
---

# Parse description to extract ID
```

**Pros:**

- Full control over ID format
- Human-readable and self-documenting
- Can include rich metadata

**Cons:**

- Requires parsing description to extract ID
- Fragile (format changes break extraction)
- No direct Beads support for querying

**Evidence:**

- Current Maestro tasks use structured descriptions
- YAML frontmatter is parseable
- Not efficient for bulk checking

---

### 1.2 Input Format Options

#### Option A: JSON Format

**Approach:** Parse task plan as JSON array of task objects.

**Example:**

```json
{
  "feature_id": "019-improve-maestro-task-creation",
  "feature_title": "Improve Maestro Task Creation",
  "tasks": [
    {
      "number": 1,
      "title": "Create task creation script",
      "description": "Implement...",
      "label": "backend",
      "size": "S",
      "estimate_minutes": 360,
      "assignee": "general",
      "dependencies": []
    }
  ]
}
```

**Pros:**

- Native parsing support in all languages (jq, Python, etc.)
- Type-safe and structured
- Easy to validate with JSON Schema
- Fast to parse (no regex/scanning needed)

**Cons:**

- Not human-readable for debugging
- Requires conversion from plan.md format
- More verbose than YAML

**Evidence:**

- Beads CLI outputs JSON natively (`--json` flag)
- JSON is the standard for programmatic interfaces
- Maestro state files use JSON

---

#### Option B: YAML Format

**Approach:** Parse task plan as YAML document.

**Example:**

```yaml
feature_id: 019-improve-maestro-task-creation
feature_title: Improve Maestro Task Creation
tasks:
  - number: 1
    title: Create task creation script
    description: Implement...
    label: backend
    size: S
    estimate_minutes: 360
    assignee: general
    dependencies: []
```

**Pros:**

- Human-readable and writable
- Less verbose than JSON
- Supports comments
- Native support in most scripting languages

**Cons:**

- Requires YAML parser (not universal)
- Whitespace-sensitive
- Slightly slower parsing than JSON
- Schema validation less standardized

**Evidence:**

- Maestro config.yaml uses YAML
- Plan.md could be converted to YAML
- Good for human-editable formats

---

#### Option C: Markdown Table (Current Plan Format)

**Approach:** Parse existing plan.md format with task tables.

**Example:**

```markdown
| #   | ID   | Title              | Label   | Size | Assignee |
| --- | ---- | ------------------ | ------- | ---- | -------- |
| 1   | T001 | Create task script | backend | S    | general  |
```

**Pros:**

- No format conversion needed
- Works with current plan.md structure
- Human-readable in source control
- Familiar to users

**Cons:**

- Requires complex parsing (regex/table extraction)
- Fragile (format changes break parser)
- Limited to tabular data
- Description content harder to embed

**Evidence:**

- Current maestro.tasks command uses plan.md
- Existing plans have task tables
- Requires parsing markdown tables

---

#### Option D: Beads Markdown Format (-f flag)

**Approach:** Use Beads' native multi-issue markdown format.

**Example:**

```markdown
# Epic: Improve Task Creation

## Create task script

**Type:** task
**Label:** backend
**Estimate:** 360
**Assignee:** general

Implement the task creation script...

## Create dependency linker

**Type:** task
**Label:** backend
**Estimate:** 240
**Assignee:** general
**Deps:** blocks:1

Link dependencies between tasks...
```

**Pros:**

- Native Beads support (`bd create -f file.md`)
- Idiomatic to Beads workflow
- Supports rich descriptions

**Cons:**

- Requires converting plan to Beads format
- Less structured than JSON/YAML
- Dependency syntax is Beads-specific
- Two-pass creation harder to coordinate

**Evidence:**

- Beads CLI supports creating from markdown file (`--file` flag)
- Beads has specific markdown parsing for issues
- Used for bulk issue creation in Beads

---

## 2. Recommendations

### 2.1 Idempotency Strategy: Title + Parent Epic

**Rationale:**

1. **Simplicity:** Uses existing Beads CLI capabilities without additional state management
2. **Human Readable:** Easy to debug and verify
3. **Aligns with Current Pattern:** Maestro tasks already follow structured title format
4. **No External Dependencies:** Doesn't require state file persistence

**Implementation:**

```bash
#!/bin/bash
# Idempotency check for task creation

# Step 1: Get existing tasks under epic
EXISTING_TASKS=$(bd list --parent "$EPIC_ID" --json 2>/dev/null | jq -r '.[].title' | sort)

# Step 2: For each task in plan, check if title exists
check_task_exists() {
    local title="$1"
    echo "$EXISTING_TASKS" | grep -q "^${title}$"
}

# Step 3: Create or skip
create_or_skip() {
    local title="$1"
    if check_task_exists "$title"; then
        echo "SKIPPED: $title (already exists)"
        return 0
    else
        # Create task
        bd create --title "$title" --parent "$EPIC_ID" ...
        echo "CREATED: $title"
    fi
}
```

**Handling Edge Cases:**

1. **Title Changes:** Document that renames require manual intervention
2. **Whitespace:** Normalize titles (trim, collapse spaces) before comparison
3. **Case Sensitivity:** Use case-insensitive comparison
4. **Duplicate Titles:** Reject plan with duplicate titles before creation

---

### 2.2 Input Format: JSON

**Rationale:**

1. **Programmatic Reliability:** No parsing ambiguity, strict structure
2. **Fast Processing:** Native JSON parsing is faster than regex
3. **Type Safety:** Clear data types for validation
4. **Future-Proof:** Easy to extend with new fields
5. **Beads Integration:** Beads CLI outputs JSON, making bidirectional conversion easy

**Implementation:**

```bash
#!/bin/bash
# Task creation script using JSON input

TASK_PLAN_FILE="$1"

# Validate JSON
if ! jq empty "$TASK_PLAN_FILE" 2>/dev/null; then
    echo "Error: Invalid JSON in $TASK_PLAN_FILE" >&2
    exit 1
fi

# Extract metadata
FEATURE_ID=$(jq -r '.feature_id' "$TASK_PLAN_FILE")
FEATURE_TITLE=$(jq -r '.feature_title' "$TASK_PLAN_FILE")

# Create epic
EPIC_ID=$(bd create --title "$FEATURE_TITLE" --type=epic --silent)

# Process tasks
total_tasks=$(jq '.tasks | length' "$TASK_PLAN_FILE")
for i in $(seq 0 $((total_tasks - 1))); do
    task=$(jq -r ".tasks[$i]" "$TASK_PLAN_FILE")
    title=$(echo "$task" | jq -r '.title')

    # Idempotency check
    if task_exists "$title" "$EPIC_ID"; then
        echo "[SKIPPED] $title"
        continue
    fi

    # Create task
    # ...
done
```

**JSON Schema:**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["feature_id", "feature_title", "tasks"],
  "properties": {
    "feature_id": { "type": "string" },
    "feature_title": { "type": "string" },
    "tasks": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["title", "label", "size", "assignee"],
        "properties": {
          "number": { "type": "integer" },
          "title": { "type": "string" },
          "description": { "type": "string" },
          "label": { "type": "string" },
          "size": { "type": "string", "enum": ["XS", "S", "M", "L"] },
          "estimate_minutes": { "type": "integer" },
          "assignee": { "type": "string" },
          "dependencies": { "type": "array", "items": { "type": "integer" } }
        }
      }
    }
  }
}
```

---

## 3. Risks and Mitigations

| Risk                                           | Likelihood | Impact | Mitigation                                                                                     |
| ---------------------------------------------- | ---------- | ------ | ---------------------------------------------------------------------------------------------- |
| Title-based idempotency fails if titles change | Medium     | Medium | Document that task renames require manual cleanup; add validation for duplicate titles in plan |
| JSON parsing fails on malformed input          | Low        | High   | Validate JSON with schema before processing; provide clear error messages                      |
| Beads CLI changes output format                | Low        | High   | Pin Beads version; add integration tests for CLI parsing                                       |
| Two-pass linking leaves partial dependencies   | Medium     | Medium | Implement rollback on failure; store intermediate state                                        |
| Script execution permissions                   | Low        | Medium | Add executable permissions check; document chmod requirements                                  |
| Large task plans (100+) cause timeouts         | Low        | Medium | Add batching logic; implement progress indicators                                              |
| Beads database locked during creation          | Low        | High   | Implement retry with exponential backoff; use `--lock-timeout` flag                            |
| Feature ID collision in title search           | Low        | Medium | Include epic context in search; validate epic belongs to feature                               |

---

## 4. References

### Documentation

1. **Beads CLI Reference:**
   - `bd create --help`: Issue creation flags and options
   - `bd list --help`: Listing and filtering issues
   - `bd search --help`: Search capabilities
   - `bd dep --help`: Dependency management

2. **Current Maestro Task Format:**
   - `.maestro/commands/maestro.tasks.md`: Current task creation workflow
   - `.maestro/specs/003-create-a-maestro-research-command-that-adds-a-pre-/plan.md`: Example task plan structure
   - `.maestro/specs/018-drop-the-review-risk-classification-i-noticed-some/plan.md`: Another example with task tables

3. **Task Creation Patterns:**
   - `.config/opencode/skills/task-creation/SKILL.md`: Task creation standards
   - Defines task structure: `{ACRONYM}-{FEATURE}-{TASK}` format
   - Size mapping: XS=120min, S=360min, M=720min, L=1200min

4. **Beads Database Schema:**
   - `.beads/issues.jsonl`: Example issue storage format
   - Shows fields: `id`, `title`, `description`, `status`, `priority`, `labels`, `assignee`, `estimated_minutes`, `dependencies`

### Examples

1. **Beads JSON Output:**

   ```json
   {
     "id": "agent-maestro-s00.39",
     "title": "PM-VAL: Task Detail Page",
     "status": "open",
     "priority": 1,
     "labels": ["pm-validation"],
     "assignee": "pm-feature-validator",
     "estimated_minutes": 720,
     "dependencies": [...]
   }
   ```

2. **Current Plan Task Table:**

   ```markdown
   | #   | ID   | Title        | Label   | Size | Minutes | Assignee | Blocked By |
   | --- | ---- | ------------ | ------- | ---- | ------- | -------- | ---------- |
   | 1   | T001 | {title}      | backend | S    | 360     | {agent}  | —          |
   | 2   | R001 | Review: T001 | review  | XS   | 120     | {agent}  | T001       |
   ```

3. **Beads Create Command:**
   ```bash
   bd create \
     --title="MST-001-001: Create task script" \
     --type=task \
     --priority=2 \
     --labels=backend \
     --estimate=360 \
     --assignee="general" \
     --description="..." \
     --parent=epic-id
   ```

---

## 5. Decision Log

| Decision            | Options Considered                                       | Chosen                  | Rationale                                                      |
| ------------------- | -------------------------------------------------------- | ----------------------- | -------------------------------------------------------------- |
| Idempotency Key     | Title+epic / Beads ID / External-ref / Custom field      | **Title + Parent Epic** | Simple, no state persistence, aligns with current patterns     |
| Input Format        | JSON / YAML / Markdown table / Beads markdown            | **JSON**                | Programmatic reliability, fast parsing, type-safe              |
| Dependency Linking  | One-pass with forward refs / Two-pass (create then link) | **Two-pass**            | Clearer error handling, supports circular dependency detection |
| Progress Indication | Silent / Counter / Progress bar / Streaming              | **Counter + Status**    | Simple to implement, sufficient visibility                     |

---

## Changelog

| Date       | Change                    | Author                 |
| ---------- | ------------------------- | ---------------------- |
| 2026-02-23 | Initial research document | Maestro Research Agent |
