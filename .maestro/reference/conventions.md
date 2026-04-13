# Global Review Conventions

These conventions apply to all code reviews. Local conventions in project `CLAUDE.md` take precedence.

## Error Handling

- All errors must be wrapped with context (no bare `return err`)
- Use structured error types where possible
- Log errors at the point of handling, not creation
- Never swallow errors silently

## Naming

- Functions: verb + noun (GetUser, CreateOrder, HandlePayment)
- Variables: descriptive, no single-letter except loop counters
- Packages/modules: singular nouns, lowercase
- Constants: UPPER_SNAKE_CASE or PascalCase (language-dependent)

## Testing

- Test names describe behavior: TestGetUser_WhenNotFound_ReturnsError
- Table-driven tests for multiple scenarios
- Mock external dependencies, not internal logic
- Assert on behavior, not implementation

## Security

- Never log PII (emails, SSNs, payment info)
- Use parameterized queries (no string concatenation for SQL)
- Validate all input at boundaries
- Use constant-time comparison for secrets

## Performance

- Avoid N+1 queries
- Use pagination for list endpoints
- Consider caching for read-heavy paths
- Profile before optimizing

---

# Specs Folder Naming Convention

This document describes the naming convention for folders created in `.maestro/specs/`.

## Overview

Folder names follow the pattern: `{NNN}-{descriptive-name}`

- **Numeric prefix:** 3-digit feature ID (e.g., `001`, `013`, `014`)
- **Separator:** hyphen `-`
- **Descriptive name:** kebab-case, 10-40 characters

## Rules

### 1. Format

- Use **kebab-case** (lowercase with hyphens) for consistency with shell conventions
- Always prefix with the 3-digit feature ID followed by a hyphen
- No spaces, underscores, or mixed case

### 2. Character Limits

| Portion | Minimum | Maximum |
|---------|---------|---------|
| Descriptive name | 10 chars | 40 chars |
| Total (including ID) | 14 chars | 44 chars |

### 3. Truncation

- Truncate at **word boundaries**, never mid-word
- If truncation would result in fewer than 10 characters, add more words to meet minimum
- Prioritize unique, distinguishing words over common ones

### 4. Stop Words

The following words are filtered out during name generation:

| Category | Words |
|----------|-------|
| Articles | a, an, the |
| Conjunctions | and, or, but |
| Prepositions | to, of, for, on, in, at, by, with, from |
| Pronouns | we, our, us, I, my |
| Helpers | need, want, have, do, make, get, let |

### 5. Duplicate Handling

When truncation creates duplicate folder names:

- Append counter suffix: `-v2`, `-v3`, `-v4`, etc.
- First occurrence uses no suffix
- Second occurrence uses `-v2`, and so on

---

## Examples

### Before/After Transformations

| Original Description | Old Folder Name (50-char slug) | New Folder Name |
|---------------------|-------------------------------|-----------------|
| "We need to build a kanban board on our Tauri UI to track tasks" | `001-we-need-to-build-a-kanban-board-on-our-tauri-ui-to` | `001-kanban-board-tauri-ui` |
| "Let's change the way we select the agent to implement better routing" | `012-lets-change-the-way-we-select-the-agent-to-impleme` | `012-agent-selection-routing` |
| "Create automatic git worktree support for Maestro" | `013-create-automatic-git-worktree-support-for-maestro` | `013-git-worktree-support` |
| "Add custom task templates to Maestro" | `014-add-custom-task-templates-to-maestro` | `014-custom-task-templates` |

### Character Limit Examples

| Description | Generated Name | Length | Notes |
|-------------|----------------|--------|-------|
| "Fix UI bug" | `015-fix-ui-bug` | 11 chars | Below minimum, uses full phrase |
| "Create kanban board" | `016-kanban-board` | 12 chars | Within range |
| "Implement wave-based parallel execution for maestro task orchestration" | `017-wave-based-parallel-execution` | 27 chars | Truncated at word boundary |
| "Build custom report generator with PDF export for billing system" | `018-custom-report-generator-pdf` | 25 chars | Prioritizes key words |

