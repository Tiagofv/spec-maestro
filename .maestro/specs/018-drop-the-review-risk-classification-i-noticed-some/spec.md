# Feature: Drop Review Risk Classification

**Spec ID:** 018-drop-the-review-risk-classification-i-noticed-some
**Author:** Maestro
**Created:** 2026-02-23
**Last Updated:** 2026-02-23
**Status:** Draft

---

## 1. Problem Statement

The current review system uses a risk classification mechanism that categorizes files as HIGH, MEDIUM, or LOW risk. Files classified as LOW risk are automatically skipped and marked as "SKIPPED" in reviews, regardless of the actual changes made.

This classification is causing relevant changes in domain files and other "low risk" categories to be overlooked. For example, small modifications to domain files—which often contain critical business logic—are being skipped because they fall under the LOW RISK category. This creates a blind spot where important changes are not reviewed, potentially allowing bugs or inconsistencies to reach production.

The risk classification was intended to optimize review time by skipping trivial changes, but in practice it's skipping changes that should be reviewed, reducing the quality assurance coverage of the codebase.

---

## 2. Proposed Solution

Remove the review risk classification system entirely. All files should be subject to review, regardless of file type or change size. The review process should evaluate each change based on its actual content and impact, not on a predetermined risk category.

This ensures that every modification receives appropriate attention and prevents important changes from being automatically bypassed.

---

## 3. User Stories

### Story 1: Review All Domain Changes

**As a** developer submitting code for review,
**I want** all my changes to domain files to be reviewed,
**so that** critical business logic modifications are not silently skipped.

**Acceptance Criteria:**

- [ ] When a domain file is modified, it receives a code review
- [ ] The review output includes findings specific to the domain file changes
- [ ] The review is not marked as "SKIPPED" based on file type alone

### Story 2: No Automatic File Skipping

**As a** reviewer checking code changes,
**I want** to see reviews for all modified files,
**so that** I can catch issues in files that were previously classified as "low risk".

**Acceptance Criteria:**

- [ ] Files previously classified as LOW RISK now receive full reviews
- [ ] Files previously classified as MEDIUM RISK continue to receive reviews
- [ ] No files are automatically skipped based on predetermined risk categories
- [ ] Auto-generated files (entgo and protobuf) are identified and skipped based on patterns (e.g., files in `ent/` directories for entgo, `.pb.go` files for protobuf)

### Story 3: Consistent Review Coverage

**As a** code quality engineer,
**I want** the review system to provide consistent coverage across all file types,
**so that** I can trust that no important changes are bypassing the review process.

**Acceptance Criteria:**

- [ ] All changed files in a commit are listed in the review output
- [ ] Each file shows either PASS, MINOR, or CRITICAL verdict
- [ ] No files show "SKIPPED" status due to risk classification
- [ ] Review statistics show 100% coverage of changed files

---

## 4. Success Criteria

The feature is considered complete when:

1. The review system no longer uses risk classification (HIGH/MEDIUM/LOW) to determine whether to review a file
2. All files that have changes receive a review verdict (PASS, MINOR, or CRITICAL)
3. Files that were previously classified as LOW RISK (domain files, constants, interfaces) now receive reviews
4. Auto-generated files (entgo and protobuf) are identified and skipped based on patterns:
   - entgo: files in `ent/` directories
   - protobuf: files with `.pb.go` extension
5. Review reports no longer include "SKIPPED" status due to risk classification
6. The review-routing.md cookbook is updated to reflect the new behavior or removed

---

## 5. Scope

### 5.1 In Scope

- Removing the risk classification logic from the review system
- Ensuring all file types receive reviews
- Updating documentation to reflect the change
- Remove the `review-routing.md` cookbook file entirely

### 5.2 Out of Scope

- Changing the review verdict system (PASS/MINOR/CRITICAL remains)
- Modifying the review output format (JSON schema remains unchanged)
- Adding new review rules or checks
- Performance optimization of the review process
- Changes to the review template structure

### 5.3 Deferred

- Implementing a more nuanced file importance detection system
- Adding user-configurable skip patterns for specific file types
- Integration with external code quality tools

---

## 6. Dependencies

- The review system implementation (currently uses risk classification from review-routing.md)
- Review orchestrator that makes skip decisions
- Review output generator that reports SKIPPED status

---

## 7. Open Questions

- Auto-generated files (entgo and protobuf) should be skipped. No vendor files.
- [RESOLVED: Original LOW RISK rationale was to optimize review time, but led to missing important changes. Now addressed by reviewing all files except auto-generated ones.]
- [RESOLVED: Applies to new reviews going forward; existing reviews remain unchanged]

---

## 8. Risks

1. **Performance Impact**: Removing risk classification may increase review time as more files are processed. [RESOLVED: No maximum time constraint identified.]

2. **Noise Increase**: Reviews may become noisier with trivial findings in files that were previously skipped. However, the review template's verdict system (MINOR vs CRITICAL) should help filter important issues.

3. **Developer Workflow**: Developers may see more review comments on files they previously expected to be skipped. This is the intended behavior change but may require communication.

---

## Changelog

| Date       | Change               | Author  |
| ---------- | -------------------- | ------- |
| 2026-02-23 | Initial spec created | Maestro |
