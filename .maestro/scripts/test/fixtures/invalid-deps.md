# Test Plan: Invalid Dependencies

## Implementation Tasks

<!-- TASK:BEGIN id=T001 -->
### T001: Valid First Task

**Metadata:**
- **Label:** setup
- **Size:** XS
- **Assignee:** developer1
- **Dependencies:** —

**Description:**
A valid task.

**Files to Modify:**
- `file1.txt`

**Acceptance Criteria:**
- [ ] Criterion 1

<!-- TASK:END -->

<!-- TASK:BEGIN id=T002 -->
### T002: Invalid Dependency Format

**Metadata:**
- **Label:** feature
- **Size:** XS
- **Assignee:** developer2
- **Dependencies:** task-001

**Description:**
This task has invalid dependency format (should be T###).

**Files to Modify:**
- `file2.txt`

**Acceptance Criteria:**
- [ ] Criterion 1

<!-- TASK:END -->

<!-- TASK:BEGIN id=T003 -->
### T003: Non-existent Dependency

**Metadata:**
- **Label:** cleanup
- **Size:** S
- **Assignee:** developer3
- **Dependencies:** T999

**Description:**
This task references T999 which does not exist.

**Files to Modify:**
- `file3.txt`

**Acceptance Criteria:**
- [ ] Criterion 1

<!-- TASK:END -->

<!-- TASK:BEGIN id=T004 -->
### T004: Mixed Valid and Invalid Dependencies

**Metadata:**
- **Label:** test
- **Size:** XS
- **Assignee:** developer4
- **Dependencies:** T001, T999, bad-format

**Description:**
This task has T001 (valid), T999 (non-existent), and bad-format (invalid).

**Files to Modify:**
- `file4.txt`

**Acceptance Criteria:**
- [ ] Criterion 1

<!-- TASK:END -->
