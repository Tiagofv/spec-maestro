# Feature: Maestro Foundational Quality and DX Fixes

**Spec ID:** 033-specify-fix-all-these-issues
**Author:** Maestro
**Created:** 2026-03-16
**Last Updated:** 2026-03-16
**Status:** Review

---

## 1. Problem Statement

A comprehensive analysis of the maestro project across five dimensions (pipeline workflow, CLI/UI, testing, agent system, and developer experience) uncovered systemic quality issues that undermine reliability, adoption, and maintainability.

The most damaging problems fall into three categories:

**Broken fundamentals:** The CI pipeline only runs Go tests -- frontend, Rust, and shell script tests never execute automatically. Code with broken TypeScript, failing Vitest tests, or Rust compilation errors can be merged to main without detection. Ten Go tests are permanently skipped with stale justifications. The compile gate only validates one language despite the project being polyglot.

**Onboarding blockers:** New users encounter undocumented dependencies (`jq`, `python3`), broken install guidance for `bd` (literal ellipsis in the install command), wrong config defaults (`stack: go` for non-Go projects), no quickstart tutorial, and 11 orphan test specs polluting the feature listing. The README is outdated (lists 11 commands when 14 exist).

**Silent data integrity risks:** Pipeline state files have no schema validation and exhibit significant drift across 32 features. Parallel sub-agents can corrupt state files during implementation. The `list-features.sh` script does not recognize the `research` stage. A JSON generation bug in `parse-plan-tasks.sh` produces malformed output.

These issues compound: a new user hits broken docs, gets past that only to hit undocumented dependencies, then encounters silent state corruption when running the pipeline. Fixing these foundational issues is prerequisite to all other improvements.

---

## 2. Proposed Solution

Address the highest-impact issues in four work streams:

1. **CI/CD expansion** -- Make the CI pipeline test all four language stacks (Go, TypeScript, Rust, Bash) so broken code cannot be merged silently.

2. **Data integrity fixes** -- Fix the JSON bug in `parse-plan-tasks.sh`, add the `research` stage to `list-features.sh`, and fix the broken `node` compile gate reference.

3. **Developer onboarding** -- Document all prerequisites, fix the `bd` install guidance, update the README command table, clean up orphan specs, and create a quickstart tutorial.

4. **Test hygiene** -- Un-skip or remove the 10 stale Go tests, delete the duplicate dashboard test file, and add missing lint tooling.

---

## 3. User Stories

### Story 1: CI Catches All Breakages

**As a** contributor,
**I want** the CI pipeline to run tests for all language stacks in the project,
**so that** broken TypeScript, Rust, or shell code cannot be merged to main undetected.

**Acceptance Criteria:**

- [ ] A pull request that breaks a Vitest test is blocked by CI
- [ ] A pull request that fails `cargo check` in `src-tauri/` is blocked by CI
- [ ] A pull request that fails shell script tests (list-features, validate-plan, create-tasks) is blocked by CI
- [ ] A pull request that introduces TypeScript type errors (failing `tsc`) is blocked by CI
- [ ] All four test jobs (Go, TypeScript, Rust, Shell) run in parallel

### Story 2: New User Completes Setup Without Hitting Undocumented Errors

**As a** new user installing maestro for the first time,
**I want** all system prerequisites to be clearly documented and validated,
**so that** I can complete setup without encountering cryptic "command not found" errors.

**Acceptance Criteria:**

- [ ] README lists all prerequisites: `bd`, `jq`, `python3`, `git`, and a supported AI agent
- [ ] The `bd` install guidance shows an actual working install command (not a placeholder with ellipsis)
- [ ] Running `maestro doctor` checks for the presence of `bd`, `jq`, `python3`, and `git` on PATH
- [ ] `maestro doctor` outputs actionable fix instructions for each missing dependency
- [ ] The README command table lists all 14 commands (currently missing `list`, `research.list`, `research.search`)

### Story 3: Feature List Shows Clean, Accurate Pipeline State

**As a** developer using the maestro pipeline,
**I want** the feature listing to show accurate stage information and exclude orphan data,
**so that** I can trust the dashboard and know what to do next.

**Acceptance Criteria:**

