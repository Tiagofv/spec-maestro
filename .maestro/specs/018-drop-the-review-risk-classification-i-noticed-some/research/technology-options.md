# Technology Options: Review Risk Classification Removal

**Feature:** Drop Review Risk Classification  
**Research Date:** 2026-02-23  
**Researcher:** Maestro

---

## 1. Current Implementation Analysis

### 1.1 Risk Classification System

The current system uses a three-tier risk classification:

- **HIGH RISK**: Always reviewed (business logic, handlers, data access, auth, payments, API endpoints, migrations)
- **MEDIUM RISK**: Reviewed if >50 lines changed (wiring, middleware, DTOs, adapters, build scripts)
- **LOW RISK**: Automatically skipped (generated code, pure structs, type definitions, constants, test fixtures, docs, imports)

### 1.2 Implementation Location

Risk classification is implemented in:

- `.maestro/commands/maestro.review.md` - Step 3: Risk Classification
- `.maestro/cookbook/review-routing.md` - Risk classification table

---

## 2. Technology Options

### Option A: Complete Removal (Selected)

**Description:** Remove risk classification entirely; review all files except explicitly identified auto-generated files.

**Findings:**

- ✅ Simplest implementation
- ✅ Eliminates the root cause of skipped reviews
- ✅ Matches user requirement to "drop" the classification
- ✅ Auto-generated files can still be identified by pattern matching

**Implementation:**

- Remove Step 3 from maestro.review.md
- Delete review-routing.md cookbook
- Add pattern-based filtering for auto-generated files (entgo, protobuf)

---

### Option B: Modify Risk Thresholds

**Description:** Adjust the risk classification to be more conservative (e.g., move domain files from LOW to MEDIUM).

**Findings:**

- ⚠️ Partial fix; doesn't address underlying issue
- ⚠️ Still requires maintenance of classification table
- ⚠️ Risk of future files being misclassified
- ❌ Doesn't match user requirement to "drop" classification

**Verdict:** Rejected - doesn't fully solve the problem

---

### Option C: Configurable Risk Rules

**Description:** Make risk classification configurable per project or file type.

**Findings:**

- ⚠️ Adds complexity
- ⚠️ Requires configuration management
- ⚠️ Out of scope for this feature (deferred)
- ❌ Doesn't match user requirement to "drop" classification

**Verdict:** Rejected - too complex for current needs

---

## 3. Auto-Generated File Detection

### Detection Patterns

| Type     | Pattern                     | Example       |
| -------- | --------------------------- | ------------- |
| entgo    | Files in `ent/` directories | `ent/user.go` |
| protobuf | `.pb.go` extension          | `user.pb.go`  |

### Detection Approach

**Selected:** Simple pattern matching on file paths

- Check if path contains `/ent/` for entgo files
- Check if filename ends with `.pb.go` for protobuf

**Alternative:** File header detection

- Read first N lines of file for "generated" comment
- ❌ More complex
- ❌ Requires file I/O for every file

**Verdict:** Pattern matching is sufficient and efficient

---

## 4. Recommendations

1. **Adopt Option A** - Complete removal of risk classification
2. **Use pattern-based filtering** for auto-generated files
3. **Document the change** in changelog and team communications

---

## 5. References

- Current risk classification: `.maestro/cookbook/review-routing.md`
- Review command: `.maestro/commands/maestro.review.md` Step 3
- Feature specification: `.maestro/specs/018-drop-the-review-risk-classification-i-noticed-some/spec.md`
