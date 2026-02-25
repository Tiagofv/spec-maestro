# Implementation Plan: Better Naming for Specs Folder Creation

**Feature ID:** 013-better-naming-for-the-folders-created-inside-specs
**Spec:** .maestro/specs/013-better-naming-for-the-folders-created-inside-specs/spec.md
**Created:** 2024-02-19
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

This feature modifies the `create-feature.sh` script to generate more readable folder names. The script will:

1. Extract key words from the feature description
2. Truncate intelligently at word boundaries (10-40 chars)
3. Check for duplicates and append counter suffixes if needed
4. Maintain backward compatibility with existing folders

```
Feature Description → Word Extraction → Smart Truncation → Duplicate Check → Folder Name
```

### 1.2 Component Interactions

```
User Input (description)
    ↓
create-feature.sh
    ├── Extract meaningful words (filter out stop words)
    ├── Truncate at word boundary (10-40 chars)
    ├── Check existing folders for duplicates
    ├── Append counter suffix if duplicate
    └── Output JSON with paths
```

### 1.3 Key Design Decisions

| Decision           | Options Considered     | Chosen                      | Rationale                                   |
| ------------------ | ---------------------- | --------------------------- | ------------------------------------------- |
| Truncation method  | Fixed 40 char cutoff   | Word-boundary truncation    | Prevents mid-word cuts, more readable       |
| Stop words         | Strip all common words | Strip only "the", "a", "an" | Too aggressive stripping loses meaning      |
| Duplicate handling | Timestamp suffix       | Counter suffix (-v2, -v3)   | More readable than timestamps               |
| Min length         | No minimum             | 10 char minimum             | Prevents cryptic names like "fix-ui"        |
| Existing folders   | Auto-rename            | Leave as-is                 | Backward compatibility, no breaking changes |

---

## 2. Component Design

### 2.1 New Components

None - this feature modifies existing components only.

### 2.2 Modified Components

#### Component: create-feature.sh

- **Current:** Generates 50-char slug with basic truncation using `cut -c1-50`
- **Change:** Implement intelligent truncation at word boundaries with 10-40 char range, duplicate detection
- **Risk:** Medium - core script used for all feature creation

#### Component: conventions.md (new file)

- **Current:** Does not exist
- **Change:** Create `.maestro/reference/conventions.md` documenting the naming convention
- **Risk:** Low - documentation only

---

## 3. Data Model

No new data entities. The script operates on:

- **Input:** Feature description string
- **Existing data:** Folder names in `.maestro/specs/`
- **Output:** JSON with derived folder name and paths

### 3.3 Data Flow

```
1. Receive description: "Create a kanban board on our Tauri UI"
2. Extract words: ["create", "kanban", "board", "tauri", "ui"]
3. Filter stop words: ["kanban", "board", "tauri", "ui"] (removed "a", "our", "on")
4. Build slug: "kanban-board-tauri-ui" (20 chars, within 10-40 range)
5. Check duplicates: Scan `.maestro/specs/` for existing "XXX-kanban-board-tauri-ui*"
6. If duplicate exists: Append "-v2", "-v3", etc.
7. Output: {"feature_id": "014-kanban-board-tauri-ui", ...}
```

---

## 4. API Contracts

### 4.1 New Endpoints/Methods

None - this is a script modification, not a service API.

### 4.2 Modified Behavior

#### Script: create-feature.sh

- **Current behavior:** Truncates at exactly 50 characters using `cut -c1-50`, may cut words mid-character
- **New behavior:**
  - Truncates at word boundaries between 10-40 characters
  - Checks for existing folders with same base name
  - Appends counter suffixes (-v2, -v3) if duplicates detected
  - Maintains same JSON output format for backward compatibility

---

## 5. Implementation Phases

### Phase 1: Core Naming Logic

- **Goal:** Implement intelligent truncation and word boundary detection
- **Tasks:**
  - Update slug generation to extract key words
  - Implement word-boundary truncation (10-40 chars)
  - Add stop word filtering (the, a, an, and, for, to, of, etc.)
