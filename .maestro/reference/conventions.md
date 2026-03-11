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

## References

- Feature Spec: `.maestro/specs/013-better-naming-for-the-folders-created-inside-specs/spec.md`
- Implementation Plan: `.maestro/specs/013-better-naming-for-the-folders-created-inside-specs/plan.md`
