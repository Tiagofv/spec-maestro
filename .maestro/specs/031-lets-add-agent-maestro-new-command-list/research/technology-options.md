# Technology Options: maestro.list Command

**Research ID:** 031-technology-options
**Date:** 2026-03-16
**Source Type:** codebase
**Domain:** CLI command architecture

## Query

What technology options and patterns exist in the maestro codebase for implementing the `maestro.list` command?

## Summary

The `maestro.list` command is an AI-agent slash command (markdown instruction file), not a Go CLI command. It will follow the same dual-layer architecture as all other maestro commands: a `.maestro/commands/maestro.list.md` file with step-by-step instructions, optionally backed by a shell helper script for deterministic operations like JSON parsing and directory scanning.

## Options Analyzed

### Option 1: Pure Markdown Slash Command (No Script)

**Overview**: Create `maestro.list.md` as an AI-readable instruction file that the agent reads state files and spec directories directly, formats output inline.

**Maturity**: Proven — 13 existing commands follow this pattern.

#### Pros

- Consistent with all existing maestro commands
- No build step required — changes take effect immediately
- AI agent can adapt output formatting dynamically
- Easy to iterate on the format

#### Cons

- Performance depends on agent tool calls (multiple file reads)
- No caching of directory listings
- Agent must handle JSON parsing inline

#### Best For

- Rapid iteration on output format
- When the command logic is simple enough for agent instructions

### Option 2: Markdown Command + Shell Helper Script

**Overview**: Create `maestro.list.md` for orchestration plus a `list-features.sh` script that scans directories, parses state files, and outputs structured JSON.

**Maturity**: Proven — used by `maestro.tasks` (with `create-tasks.sh`, `parse-plan-tasks.sh`), `maestro.research.list` (with `research-state.sh`).

#### Pros

- Deterministic directory scanning and JSON parsing via `jq`
- Single script call returns all data; agent only needs to format output
- Testable independently (can run script outside of agent context)
- Handles edge cases (malformed JSON, missing files) in shell with proper error codes

#### Cons

- Requires maintaining a separate shell script
- Two files to coordinate (command + script)
- Shell script complexity can grow

#### Best For

- When data aggregation involves scanning multiple files
- When deterministic behavior matters (consistent sorting, filtering)

### Option 3: Go CLI Subcommand

**Overview**: Add a `maestro list` subcommand to the Go binary alongside `init`, `update`, `doctor`, `remove`.

**Maturity**: Proven for infra commands, but NO existing Go command does feature-level operations.

#### Pros

- Compiled binary — fastest execution
- Could use Go table libraries (e.g., `text/tabwriter`)
- Type-safe JSON parsing with structs

#### Cons

- Requires `make build` after every change
- Breaks the architectural separation (Go CLI = infrastructure, markdown = feature workflow)
- Would be the only Go command that reads feature state
- Inconsistent with how all other feature commands work

#### Best For

- NOT recommended — violates the established architecture

## Comparison Matrix

| Criteria                           | Pure Markdown | Markdown + Script |   Go CLI   |
| ---------------------------------- | :-----------: | :---------------: | :--------: |
| Consistency with existing commands |     High      |       High        |    Low     |
| Iteration speed                    |     Fast      |      Medium       |    Slow    |
| Deterministic behavior             |      Low      |       High        |    High    |
| Error handling                     |     Basic     |       Good        |    Best    |
| Testability                        |     None      |   Script-level    | Unit tests |
| Build step needed                  |      No       |        No         |    Yes     |

## Recommendation

**Recommended**: Option 2 — Markdown Command + Shell Helper Script

**Rationale**:

1. Consistent with the `maestro.research.list` command which solves a very similar problem (listing artifacts with metadata)
2. The shell script can deterministically scan `.maestro/state/` and `.maestro/specs/` directories, parse JSON, compute stalled status, and return structured data
3. The markdown command handles output formatting and next-step suggestions
4. The `research-state.sh` script is a proven pattern for this exact type of operation

**When to use alternatives**:

- Pure Markdown: If the shell script adds no value (unlikely given the JSON parsing and directory scanning requirements)
- Go CLI: Only if performance becomes a real issue with hundreds of features (deferred concern)

## Risks and Mitigations

| Risk                                       | Likelihood | Impact | Mitigation                                                                         |
| ------------------------------------------ | ---------- | ------ | ---------------------------------------------------------------------------------- |
| Shell script handles malformed JSON poorly | Medium     | Low    | Use `jq` with error suppression (`// empty`); show "corrupt state" warning         |
| Date parsing inconsistencies in shell      | Medium     | Medium | Standardize on ISO 8601 parsing with `date` command; handle all 3 observed formats |
| Script grows too complex over time         | Low        | Medium | Keep script focused on data retrieval; let the AI agent handle presentation logic  |
