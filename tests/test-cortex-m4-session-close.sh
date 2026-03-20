#!/bin/bash
# test-cortex-m4-session-close.sh
# Tests for Milestone M4: Session Close Curation Trigger
# Requirement: REQ-CTX-024 (Should)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_FILE="$SCRIPT_DIR/core/hooks/session-close.sh"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1)); echo "  PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "  FAIL: $1"; }
assert_eq() { if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$1', got '$2')"; fi; }
assert_contains() { if echo "$1" | grep -q "$2" 2>/dev/null; then pass "$3"; else fail "$3 (missing '$2')"; fi; }
assert_file_exists() { if [ -f "$1" ]; then pass "$2"; else fail "$2 (file not found: $1)"; fi; }

echo "============================================================"
echo "TEST SUITE: Cortex M4 -- Session Close Curation Trigger"
echo "============================================================"

# ---- Group 1: Hook file structure ----
echo ""
echo "--- Group 1: Hook file structure ---"

# TEST-CTX-M4-001: session-close.sh exists
assert_file_exists "$HOOK_FILE" "TEST-CTX-M4-001: session-close.sh exists"

# TEST-CTX-M4-002: Hook checks for shareable behavioral learnings
HOOK_CONTENT=$(cat "$HOOK_FILE")
assert_contains "$HOOK_CONTENT" "behavioral_learnings" \
    "TEST-CTX-M4-002: Hook checks behavioral_learnings table"

# TEST-CTX-M4-003: Hook checks for shareable incidents
assert_contains "$HOOK_CONTENT" "incidents" \
    "TEST-CTX-M4-003: Hook checks incidents table"

# TEST-CTX-M4-004: Hook checks confidence threshold
assert_contains "$HOOK_CONTENT" "0.8" \
    "TEST-CTX-M4-004: Hook uses confidence >= 0.8 threshold"

# TEST-CTX-M4-005: Hook checks shared_uuid IS NULL (unshared entries)
assert_contains "$HOOK_CONTENT" "shared_uuid IS NULL" \
    "TEST-CTX-M4-005: Hook filters entries where shared_uuid IS NULL"

# TEST-CTX-M4-006: Hook checks is_private
assert_contains "$HOOK_CONTENT" "is_private" \
    "TEST-CTX-M4-006: Hook checks is_private flag"

# TEST-CTX-M4-007: Hook writes curation_pending flag file
assert_contains "$HOOK_CONTENT" "curation_pending" \
    "TEST-CTX-M4-007: Hook writes .curation_pending flag file"

# TEST-CTX-M4-008: Hook uses error suppression
assert_contains "$HOOK_CONTENT" '2>/dev/null' \
    "TEST-CTX-M4-008: Hook uses error suppression (2>/dev/null)"

# TEST-CTX-M4-009: Hook does not block on failure (|| true pattern)
assert_contains "$HOOK_CONTENT" '|| true' \
    "TEST-CTX-M4-009: Hook does not block on failure (|| true)"

# TEST-CTX-M4-010: Hook exits 0
assert_contains "$HOOK_CONTENT" 'exit 0' \
    "TEST-CTX-M4-010: Hook exits with 0"

# ---- Group 2: Functional tests ----
echo ""
echo "--- Group 2: Functional tests (with temp DB) ---"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Create project structure
mkdir -p "$TMPDIR/.claude/hooks"
TEST_DB="$TMPDIR/.claude/memory.db"

# Init DB with schema
sqlite3 "$TEST_DB" < "$SCRIPT_DIR/core/db/schema.sql"
bash "$SCRIPT_DIR/core/db/migrate-1.3.0.sh" "$TEST_DB" > /dev/null 2>&1

# TEST-CTX-M4-011: Hook runs without error on empty DB
CLAUDE_PROJECT_DIR="$TMPDIR" bash "$HOOK_FILE" < /dev/null 2>/dev/null
assert_eq "0" "$?" "TEST-CTX-M4-011: Hook runs without error on empty DB"

# TEST-CTX-M4-012: No curation_pending flag when nothing to share
if [ ! -f "$TMPDIR/.claude/hooks/.curation_pending" ]; then
    pass "TEST-CTX-M4-012: No .curation_pending when nothing to share"
else
    fail "TEST-CTX-M4-012: No .curation_pending when nothing to share (flag exists unexpectedly)"
fi

# Insert a high-confidence shareable behavioral learning
sqlite3 "$TEST_DB" "INSERT INTO behavioral_learnings (rule, confidence, status, occurrences) VALUES ('Never mock the database in tests', 0.9, 'active', 3);"

# TEST-CTX-M4-013: Curation pending flag written when shareable entries exist
CLAUDE_PROJECT_DIR="$TMPDIR" bash "$HOOK_FILE" < /dev/null 2>/dev/null
if [ -f "$TMPDIR/.claude/hooks/.curation_pending" ]; then
    pass "TEST-CTX-M4-013: .curation_pending flag written when shareable entries exist"
else
    fail "TEST-CTX-M4-013: .curation_pending flag written when shareable entries exist (no flag found)"
fi

# TEST-CTX-M4-014: Flag file contains count or indicator
FLAG_CONTENT=$(cat "$TMPDIR/.claude/hooks/.curation_pending" 2>/dev/null || echo "")
if [ -n "$FLAG_CONTENT" ]; then
    pass "TEST-CTX-M4-014: Flag file has content (not empty)"
else
    fail "TEST-CTX-M4-014: Flag file has content (not empty)"
fi

# Clean up flag
rm -f "$TMPDIR/.claude/hooks/.curation_pending"

# Mark the learning as shared (set shared_uuid)
sqlite3 "$TEST_DB" "UPDATE behavioral_learnings SET shared_uuid = 'test-uuid-001' WHERE rule = 'Never mock the database in tests';"

# TEST-CTX-M4-015: No flag when all entries already shared
CLAUDE_PROJECT_DIR="$TMPDIR" bash "$HOOK_FILE" < /dev/null 2>/dev/null
if [ ! -f "$TMPDIR/.claude/hooks/.curation_pending" ]; then
    pass "TEST-CTX-M4-015: No flag when all shareable entries already have shared_uuid"
else
    fail "TEST-CTX-M4-015: No flag when all shareable entries already have shared_uuid"
fi

# Insert a private entry (should not trigger)
sqlite3 "$TEST_DB" "INSERT INTO behavioral_learnings (rule, confidence, status, occurrences, is_private) VALUES ('Personal preference rule', 0.95, 'active', 5, 1);"

# TEST-CTX-M4-016: Private entries don't trigger curation
CLAUDE_PROJECT_DIR="$TMPDIR" bash "$HOOK_FILE" < /dev/null 2>/dev/null
if [ ! -f "$TMPDIR/.claude/hooks/.curation_pending" ]; then
    pass "TEST-CTX-M4-016: Private entries (is_private=1) don't trigger curation flag"
else
    fail "TEST-CTX-M4-016: Private entries (is_private=1) don't trigger curation flag"
fi

# Insert a resolved incident
sqlite3 "$TEST_DB" "INSERT INTO incidents (incident_id, title, status, domain) VALUES ('INC-TEST-001', 'Test bug', 'resolved', 'auth');"

# TEST-CTX-M4-017: Resolved incidents trigger curation
rm -f "$TMPDIR/.claude/hooks/.curation_pending"
CLAUDE_PROJECT_DIR="$TMPDIR" bash "$HOOK_FILE" < /dev/null 2>/dev/null
if [ -f "$TMPDIR/.claude/hooks/.curation_pending" ]; then
    pass "TEST-CTX-M4-017: Resolved incident triggers .curation_pending flag"
else
    fail "TEST-CTX-M4-017: Resolved incident triggers .curation_pending flag"
fi

# TEST-CTX-M4-018: Hook still does hotspot promotion (backward compat)
sqlite3 "$TEST_DB" "INSERT INTO hotspots (file_path, risk_level, times_touched) VALUES ('src/fragile.rs', 'low', 10);"
rm -f "$TMPDIR/.claude/hooks/.curation_pending"
CLAUDE_PROJECT_DIR="$TMPDIR" bash "$HOOK_FILE" < /dev/null 2>/dev/null
RISK=$(sqlite3 "$TEST_DB" "SELECT risk_level FROM hotspots WHERE file_path = 'src/fragile.rs';")
assert_eq "critical" "$RISK" "TEST-CTX-M4-018: Hotspot promotion still works (10 touches -> critical)"

# ---- Group 3: Edge cases ----
echo ""
echo "--- Group 3: Edge cases ---"

# TEST-CTX-M4-019: Hook handles missing DB gracefully
TMPDIR2=$(mktemp -d)
CLAUDE_PROJECT_DIR="$TMPDIR2" bash "$HOOK_FILE" < /dev/null 2>/dev/null
EXIT_CODE=$?
assert_eq "0" "$EXIT_CODE" "TEST-CTX-M4-019: Hook exits 0 when no memory.db exists"
rm -rf "$TMPDIR2"

# TEST-CTX-M4-020: Hook handles missing .claude/hooks/ directory
TMPDIR3=$(mktemp -d)
mkdir -p "$TMPDIR3/.claude"
cp "$TEST_DB" "$TMPDIR3/.claude/memory.db"
# Insert shareable data
sqlite3 "$TMPDIR3/.claude/memory.db" "INSERT INTO behavioral_learnings (rule, confidence, status, occurrences) VALUES ('Test rule edge', 0.85, 'active', 2);"
CLAUDE_PROJECT_DIR="$TMPDIR3" bash "$HOOK_FILE" < /dev/null 2>/dev/null
EXIT_CODE=$?
assert_eq "0" "$EXIT_CODE" "TEST-CTX-M4-020: Hook exits 0 even when .claude/hooks/ dir missing (creates it)"
rm -rf "$TMPDIR3"

# ---- Results ----
echo ""
echo "============================================================"
echo "RESULTS"
echo "============================================================"
echo "  Total:   $TESTS_RUN"
echo "  Passed:  $TESTS_PASSED"
echo "  Failed:  $TESTS_FAILED"
echo ""
if [ "$TESTS_FAILED" -eq 0 ]; then
    echo "STATUS: ALL PASSED"
else
    echo "STATUS: FAILED ($TESTS_FAILED failures)"
fi
