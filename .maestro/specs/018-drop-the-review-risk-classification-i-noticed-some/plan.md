# Implementation Plan: Drop Review Risk Classification

**Feature ID:** 018-drop-the-review-risk-classification-i-noticed-some
**Spec:** `.maestro/specs/018-drop-the-review-risk-classification-i-noticed-some/spec.md`
**Created:** 2026-02-23
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

This feature modifies the review command workflow to remove the risk classification tier system (HIGH/MEDIUM/LOW) and replace it with a simpler approach: review all files except explicitly identified auto-generated files.

```
Current Flow:
  Files Changed → Risk Classification → Skip LOW RISK → Review HIGH/MEDIUM

New Flow:
  Files Changed → Check Auto-Generated Pattern → Skip entgo/protobuf → Review All Others
```

### 1.2 Component Interactions

The change affects the review command workflow:

1. Review command reads changed files
2. Instead of classifying by risk tier, checks if file matches auto-generated patterns
3. If auto-generated: skip with explicit documentation
4. If not auto-generated: proceed to review

### 1.3 Key Design Decisions

| Decision                      | Options Considered                                    | Chosen                         | Rationale                                                                                        |
| ----------------------------- | ----------------------------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------ |
| Risk classification removal   | Keep/Modify/Remove                                    | Remove                         | User explicitly requested to "drop" classification; domain files being skipped is critical issue |
| Auto-generated detection      | Header scanning/Directory patterns/Extension patterns | Directory + Extension patterns | Simple, fast, reliable for entgo (ent/) and protobuf (.pb.go)                                    |
| Scope of auto-generated files | All generated types/User-specified list               | entgo + protobuf only          | Per user requirements; keeps scope minimal                                                       |
| Cookbook handling             | Update/Deprecate/Remove                               | Remove                         | Dead code elimination; user requested removal                                                    |

---

## 2. Component Design

### 2.1 New Components

No new components required. This is a modification to existing documentation/command files.

### 2.2 Modified Components

#### Component: Review Command (`maestro.review.md`)

- **Current:** Step 3 classifies files as HIGH/MEDIUM/LOW risk; LOW risk files are automatically skipped
- **Change:**
  - Remove Step 3 (Risk Classification section)
  - Add pattern matching to identify auto-generated files
  - Skip only files matching entgo or protobuf patterns
  - Update Step 5 (Spawn Reviewer) to pass all non-auto-generated files
  - Update Step 8 (Report Results) to document skipped files
- **Risk:** LOW - Documentation change; reversible by reverting the file

#### Component: Review Routing Cookbook (`review-routing.md`)

- **Current:** Contains risk classification table (HIGH/MEDIUM/LOW)
- **Change:** Delete the entire file
- **Risk:** LOW - Dead code removal; no dependencies in code (only referenced in documentation)

---

## 3. Data Model

### 3.1 New Entities

No new entities. This feature modifies workflow logic only.

### 3.2 Modified Entities

#### Entity: Review Task Output

- **Current fields:** `verdict` (PASS/MINOR/CRITICAL/SKIPPED), `files`, `risk_level`
- **New fields:** None
- **Modified behavior:**
  - SKIPPED status only for auto-generated files, not LOW RISK files
  - New reason format: "SKIPPED | auto-generated: entgo" or "SKIPPED | auto-generated: protobuf"

### 3.3 Data Flow

**Before:**

1. Get changed files → 2. Classify by risk → 3. Skip LOW → 4. Review HIGH/MEDIUM → 5. Output verdict

**After:**

1. Get changed files → 2. Check auto-gen patterns → 3. Skip entgo/protobuf → 4. Review rest → 5. Output verdict

---

## 4. API Contracts

### 4.1 New Endpoints/Methods

None. This feature modifies existing command behavior.

### 4.2 Modified Endpoints/Methods

#### Command: `/maestro.review`

- **Current behavior:** Uses risk classification from `review-routing.md` to determine which files to review
- **New behavior:**
  - Reviews all files except those matching auto-generated patterns
  - Patterns:
    - entgo: path contains `/ent/` or starts with `ent/`
    - protobuf: filename ends with `.pb.go`
- **Breaking:** No - output format (JSON) remains the same, only which files are reviewed changes

---

## 5. Implementation Phases

### Phase 1: Remove Risk Classification from Review Command

- **Goal:** Update the review command to remove Step 3 and add auto-generated file detection
- **Tasks:**
  - Remove Step 3 (Risk Classification) from `.maestro/commands/maestro.review.md` — Assignee: general
  - Add pattern matching logic for auto-generated files — Assignee: general
  - Update Step 5 to pass all non-auto-generated files to reviewer — Assignee: general
  - Update Step 8 to document skipped files — Assignee: general
