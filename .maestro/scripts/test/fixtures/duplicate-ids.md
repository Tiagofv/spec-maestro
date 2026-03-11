# Test Plan: Duplicate IDs

## Implementation Tasks

<!-- TASK:BEGIN id=T001 -->
### T001: First Task

**Metadata:**
- **Label:** setup
- **Size:** XS
- **Assignee:** developer1
- **Dependencies:** —

**Description:**
First occurrence of T001.

**Files to Modify:**
- `file1.txt`

**Acceptance Criteria:**
- [ ] Criterion 1

<!-- TASK:END -->

<!-- TASK:BEGIN id=T001 -->
### T001: Duplicate Task

**Metadata:**
- **Label:** feature
- **Size:** S
- **Assignee:** developer2
- **Dependencies:** —

**Description:**
Duplicate T001 ID - this should be rejected.

**Files to Modify:**
- `file2.txt`

**Acceptance Criteria:**
- [ ] Criterion 1

<!-- TASK:END -->
