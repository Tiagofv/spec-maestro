#!/usr/bin/env bash
# Validate plan.md follows the parseable format
# Usage: validate-plan-format.sh <plan.md-path>
# Exit 0 = valid, exit 1 = invalid

set -euo pipefail

PLAN_FILE="${1:-}"

# Check file argument
if [[ -z "$PLAN_FILE" ]]; then
    echo "ERROR: No plan.md file path provided" >&2
    echo "Usage: validate-plan-format.sh <plan.md-path>" >&2
    exit 1
fi

if [[ ! -f "$PLAN_FILE" ]]; then
    echo "ERROR: File not found: $PLAN_FILE" >&2
    exit 1
fi

echo "=== Validating Plan Format: $PLAN_FILE ===" >&2

# ----------------------------------------------------------------------------
# Repos-header validation (feature 062, T009)
#
# Every plan.md must declare a non-empty `**Repos:**` line in the metadata
# header block (everything before the first `## 1.` heading). The captured
# value is a comma-separated list of repo names; each name must match
# ^[a-z0-9][a-z0-9-]*$ . On success the parsed list is exported as the
# bash array PLAN_REPOS (and PLAN_REPOS_CSV) so follow-up validators
# (T010 per-task **Repo:**, T011 header-vs-task consistency, T012 cross-repo
# Files-to-Modify rejection) can reuse it.
# ----------------------------------------------------------------------------

# Bash array populated by parse_repos_header on success.
PLAN_REPOS=()
PLAN_REPOS_CSV=""

# Repo-name regex (POSIX BRE / Perl-compatible).
PLAN_REPO_NAME_REGEX='^[a-z0-9][a-z0-9-]*$'