### Duplicate Handling

| Order | Feature Description | Folder Name |
|-------|---------------------|-------------|
| 1st | "Create user dashboard" | `019-user-dashboard` |
| 2nd | "Build dashboard for analytics" | `019-user-dashboard-v2` |
| 3rd | "Add analytics dashboard" | `019-user-dashboard-v3` |

---

## Rationale

### Why kebab-case?

- Universal compatibility with all operating systems and filesystems
- Standard convention in web development and DevOps tooling
- Readable in terminal listings without case-conversion ambiguity
- Works seamlessly with shell autocomplete

### Why 10-40 character limit?

- **10 chars minimum:** Prevents cryptic names like "fix-ui" that lack context
- **40 chars maximum:** Ensures names fit in standard terminal width (80 chars) with ID prefix
- Balances readability with descriptiveness

### Why word-boundary truncation?

- Mid-word truncation creates confusion (e.g., "implementa" vs "implementation")
- Word boundaries maintain readability and guessability
- Users can predict the full word from the truncated form

### Why conservative stop word list?

- Removing too many words strips meaning from the name
- Words like "we", "need", "create" don't add distinguishing information
- But preserving nouns and verbs maintains semantic clarity

### Why counter suffixes (-v2, -v3)?

- More readable than timestamps (e.g., `-20240219`)
- Predictable naming pattern
- Easy to sort and compare
- Clear indication of duplicate handling

### Why no automatic renaming?

- Backward compatibility with existing folders
- No breaking changes to existing workflows
- Developers can migrate manually if desired
- State files remain valid

---

## Implementation

This convention is implemented in `.maestro/scripts/create-feature.sh`. The script:

1. Extracts key words from the feature description
2. Filters stop words
3. Builds kebab-case slug
4. Truncates at word boundary (10-40 chars)
5. Checks for existing folders with same base name
6. Appends counter suffix if duplicate detected

---

## Real Examples from This Project

The following folder names exist in `.maestro/specs/`:

| Folder Name | Description (Original) | Notes |
|-------------|------------------------|-------|
| `001-kanban-board-tauri-ui` | "We need to build a kanban board on our Tauri UI to track tasks" | Filters stop words, keeps key nouns |
| `013-better-naming-for-the-folders-created-inside-specs` | "Add better naming for the folders created inside specs" | Exact match with convention, 48 chars |
| `014-add-automatic-git-worktree-support-to-maestro` | "Add automatic git worktree support to Maestro" | Long descriptive name kept |
| `017-lets-add-support-for-codex-on-maestro` | "Let's add support for Codex on Maestro" | Filters "let's", keeps nouns |

---

## Edge Cases and How They're Handled

### Edge Case 1: Very Short Descriptions

**Problem:** Description is too brief (e.g., "Fix bug").

**Handling:** When the description is below minimum after stop word filtering, the full phrase is used even if under 10 characters. Example: `015-fix-ui-bug` (11 chars).

### Edge Case 2: All Stop Words

**Problem:** Description contains only stop words.

**Handling:** The script keeps at least the original words regardless of stop word filtering. A description like "Add the feature" becomes `xxx-add-feature`.

### Edge Case 3: Numbers in Description

**Problem:** Description contains numbers (e.g., "Add v2 support").

**Handling:** Numbers are preserved in the slug. Example: `020-v2-api-support`.

### Edge Case 4: Special Characters

**Problem:** Description contains special characters or punctuation.

**Handling:** Only alphanumeric characters and spaces are kept. Hyphens are used as word separators. Example: "API's & Webhooks!" becomes `api-s-webhooks`.

### Edge Case 5: Duplicate Names After Truncation

**Problem:** Two different descriptions result in the same truncated name.

**Handling:** Counter suffix is appended (-v2, -v3, etc.) to create uniqueness.

### Edge Case 6: Unicode Characters

**Problem:** Description contains non-ASCII characters.

**Handling:** Unicode characters are converted to ASCII equivalents where possible, or removed. Only a-z, 0-9 are kept in the final slug.

