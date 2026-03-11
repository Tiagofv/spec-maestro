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