- **Deliverable:** Review command documentation updated

### Phase 2: Delete Review Routing Cookbook

- **Goal:** Remove dead code (review-routing.md)
- **Dependencies:** Phase 1 (ensure no references remain)
- **Tasks:**
  - Verify no other files reference `review-routing.md` — Assignee: general
  - Delete `.maestro/cookbook/review-routing.md` — Assignee: general
- **Deliverable:** Cookbook file removed

### Phase 3: Testing

- **Goal:** Verify patterns work correctly
- **Dependencies:** Phase 1 and 2
- **Tasks:**
  - Test entgo pattern with actual entgo generated files — Assignee: general
  - Test protobuf pattern with actual .pb.go files — Assignee: general
  - Verify domain files (previously LOW RISK) are now reviewed — Assignee: general
- **Deliverable:** Test results confirming correct behavior

---

## 6. Task Sizing Guidance

### 6.1 Size Definitions

| Size   | Time Range      | Status        |
| ------ | --------------- | ------------- |
| **XS** | 0-120 minutes   | ✅ Accepted   |
| **S**  | 121-360 minutes | ✅ Accepted   |
| **M**  | 361-720 minutes | ❌ Must split |
| **L**  | 721+ minutes    | ❌ Must split |

### 6.2 Task Breakdown

All tasks in this plan are **XS** or **S** size:

1. **Remove Step 3 from review command** — Size: XS (~60 min)
2. **Add auto-generated file detection** — Size: XS (~90 min)
3. **Update Step 5 (file passing)** — Size: XS (~30 min)
4. **Update Step 8 (documentation)** — Size: XS (~30 min)
5. **Verify no references to cookbook** — Size: XS (~30 min)
6. **Delete review-routing.md** — Size: XS (~15 min)
7. **Test entgo pattern** — Size: S (~180 min)
8. **Test protobuf pattern** — Size: S (~180 min)
9. **Test domain file review** — Size: S (~180 min)

---

## 7. Testing Strategy

### 7.1 Unit Tests

Not applicable - this feature modifies documentation/commands, not code.

### 7.2 Integration Tests

Test the review command behavior:

- **Test Case 1:** entgo file detection
  - Create a file at `ent/user.go`
  - Run review command
  - Verify file is skipped with "auto-generated: entgo" reason

- **Test Case 2:** protobuf file detection
  - Create a file at `api/user.pb.go`
  - Run review command
  - Verify file is skipped with "auto-generated: protobuf" reason

- **Test Case 3:** Domain file review
  - Create a file at `domain/user.go`
  - Run review command
  - Verify file is reviewed (not skipped)

- **Test Case 4:** Interface file review
  - Create a file at `interfaces/repository.go`
  - Run review command
  - Verify file is reviewed (previously LOW RISK)

### 7.3 End-to-End Tests

Run complete review workflow on a test feature:

1. Create a test feature with mixed file types
2. Run `/maestro.review`
3. Verify correct files are reviewed vs skipped
4. Verify output format is correct

### 7.4 Test Data

Required test files:

- `ent/test.go` (simulated entgo generated file)
- `test.pb.go` (simulated protobuf generated file)
- `domain/test.go` (simulated domain file)
- `interfaces/test.go` (simulated interface file)
- `constants/test.go` (simulated constants file)

---

## 8. Risks and Mitigations

| Risk                          | Likelihood | Impact | Mitigation                                                                                                     |
| ----------------------------- | ---------- | ------ | -------------------------------------------------------------------------------------------------------------- |
| Review noise increase         | High       | Low    | MINOR vs CRITICAL distinction filters trivial issues; monitor after deployment                                 |
| Performance impact            | Medium     | Low    | Monitor review duration; no constraint specified                                                               |
| entgo pattern false positives | Low        | Medium | Test with actual entgo files; edge case: `ent/schema/` contains non-generated code - ensure these are reviewed |
| Breaking existing workflows   | Low        | Medium | Search for "SKIPPED" status dependencies; preserve SKIPPED status for auto-generated files                     |
| Incomplete cookbook removal   | Low        | Medium | Verify no references before deletion; git history preserves file if needed                                     |

---

## 9. Open Questions

- None. All clarification markers resolved in `/maestro.clarify` phase.

---

## Changelog

| Date       | Change               | Author  |
| ---------- | -------------------- | ------- |
| 2026-02-23 | Initial plan created | Maestro |