### Edge Case 7: Single Word Description

**Problem:** Description is a single word.

**Handling:** The single word is used with the ID prefix. Example: "Refactor" becomes `021-refactor`.

---

## FAQ

### Q: Why not use timestamps instead of -v2, -v3?

**A:** Timestamps (e.g., `-20240219`) are less readable and harder to sort mentally. Counter suffixes are predictable, chronological by nature, and easier to type.

### Q: Can I rename existing folders manually?

**A:** Yes. The convention doesn't enforce renaming. Existing folders work as-is. Manual migration is optional.

### Q: What if my description is exactly 40 characters?

**A:** That's acceptable. The maximum is inclusive, so 40 characters is valid.

### Q: Does the numeric ID have to be 3 digits?

**A:** Yes. The prefix is always 3 digits (001-999) for consistent sorting and alignment.

### Q: What happens if I create a folder outside this convention?

**A:** The folder will still work, but it won't follow project conventions. The script enforces the convention for new creations.

### Q: Can I override the convention for specific cases?

**A:** Yes, but it's discouraged. The conventions ensure consistency across the project. Override only when absolutely necessary.

### Q: How do I update existing state files after renaming?

**A:** State files in `.maestro/state/` reference folder names. After renaming, update any references manually. The convention doesn't auto-update state files.

### Q: Is there a length minimum for the descriptive portion?

**A:** Yes, 10 characters minimum for the descriptive portion alone (after the ID and hyphen). If below minimum, use the full phrase.

---

## References

- Feature Spec: `.maestro/specs/013-better-naming-for-the-folders-created-inside-specs/spec.md`
- Implementation Plan: `.maestro/specs/013-better-naming-for-the-folders-created-inside-specs/plan.md`

---

# Commit Attribution Convention

Maestro uses a `[bd:ISSUE_ID]` suffix in commit messages to attribute commits to specific tasks. This enables the `/maestro.diff` command to reconstruct the full diff for any task by finding all commits that belong to it.

## Format

Append `[bd:<task-id>]` at the end of the commit message subject line.

**Example:**

```
feat(api): add payment handler [bd:agent-maestro-xyz.3]
```

The suffix consists of:

- `[bd:` -- opening marker (short for "beads", the internal task tracking system)
- `<task-id>` -- the full task ID including epic prefix and subtask number (e.g., `agent-maestro-xyz.3`)
- `]` -- closing marker

## When It Is Applied

### Automatic (during /maestro.implement)

When you run `/maestro.implement`, the commit message is automatically suffixed with the `[bd:<task-id>]` marker for the task being implemented. No manual action is needed.

### Manual (commits outside maestro)

If you make commits outside the maestro workflow (e.g., hotfixes, manual changes related to a task), append the suffix yourself:

```bash
git commit -m "fix(api): correct null check [bd:agent-maestro-xyz.3]"
```

This ensures those commits are included when computing the task diff.

## Viewing a Task Diff

Use the `task-diff.sh` script to see the combined diff for all commits attributed to a task:

```bash
bash .maestro/scripts/task-diff.sh <task-id>
# Example:
bash .maestro/scripts/task-diff.sh agent-maestro-xyz.3
```

Add `--summary` for a one-line stat:

```bash
bash .maestro/scripts/task-diff.sh agent-maestro-xyz.3 --summary
```

## Known Limitations

1. **Rebase and squash may lose suffixes.** If you interactively rebase or squash commits, the `[bd:...]` suffix may be dropped from the rewritten commit messages. After rebasing, verify that the suffixes are still present in the final commit messages.

2. **Manual commits are not tagged automatically.** Commits made outside `/maestro.implement` will not have the suffix unless you add it yourself. Tasks with missing attribution will show: *"No commits found for task {task_id}. This task may have been completed before commit attribution was enabled."*

3. **Older tasks have no attribution.** Tasks completed before commit attribution was introduced will not have any attributed commits. The `task-diff.sh` script handles this gracefully with a descriptive message.
