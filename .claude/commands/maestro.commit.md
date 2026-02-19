---
description: >
  Create layer-separated atomic commits from staged changes.
  Groups by architectural layer, proposes plan, waits for confirmation.
  Never stages additional files. Never pushes.
argument-hint: [--auto to skip confirmation]
---

# maestro.commit

Create layer-separated commits.

## Step 1: Check Staged Changes

```bash
git diff --cached --name-only
```

If no staged changes:

- Tell the user: "No staged changes. Stage files with `git add` first."
- Stop

## Step 2: Classify Files by Layer

Read the constitution (`.maestro/constitution.md`) to understand the project's layer structure.

If no constitution, use default layers:

1. **data** — Database migrations, schemas, models
2. **domain** — Business logic, entities, value objects
3. **application** — Use cases, commands, queries
4. **infrastructure** — External services, repositories, messaging
5. **presentation** — API, UI, handlers, controllers
6. **test** — Test files
7. **config** — Configuration files

Classify each staged file into a layer based on:

- File path patterns
- Directory names
- File extensions

## Step 3: Determine Commit Order

Order commits from innermost to outermost layer:

1. data (migrations first — they're prerequisites)
2. domain (pure business logic)
3. application (orchestrates domain)
4. infrastructure (depends on domain/application)
5. presentation (depends on everything)
6. test (tests the above)
7. config (configuration changes)

This ensures each commit is independently deployable and dependencies are satisfied.

## Step 4: Generate Commit Messages

For each layer with changes, draft a commit message:

```
{emoji} {layer}: {summary}

{optional body with details}
```

Layer emojis:

- data
- domain
- application
- infrastructure
- presentation
- test
- config

Message rules:

- Imperative mood ("Add X" not "Added X")
- First line <= 72 characters
- Focus on WHY, not WHAT (the diff shows WHAT)

## Step 5: Present Commit Plan

Show the proposed commits:

```
## Commit Plan

1. data: Add vendor_status column to vendors table
   - migrations/20240115_add_vendor_status.sql

2. domain: Add VendorStatus enum and validation
   - internal/domain/vendor/status.go

3. application: Add UpdateVendorStatus command
   - internal/app/commands/update_vendor_status.go

4. infrastructure: Implement status update in repository
   - internal/infra/repo/vendor_repo.go

5. test: Add vendor status tests
   - internal/domain/vendor/status_test.go
   - internal/app/commands/update_vendor_status_test.go

Execute this plan? [y/N/edit]
```

## Step 6: Wait for Confirmation

If `$ARGUMENTS` contains `--auto`:

- Skip confirmation, proceed to Step 7

Otherwise:

- Wait for user input
- **y/yes**: Proceed to Step 7
- **n/no**: Abort
- **edit**: Let user modify the plan (change messages, reorder, combine)

## Step 7: Execute Commits

For each commit in order:

```bash
# Unstage all first
git reset HEAD

# Stage only files for this commit
git add {files for this layer}

# Commit with message
git commit -m "{commit message}"
```

After each commit, verify it succeeded.

## Step 8: Report Results

Show the user:

1. Commits created: {count}
2. Files committed: {total}
3. Branch: {current branch}
4. Last commit: {SHA}

Remind:

- "Run `git push` to push to remote when ready."
- "Commits are NOT pushed automatically."

---

## Rules

1. **Never stage additional files** — Only work with what's already staged
2. **Never push** — User decides when to push
3. **Wait for confirmation** — Unless --auto flag
4. **Inner to outer order** — Dependencies satisfied in each commit
5. **Each commit is atomic** — Single layer, single purpose
