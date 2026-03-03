# Feature: Better Naming for Specs Folder Creation

**Spec ID:** 013-better-naming-for-the-folders-created-inside-specs
**Author:** Maestro
**Created:** 2024-02-19
**Last Updated:** 2024-02-19 (clarifications resolved)
**Status:** Draft

---

## 1. Problem Statement

Currently, when Maestro creates folders inside the `.maestro/specs/` directory, it generates folder names by converting the feature description into a slug. This approach results in folder names that are difficult to read and navigate:

- Names are excessively long (often 50+ characters)
- Descriptions get truncated mid-word, creating confusion
- No clear distinction between the numeric ID and descriptive text
- Developers struggle to quickly identify which folder contains which feature
- Tab completion in terminals becomes cumbersome

For example, folders like `001-we-need-to-build-a-kanban-board-on-our-tauri-ui-to` and `012-lets-change-the-way-we-select-the-agent-to-impleme` are truncated and hard to scan visually.

This naming convention makes it difficult for developers to quickly locate specific feature specifications when working with multiple features in parallel.

---

## 2. Proposed Solution

Introduce a more readable and navigable folder naming convention for specs directories. The new naming scheme should prioritize human readability while maintaining uniqueness and the sequential numbering system.

The goal is to transform folder names from truncated, hyphen-heavy slugs into concise, meaningful names that developers can quickly identify and type.

---

## 3. User Stories

### Story 1: Developer Navigation

**As a** developer working with multiple features,
**I want** specs folders to have short, meaningful names,
**so that** I can quickly identify and navigate to the correct feature specification.

**Acceptance Criteria:**

- [ ] Folder names are readable at a glance without scrolling in terminal listings
- [ ] Folder names convey the feature's purpose within 3-5 words maximum
- [ ] Developers can type folder names quickly using tab completion
- [ ] Descriptive portion is between 10-40 characters (excluding numeric prefix)
- [ ] Names use kebab-case (lowercase with hyphens)

### Story 2: Feature Identification

**As a** developer reviewing the specs directory,
**I want** each folder name to clearly represent the feature it contains,
**so that** I don't need to open the folder or read the spec.md to understand what's inside.

**Acceptance Criteria:**

- [ ] Folder names use descriptive keywords from the feature title
- [ ] Truncation, if necessary, occurs at word boundaries, not mid-word
- [ ] Numeric prefix remains consistent and clearly separated from the descriptive portion

### Story 3: Consistent Naming Pattern

**As a** team member following Maestro workflows,
**I want** all specs folders to follow the same naming convention,
**so that** I can predict and rely on the folder structure.

**Acceptance Criteria:**

- [ ] The naming convention is documented and applied automatically by Maestro
- [ ] Existing folders maintain backward compatibility (no forced renames)
- [ ] New folders consistently follow the improved naming pattern

---

## 4. Success Criteria

The feature is considered complete when:

1. New specs folders are created with names that are readable within a standard terminal window width (80 characters)
2. Developers can identify the feature purpose from the folder name without opening files
3. Folder names use kebab-case (lowercase with hyphens)
4. Descriptive portion is between 10-40 characters (excluding the numeric prefix)
5. No mid-word truncation occurs when generating folder names
6. Duplicate names are handled by appending counter suffixes (e.g., `-v2`, `-v3`)
7. The naming convention is documented in `.maestro/reference/conventions.md`

---

## 5. Scope

### 5.1 In Scope

- Defining a new naming convention for specs folder generation
- Updating the `create-feature.sh` script to use the new naming pattern
- Documentation of the naming convention in `.maestro/reference/conventions.md`
- Handling of existing folders (backward compatibility)
- Implementing duplicate name detection with counter suffixes

### 5.2 Out of Scope

- Renaming existing spec folders automatically
- Changes to folder structure inside `.maestro/` other than specs/
- Renaming of existing branches or worktrees
- Modifications to the branch naming convention

### 5.3 Deferred

- Potential migration tool for manually renaming old folders (if desired later)
- User-configurable naming patterns

---

## 6. Dependencies

- The `create-feature.sh` script in `.maestro/scripts/`
- Existing `.maestro/specs/` directory structure

---

## 7. Open Questions

- **Naming approach:** Balance brevity and descriptiveness — names should be concise yet meaningful
- **Character limits:** Maximum 40 characters for the descriptive portion; minimum 10 characters to prevent overly cryptic names
- **Naming convention:** Use kebab-case (lowercase with hyphens) for consistency with shell conventions
- **Word handling:** Do not automatically strip common words; preserve the feature's core meaning
- **Duplicate handling:** If truncation would create a duplicate name, append a counter suffix (e.g., `-v2`, `-v3`)
- **Documentation:** The naming convention will be documented in `.maestro/reference/conventions.md`

---

## 8. Risks

- Existing automation or scripts may depend on the current folder naming pattern
- Developers accustomed to the current naming may experience temporary confusion
- Need to ensure the slug generation is deterministic and doesn't create duplicate names

---

## Changelog

| Date       | Change                           | Author  |
| ---------- | -------------------------------- | ------- |
| 2024-02-19 | Initial spec created             | Maestro |
| 2024-02-19 | Resolved 4 clarification markers | Maestro |
