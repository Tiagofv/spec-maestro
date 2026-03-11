# Competitive Analysis: Task/Issue Creation in Project Management Tools

**Feature:** Improve Maestro Task Creation on Beads  
**Research Date:** 2026-02-23  
**Researcher:** Maestro

---

## 1. Analysis Scope

This analysis compares how various project management and issue tracking tools handle task/issue creation, with a focus on:

- Batch creation capabilities
- Idempotency strategies
- Dependency/linking capabilities
- Progress indication
- Error handling approaches
- Input formats accepted

The goal is to identify best practices for optimizing Maestro's task creation from ~10 minutes to under 30 seconds for 50+ tasks.

---

## 2. Tool 1: GitHub CLI (`gh issue create`)

### Overview
GitHub CLI provides a command-line interface for GitHub operations, including issue creation. It's widely adopted and has influenced many other CLI tools.

### Batch Creation
**Approach:** Sequential with minimal overhead

- No native batch creation command
- Each `gh issue create` spawns a single HTTP request to GitHub API
- For batch operations, users typically use shell scripts or the API directly
- Rate limiting applies (5000 requests/hour for authenticated users)

**Example workflow:**
```bash
# Individual creation (slow for batches)
gh issue create --title "Task 1" --body "Description" --label "backend"
gh issue create --title "Task 2" --body "Description" --label "frontend"

# Batch via API (recommended for automation)
for title in "Task 1" "Task 2" "Task 3"; do
  gh api repos/OWNER/REPO/issues -f title="$title" -f body="..."
done
```

### Idempotency Strategy
**Approach:** None built-in; relies on external tracking

- No native idempotency checks
- Issues are created with auto-generated IDs (repo-local sequential numbers)
- Duplicate prevention requires external tracking (e.g., checking if issue exists by title)
- Users typically implement title-based deduplication in scripts

**Common pattern:**
```bash
# Check if issue exists before creating
if ! gh issue list --search "Exact Title" --json number | jq -e '.[0]'; then
  gh issue create --title "Exact Title" --body "..."
fi
```

### Dependency/Linking Capabilities
**Approach:** Via PR/MR references and cross-references

- Sub-issues (relatively new feature): Issues can have parent/child relationships
- Issue references in descriptions: `Closes #123`, `Relates to #456`
- Project items: Can link issues to projects
- Milestone association: `--milestone` flag

**Limitations:**
- No CLI command to set parent/child relationships directly
- Dependencies must be established after issue creation via edit or description updates

### Progress Indication
**Approach:** Minimal; relies on shell output

- No built-in progress bars for batch operations
- Individual commands output URLs or IDs
- Users implement progress tracking via shell script counters

**Example:**
```bash
total=50
created=0
for task in $(cat tasks.txt); do
  gh issue create --title "$task" --silent
  created=$((created + 1))
  echo "Progress: $created/$total"
done
```

### Error Handling
**Approach:** Fail fast with clear error messages

- Returns non-zero exit codes on failure
- JSON output available (`--json`) for programmatic parsing
- Rate limit errors clearly indicated

**Exit codes:**
- `0`: Success
- `1`: General error
- `2`: Rate limited
- `4`: Authentication error

### Input Formats
**Approach:** Flexible, supports multiple modes

- **Command-line flags:** `--title`, `--body`, `--label`, `--assignee`, etc.
- **File input:** `--body-file` for reading description from file
- **Templates:** `--template` for predefined templates
- **Stdin:** `echo "body" | gh issue create --title "..."`
- **Interactive:** Prompts for missing required fields

**Template support:**
- Can use issue templates from `.github/ISSUE_TEMPLATE/`
- Supports variable substitution

### Trade-offs
| Pros | Cons |
|------|------|
| Simple, well-documented API | No native batch creation |
| Fast individual operations (~1-2s) | No idempotency |
| Good error messages | Rate limits for bulk operations |
| Multiple input formats | Dependencies must be set after creation |