- **Deliverable:** Script generates readable folder names like "014-kanban-board-ui" instead of "014-we-need-to-build-a-kanban-board-on-our-tauri-ui-to"

### Phase 2: Duplicate Detection

- **Goal:** Handle naming collisions gracefully
- **Dependencies:** Phase 1
- **Tasks:**
  - Scan existing `.maestro/specs/` folders
  - Detect potential duplicates from truncation
  - Implement counter suffix logic (-v2, -v3)
- **Deliverable:** Script handles edge cases where truncation creates duplicate names

### Phase 3: Documentation

- **Goal:** Document the naming convention
- **Dependencies:** Phase 1-2 complete and tested
- **Tasks:**
  - Create `.maestro/reference/conventions.md`
  - Document naming rules, examples, and rationale
  - Update any relevant README or AGENTS.md references
- **Deliverable:** Clear documentation for developers

---

## 6. Task Sizing Guidance

### Phase 1 Tasks

| Task | Description                                      | Estimated Size |
| ---- | ------------------------------------------------ | -------------- |
| T1   | Refactor slug generation to extract key words    | S (180 min)    |
| T2   | Implement word-boundary truncation (10-40 chars) | S (120 min)    |
| T3   | Add stop word filtering                          | XS (60 min)    |
| T4   | Test with sample feature descriptions            | XS (45 min)    |

### Phase 2 Tasks

| Task | Description                           | Estimated Size |
| ---- | ------------------------------------- | -------------- |
| T5   | Implement duplicate folder scanning   | S (150 min)    |
| T6   | Add counter suffix logic (-v2, -v3)   | XS (60 min)    |
| T7   | Test edge cases (multiple duplicates) | XS (45 min)    |

### Phase 3 Tasks

| Task | Description                                  | Estimated Size |
| ---- | -------------------------------------------- | -------------- |
| T8   | Create conventions.md with naming rules      | XS (90 min)    |
| T9   | Add examples and edge cases to documentation | XS (45 min)    |
| T10  | Update README/AGENTS.md references           | XS (30 min)    |

---

## 7. Testing Strategy

### 7.1 Unit Tests (Shell Script Tests)

- Test word extraction from various description formats
- Test truncation at word boundaries
- Test stop word filtering
- Test duplicate detection logic
- Test counter suffix generation

### 7.2 Integration Tests

- Create test features with various descriptions
- Verify generated folder names meet criteria (10-40 chars, kebab-case)
- Verify backward compatibility with existing folders
- Verify JSON output format unchanged

### 7.3 Test Data

Sample descriptions for testing:

- Short: "Fix login bug" → Should add words to meet min 10 chars
- Medium: "Create kanban board" → "kanban-board" (12 chars)
- Long: "We need to build a kanban board on our Tauri UI to track tasks" → "kanban-board-tauri" (16 chars)
- Very long: "Implement wave-based parallel execution for maestro task orchestration system" → "wave-based-parallel-execution" (27 chars)
- Duplicate test: Create "kanban-board" twice → Second should be "kanban-board-v2"

---

## 8. Risks and Mitigations

| Risk                                        | Likelihood | Impact | Mitigation                                                  |
| ------------------------------------------- | ---------- | ------ | ----------------------------------------------------------- |
| Existing automation depends on 50-char slug | Medium     | High   | Keep output JSON format identical; test with existing tools |
| Truncation creates ambiguous names          | Low        | Medium | Use 10-char minimum; add manual review if concerned         |
| Duplicate detection misses edge cases       | Low        | Medium | Comprehensive testing with sample data                      |
| Stop word filtering too aggressive          | Low        | Low    | Conservative stop word list (only articles/conjunctions)    |
| Developers confused by new naming           | Low        | Low    | Document in conventions.md; add examples                    |

---

## 9. Open Questions

None - all clarifications resolved in /maestro.clarify.

---

## Changelog

| Date       | Change               | Author  |
| ---------- | -------------------- | ------- |
| 2024-02-19 | Initial plan created | Maestro |
