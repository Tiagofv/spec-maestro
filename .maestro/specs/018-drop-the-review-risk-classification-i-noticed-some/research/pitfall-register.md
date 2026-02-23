# Pitfall Register: Review Risk Classification Removal

**Feature:** Drop Review Risk Classification  
**Research Date:** 2026-02-23  
**Researcher:** Maestro

---

## 1. Identified Pitfalls

### Pitfall 1: Performance Impact from Reviewing All Files

**Risk Level:** LOW  
**Likelihood:** Medium  
**Impact:** Medium

**Description:**
Removing risk classification means all files will be reviewed, potentially increasing review time and token usage.

**Evidence:**

- Current system skips ~20-30% of files based on LOW RISK classification
- Files like constants, interfaces, and type definitions will now be reviewed
- Each file requires token processing by LLM

**Mitigation:**

- ✅ Auto-generated files (entgo, protobuf) are still skipped
- ✅ Review system already handles multiple files in parallel
- ✅ No maximum time constraint specified by user
- ⚠️ Monitor review duration after deployment

**Recommendation:**
Accept the risk. Monitor review times post-deployment. If issues arise, consider optimizing the review process (e.g., batching) rather than reintroducing risk classification.

---

### Pitfall 2: Increased Review Noise

**Risk Level:** LOW  
**Likelihood:** High  
**Impact:** Low

**Description:**
Files previously skipped (constants, interfaces) may generate MINOR-level findings, creating noise in reviews.

**Evidence:**

- These files often have simple patterns that LLMs flag (naming, comments)
- Review template's verdict system (MINOR vs CRITICAL) helps filter importance

**Mitigation:**

- ✅ Verdict system distinguishes CRITICAL from MINOR
- ✅ Developers can ignore MINOR suggestions
- ⚠️ May require team communication about new review behavior

**Recommendation:**
Proceed. The benefit of catching issues in domain files outweighs the cost of minor noise. Consider updating team documentation.

---

### Pitfall 3: Accidentally Reviewing Auto-Generated Files

**Risk Level:** MEDIUM  
**Likelihood:** Low  
**Impact:** Medium

**Description:**
If auto-generated file detection fails, LLM will review machine-generated code, wasting tokens and potentially flagging non-issues.

**Evidence:**

- Pattern matching is simple but reliable for entgo and protobuf
- entgo always generates files in `ent/` directory
- protobuf always generates `.pb.go` files

**Mitigation:**

- ✅ Well-defined patterns for both file types
- ✅ Can be tested with known generated files
- ⚠️ Ensure patterns cover edge cases (e.g., `ent/schema/` vs `ent/`)

**Recommendation:**
Test patterns with actual generated files. Edge case: `ent/schema/` contains non-generated schema definitions - ensure these are reviewed.

---

### Pitfall 4: Breaking Existing Review Workflows

**Risk Level:** MEDIUM  
**Likelihood:** Medium  
**Impact:** Medium

**Description:**
Teams or scripts may rely on "SKIPPED" status from reviews. Removing this may break integrations.

**Evidence:**

- Review tasks can be closed with "SKIPPED" reason
- Scripts may parse this status for reporting

**Mitigation:**

- ⚠️ Review `.maestro/commands/maestro.review.md` for status dependencies
- ⚠️ Check if any scripts parse review task status
- ✅ SKIPPED status preserved for auto-generated files (different reason)

**Recommendation:**
Search for usages of "SKIPPED" status in codebase and documentation. Update any dependent scripts.

---

### Pitfall 5: Incomplete Coverage of Auto-Generated Files

**Risk Level:** LOW  
**Likelihood:** Medium  
**Impact:** Low

**Description:**
Other auto-generated files (mocks, OpenAPI) may exist in the project and now will be reviewed.

**Evidence:**

- User specified only entgo and protobuf to skip
- Other generators may exist (mockgen, swagger-codegen, etc.)

**Mitigation:**

- ✅ Current scope limited to entgo and protobuf as specified
- ✅ Out of scope: user-configurable skip patterns (deferred)
- ⚠️ May generate noise for other generated files

**Recommendation:**
Proceed with scope. Document that only entgo and protobuf are excluded. Future enhancement can add configurable patterns.

---

## 2. Summary Table

| Pitfall                      | Risk   | Likelihood | Impact | Status                           |
| ---------------------------- | ------ | ---------- | ------ | -------------------------------- |
| Performance Impact           | LOW    | Medium     | Medium | Accepted with monitoring         |
| Review Noise                 | LOW    | High       | Low    | Accepted - MINOR filtering helps |
| Auto-Gen Detection Failure   | MEDIUM | Low        | Medium | Mitigated by testing patterns    |
| Breaking Workflows           | MEDIUM | Medium     | Medium | Requires pre-deployment check    |
| Incomplete Auto-Gen Coverage | LOW    | Medium     | Low    | In scope per requirements        |

---

## 3. Risk Mitigation Checklist

Before deployment:

- [ ] Test auto-generated file patterns with actual files
- [ ] Search for "SKIPPED" status dependencies
- [ ] Update team documentation on new review behavior
- [ ] Monitor review duration post-deployment

---

## 4. References

- Current review command: `.maestro/commands/maestro.review.md`
- Risk classification: `.maestro/cookbook/review-routing.md`
- Feature specification: `.maestro/specs/018-drop-the-review-risk-classification-i-noticed-some/spec.md`