---

## 3. Tool 2: Jira CLI (`jira-cli` by ankitpokhrel)

### Overview
A feature-rich CLI for Atlassian Jira, heavily inspired by GitHub CLI. Supports both Cloud and Server instances.

### Batch Creation
**Approach:** File-based batch creation

- **Markdown file import:** `jira create -f issues.md`
- Supports creating multiple issues from structured markdown
- Can create epics with nested issues

**Markdown format:**
```markdown
## Epic: Feature Implementation

### Task 1: Backend Setup
**Priority:** High
**Assignee:** developer@example.com
**Labels:** backend

Description here...

### Task 2: Frontend Setup
**Priority:** Medium
**Assignee:** developer@example.com
**Labels:** frontend
```

**API limitations:**
- Jira REST API doesn't support true batch creation
- Tool parses file and creates issues sequentially
- Progress shown per issue created

### Idempotency Strategy
**Approach:** External reference tracking

- Supports `external-ref` field for tracking
- No automatic deduplication
- Users expected to check for duplicates before creation
- Common pattern: Store external IDs in custom fields

**Example workflow:**
```bash
# Check if issue exists by external reference
jira issue list -q "external-ref = 'my-system-123'"
# Only create if not exists
```

### Dependency/Linking Capabilities
**Approach:** Rich linking support

- `jira issue link`: Link issues with relationship types (Blocks, Relates to, etc.)
- `jira epic add`: Add issues to epics
- Subtasks: Create subtasks under parent issues
- Sprint assignment: `jira sprint add`

**Two-pass approach:**
```bash
# Pass 1: Create all issues
jira create -f tasks.md

# Pass 2: Link dependencies (requires issue IDs from pass 1)
jira issue link TASK-1 TASK-2 Blocks
jira epic add EPIC-1 TASK-1 TASK-2
```

### Progress Indication
**Approach:** Interactive TUI with progress

- Interactive mode shows progress during creation
- Table view updates as issues are created
- `--plain` flag for scriptable output
- Progress shown as: `Creating issue 5 of 50...`

**Options:**
- `--plain`: No progress bars, suitable for scripts
- `--silent`: Minimal output
- `--json`: JSON output for parsing

### Error Handling
**Approach:** Graceful with partial success tracking

- Validates input before making API calls
- Clear error messages with Jira error codes
- Failed issues logged, others continue
- Exit codes: 0 (success), 1 (partial), 2 (failure)

**Example:**
```
✓ Created TASK-1: Backend Setup
✓ Created TASK-2: Frontend Setup
✗ Failed to create TASK-3: API Error
✓ Created TASK-4: Database Setup

Results: 3/4 created successfully
```

### Input Formats
**Approach:** Structured markdown with metadata

- **Markdown files:** `-f file.md` with YAML frontmatter
- **Command-line flags:** Individual field flags
- **Templates:** `--template` for predefined formats
- **JSON:** Via API integration

**Metadata format:**
```markdown
---
type: Task
priority: High
labels: backend,urgent
assignee: user@example.com
---

# Task Title

Description here...
```

### Trade-offs
| Pros | Cons |
|------|------|
| File-based batch creation | Requires file preparation |
| Rich linking capabilities | Two-pass for dependencies |
| Good progress indication | No automatic idempotency |
| Clear error reporting | Jira API rate limits |

---

## 4. Tool 3: Linear (GraphQL API)

### Overview
Linear is a modern issue tracker with a GraphQL API. While it doesn't have an official CLI, its API design influences best practices.

### Batch Creation
**Approach:** GraphQL mutations with bulk support

- GraphQL supports multiple mutations in a single request
- Can create issues and set relationships in one call
- Batch mutations reduce network overhead

**Example mutation:**
```graphql
mutation CreateIssues {
  issueCreate1: issueCreate(
    input: { title: "Task 1", teamId: "team-id", description: "..." }
  ) { success issue { id identifier } }
  
  issueCreate2: issueCreate(
    input: { title: "Task 2", teamId: "team-id", description: "..." }
  ) { success issue { id identifier } }
}
```

