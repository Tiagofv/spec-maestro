#!/usr/bin/env bash
# Validate spec.md acceptance-criteria quality (EARS shape + failure-path pairing).
# Usage: validate-spec-format.sh <spec.md-path> [--strict]
# Exit 0 = valid, exit 1 = invalid
#
# --strict promotes the zero-[NEEDS CLARIFICATION]-marker WARNING (rule F) into
# a hard failure (for benchmark / CI use).

set -euo pipefail

SPEC_FILE=""
STRICT=0

# Parse args: one positional <spec.md> plus an optional --strict flag, order-free.
for arg in "$@"; do
    case "$arg" in
        --strict) STRICT=1 ;;
        *)
            if [[ -z "$SPEC_FILE" ]]; then
                SPEC_FILE="$arg"
            fi
            ;;
    esac
done

# Check file argument
if [[ -z "$SPEC_FILE" ]]; then
    echo "ERROR: No spec.md file path provided" >&2
    echo "Usage: validate-spec-format.sh <spec.md-path> [--strict]" >&2
    exit 1
fi

if [[ ! -f "$SPEC_FILE" ]]; then
    echo "ERROR: File not found: $SPEC_FILE" >&2
    exit 1
fi

echo "=== Validating Spec Format: $SPEC_FILE ===" >&2

# ----------------------------------------------------------------------------
# Acceptance-criteria quality validation (feature: a-new-acceptance-criteria-
# quality-rule-for-the-spec-pipeline).
#
# Single perl -0777 pass that implements validators (A)-(F) in order and emits
# a VALIDATION_PASSED:<n> / VALIDATION_FAILED:<n> sentinel into a temp buffer
# (mirroring validate-plan-format.sh's final-pass structure):
#
#   (A) Parse acceptance criteria: extract every `- [ ] ...` checkbox bullet that
#       sits under an `**Acceptance Criteria (EARS):**` heading inside the
#       `## 3. User Stories` section. Per-story grouping + line numbers recorded.
#       Pure `[NEEDS CLARIFICATION: ...]` markers are classified separately and
#       are NOT EARS-checked.
#   (B) EARS-shape check: each non-marker criterion must match one of the five
#       anchored shapes (case-insensitive leading keyword, verb `shall` required),
#       plus the complex `While ..., when ..., the ... shall ...` combine form.
#   (C) Vague-term denylist scan over criterion text.
#   (D) Atomicity: a single criterion chaining two responses via ` and also `
#       or ` / ` is a split error.
#   (E) Failure-path pairing: every per-story `When ...` event-driven criterion
#       requires >=1 `If ..., then ...` criterion in the SAME story.
#   (F) NEEDS CLARIFICATION presence: count markers spec-wide; 0 markers is a
#       non-fatal WARNING (or a failure under --strict).
#   (G) right-altitude / implementation-free check — scans only the RESPONSE
#       clause (text after `shall`, or after `then the … shall`) of each
#       non-marker criterion for technology/implementation HOW-nouns; cites
#       ISO/IEC/IEEE 29148 Appropriate, not EARS.
# ----------------------------------------------------------------------------

