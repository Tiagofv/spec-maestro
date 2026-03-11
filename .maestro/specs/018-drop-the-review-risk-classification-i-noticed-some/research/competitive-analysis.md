# Competitive Analysis: Review Risk Classification Removal

**Feature:** Drop Review Risk Classification  
**Research Date:** 2026-02-23  
**Researcher:** Maestro

---

## 1. Analysis Scope

Comparing how different code review systems and approaches handle file filtering and auto-generated files.

---

## 2. Approach 1: GitHub Code Review (Human-Driven)

**Description:**
GitHub's pull request review system shows all changed files by default, with no automatic risk classification.

**File Handling:**

- ✅ All files appear in PR diff
- ✅ Reviewers can choose which files to focus on
- ✅ Files can be marked as "viewed"
- ⚠️ No automatic skipping of auto-generated files
- ⚠️ Large PRs with many files can be overwhelming

**Auto-Generated Files:**

- Not automatically detected or skipped
- Often included in `.gitattributes` with `linguist-generated=true` to collapse them
- Still appear in diff but marked as generated

**Trade-offs:**

- ✅ Transparency - reviewers see everything
- ✅ No risk of missing important changes
- ⚠️ Manual effort required to identify generated files
- ❌ Can be noisy with large generated files

**Relevance:**
This feature moves toward GitHub's approach but with automated detection of generated files.

---

## 3. Approach 2: Google's Code Review (Gerrit)

**Description:**
Gerrit supports labeling files and custom filters but doesn't automatically classify risk.

**File Handling:**

- ✅ All changed files shown
- ✅ Custom labels and filters can be created
- ✅ Can exclude paths via configuration
- ⚠️ Configuration required to skip generated files

**Auto-Generated Files:**

- Excluded via project configuration (`.gitignore`-style patterns)
- Requires manual setup per project

**Trade-offs:**

- ✅ Flexible and configurable
- ✅ No risk of missing files
- ⚠️ Configuration overhead
- ⚠️ Per-project setup required

**Relevance:**
Similar to this feature, but requires explicit configuration. Our approach is simpler with built-in patterns.

---

## 4. Approach 3: Phabricator/Differential

**Description:**
Phabricator allows complex review rules and can exclude files via herald rules.

**File Handling:**

- ✅ Highly configurable review rules
- ✅ Can auto-assign reviewers based on file paths
- ✅ Can exclude files from review requirements
- ⚠️ Complex configuration

**Auto-Generated Files:**

- Excluded via herald rules or `.arcconfig`
- Requires explicit configuration

**Trade-offs:**

- ✅ Very powerful and flexible
- ✅ Enterprise-grade features
- ❌ Complex to set up and maintain
- ❌ Overkill for most projects

**Relevance:**
Too complex for our needs. The current feature intentionally avoids configuration complexity.

---

## 5. Approach 4: AI-Powered Review Tools (e.g., Amazon CodeGuru, DeepCode)

**Description:**
Modern AI code review tools often filter files based on their ability to provide meaningful feedback.

**File Handling:**

- ✅ Skip files where ML model has low confidence
- ✅ Focus on files with detectable issues
- ⚠️ Black box - hard to understand why files are skipped

**Auto-Generated Files:**

- Usually skipped if detected
- Detection often based on file content analysis

**Trade-offs:**

- ✅ Reduces noise from unreviewable files
- ❌ Opacity - hard to predict what gets reviewed
- ❌ False confidence - may skip important files

**Relevance:**
This feature is the opposite approach: explicit, transparent, and user-controlled.

---

## 6. Approach 5: Our Current System (Pre-Change)

**Description:**
Risk classification with three tiers (HIGH/MEDIUM/LOW) and automatic skipping.

**File Handling:**

- ✅ LOW RISK files automatically skipped
- ✅ Clear classification table
- ❌ Domain files classified as LOW and skipped
- ❌ Risk of missing important changes

**Auto-Generated Files:**

- Classified as LOW and skipped
- ✅ Automatic
- ⚠️ Other LOW RISK files (domain, interfaces) also skipped

**Trade-offs:**

- ✅ Fast reviews (fewer files)
- ❌ Silent skipping of important files
- ❌ Brittle classification (file type ≠ importance)

**Relevance:**
This is what we're removing due to its limitations.

---

## 7. Comparison Summary

| Approach         | Transparency | Configuration | Auto-Gen Handling | Noise Level | Risk of Missing Files |
| ---------------- | ------------ | ------------- | ----------------- | ----------- | --------------------- |
| GitHub           | High         | None          | Manual            | High        | Low                   |
| Gerrit           | High         | Medium        | Configurable      | Medium      | Low                   |
| Phabricator      | High         | High          | Configurable      | Low         | Low                   |
| AI Tools         | Low          | None          | Automatic         | Low         | High                  |
| **Our Current**  | Medium       | None          | Automatic         | Low         | **High**              |
| **Our Proposed** | High         | None          | **Automatic**     | Medium      | Low                   |

---

## 8. Preferred Direction

**Adopt a hybrid approach:**

1. **GitHub's transparency** - Review all files by default
2. **Built-in auto-generation detection** - Like AI tools but transparent
3. **Zero configuration** - Simple, works out of the box
4. **Explicit skip reasons** - Clear audit trail

**Rationale:**

- Balances transparency with practicality
- Eliminates the root cause (risk classification) while preserving the benefit (skip generated files)
- Simpler than configurable systems (Gerrit, Phabricator)
- More reliable than opaque AI approaches

---

## 9. References

- GitHub: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/
- Gerrit: https://gerrit-review.googlesource.com/Documentation/
- Phabricator: https://secure.phabricator.com/book/phabricator/
- Amazon CodeGuru: https://aws.amazon.com/codeguru/