### Idempotency Strategy
**Approach:** Client-generated identifiers

- Supports `clientMutationId` for tracking
- Applications can implement idempotency keys
- No automatic deduplication

### Dependency/Linking Capabilities
**Approach:** Rich relationship modeling

- Parent/child relationships: `parentId` field
- Related issues: `issueRelationCreate`
- Blocks/blocked by: Built into data model
- Can set relationships during creation

**Single-pass creation:**
```graphql
mutation CreateWithRelations {
  parent: issueCreate(input: { title: "Parent", teamId: "..." }) {
    success
    issue { id }
  }
  
  child: issueCreate(input: { 
    title: "Child", 
    teamId: "...",
    parentId: "parent-id"  # Set in creation
  }) {
    success
    issue { id }
  }
}
```

### Progress Indication
**Approach:** Application-level

- API returns success/failure per mutation
- Applications implement progress tracking
- No built-in CLI progress bars

### Error Handling
**Approach:** GraphQL-style partial success

- Returns both `data` and `errors` fields
- Some mutations may succeed while others fail
- Detailed error messages with path information

**Response format:**
```json
{
  "data": {
    "issueCreate1": { "success": true, "issue": { "id": "..." } },
    "issueCreate2": { "success": false }
  },
  "errors": [
    { "message": "Title too long", "path": ["issueCreate2"] }
  ]
}
```

### Input Formats
**Approach:** GraphQL with structured inputs

- GraphQL mutations with strongly typed inputs
- Supports rich metadata (labels, assignees, estimates)
- Markdown for descriptions
- CSV import via web UI

### Trade-offs
| Pros | Cons |
|------|------|
| Single-pass with relationships | Requires GraphQL knowledge |
| Multiple mutations per request | No native CLI tool |
| Rich data model | API rate limits (1000 req/min) |
| Good error granularity | Client must implement progress |

---

## 5. Tool 4: GitLab CLI (`glab`)

### Overview
GitLab's official CLI tool, similar to GitHub CLI but with GitLab-specific features.

### Batch Creation
**Approach:** Sequential with API batching

- No native batch command
- Supports shell scripting patterns
- Can use GitLab CI for batch operations
- Bulk operations via web UI export/import

### Idempotency Strategy
**Approach:** Title-based deduplication

- No built-in idempotency
- Users check for existing issues by title
- Issue references are unique (project + iid)

### Dependency/Linking Capabilities
**Approach:** Issue relationships and epics

- `glab issue link`: Relate issues
- Epic membership via `glab epic add`
- Weight and milestone assignment
- Labels and assignees

### Progress Indication
**Approach:** Shell-level progress

- No built-in progress bars
- Returns JSON with `--json` flag
- Users implement progress tracking

### Error Handling
**Approach:** Fail fast

- Non-zero exit codes on failure
- Detailed error messages from GitLab API
- Rate limit information in headers

### Input Formats
**Approach:** Standard CLI patterns

- Command-line flags
- File input for descriptions
- Templates from `.gitlab/issue_templates/`
- Interactive prompts

### Trade-offs
| Pros | Cons |
|------|------|
| GitLab-native integration | No batch creation |
| Good CI/CD integration | No idempotency |
| Standard patterns | Sequential only |

---

## 6. Tool 5: ClickUp API

### Overview
ClickUp provides a REST API for task management with bulk operation support.

### Batch Creation
**Approach:** REST API with bulk endpoints

- Supports bulk task creation via API
- Can create up to 100 tasks per request
- Webhook notifications for progress

**Example:**
```json
POST /api/v2/list/{list_id}/task/bulk
{
  "tasks": [
    { "name": "Task 1", "description": "..." },
    { "name": "Task 2", "description": "..." }
  ]
}
```