# parse_repos_header <plan-file>
#
# Reads the metadata-header block (lines from the top of the file up to,
# but not including, the first `## 1.` heading) and looks for a line
# matching `^\*\*Repos:\*\*\s*(.+)$`. Splits the captured group on `,`,
# trims whitespace, validates each entry against PLAN_REPO_NAME_REGEX.
#
# On success: populates PLAN_REPOS and PLAN_REPOS_CSV, returns 0.
# On failure: prints a named error to stderr and returns nonzero.
parse_repos_header() {
    local file="$1"
    local header_block
    local repos_line=""
    local raw_csv=""

    # Slurp the metadata header — every line until we hit the first `## 1.`.
    header_block="$(awk '
        /^## 1\./ { exit }
        { print }
    ' "$file")"

    # Find the first **Repos:** line in the header block (anchored at start
    # of line). Use grep -m1 so a stray later occurrence is ignored — only
    # the first counts as the metadata header.
    repos_line="$(printf '%s\n' "$header_block" \
        | grep -m1 -E '^\*\*Repos:\*\*[[:space:]]*.*$' || true)"

    if [[ -z "$repos_line" ]]; then
        echo "plan validation failed: missing **Repos:** header in metadata block" >&2
        return 1
    fi

    # Strip the `**Repos:**` prefix and any leading whitespace, leaving the
    # comma-separated payload.
    raw_csv="${repos_line#\*\*Repos:\*\*}"
    # Trim leading/trailing whitespace from the payload, and strip any
    # trailing inline HTML comment (e.g. <!-- comma-separated repo dirnames -->).
    raw_csv="$(printf '%s' "$raw_csv" | sed -e 's/<!--.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [[ -z "$raw_csv" ]]; then
        echo "plan validation failed: **Repos:** header is empty (expected comma-separated repo names)" >&2
        return 1
    fi

    # Split on commas; trim whitespace per entry; validate.
    local IFS=','
    local -a raw_entries=()
    # shellcheck disable=SC2206
    raw_entries=( $raw_csv )

    local entry trimmed
    local -a parsed=()
    for entry in "${raw_entries[@]}"; do
        # Trim leading/trailing whitespace.
        trimmed="$(printf '%s' "$entry" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        if [[ -z "$trimmed" ]]; then
            # Empty cell from something like "a,,b" or trailing comma.
            echo "plan validation failed: **Repos:** contains an empty entry (check for stray commas)" >&2
            return 1
        fi
        if ! [[ "$trimmed" =~ $PLAN_REPO_NAME_REGEX ]]; then
            echo "plan validation failed: **Repos:** entry \"$trimmed\" does not match regex ${PLAN_REPO_NAME_REGEX}" >&2
            return 1
        fi
        parsed+=( "$trimmed" )
    done

    if [[ ${#parsed[@]} -eq 0 ]]; then
        # Defensive: shouldn't happen given the empty-payload check above,
        # but keep the named error path.
        echo "plan validation failed: **Repos:** header parsed to an empty list" >&2
        return 1
    fi

    PLAN_REPOS=( "${parsed[@]}" )
    # Comma-joined CSV form for downstream consumers / debug printing.
    local joined
    printf -v joined '%s,' "${PLAN_REPOS[@]}"
    PLAN_REPOS_CSV="${joined%,}"

    return 0
}

# validate_repos_header <plan-file>
#
# Wrapper that runs parse_repos_header and converts a failure return into
# an exit. Kept as a separate function so future tasks (T011/T012) can call
# parse_repos_header directly to reuse the parsed list without re-exiting.
validate_repos_header() {
    local file="$1"
    if ! parse_repos_header "$file"; then
        echo "=== Validation FAILED on **Repos:** header rule ===" >&2
        exit 1
    fi
    echo "=== Repos header OK: ${PLAN_REPOS_CSV} (${#PLAN_REPOS[@]} repo(s)) ===" >&2
}

validate_repos_header "$PLAN_FILE"


# ----------------------------------------------------------------------------
# Per-task **Repo:** field validation (feature 062, T010)
#
# Every task block (between `<!-- TASK:BEGIN id=T### -->` and
# `<!-- TASK:END -->`) must contain exactly one `**Repo:**` line in its
# `**Metadata:**` block, and the captured value must match
# `^[a-z0-9][a-z0-9-]*$` — same regex as PLAN_REPO_NAME_REGEX so the field
# format matches the header repo-name format.
#
# The cross-check that the per-task value is also a member of the
# `**Repos:**` header set is T011's responsibility — this validator only
# enforces presence and format.
# ----------------------------------------------------------------------------

# validate_per_task_repo_field <plan-file>
#
# Walks each `<!-- TASK:BEGIN id=T### --> ... <!-- TASK:END -->` block via
# perl so we get reliable multi-line capture, then for each block:
#   - extracts every `^\s*-\s*\*\*Repo:\*\*\s*(.*)$` line (anchored, exactly
#     the field marker, list-item style matching the existing Metadata
#     conventions);
#   - errors if zero matches (missing) or more than one match (duplicate);
#   - errors if the captured value is empty/whitespace-only or fails the
#     repo-name regex.
#
# Exits nonzero with a named error on the first failure found per task; all
# task-level failures are accumulated and reported together so a multi-task
# breakage surfaces in a single run.
validate_per_task_repo_field() {
    local file="$1"

    PLAN_REPO_NAME_REGEX="$PLAN_REPO_NAME_REGEX" perl -0777 -e '
        my $name_re = $ENV{PLAN_REPO_NAME_REGEX};
        # Strip the bash anchors — perl already anchors via =~ context, but
        # we rebuild a perl-side regex that mirrors the bash one exactly.
        my $repo_value_re = qr/^[a-z0-9][a-z0-9-]*$/;

        my $content = <STDIN>;
        my @errors;

        my @blocks = $content =~ /<!-- TASK:BEGIN id=(T\d{3}) -->(.*?)<!-- TASK:END -->/gs;

        for (my $i = 0; $i < @blocks; $i += 2) {
            my $task_id = $blocks[$i];
            my $task_content = $blocks[$i + 1];

            # Find every `**Repo:**` line, anchored to start-of-line as a
            # markdown list item ("- **Repo:** value"). Allow leading
            # whitespace before the dash to match the existing Metadata
            # conventions used for Label/Size/Assignee/Dependencies above.
            my @matches = ($task_content =~ /^\s*-\s*\*\*Repo:\*\*[ \t]*(.*?)[ \t]*$/mg);

            if (@matches == 0) {
                push @errors, "plan validation failed: task $task_id missing **Repo:** field";
                next;
            }
            if (@matches > 1) {
                push @errors, "plan validation failed: task $task_id has multiple **Repo:** fields (expected exactly one)";
                next;
            }

            my $value = $matches[0];
            # Trim any surviving whitespace defensively.
            $value =~ s/^\s+|\s+$//g;

            if ($value eq "") {
                push @errors, "plan validation failed: task $task_id has empty **Repo:** value (must match ^[a-z0-9][a-z0-9-]*\$)";
                next;
            }

            unless ($value =~ $repo_value_re) {
                push @errors, "plan validation failed: task $task_id has malformed **Repo:** value \"$value\" (must match ^[a-z0-9][a-z0-9-]*\$)";
                next;
            }
        }

        if (@errors) {
            print STDERR "$_\n" for @errors;
            exit 1;
        }
        exit 0;
    ' < "$file"

    local rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "=== Validation FAILED on per-task **Repo:** rule ===" >&2
        exit 1
    fi
    echo "=== Per-task **Repo:** field OK ===" >&2
}

validate_per_task_repo_field "$PLAN_FILE"


# ----------------------------------------------------------------------------
# Repos-consistency check (feature 062, T011)
#
# Cross-checks two invariants that together implement Decision 8.3:
#
#   (a) Every task's **Repo:** value must appear in the plan's **Repos:** set.
#       A task referencing an unknown repo means the header is stale or the
#       task field is wrong — either way it is an error.
#
#   (b) Every entry in **Repos:** must be referenced by at least one task.
#       An unused header entry means either the header is wrong or a whole
#       repo's worth of tasks is missing.
#
# Requires PLAN_REPOS to be populated by validate_repos_header (T009) and
# per-task **Repo:** fields to have passed validate_per_task_repo_field (T010)
# before this is called.
# ----------------------------------------------------------------------------

# validate_repos_consistency <plan-file>
#
# Uses perl to extract every task's **Repo:** value, then:
#   - checks each against the shell-side PLAN_REPOS_CSV list;
#   - records which header repos were seen;
#   - reports any header repo with zero tasks.
#
# PLAN_REPOS_CSV is passed into perl via the environment variable of the same
# name so no subshell or temp-file is needed.
validate_repos_consistency() {
    local file="$1"

    PLAN_REPOS_CSV="$PLAN_REPOS_CSV" perl -0777 -e '
        my $repos_csv = $ENV{PLAN_REPOS_CSV};

        # Build a lookup set from the header repos.
        my %header_repos;
        for my $r (split /\s*,\s*/, $repos_csv) {
            $r =~ s/^\s+|\s+$//g;
            $header_repos{$r} = 0;  # 0 = not yet seen by any task
        }

        my $content = <STDIN>;
        my @errors;

        my @blocks = $content =~ /<!-- TASK:BEGIN id=(T\d{3}) -->(.*?)<!-- TASK:END -->/gs;

        for (my $i = 0; $i < @blocks; $i += 2) {
            my $task_id      = $blocks[$i];
            my $task_content = $blocks[$i + 1];

            # Extract the single **Repo:** value (T010 guarantees exactly one
            # valid entry exists; we just read it here without re-validating).
            my ($value) = ($task_content =~ /^\s*-\s*\*\*Repo:\*\*[ \t]*(.*?)[ \t]*$/m);
            next unless defined $value;
            $value =~ s/^\s+|\s+$//g;
            next if $value eq "";

            if (!exists $header_repos{$value}) {
                push @errors,
                    "plan validation failed: task $task_id declares **Repo:** \"$value\""
                    . " which is not in the plan **Repos:** header ($repos_csv)";
            } else {
                $header_repos{$value}++;
            }
        }

        # Check for header repos with zero task references.
        for my $repo (sort keys %header_repos) {
            if ($header_repos{$repo} == 0) {
                push @errors,
                    "plan validation failed: **Repos:** lists \"$repo\""
                    . " but no task declares **Repo:** $repo"
                    . " (remove it from the header or add a task for it)";
            }
        }

        if (@errors) {
            print STDERR "$_\n" for @errors;
            exit 1;
        }
        exit 0;
    ' < "$file" || { echo "=== Validation FAILED on Repos-consistency rule ===" >&2; exit 1; }
    echo "=== Repos-consistency OK ===" >&2
}

validate_repos_consistency "$PLAN_FILE"


# ----------------------------------------------------------------------------
# Cross-repo-task rejection (feature 062, T012)
#
# Implements Decision 8.5: a single task must not span multiple repos.
#
# For each task the validator:
#   1. Reads the task's **Repo:** declaration (the "declared repo").
#   2. Parses the **Files to Modify:** bullet list within that task block.
#   3. For every path, checks whether it starts with "<other-repo-name>/"
#      where <other-repo-name> is any repo in PLAN_REPOS_CSV that is NOT
#      the declared repo.
#   4. If any path is foreign, the task fails.
#
# Path-resolution rules (Decision 8.8 / task spec):
#   - Bare paths (no leading repo-dirname prefix) belong to the declared repo.
#   - Paths starting with "<other-repo>/" belong to that other repo.
#   - The validator only needs dirname-prefix matching — no filesystem access.
# ----------------------------------------------------------------------------

# validate_no_cross_repo_files <plan-file>
#
# Passes PLAN_REPOS_CSV into perl so the complete repo set is available
# for foreign-prefix detection without a temp file.
validate_no_cross_repo_files() {
    local file="$1"

    PLAN_REPOS_CSV="$PLAN_REPOS_CSV" perl -0777 -e '
        my $repos_csv = $ENV{PLAN_REPOS_CSV};

        # Build the set of all known repo names.
        my @all_repos;
        for my $r (split /\s*,\s*/, $repos_csv) {
            $r =~ s/^\s+|\s+$//g;
            push @all_repos, $r if $r ne "";
        }

        my $content = <STDIN>;
        my @errors;

        my @blocks = $content =~ /<!-- TASK:BEGIN id=(T\d{3}) -->(.*?)<!-- TASK:END -->/gs;

        for (my $i = 0; $i < @blocks; $i += 2) {
            my $task_id      = $blocks[$i];
            my $task_content = $blocks[$i + 1];

            # Read the declared repo (T010 guarantees presence and validity).
            my ($declared_repo) = ($task_content =~ /^\s*-\s*\*\*Repo:\*\*[ \t]*(.*?)[ \t]*$/m);
            next unless defined $declared_repo;
            $declared_repo =~ s/^\s+|\s+$//g;
            next if $declared_repo eq "";

            # Extract the **Files to Modify:** section.
            # The section runs from the `**Files to Modify:**` heading line
            # through each subsequent bullet (`- `) line; it ends when a
            # non-bullet, non-blank line is encountered or the task block ends.
            my ($ftm_block) = ($task_content =~ /\*\*Files to Modify:\*\*\n((?:[ \t]*[-*][ \t]+[^\n]*\n?)*)/);
            next unless defined $ftm_block;  # no Files to Modify section — skip

            # Collect each bullet value (strip leading "- " and whitespace).
            my @paths;
            while ($ftm_block =~ /^[ \t]*[-*][ \t]+(.+?)[ \t]*$/mg) {
                my $path = $1;
                $path =~ s/^\s+|\s+$//g;
                # Strip surrounding backticks (paths often written as `foo/bar`).
                $path =~ s/^`(.*)`$/$1/;
                # Strip inline parenthetical annotations like "(new)" or "(new file)".
                $path =~ s/\s*\([^)]*\)\s*$//;
                $path =~ s/^\s+|\s+$//g;
                push @paths, $path if $path ne "";
            }

            # For each path, check whether it starts with "<other-repo>/".
            my @foreign;
            for my $path (@paths) {
                for my $repo (@all_repos) {
                    next if $repo eq $declared_repo;
                    if ($path =~ /^\Q$repo\E\//) {
                        push @foreign, "\"$path\" (looks like repo \"$repo\")";
                        last;  # one match per path is enough
                    }
                }
            }

            if (@foreign) {
                my $foreign_list = join(", ", @foreign);
                push @errors,
                    "plan validation failed: task $task_id declares **Repo:** \"$declared_repo\""
                    . " but **Files to Modify:** contains path(s) that appear to belong to"
                    . " a different repo: $foreign_list"
                    . " — split this task so each task touches only one repo";
            }
        }

        if (@errors) {
            print STDERR "$_\n" for @errors;
            exit 1;
        }
        exit 0;
    ' < "$file" || { echo "=== Validation FAILED on cross-repo Files-to-Modify rule ===" >&2; exit 1; }
    echo "=== Cross-repo Files-to-Modify OK ===" >&2
}

validate_no_cross_repo_files "$PLAN_FILE"


# Use perl for validation
perl -0777 -e '
    my $content = <STDIN>;
    my @errors_list;
    my %task_ids;
    my @task_order;
    my %deps_for_task;
    
    # Extract all task blocks
    my @blocks = $content =~ /<!-- TASK:BEGIN id=(T\d{3}) -->(.*?)<!-- TASK:END -->/gs;
    
    if (@blocks == 0) {
        push @errors_list, "No task blocks found (no TASK:BEGIN markers)";
    }
    
    for (my $i = 0; $i < @blocks; $i += 2) {
        my $task_id = $blocks[$i];
        my $task_content = $blocks[$i + 1];
        
        push @task_order, $task_id;
        
        # Check for duplicate IDs
        if (exists $task_ids{$task_id}) {
            push @errors_list, "Duplicate task ID found: $task_id";
        }
        $task_ids{$task_id} = 1;
        
        # Check required fields
        if ($task_content !~ /^\s*-\s*\*\*Label:\*\*/m) {
            push @errors_list, "Task $task_id - Missing Label field";
        }
        
        if ($task_content !~ /^\s*-\s*\*\*Size:\*\*/m) {
            push @errors_list, "Task $task_id - Missing Size field";
        } else {
            # Extract and validate size
            if ($task_content =~ /^\s*-\s*\*\*Size:\*\*\s*(\w+)/m) {
                my $size = $1;
                if ($size ne "XS" && $size ne "S") {
                    push @errors_list, "Task $task_id - Invalid size $size (must be XS or S)";
                }
            }
        }
        
        if ($task_content !~ /^\s*-\s*\*\*Assignee:\*\*/m) {
            push @errors_list, "Task $task_id - Missing Assignee field";
        }
        
        if ($task_content !~ /^\s*-\s*\*\*Dependencies:\*\*/m) {
            push @errors_list, "Task $task_id - Missing Dependencies field";
        } else {
            # Extract and validate dependencies
            if ($task_content =~ /^\s*-\s*\*\*Dependencies:\*\*\s*(.+)$/m) {
                my $deps = $1;
                $deps =~ s/^[\s,—-]+$//;  # Handle various empty markers
                
                if ($deps && $deps !~ /^[\s,—-]+$/) {
                    # Has actual dependencies - validate format
                    my @dep_list = split /[,\s]+/, $deps;
                    foreach my $dep (@dep_list) {
                        $dep =~ s/^\s+|\s+$//g;
                        next if $dep eq "—" || $dep eq "" || $dep eq "-";
                        if ($dep !~ /^T\d{3}$/) {
                            push @errors_list, "Task $task_id - Invalid dependency format $dep (must be T###)";
                        } else {
                            push @{$deps_for_task{$task_id}}, $dep;
                        }
                    }
                }
            }
        }
    }
    
    # Validate dependencies reference existing IDs
    foreach my $task_id (@task_order) {
        if (exists $deps_for_task{$task_id}) {
            foreach my $dep (@{$deps_for_task{$task_id}}) {
                unless (exists $task_ids{$dep}) {
                    push @errors_list, "Task $task_id - Dependency $dep references non-existent task ID";
                }
            }
        }
    }
    
    # Print errors or success
    my $error_count = scalar @errors_list;
    if ($error_count > 0) {
        foreach my $err (@errors_list) {
            print "ERROR: $err\n";
        }
        print "VALIDATION_FAILED:$error_count\n";
        exit 1;
    } else {
        my $count = scalar @task_order;
        print "VALIDATION_PASSED:$count\n";
        exit 0;
    }
' < "$PLAN_FILE" > /tmp/validation_result_$$.txt 2>&1

# Read validation result
VALIDATION_RESULT=$(cat /tmp/validation_result_$$.txt)

# Check for errors in output
if echo "$VALIDATION_RESULT" | grep -q "VALIDATION_FAILED"; then
    ERROR_COUNT=$(echo "$VALIDATION_RESULT" | grep "VALIDATION_FAILED:" | head -1 | sed 's/VALIDATION_FAILED://')
    echo "$VALIDATION_RESULT" | grep "^ERROR:" | sed 's/^ERROR: //' >&2
    echo "=== Validation FAILED with $ERROR_COUNT error(s) ===" >&2
    rm -f /tmp/validation_result_$$.txt
    exit 1
elif echo "$VALIDATION_RESULT" | grep -q "VALIDATION_PASSED"; then
    TASK_COUNT=$(echo "$VALIDATION_RESULT" | grep "VALIDATION_PASSED:" | head -1 | sed 's/VALIDATION_PASSED://')
    echo "=== Validation PASSED ($TASK_COUNT task(s) found) ===" >&2
    rm -f /tmp/validation_result_$$.txt
    exit 0
else
    echo "ERROR: Validation script failed to produce valid output" >&2
    echo "$VALIDATION_RESULT" >&2
    rm -f /tmp/validation_result_$$.txt
    exit 1
fi