# The criteria-parsing slurp uses awk to isolate the `## 3. User Stories`
# section (from that heading to the next `## ` heading), preserving original
# 1-based line numbers so error messages can cite them. Perl then walks the
# isolated block.
STRICT="$STRICT" perl -0777 -e '
    my $strict = $ENV{STRICT} ? 1 : 0;

    # Read the whole file (slurp mode under -0777), then split into lines so we
    # can keep 1-based line numbers for reporting.
    my $content = <STDIN>;
    $content = "" unless defined $content;
    my @lines = split /\n/, $content, -1;

    # --- Locate the `## 3. User Stories` section ----------------------------
    # Start at the `## 3.` heading; end at the next top-level `## ` heading.
    my $start = -1;
    my $end   = scalar(@lines);   # default: end of file
    for (my $i = 0; $i < @lines; $i++) {
        if ($lines[$i] =~ /^##\s+3\.\s/) { $start = $i; next; }
        if ($start >= 0 && $i > $start && $lines[$i] =~ /^##\s/) { $end = $i; last; }
    }

    my @errors;     # blocking "spec validation failed: ..." messages
    my @warnings;   # non-fatal warnings (rule F, non-strict)

    # --- (A) Parse criteria per story ---------------------------------------
    # Walk the section. Track the current story name (from `### Story N: name`
    # or any `### ` heading) and whether we are under an
    # `**Acceptance Criteria (EARS):**` heading. Collect `- [ ] ...` bullets.
    my $cur_story = "(unnamed story)";
    my $in_ac     = 0;   # 1 while inside an Acceptance Criteria (EARS) block
    my @criteria;        # list of { story, line (1-based), text, is_marker }
    my $marker_count = 0;  # spec-wide [NEEDS CLARIFICATION] markers

    if ($start >= 0) {
        for (my $i = $start; $i < $end; $i++) {
            my $line = $lines[$i];

            if ($line =~ /^###\s+(?:Story\s+\d+\s*:\s*)?(.+?)\s*$/) {
                $cur_story = $1;
                $cur_story =~ s/^Story\s+\d+\s*:\s*//i;  # tolerate "Story N: name"
                $in_ac = 0;
                next;
            }

            if ($line =~ /\*\*Acceptance Criteria \(EARS\):\*\*/) {
                $in_ac = 1;
                next;
            }

            # A new heading ends the current AC block.
            if ($line =~ /^#{1,6}\s/) { $in_ac = 0; }

            next unless $in_ac;

            # Checkbox bullet: "- [ ] text" (allow leading whitespace).
            if ($line =~ /^\s*-\s*\[\s?\]\s*(.+?)\s*$/) {
                my $text = $1;
                my $is_marker = ($text =~ /^\[NEEDS CLARIFICATION:.*\]$/) ? 1 : 0;
                push @criteria, {
                    story     => $cur_story,
                    line      => $i + 1,   # 1-based
                    text      => $text,
                    is_marker => $is_marker,
                };
            }
        }
    }

    # Spec-wide [NEEDS CLARIFICATION] marker count (anywhere in the file).
    for my $l (@lines) {
        my $count = () = ($l =~ /\[NEEDS CLARIFICATION:/g);
        $marker_count += $count;
    }

    # --- EARS shape regexes (case-insensitive leading keyword) --------------
    # Verb "shall" required; each criterion ends in a period.
    my @ears_shapes = (
        qr/^The\s+.+\s+shall\s+.+\.$/i,                        # Ubiquitous
        qr/^When\s+.+,\s*the\s+.+\s+shall\s+.+\.$/i,           # Event-driven
        qr/^While\s+.+,\s*the\s+.+\s+shall\s+.+\.$/i,          # State-driven
        qr/^If\s+.+,\s*then\s+the\s+.+\s+shall\s+.+\.$/i,      # Unwanted behavior
        qr/^Where\s+.+,\s*the\s+.+\s+shall\s+.+\.$/i,          # Optional feature
        qr/^While\s+.+,\s*when\s+.+,\s*the\s+.+\s+shall\s+.+\.$/i,  # Complex combine
    );

    # --- Vague-term denylist ------------------------------------------------
    my @vague_terms = (
        "fast", "quick", "quickly", "easy", "intuitive", "user-friendly",
        "robust", "seamless", "scalable", "appropriate", "reasonable",
        "efficiently", "properly", "gracefully", "nice", "good",
        "several", "a few", "most",
    );

    # --- (G) Solution-leakage / right-altitude denylist ---------------------
    # High-signal technology/implementation HOW-nouns. Curated for precision:
    # only scanned against each criterion RESPONSE clause (post-shall), so
    # domain nouns in triggers/preconditions do not false-fire.
    my @leak_terms = qw(
        Redis Postgres PostgreSQL JWT regex endpoint
        table index cache queue cron
    );

    # Per-story event/failure tallies for rule (E).
    my %story_when;   # story => count of "When ..." criteria
    my %story_if;     # story => count of "If ..., then ..." criteria
    my %story_when_lines;  # story => [line numbers of When criteria]

    for my $c (@criteria) {
        next if $c->{is_marker};   # markers are not EARS-checked

        my $text  = $c->{text};
        my $story = $c->{story};
        my $line  = $c->{line};

        # (E) per-story event/failure tallies (independent of shape validity).
        if ($text =~ /^When\s+/i) {
            $story_when{$story}++;
            push @{ $story_when_lines{$story} }, $line;
        }
        if ($text =~ /^If\s+.+,\s*then\s+/i) {
            $story_if{$story}++;
        }

        # (B) EARS-shape check.
        my $ears_ok = 0;
        for my $re (@ears_shapes) {
            if ($text =~ $re) { $ears_ok = 1; last; }
        }
        unless ($ears_ok) {
            push @errors,
                "spec validation failed: story \"$story\" criterion (line $line)"
                . " is not EARS-shaped: \"$text\""
                . " — rewrite as When/While/If…then/Where/The <system> shall …,"
                . " or mark [NEEDS CLARIFICATION]";
        }

        # (C) Vague-term denylist scan.
        for my $term (@vague_terms) {
            my $tre = ($term =~ /\s/)
                ? qr/(?<![A-Za-z])\Q$term\E(?![A-Za-z])/i
                : qr/\b\Q$term\E\b/i;
            if ($text =~ $tre) {
                push @errors,
                    "spec validation failed: criterion (line $line) uses vague"
                    . " term \"$term\"; quantify it or mark [NEEDS CLARIFICATION]";
            }
        }

        # (D) Atomicity: a single criterion chaining two responses.
        if ($text =~ /\s+and also\s+/i || $text =~ /\s+\/\s+/) {
            push @errors,
                "spec validation failed: criterion (line $line) chains two"
                . " responses (\" and also \" / \" / \"); split it into one"
                . " atomic trigger→response criterion per line: \"$text\"";
        }

        # (G) Solution-leakage / right-altitude: scan ONLY the response clause
        # (text after `shall`) so domain nouns in triggers/preconditions
        # ("When the user joins the queue, …") do not false-fire.
        my $resp = $text;
        if ($resp =~ /\bshall\b/i) {
            $resp = substr($text, $+[0]);   # substring after `shall`
        }
        for my $term (@leak_terms) {
            if ($resp =~ /\b\Q$term\E\b/i) {
                push @errors,
                    "spec validation failed: criterion (line $line) names"
                    . " implementation detail \"$term\" — describe the"
                    . " observable behavior (the WHAT/WHY), not the technology;"
                    . " move any hard technical constraint to the Constraints/"
                    . "Non-Functional section or mark [NEEDS CLARIFICATION]";
            }
        }
    }

    # --- (E) Failure-path pairing -------------------------------------------
    for my $story (sort keys %story_when) {
        my $when = $story_when{$story} // 0;
        my $iff  = $story_if{$story}   // 0;
        if ($when > 0 && $iff == 0) {
            my $lines_csv = join(", ", @{ $story_when_lines{$story} });
            push @errors,
                "spec validation failed: story \"$story\" has When-criterion(s)"
                . " with no matching If…then failure/edge criterion"
                . " (line $lines_csv)";
        }
    }

    # --- (F) NEEDS CLARIFICATION presence -----------------------------------
    if ($marker_count == 0) {
        if ($strict) {
            push @errors,
                "spec validation failed: spec has zero [NEEDS CLARIFICATION]"
                . " markers (--strict) — confirm nothing was guessed";
        } else {
            push @warnings,
                "spec has zero [NEEDS CLARIFICATION] markers"
                . " — confirm nothing was guessed";
        }
    }

    # --- Emit warnings (non-fatal) ------------------------------------------
    for my $w (@warnings) {
        print "WARNING: $w\n";
    }

    # --- Sentinel -----------------------------------------------------------
    my $error_count = scalar @errors;
    if ($error_count > 0) {
        print "ERROR: $_\n" for @errors;
        print "VALIDATION_FAILED:$error_count\n";
        exit 1;
    } else {
        my $n = scalar @criteria;
        print "VALIDATION_PASSED:$n\n";
        exit 0;
    }
' < "$SPEC_FILE" > "/tmp/validation_result_$$.txt" 2>&1 || true

# Read validation result
VALIDATION_RESULT=$(cat "/tmp/validation_result_$$.txt")

# Surface any non-fatal warnings to stderr regardless of outcome.
if echo "$VALIDATION_RESULT" | grep -q "^WARNING:"; then
    echo "$VALIDATION_RESULT" | grep "^WARNING:" | sed 's/^WARNING: //' >&2
fi

# Check for errors in output
if echo "$VALIDATION_RESULT" | grep -q "VALIDATION_FAILED"; then
    ERROR_COUNT=$(echo "$VALIDATION_RESULT" | grep "VALIDATION_FAILED:" | head -1 | sed 's/VALIDATION_FAILED://')
    echo "$VALIDATION_RESULT" | grep "^ERROR:" | sed 's/^ERROR: //' >&2
    echo "=== Validation FAILED with $ERROR_COUNT error(s) ===" >&2
    rm -f "/tmp/validation_result_$$.txt"
    exit 1
elif echo "$VALIDATION_RESULT" | grep -q "VALIDATION_PASSED"; then
    CRITERIA_COUNT=$(echo "$VALIDATION_RESULT" | grep "VALIDATION_PASSED:" | head -1 | sed 's/VALIDATION_PASSED://')
    echo "=== Validation PASSED ($CRITERIA_COUNT criterion(s) checked) ===" >&2
    rm -f "/tmp/validation_result_$$.txt"
    exit 0
else
    echo "ERROR: Validation script failed to produce valid output" >&2
    echo "$VALIDATION_RESULT" >&2
    rm -f "/tmp/validation_result_$$.txt"
    exit 1
fi