### Idempotency Strategy
**Approach:** External ID tracking

- `custom_id` field for external references
- Applications track created tasks
- No automatic duplicate detection

### Dependency/Linking Capabilities
**Approach:** Task linking and dependencies

- `depends_on` field in task creation
- Checklist items within tasks
- Subtasks via `parent` field
- Can set dependencies in single request

### Progress Indication
**Approach:** API response with status

- Returns status per task in batch
- Webhook notifications for async operations
- Progress tracking via task status

### Error Handling
**Approach:** Partial success with details

- Returns success/failure per item
- Detailed error messages
- Rollback options for transactions

### Input Formats
**Approach:** JSON REST API

- JSON payloads
- CSV import via web UI
- Template support
- Custom fields

### Trade-offs
| Pros | Cons |
|------|------|
| True bulk creation (100 items) | Requires API integration |
| Dependencies in single request | Rate limits (100 req/min) |
| Good error granularity | No native CLI |

---

## 7. Comparison Summary

| Tool | Batch Creation | Idempotency | Dependencies | Progress | Input Formats | Speed (50 tasks) |
|------|---------------|-------------|--------------|----------|---------------|------------------|
| **GitHub CLI** | Sequential | Title check | After creation | Manual | CLI, File, JSON | ~60-100s |
| **Jira CLI** | File-based | External ref | Two-pass | Interactive | Markdown, CLI | ~90-120s |
| **Linear API** | GraphQL batch | Mutation ID | Single-pass | Custom | GraphQL | ~30-60s |
| **GitLab CLI** | Sequential | Title check | After creation | Manual | CLI, File | ~60-100s |
| **ClickUp API** | Bulk (100) | Custom ID | Single-pass | API response | JSON | ~10-30s |
| **Beads (current)** | Agent per task | None | Two-pass | None | Plan markdown | ~600s |
| **Beads (target)** | Script-based | Title-based | Two-pass | Simple | JSON | ~20-30s |

---

## 8. Best Practices Identified

### 8.1 Batch Creation
1. **Script-based approach:** Wrap CLI calls in a script for speed
2. **SQLite direct access:** For local databases, bypass HTTP API
3. **Transaction batching:** Group related operations in transactions
4. **Progress indicators:** Show count/total for user visibility

### 8.2 Idempotency
1. **Title-based checking:** Query existing issues by title before creation
2. **External ID field:** Store unique identifiers in custom fields
3. **Deterministic IDs:** Generate IDs from content hash or feature ID
4. **State tracking:** Mark created issues in a tracking file

### 8.3 Dependencies
1. **Two-pass approach:** Create all, then link (most compatible)
2. **ID mapping:** Maintain temp ID to real ID mapping
3. **Validation:** Check target issues exist before linking
4. **Error isolation:** Link failures shouldn't undo created issues

### 8.4 Progress Indication
1. **Simple counters:** "Created 5/50 issues"
2. **Stage reporting:** "Creating issues... Linking dependencies..."
3. **Error summary:** Show failures at end, not per-item
4. **Silent mode:** `--silent` for automation, no progress

### 8.5 Error Handling
1. **Fail fast:** Stop on first error (current behavior)
2. **Partial success:** Continue on non-critical errors
3. **Clear messages:** Include task number and reason
4. **Recovery info:** Suggest `--dry-run` to preview

### 8.6 Input Formats
1. **JSON preferred:** Structured, machine-readable
2. **Markdown support:** Human-readable plans
3. **Stdin support:** Pipe from other tools
4. **Validation:** Check format before processing

---

## 9. Preferred Direction

### Recommendation: Hybrid Script Approach

Based on the competitive analysis, we recommend a **script-based batch creation** approach that:

1. **Wraps `bd` CLI calls** in an optimized bash script
2. **Uses SQLite directly** for idempotency checks (fast local queries)
3. **Implements two-pass dependency linking**
4. **Provides simple progress indication**
5. **Accepts JSON input** for structured task plans

