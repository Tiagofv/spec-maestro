#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0

ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }

# Create stub bd directory
STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR"' EXIT

# Test 1: Happy path - bd returns valid JSON
cat > "$STUB_DIR/bd" << 'EOF'
#!/usr/bin/env bash
case "$1" in
  create) echo '{"id": "altpay-test-123", "title": "test"}' ;;
  dep)    exit 0 ;;
  *)      exit 1 ;;
esac
EOF
chmod +x "$STUB_DIR/bd"
PATH="$STUB_DIR:$PATH" source "$SCRIPT_DIR/bd-helpers.sh"
ID=$(PATH="$STUB_DIR:$PATH" bd_create_epic "test-title" "test-desc")
[[ "$ID" == "altpay-test-123" ]] && ok "happy path: bd_create_epic returns altpay ID" || fail "happy path: expected altpay-test-123, got '$ID'"

# Test 2: Malformed JSON - bd returns garbage
cat > "$STUB_DIR/bd" << 'EOF'
#!/usr/bin/env bash
echo "not-json-at-all"
EOF
if ID=$(PATH="$STUB_DIR:$PATH" bd_create_epic "test" "" 2>/tmp/t005-err); then
  fail "malformed JSON: expected non-zero exit, got success with ID='$ID'"
else
  grep -q "could not be parsed" /tmp/t005-err && ok "malformed JSON: non-zero exit + parse error message" || fail "malformed JSON: exit was non-zero but error message missing"
fi

# Test 3: bd exits non-zero
cat > "$STUB_DIR/bd" << 'EOF'
#!/usr/bin/env bash
echo "permission denied" >&2; exit 1
EOF
if ID=$(PATH="$STUB_DIR:$PATH" bd_create_epic "test" "" 2>/tmp/t005-err); then
  fail "non-zero bd: expected non-zero exit, got success"
else
  grep -q "bd create failed" /tmp/t005-err && ok "non-zero bd: non-zero exit + bd create failed message" || fail "non-zero bd: exit was non-zero but error message missing"
fi

# Test 4: bd_add_dep idempotent-OK on duplicate
cat > "$STUB_DIR/bd" << 'EOF'
#!/usr/bin/env bash
echo "dependency already exists" >&2; exit 1
EOF
if PATH="$STUB_DIR:$PATH" bd_add_dep "altpay-a" "altpay-b" 2>/dev/null; then
  ok "bd_add_dep: idempotent OK for 'already exists'"
else
  fail "bd_add_dep: should return 0 for 'already exists', got non-zero"
fi

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