- [ ] Running `/maestro.list` correctly shows features in the `research` stage (not "Unknown stage")
- [ ] The `list-features.sh` script recognizes `research` as a valid pipeline stage with correct next-action
- [ ] Orphan spec directories (those with no corresponding state file) are either cleaned up or excluded from the listing
- [ ] The `parse-plan-tasks.sh` JSON output is valid (parseable by `jq` without errors)

### Story 4: Compile Gate Works for All Configured Stacks

**As a** developer running the compile gate,
**I want** every configured stack command to actually work when invoked, and to be able to run multiple stacks for polyglot projects,
**so that** the compile gate validates all relevant languages in the project.

**Acceptance Criteria:**

- [ ] The `node` compile gate command references scripts that exist in `package.json`
- [ ] Running the compile gate with `stack: node` completes without "script not found" errors
- [ ] The compile gate supports running multiple stacks (Go, Python, Elixir, JavaScript/TS) in a single invocation for polyglot projects
- [ ] Each supported stack has a working default compile/test command (exact commands to be defined during planning)
- [ ] When multiple stacks are configured, the gate reports pass/fail per stack and fails if any stack fails

### Story 5: Test Suite is Clean and Trustworthy

**As a** contributor,
**I want** all tests in the suite to either run or be removed,
**so that** the test count reflects actual coverage and skip messages are not misleading.

**Acceptance Criteria:**

- [ ] The 10 skipped Go tests in `commands_test.go` are either un-skipped and passing, or removed with an explanation
- [ ] The duplicate dashboard test file (`src/stores/dashboard.test.ts` vs `src/stores/dashboard.store.test.ts`) is consolidated into one file
- [ ] All remaining tests pass when run locally

### Story 6: Quickstart Tutorial Exists

**As a** new user evaluating maestro,
**I want** a step-by-step tutorial that walks me through the entire pipeline on a trivial example,
**so that** I can validate my setup works and understand the flow before using it on real features.

**Acceptance Criteria:**

- [ ] A quickstart document exists that walks through: install, init, specify, clarify, plan, tasks (stops before implement/review which require a live AI agent session)
- [ ] The tutorial uses a concrete, trivial example feature (not abstract placeholders)
- [ ] Each step shows expected output so the user can verify they are on track
- [ ] The tutorial can be completed in under 10 minutes on a fresh project
- [ ] The tutorial stops at the `tasks` stage (install, init, specify, clarify, plan, tasks). The implement/review stages require a live AI agent session and are out of scope for a written tutorial.

---

## 4. Success Criteria

The feature is considered complete when:

1. The CI workflow runs tests for Go, TypeScript, Rust, and shell scripts -- and a PR that breaks any of them is blocked from merging
2. A new user can follow the README and `maestro doctor` to install all prerequisites and reach a working state without encountering undocumented errors
3. `/maestro.list` correctly handles all pipeline stages including `research` and produces accurate next-action suggestions
4. The compile gate supports multiple stacks (Go, Python, Elixir, JavaScript/TS) and each configured stack's commands work without errors
5. Zero skipped tests remain in the Go test suite (all tests either run and pass or are removed)
6. A quickstart tutorial document exists and is linked from the README

---

## 5. Scope

### 5.1 In Scope

- Expanding the CI workflow to cover all four language stacks
- Fixing the `parse-plan-tasks.sh` JSON generation bug
- Adding `research` to `list-features.sh` valid stages
- Fixing the `node` compile gate command in config.yaml
- Adding multi-stack compile gate support for Go, Python, Elixir, and JavaScript/TS
- New CI jobs start as non-blocking (continue-on-error) with a follow-up to make them required
- Documenting all system prerequisites in README
- Fixing the `bd` install guidance placeholder
- Updating the README command table to include all 14 commands
- Un-skipping or removing the 10 stale Go tests
- Removing the duplicate dashboard test file
- Cleaning up orphan spec directories (020-030)
- Creating a quickstart tutorial
- Enhancing `maestro doctor` to check for `bd`, `jq`, `python3`, `git`

### 5.2 Out of Scope