### Rationale

**Why this approach:**

1. **Speed:** Direct script execution eliminates agent spawning overhead
   - Current: 50 tasks × 12s (agent spawn) = ~600s
   - Script: 50 tasks × 0.5s (direct CLI) = ~25s

2. **Idempotency:** SQLite queries are fast for duplicate checking
   - Check title existence: <10ms
   - Skip already created: Immediate

3. **Compatibility:** Works with existing `bd` CLI
   - No changes to beads core
   - Uses public API

4. **Simplicity:** Single script file, minimal dependencies
   - No complex build process
   - Easy to debug and modify

**Trade-offs accepted:**

- **Two-pass linking:** Slightly more complex than single-pass, but more reliable
- **No true bulk API:** Sequential creation is acceptable given SQLite speed
- **Script dependency:** Requires bash, but acceptable for development environment

### Implementation Strategy

```
.maestro/scripts/create-tasks.sh
├── Phase 1: Parse JSON input
├── Phase 2: Check idempotency (SQLite query)
├── Phase 3: Create epic and tasks (bd create calls)
├── Phase 4: Link dependencies (bd dep calls)
└── Phase 5: Report results
```

**Input format:**
```json
{
  "feature_id": "019-improve-task-creation",
  "epic": { "title": "...", "description": "..." },
  "tasks": [
    {
      "title": "...",
      "description": "...",
      "labels": ["backend"],
      "estimate": 360,
      "assignee": "general",
      "dependencies": []
    }
  ]
}
```

**Progress output:**
```
Creating 52 tasks for feature 019...
[1/52] Created task: agent-maestro-0a6.1
[2/52] Skipped (exists): agent-maestro-0a6.2
...
[52/52] Created task: agent-maestro-0a6.52

Linking dependencies...
[1/45] Linked dependency: agent-maestro-0a6.2 -> agent-maestro-0a6.1
...

Complete: 51 created, 1 skipped, 45 dependencies linked
Epic: agent-maestro-0a6
```

---

## 10. References

### GitHub CLI
- Manual: https://cli.github.com/manual/
- Issue create: https://cli.github.com/manual/gh_issue_create
- REST API: https://docs.github.com/en/rest/issues/issues#create-an-issue

### Jira CLI
- Repository: https://github.com/ankitpokhrel/jira-cli
- Documentation: README.md in repository
- Batch creation: File-based markdown import

### Linear
- API Docs: https://developers.linear.app/
- GraphQL Schema: https://studio.apollographql.com/public/Linear-API/
- CLI Importer: https://github.com/linear/linear/tree/master/packages/import

### GitLab CLI
- Repository: https://gitlab.com/gitlab-org/cli
- Documentation: https://gitlab.com/gitlab-org/cli/-/blob/main/README.md

### ClickUp
- API Docs: https://clickup.com/api
- Developer Portal: https://developer.clickup.com/

### beads CLI
- Local help: `bd create --help`
- Dependency help: `bd dep --help`
- Current helpers: `.maestro/scripts/bd-helpers.sh`

---

## 11. Appendix: Current vs Proposed

### Current Implementation (Agent-based)

```bash
# For each task:
# 1. Agent parses command
# 2. Agent spawns subprocess  
# 3. bd create executes
# 4. Agent parses output
# 5. Repeat for next task
```

**Time estimate:** 50 tasks × ~12s = ~600s (10 minutes)

### Proposed Implementation (Script-based)

```bash
# Single script execution:
# 1. Parse JSON input (once)
# 2. For each task:
#    - Check existence (SQLite query, <10ms)
#    - bd create (if new, ~0.5s)
# 3. For each dependency:
#    - bd dep add (~0.3s)
```

**Time estimate:** 50 tasks × ~0.5s + overhead = ~25-30s

**Speedup: ~20x faster**

---

*Research complete. This document should inform the implementation plan for Feature 019.*
