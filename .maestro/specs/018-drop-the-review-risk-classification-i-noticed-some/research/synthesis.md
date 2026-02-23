# Synthesis: Review Risk Classification Removal

**Feature:** Drop Review Risk Classification  
**Research Date:** 2026-02-23  
**Researcher:** Maestro  
**Readiness Verdict:** ✅ READY

---

## 1. Executive Summary

Research confirms that removing the risk classification system is the correct approach. The current three-tier system (HIGH/MEDIUM/LOW) is causing important files (domain files, interfaces, constants) to be automatically skipped, creating a blind spot in code reviews.

The solution is straightforward:

1. Remove risk classification logic from the review command
2. Delete the review-routing.md cookbook file
3. Implement simple pattern matching to skip only auto-generated files (entgo, protobuf)
4. Review all other files regardless of type or size

---

## 2. Major Recommendation

### Decision: Remove Risk Classification Entirely

**Rationale:**

- The current system classifies domain files as LOW RISK and skips them, causing important changes to be missed
- File type is not a reliable predictor of change importance
- The user explicitly requested to "drop" the classification
- Simple solution: review everything except clearly identified auto-generated files

**Implementation Approach:**

1. **Remove Step 3** from `.maestro/commands/maestro.review.md` (Risk Classification section)
2. **Delete** `.maestro/cookbook/review-routing.md`
3. **Add pattern-based filtering** for auto-generated files:
   - entgo: files in `ent/` directories
   - protobuf: files ending with `.pb.go`
4. **Update review output** to explicitly list skipped auto-generated files

**Alternatives Considered:**

- **Modify thresholds** (rejected - partial fix, doesn't solve root cause)
- **Make configurable** (rejected - out of scope, adds complexity)
- **Keep system** (rejected - doesn't meet user requirement)

**Confidence:** HIGH

---

## 3. Adopt-Now vs Defer Split

### Adopt Now (In Scope)

| Item                                        | Priority | Reason                          |
| ------------------------------------------- | -------- | ------------------------------- |
| Remove risk classification logic            | P0       | Core requirement                |
| Delete review-routing.md                    | P0       | Removes dead code               |
| Skip auto-generated files (entgo, protobuf) | P0       | Preserves valuable optimization |
| Document skipped files in output            | P1       | Transparency and auditability   |
| Update review command docs                  | P1       | Keeps documentation current     |

### Defer (Out of Scope)

| Item                       | Reason                                         |
| -------------------------- | ---------------------------------------------- |
| Configurable skip patterns | User explicitly said "just entgo and protobuf" |
| Header-based detection     | Pattern matching is sufficient                 |
| Performance optimizations  | No constraint specified, can monitor           |
| Other generated file types | Out of scope per requirements                  |

---

## 4. External Approach Comparison

| Approach        | Key Difference                | Our Direction                             |
| --------------- | ----------------------------- | ----------------------------------------- |
| **GitHub PRs**  | Shows all files, no auto-skip | ✅ Similar - we skip only generated files |
| **Gerrit**      | Configurable path exclusion   | ✅ Simpler - built-in patterns, no config |
| **Phabricator** | Complex herald rules          | ✅ Simpler - no rule engine needed        |
| **AI Tools**    | Black-box file filtering      | ✅ Transparent - explicit patterns        |
| **Our Current** | Risk classification           | ❌ Removing - caused missed reviews       |

**Preferred Direction:** Transparent, simple, user-controlled approach that reviews everything except clearly identified auto-generated files.

---

## 5. Ambiguities: Blocker vs Non-Blocker

| Ambiguity                     | Status          | Resolution                                                                   |
| ----------------------------- | --------------- | ---------------------------------------------------------------------------- |
| entgo pattern edge cases      | **Non-blocker** | Test with actual files; edge case: `ent/schema/` contains non-generated code |
| Protobuf file locations       | **Non-blocker** | `.pb.go` extension is reliable across locations                              |
| "SKIPPED" status dependencies | **Non-blocker** | Search for usages; preserve for auto-generated with different reason         |
| Performance impact            | **Non-blocker** | No constraint specified; monitor post-deployment                             |

**No blockers identified.** All ambiguities can be resolved during implementation or have acceptable mitigations.

---

## 6. Risk Assessment

| Risk                    | Level  | Mitigation                            |
| ----------------------- | ------ | ------------------------------------- |
| Performance increase    | LOW    | Monitor; auto-gen files still skipped |
| Review noise            | LOW    | MINOR vs CRITICAL distinction         |
| Missing generated files | LOW    | Test patterns pre-deployment          |
| Breaking workflows      | MEDIUM | Search for "SKIPPED" dependencies     |

**Overall Risk:** LOW

---

## 7. Planning Readiness

### ✅ Minimum Items Met

- [x] Clear decision on approach (remove classification)
- [x] Auto-generated file detection patterns defined
- [x] Scope boundaries established (entgo + protobuf only)
- [x] Risk assessment complete
- [x] No blockers identified
- [x] Files to modify identified:
  - `.maestro/commands/maestro.review.md` (remove Step 3)
  - `.maestro/cookbook/review-routing.md` (delete)
- [x] Success criteria defined in spec

### Open Questions Carried Forward

None. All clarification markers from spec have been resolved.

---

## 8. Recommendations for Planning

### Task Breakdown Suggestions

1. **Modify review command** - Remove risk classification step, add pattern matching for auto-generated files
2. **Delete cookbook** - Remove review-routing.md entirely
3. **Update documentation** - Ensure commands reflect new behavior
4. **Test** - Verify patterns work with actual entgo and protobuf files

### Estimation Notes

- **Complexity:** LOW - documentation/command changes only
- **Risk:** LOW - well understood, reversible
- **Dependencies:** None - self-contained change

---

## 9. Conclusion

The research supports proceeding with planning. The feature is:

- Well understood
- Technically feasible
- Low risk
- Ready for implementation

**Next Step:** Run `/maestro.plan` to generate implementation tasks.

---

## Changelog

| Date       | Change            | Author  |
| ---------- | ----------------- | ------- |
| 2026-02-23 | Initial synthesis | Maestro |