- Adding new CLI commands (`maestro status`, `maestro rollback`, `maestro archive`)
- Building new Tauri UI pages (spec viewer, pipeline status, gate approval queue)
- Implementing the plugin/extension system for agents
- Adding pre-commit hooks or ESLint configuration
- Fixing Rust backend issues (cache population, missing invoke handlers, event type mismatches)
- Adding state file schema validation or migration system
- Adding file-level locking for state updates during parallel execution
- Agent system changes (Codex support, agent registry, capability matrix)
- Feedback loops from pm-validate back to specify

### 5.3 Deferred

- State file schema versioning and validation
- Full test coverage for untested components (13 React components, 6 shell scripts)
- Adding golangci-lint, shellcheck, and ESLint to CI
- Pre-commit hooks via husky
- Coverage thresholds and reporting

---

## 6. Research

No formal research was conducted. Findings are based on a comprehensive codebase analysis performed across five dimensions:

### Linked Research Items

- **Pipeline Workflow Analysis** - Identified 6 workflow gaps, 6 missing commands, 6 friction points
  - Key insight: Research is not a first-class pipeline stage; `list-features.sh` does not recognize it
  - Recommendation: Add `research` to valid stages and fix navigation suggestions

- **CLI & Tauri UI Analysis** - Identified CLI gaps, 10+ UI missing features, 6 Rust backend bugs
  - Key insight: CLI has only 5 commands vs 14 pipeline stages; `GenerateAgentsMD()` is never called
  - Recommendation: Focus on CLI doctor enhancement; defer UI work

- **Testing & Quality Analysis** - Scored overall test health at 4/10
  - Key insight: CI only runs Go tests; frontend, Rust, shell, and e2e tests never run automatically
  - Recommendation: Expand CI first; it is the single highest-impact improvement

- **Agent System Analysis** - Identified hardcoded agent lists, dead config, no plugin system
  - Key insight: `init.sh` and `detect.go` maintain independent agent lists
  - Recommendation: Defer to a separate spec; foundation must be solid first

- **DX & Onboarding Analysis** - Identified 7 friction points, 7 documentation gaps
  - Key insight: No quickstart tutorial; `bd` has broken install guidance; hidden jq/python3 deps
  - Recommendation: Prerequisites documentation and quickstart are highest priority

### Research Summary

The analysis consistently pointed to CI/CD and onboarding as the two highest-leverage improvement areas. Fixing CI prevents quality regression. Fixing onboarding enables adoption. Both must precede feature development work (new commands, UI pages, plugin systems).

---

## 7. Dependencies

- `bd` (beads) CLI must be available for validating the `maestro doctor` enhancement
- GitHub Actions access is required for CI workflow modifications
- The existing test suites (Vitest, cargo test, Go test, shell test scripts) must be runnable locally before adding them to CI

---

## 8. Open Questions

All clarification markers resolved:

- **Compile gate multi-stack:** Yes, support Go, Python, Elixir, and JavaScript/TS simultaneously. Exact commands per stack to be defined during planning.
- **Quickstart scope:** Stop at the `tasks` stage. Implement/review require a live AI agent session.
- **Orphan spec cleanup:** Delete directories 020-030 entirely. They are test/duplicate data with no state files.
- **GenerateAgentsMD():** Deferred to a separate init-refactoring spec. Not part of this work.
- **CI rollout strategy:** New CI jobs (TypeScript, Rust, Shell) start as non-blocking (continue-on-error). Existing failures are fixed in a follow-up task, then jobs are flipped to required.

---

## 9. Risks

- **Scope creep risk:** The analysis surfaced 80+ issues. This spec intentionally focuses on ~15 foundational items. Pressure to include "just one more fix" could balloon the work.
- **CI expansion may expose many existing failures:** When frontend, Rust, and shell tests are added to CI, existing broken tests may surface. Mitigated by starting with non-blocking jobs (continue-on-error) and fixing failures before flipping to required.
- **Orphan spec cleanup is destructive:** Directories 020-030 will be deleted entirely. This is acceptable because they are test/duplicate data with no state files and no unique content.

---

## Changelog

| Date       | Change                                                                                                                              | Author  |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------- |
| 2026-03-16 | Initial spec created                                                                                                                | Maestro |
| 2026-03-16 | Resolved 4 clarification markers + 3 gap detection items. Promoted multi-stack compile gate to In Scope. Added CI rollout strategy. | Maestro |
