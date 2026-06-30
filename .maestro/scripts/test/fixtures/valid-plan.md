# Test Plan: Valid Plan

**Repos:** test-repo

## Implementation Tasks

<!-- TASK:BEGIN id=T001 -->
### T001: First Task

**Metadata:**
- **Repo:** test-repo
- **Label:** setup
- **Size:** XS
- **Assignee:** developer1
- **Dependencies:** —

**Description:**
A valid task with all required fields.

**Files to Modify:**
- `file1.txt`

**Acceptance Criteria:**
- [ ] Criterion 1

<!-- TASK:END -->

<!-- TASK:BEGIN id=T002 -->
### T002: Second Task

**Metadata:**
- **Repo:** test-repo
- **Label:** feature
- **Size:** S
- **Assignee:** developer2
- **Dependencies:** T001

**Description:**
Another valid task depending on T001.

**Files to Modify:**
- `file2.txt`

**Acceptance Criteria:**
- [ ] Criterion 1
- [ ] Criterion 2

<!-- TASK:END -->

<!-- TASK:BEGIN id=T003 -->
### T003: Third Task

**Metadata:**
- **Repo:** test-repo
- **Label:** cleanup
- **Size:** XS
- **Assignee:** developer3
- **Dependencies:** T001, T002

**Description:**
Task with multiple dependencies.

**Files to Modify:**
- `file3.txt`

**Acceptance Criteria:**
- [ ] Criterion 1

<!-- TASK:END -->
