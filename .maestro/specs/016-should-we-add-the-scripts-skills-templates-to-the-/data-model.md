# Data Model: 016-should-we-add-the-scripts-skills-templates-to-the-

## Overview

This feature does not introduce persistent database entities. The model below defines the in-memory transaction structure used to guarantee all-or-nothing installation for required starter asset groups.

## Entity: InstallTransaction

```
InstallTransaction
  required_groups: ["scripts", "skills", "templates"]
  conflict_action: "overwrite" | "backup" | "cancel"
  staged_paths: string[]
  backups_created: string[]
  fetch_results:
    - group: string
      status: "fetched" | "failed"
      error_message: string?
  install_status: "pending" | "committed" | "rolled_back"
```

## Rules

1. `required_groups` always contains all three baseline groups.
2. `install_status` moves to `committed` only when all required groups are successfully fetched and written.
3. Any required-group failure transitions to `rolled_back` and removes staged required-asset changes.
4. Paths recorded in `staged_paths` and `backups_created` are used only for operation safety and cleanup.

## Persistence

- No long-term persistence required.
- State exists only for command execution scope and logging/output decisions.
