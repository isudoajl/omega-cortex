#!/bin/bash
# test-persona.sh
#
# TDD red-phase tests for OMEGA Persona feature (Milestone M1).
# Tests written BEFORE implementation — all must fail initially.
#
# Usage:
#   bash tests/test-persona.sh
#   bash tests/test-persona.sh --verbose
#
# Covers:
#   Module 1: Schema (REQ-PERSONA-001, 002, 003) — Must
#   Module 2: Briefing Hook (REQ-PERSONA-004, 005, 006, 009, 010) — Must/Should
#   Module 3: CLAUDE.md Identity Protocol (REQ-PERSONA-007) — Must
#   Module 4: Onboarding Command (REQ-PERSONA-008) — Should

set -u

# ============================================================
# TEST FRAMEWORK (matches existing convention from test-setup-idempotency.sh)
# ============================================================
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
VERBOSE=false

for arg in "$@"; do
    [ "$arg" = "--verbose" ] && VERBOSE=true
done

assert_eq() {
    local expected="$1"
    local actual="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Expected: $expected"
        echo "    Actual:   $actual"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -qF -- "$needle"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Needle not found: $needle"
        if [ "$VERBOSE" = true ]; then
            echo "    Haystack: $(echo "$haystack" | head -20)"
        fi
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -qF -- "$needle"; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Should NOT contain: $needle"
        if [ "$VERBOSE" = true ]; then
            echo "    Haystack: $(echo "$haystack" | head -20)"
        fi
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    fi
}

assert_contains_regex() {
    local haystack="$1"
    local pattern="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -qE "$pattern"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Pattern not matched: $pattern"
        if [ "$VERBOSE" = true ]; then
            echo "    Haystack: $(echo "$haystack" | head -20)"
        fi
    fi
}

assert_file_exists() {
    local path="$1"
    local description="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$path" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    File not found: $path"
    fi
}

assert_gt() {
    local actual="$1"
    local threshold="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$actual" -gt "$threshold" ] 2>/dev/null; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    $actual is not > $threshold"
    fi
}

assert_le() {
    local actual="$1"
    local threshold="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$actual" -le "$threshold" ] 2>/dev/null; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    $actual is not <= $threshold"
    fi
}

skip_test() {
    local description="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo "  SKIP: $description"
}

# ============================================================
# SETUP: Resolve paths and create isolated test environment
# ============================================================

REAL_TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_SQL="$REAL_TOOLKIT_DIR/core/db/schema.sql"
BRIEFING_SH="$REAL_TOOLKIT_DIR/core/hooks/briefing.sh"
CLAUDE_MD="$REAL_TOOLKIT_DIR/CLAUDE.md"
ONBOARD_CMD="$REAL_TOOLKIT_DIR/core/commands/omega-onboard.md"

# Verify critical source files exist
if [ ! -f "$SCHEMA_SQL" ]; then
    echo "ERROR: Cannot find schema.sql at $SCHEMA_SQL"
    exit 1
fi
if [ ! -f "$BRIEFING_SH" ]; then
    echo "ERROR: Cannot find briefing.sh at $BRIEFING_SH"
    exit 1
fi

# Create temp root for all tests
TEST_ROOT=$(mktemp -d)

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

echo "============================================"
echo "  OMEGA Persona Tests (Milestone M1)"
echo "============================================"
echo "  Toolkit: $REAL_TOOLKIT_DIR"
echo "  Temp:    $TEST_ROOT"
echo ""

# ============================================================
# HELPER: Create a fresh memory.db from schema.sql
# ============================================================
create_fresh_db() {
    local db_path="$1"
    mkdir -p "$(dirname "$db_path")"
    sqlite3 "$db_path" < "$SCHEMA_SQL" > /dev/null 2>&1
}

# ============================================================
# HELPER: Create a fresh memory.db from ONLY the pre-persona schema
# (simulates an old DB that predates the persona feature)
# ============================================================
create_pre_persona_db() {
    local db_path="$1"
    mkdir -p "$(dirname "$db_path")"
    # Extract schema but strip user_profile, onboarding_state, and v_workflow_usage
    # We build it by running the full schema then dropping the new tables/view
    # But since we're testing BEFORE implementation, the current schema.sql
    # should NOT have these yet. So the current schema IS the pre-persona schema.
    sqlite3 "$db_path" < "$SCHEMA_SQL" > /dev/null 2>&1
}

# ============================================================
# HELPER: Set up a fake project dir with a DB for briefing tests
# ============================================================
create_briefing_test_env() {
    local test_dir="$1"
    mkdir -p "$test_dir/.claude/hooks"
    create_fresh_db "$test_dir/.claude/memory.db"
    return 0
}

# ============================================================
# HELPER: Run briefing.sh with a fake session, capturing stdout
# ============================================================
run_briefing() {
    local project_dir="$1"
    local session_id="${2:-test-session-$(date +%s)-$$}"

    # Remove any existing briefing flag so it always runs
    rm -f "$project_dir/.claude/hooks/.briefing_done"

    # briefing.sh reads JSON from stdin with session_id
    local input_json="{\"session_id\": \"$session_id\"}"

    # Run briefing.sh with the project dir set via env var
    echo "$input_json" | CLAUDE_PROJECT_DIR="$project_dir" bash "$BRIEFING_SH" 2>/dev/null
}


# ############################################################
# MODULE 1: SCHEMA TESTS
# ############################################################

echo "--- Module 1: Schema (Must) ---"
echo ""

# ============================================================
# Requirement: REQ-PERSONA-001 (Must)
# user_profile table in schema.sql
# ============================================================

test_schema_user_profile_table_exists() {
    echo "[TEST] REQ-PERSONA-001: user_profile table created by schema"
    local db="$TEST_ROOT/m1_001/memory.db"
    create_fresh_db "$db"

    local table_exists
    table_exists=$(sqlite3 "$db" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='user_profile' LIMIT 1;" 2>/dev/null)
    assert_eq "1" "$table_exists" "user_profile table exists after schema init"
}

test_schema_user_profile_columns() {
    echo "[TEST] REQ-PERSONA-001: user_profile has correct columns"
    local db="$TEST_ROOT/m1_001b/memory.db"
    create_fresh_db "$db"

    # Check each required column exists with correct type/default
    local cols
    cols=$(sqlite3 "$db" "PRAGMA table_info(user_profile);" 2>/dev/null)

    assert_contains "$cols" "id" "user_profile has id column"
    assert_contains "$cols" "user_name" "user_profile has user_name column"
    assert_contains "$cols" "experience_level" "user_profile has experience_level column"
    assert_contains "$cols" "communication_style" "user_profile has communication_style column"
    assert_contains "$cols" "created_at" "user_profile has created_at column"
    assert_contains "$cols" "last_seen" "user_profile has last_seen column"
}

test_schema_user_profile_experience_level_default() {
    echo "[TEST] REQ-PERSONA-001: experience_level defaults to 'beginner'"
    local db="$TEST_ROOT/m1_001c/memory.db"
    create_fresh_db "$db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name) VALUES ('Test');" 2>/dev/null
    local level
    level=$(sqlite3 "$db" "SELECT experience_level FROM user_profile LIMIT 1;" 2>/dev/null)
    assert_eq "beginner" "$level" "experience_level defaults to beginner"
}

test_schema_user_profile_communication_style_default() {
    echo "[TEST] REQ-PERSONA-001: communication_style defaults to 'balanced'"
    local db="$TEST_ROOT/m1_001d/memory.db"
    create_fresh_db "$db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name) VALUES ('Test');" 2>/dev/null
    local style
    style=$(sqlite3 "$db" "SELECT communication_style FROM user_profile LIMIT 1;" 2>/dev/null)
    assert_eq "balanced" "$style" "communication_style defaults to balanced"
}

test_schema_user_profile_check_experience_level_valid() {
    echo "[TEST] REQ-PERSONA-001: CHECK constraint accepts valid experience levels"
    local db="$TEST_ROOT/m1_001e/memory.db"
    create_fresh_db "$db"

    local result
    # All three valid values should work
    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level) VALUES ('A', 'beginner');" 2>/dev/null
    result=$(sqlite3 "$db" "SELECT COUNT(*) FROM user_profile WHERE experience_level='beginner';" 2>/dev/null)
    assert_eq "1" "$result" "CHECK accepts 'beginner'"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level) VALUES ('B', 'intermediate');" 2>/dev/null
    result=$(sqlite3 "$db" "SELECT COUNT(*) FROM user_profile WHERE experience_level='intermediate';" 2>/dev/null)
    assert_eq "1" "$result" "CHECK accepts 'intermediate'"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level) VALUES ('C', 'advanced');" 2>/dev/null
    result=$(sqlite3 "$db" "SELECT COUNT(*) FROM user_profile WHERE experience_level='advanced';" 2>/dev/null)
    assert_eq "1" "$result" "CHECK accepts 'advanced'"
}

test_schema_user_profile_check_experience_level_rejects_invalid() {
    echo "[TEST] REQ-PERSONA-001: CHECK constraint rejects invalid experience levels"
    local db="$TEST_ROOT/m1_001f/memory.db"
    create_fresh_db "$db"

    # Invalid value should be rejected
    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level) VALUES ('X', 'expert');" 2>/dev/null
    local count
    count=$(sqlite3 "$db" "SELECT COUNT(*) FROM user_profile;" 2>/dev/null)
    assert_eq "0" "$count" "CHECK rejects 'expert' (invalid experience_level)"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level) VALUES ('X', '');" 2>/dev/null
    count=$(sqlite3 "$db" "SELECT COUNT(*) FROM user_profile;" 2>/dev/null)
    assert_eq "0" "$count" "CHECK rejects empty string for experience_level"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level) VALUES ('X', 'BEGINNER');" 2>/dev/null
    count=$(sqlite3 "$db" "SELECT COUNT(*) FROM user_profile;" 2>/dev/null)
    assert_eq "0" "$count" "CHECK rejects case-mismatched 'BEGINNER'"
}

test_schema_user_profile_check_communication_style_valid() {
    echo "[TEST] REQ-PERSONA-001: CHECK constraint accepts valid communication styles"
    local db="$TEST_ROOT/m1_001g/memory.db"
    create_fresh_db "$db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, communication_style) VALUES ('A', 'verbose');" 2>/dev/null
    local count
    count=$(sqlite3 "$db" "SELECT COUNT(*) FROM user_profile WHERE communication_style='verbose';" 2>/dev/null)
    assert_eq "1" "$count" "CHECK accepts 'verbose'"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, communication_style) VALUES ('B', 'balanced');" 2>/dev/null
    count=$(sqlite3 "$db" "SELECT COUNT(*) FROM user_profile WHERE communication_style='balanced';" 2>/dev/null)
    assert_eq "1" "$count" "CHECK accepts 'balanced'"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, communication_style) VALUES ('C', 'terse');" 2>/dev/null
    count=$(sqlite3 "$db" "SELECT COUNT(*) FROM user_profile WHERE communication_style='terse';" 2>/dev/null)
    assert_eq "1" "$count" "CHECK accepts 'terse'"
}

test_schema_user_profile_check_communication_style_rejects_invalid() {
    echo "[TEST] REQ-PERSONA-001: CHECK constraint rejects invalid communication styles"
    local db="$TEST_ROOT/m1_001h/memory.db"
    create_fresh_db "$db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, communication_style) VALUES ('X', 'detailed');" 2>/dev/null
    local count
    count=$(sqlite3 "$db" "SELECT COUNT(*) FROM user_profile;" 2>/dev/null)
    assert_eq "0" "$count" "CHECK rejects 'detailed' (invalid communication_style)"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, communication_style) VALUES ('X', 'TERSE');" 2>/dev/null
    count=$(sqlite3 "$db" "SELECT COUNT(*) FROM user_profile;" 2>/dev/null)
    assert_eq "0" "$count" "CHECK rejects case-mismatched 'TERSE'"
}

test_schema_user_profile_created_at_default() {
    echo "[TEST] REQ-PERSONA-001: created_at auto-populates with datetime"
    local db="$TEST_ROOT/m1_001i/memory.db"
    create_fresh_db "$db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name) VALUES ('Test');" 2>/dev/null
    local created_at
    created_at=$(sqlite3 "$db" "SELECT created_at FROM user_profile LIMIT 1;" 2>/dev/null)
    # Should be a non-empty datetime string like "2024-01-01 00:00:00"
    assert_contains_regex "$created_at" "^[0-9]{4}-[0-9]{2}-[0-9]{2}" "created_at has datetime format"
}

test_schema_user_profile_last_seen_default() {
    echo "[TEST] REQ-PERSONA-001: last_seen auto-populates with datetime"
    local db="$TEST_ROOT/m1_001j/memory.db"
    create_fresh_db "$db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name) VALUES ('Test');" 2>/dev/null
    local last_seen
    last_seen=$(sqlite3 "$db" "SELECT last_seen FROM user_profile LIMIT 1;" 2>/dev/null)
    assert_contains_regex "$last_seen" "^[0-9]{4}-[0-9]{2}-[0-9]{2}" "last_seen has datetime format"
}

test_schema_user_profile_idempotent() {
    echo "[TEST] REQ-PERSONA-001: Schema is idempotent (re-run does not break)"
    local db="$TEST_ROOT/m1_001k/memory.db"
    create_fresh_db "$db"

    # Insert data, then re-run schema
    sqlite3 "$db" "INSERT INTO user_profile (user_name) VALUES ('Survives');" 2>/dev/null
    sqlite3 "$db" < "$SCHEMA_SQL" > /dev/null 2>&1

    local name
    name=$(sqlite3 "$db" "SELECT user_name FROM user_profile LIMIT 1;" 2>/dev/null)
    assert_eq "Survives" "$name" "Data survives schema re-run (CREATE TABLE IF NOT EXISTS)"
}

test_schema_user_profile_null_name_allowed() {
    echo "[TEST] REQ-PERSONA-001: user_name allows NULL"
    local db="$TEST_ROOT/m1_001l/memory.db"
    create_fresh_db "$db"

    sqlite3 "$db" "INSERT INTO user_profile (experience_level) VALUES ('beginner');" 2>/dev/null
    local count
    count=$(sqlite3 "$db" "SELECT COUNT(*) FROM user_profile;" 2>/dev/null)
    assert_eq "1" "$count" "Row inserted with NULL user_name"
}

echo ""

# ============================================================
# Requirement: REQ-PERSONA-002 (Must)
# onboarding_state table in schema.sql
# ============================================================

test_schema_onboarding_state_table_exists() {
    echo "[TEST] REQ-PERSONA-002: onboarding_state table created by schema"
    local db="$TEST_ROOT/m1_002/memory.db"
    create_fresh_db "$db"

    local table_exists
    table_exists=$(sqlite3 "$db" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='onboarding_state' LIMIT 1;" 2>/dev/null)
    assert_eq "1" "$table_exists" "onboarding_state table exists after schema init"
}

test_schema_onboarding_state_columns() {
    echo "[TEST] REQ-PERSONA-002: onboarding_state has correct columns"
    local db="$TEST_ROOT/m1_002b/memory.db"
    create_fresh_db "$db"

    local cols
    cols=$(sqlite3 "$db" "PRAGMA table_info(onboarding_state);" 2>/dev/null)

    assert_contains "$cols" "id" "onboarding_state has id column"
    assert_contains "$cols" "step" "onboarding_state has step column"
    assert_contains "$cols" "status" "onboarding_state has status column"
    assert_contains "$cols" "data" "onboarding_state has data column"
    assert_contains "$cols" "started_at" "onboarding_state has started_at column"
    assert_contains "$cols" "completed_at" "onboarding_state has completed_at column"
}

test_schema_onboarding_state_status_default() {
    echo "[TEST] REQ-PERSONA-002: status defaults to 'not_started'"
    local db="$TEST_ROOT/m1_002c/memory.db"
    create_fresh_db "$db"

    sqlite3 "$db" "INSERT INTO onboarding_state (step) VALUES ('name');" 2>/dev/null
    local status
    status=$(sqlite3 "$db" "SELECT status FROM onboarding_state LIMIT 1;" 2>/dev/null)
    assert_eq "not_started" "$status" "status defaults to not_started"
}

test_schema_onboarding_state_step_default() {
    echo "[TEST] REQ-PERSONA-002: step defaults to 'not_started'"
    local db="$TEST_ROOT/m1_002d/memory.db"
    create_fresh_db "$db"

    sqlite3 "$db" "INSERT INTO onboarding_state (data) VALUES ('{}');" 2>/dev/null
    local step
    step=$(sqlite3 "$db" "SELECT step FROM onboarding_state LIMIT 1;" 2>/dev/null)
    assert_eq "not_started" "$step" "step defaults to not_started"
}

test_schema_onboarding_state_check_status_valid() {
    echo "[TEST] REQ-PERSONA-002: CHECK constraint accepts valid statuses"
    local db="$TEST_ROOT/m1_002e/memory.db"
    create_fresh_db "$db"

    sqlite3 "$db" "INSERT INTO onboarding_state (status) VALUES ('not_started');" 2>/dev/null
    sqlite3 "$db" "INSERT INTO onboarding_state (status) VALUES ('in_progress');" 2>/dev/null
    sqlite3 "$db" "INSERT INTO onboarding_state (status) VALUES ('completed');" 2>/dev/null

    local count
    count=$(sqlite3 "$db" "SELECT COUNT(*) FROM onboarding_state;" 2>/dev/null)
    assert_eq "3" "$count" "All three valid status values accepted"
}

test_schema_onboarding_state_check_status_rejects_invalid() {
    echo "[TEST] REQ-PERSONA-002: CHECK constraint rejects invalid statuses"
    local db="$TEST_ROOT/m1_002f/memory.db"
    create_fresh_db "$db"

    sqlite3 "$db" "INSERT INTO onboarding_state (status) VALUES ('done');" 2>/dev/null
    local count
    count=$(sqlite3 "$db" "SELECT COUNT(*) FROM onboarding_state;" 2>/dev/null)
    assert_eq "0" "$count" "CHECK rejects 'done' (invalid status)"

    sqlite3 "$db" "INSERT INTO onboarding_state (status) VALUES ('COMPLETED');" 2>/dev/null
    count=$(sqlite3 "$db" "SELECT COUNT(*) FROM onboarding_state;" 2>/dev/null)
    assert_eq "0" "$count" "CHECK rejects case-mismatched 'COMPLETED'"
}

test_schema_onboarding_state_data_stores_json() {
    echo "[TEST] REQ-PERSONA-002: data column stores JSON blob"
    local db="$TEST_ROOT/m1_002g/memory.db"
    create_fresh_db "$db"

    local json_data='{"name":"Ivan","experience_level":"intermediate"}'
    sqlite3 "$db" "INSERT INTO onboarding_state (data) VALUES ('$json_data');" 2>/dev/null
    local stored
    stored=$(sqlite3 "$db" "SELECT data FROM onboarding_state LIMIT 1;" 2>/dev/null)
    assert_eq "$json_data" "$stored" "JSON blob stored and retrieved correctly"
}

test_schema_onboarding_state_idempotent() {
    echo "[TEST] REQ-PERSONA-002: Schema is idempotent for onboarding_state"
    local db="$TEST_ROOT/m1_002h/memory.db"
    create_fresh_db "$db"

    sqlite3 "$db" "INSERT INTO onboarding_state (status) VALUES ('completed');" 2>/dev/null
    sqlite3 "$db" < "$SCHEMA_SQL" > /dev/null 2>&1

    local status
    status=$(sqlite3 "$db" "SELECT status FROM onboarding_state LIMIT 1;" 2>/dev/null)
    assert_eq "completed" "$status" "Data survives schema re-run"
}

echo ""

# ============================================================
# Requirement: REQ-PERSONA-003 (Must)
# v_workflow_usage view in schema.sql
# ============================================================

test_schema_view_exists() {
    echo "[TEST] REQ-PERSONA-003: v_workflow_usage view created by schema"
    local db="$TEST_ROOT/m1_003/memory.db"
    create_fresh_db "$db"

    local view_exists
    view_exists=$(sqlite3 "$db" "SELECT 1 FROM sqlite_master WHERE type='view' AND name='v_workflow_usage' LIMIT 1;" 2>/dev/null)
    assert_eq "1" "$view_exists" "v_workflow_usage view exists after schema init"
}

test_schema_view_returns_empty_on_fresh_db() {
    echo "[TEST] REQ-PERSONA-003: v_workflow_usage returns empty on fresh DB (no error)"
    local db="$TEST_ROOT/m1_003b/memory.db"
    create_fresh_db "$db"

    local result
    result=$(sqlite3 "$db" "SELECT COUNT(*) FROM v_workflow_usage;" 2>/dev/null)
    assert_eq "0" "$result" "View returns 0 rows on fresh DB"
}

test_schema_view_aggregates_by_type() {
    echo "[TEST] REQ-PERSONA-003: v_workflow_usage aggregates workflow_runs by type"
    local db="$TEST_ROOT/m1_003c/memory.db"
    create_fresh_db "$db"

    # Insert various workflow runs
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'failed');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('bugfix', 'completed');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('bugfix', 'running');"

    local nf_total nf_completed bf_total bf_completed
    nf_total=$(sqlite3 "$db" "SELECT total_runs FROM v_workflow_usage WHERE type='new-feature';" 2>/dev/null)
    nf_completed=$(sqlite3 "$db" "SELECT completed_runs FROM v_workflow_usage WHERE type='new-feature';" 2>/dev/null)
    bf_total=$(sqlite3 "$db" "SELECT total_runs FROM v_workflow_usage WHERE type='bugfix';" 2>/dev/null)
    bf_completed=$(sqlite3 "$db" "SELECT completed_runs FROM v_workflow_usage WHERE type='bugfix';" 2>/dev/null)

    assert_eq "3" "$nf_total" "new-feature: total_runs = 3"
    assert_eq "2" "$nf_completed" "new-feature: completed_runs = 2"
    assert_eq "2" "$bf_total" "bugfix: total_runs = 2"
    assert_eq "1" "$bf_completed" "bugfix: completed_runs = 1"
}

test_schema_view_has_correct_columns() {
    echo "[TEST] REQ-PERSONA-003: v_workflow_usage has type, total_runs, completed_runs, last_run columns"
    local db="$TEST_ROOT/m1_003d/memory.db"
    create_fresh_db "$db"

    # Insert one run so the view returns a row
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('test', 'completed');"

    local cols
    cols=$(sqlite3 -header "$db" "SELECT * FROM v_workflow_usage LIMIT 1;" 2>/dev/null | head -1)

    assert_contains "$cols" "type" "View has 'type' column"
    assert_contains "$cols" "total_runs" "View has 'total_runs' column"
    assert_contains "$cols" "completed_runs" "View has 'completed_runs' column"
    assert_contains "$cols" "last_run" "View has 'last_run' column"
}

test_schema_view_ordered_by_completed_desc() {
    echo "[TEST] REQ-PERSONA-003: v_workflow_usage orders by completed_runs DESC"
    local db="$TEST_ROOT/m1_003e/memory.db"
    create_fresh_db "$db"

    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('bugfix', 'completed');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('improve', 'completed');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('improve', 'completed');"

    # First row should be new-feature (3 completed), then improve (2), then bugfix (1)
    local first_type
    first_type=$(sqlite3 "$db" "SELECT type FROM v_workflow_usage LIMIT 1;" 2>/dev/null)
    assert_eq "new-feature" "$first_type" "First row is highest completed_runs type"
}

test_schema_view_last_run_populated() {
    echo "[TEST] REQ-PERSONA-003: v_workflow_usage last_run shows most recent started_at"
    local db="$TEST_ROOT/m1_003f/memory.db"
    create_fresh_db "$db"

    sqlite3 "$db" "INSERT INTO workflow_runs (type, status, started_at) VALUES ('bugfix', 'completed', '2025-01-01 00:00:00');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status, started_at) VALUES ('bugfix', 'completed', '2025-06-15 12:00:00');"

    local last_run
    last_run=$(sqlite3 "$db" "SELECT last_run FROM v_workflow_usage WHERE type='bugfix';" 2>/dev/null)
    assert_eq "2025-06-15 12:00:00" "$last_run" "last_run shows most recent started_at"
}

test_schema_view_works_without_user_profile() {
    echo "[TEST] REQ-PERSONA-003/005: v_workflow_usage works regardless of user_profile existence"
    local db="$TEST_ROOT/m1_003g/memory.db"
    # Create a DB with only pre-persona schema (no user_profile)
    create_pre_persona_db "$db"

    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('audit', 'completed');"
    local count
    count=$(sqlite3 "$db" "SELECT total_runs FROM v_workflow_usage WHERE type='audit';" 2>/dev/null)
    assert_eq "1" "$count" "View works without user_profile table"
}

test_schema_existing_tables_unaffected() {
    echo "[TEST] REQ-PERSONA-001/002: New tables do not break existing tables"
    local db="$TEST_ROOT/m1_existing/memory.db"
    create_fresh_db "$db"

    # Insert data into existing tables
    sqlite3 "$db" "INSERT INTO workflow_runs (type, description) VALUES ('test', 'existing data');"
    sqlite3 "$db" "INSERT INTO hotspots (file_path, risk_level) VALUES ('test.rs', 'high');"
    sqlite3 "$db" "INSERT INTO decisions (run_id, domain, decision) VALUES (1, 'test', 'Keep it simple');"

    # Verify existing data intact
    local wr_count hs_count dec_count
    wr_count=$(sqlite3 "$db" "SELECT COUNT(*) FROM workflow_runs;" 2>/dev/null)
    hs_count=$(sqlite3 "$db" "SELECT COUNT(*) FROM hotspots;" 2>/dev/null)
    dec_count=$(sqlite3 "$db" "SELECT COUNT(*) FROM decisions;" 2>/dev/null)

    assert_eq "1" "$wr_count" "workflow_runs data preserved"
    assert_eq "1" "$hs_count" "hotspots data preserved"
    assert_eq "1" "$dec_count" "decisions data preserved"
}

echo ""

# ############################################################
# MODULE 2: BRIEFING HOOK TESTS
# ############################################################

echo "--- Module 2: Briefing Hook (Must/Should) ---"
echo ""

# ============================================================
# Requirement: REQ-PERSONA-004 (Must)
# OMEGA Identity Block in briefing.sh
# ============================================================

test_briefing_identity_block_shown_with_profile() {
    echo "[TEST] REQ-PERSONA-004: Identity block appears when profile exists"
    local test_dir="$TEST_ROOT/m2_004"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    # Insert a profile
    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('Ivan', 'intermediate', 'balanced');"

    local output
    output=$(run_briefing "$test_dir")

    assert_contains "$output" "OMEGA IDENTITY" "Identity block header appears in briefing"
    assert_contains "$output" "Ivan" "User name appears in identity block"
    assert_contains "$output" "intermediate" "Experience level appears in identity block"
    assert_contains "$output" "balanced" "Communication style appears in identity block"
}

test_briefing_identity_block_format() {
    echo "[TEST] REQ-PERSONA-004: Identity block has correct format"
    local test_dir="$TEST_ROOT/m2_004b"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('Ivan', 'intermediate', 'balanced');"

    local output
    output=$(run_briefing "$test_dir")

    # Expected format: OMEGA IDENTITY: Ivan | Experience: intermediate | Style: balanced | Workflows: N completed
    assert_contains "$output" "Experience:" "Format includes 'Experience:'"
    assert_contains "$output" "Style:" "Format includes 'Style:'"
    assert_contains "$output" "Workflows:" "Format includes 'Workflows:'"
}

test_briefing_identity_block_shows_usage_summary() {
    echo "[TEST] REQ-PERSONA-004: Identity block shows workflow usage summary"
    local test_dir="$TEST_ROOT/m2_004c"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('Ivan', 'intermediate', 'balanced');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('bugfix', 'completed');"

    local output
    output=$(run_briefing "$test_dir")

    # Should show total completed count
    assert_contains "$output" "3 completed" "Shows total completed workflows count"
}

test_briefing_identity_block_with_usage_breakdown() {
    echo "[TEST] REQ-PERSONA-004: Identity block shows type breakdown"
    local test_dir="$TEST_ROOT/m2_004d"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('Ivan', 'advanced', 'terse');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('bugfix', 'completed');"
    sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('bugfix', 'completed');"

    local output
    output=$(run_briefing "$test_dir")

    assert_contains "$output" "new-feature" "Breakdown includes new-feature"
    assert_contains "$output" "bugfix" "Breakdown includes bugfix"
}

test_briefing_identity_block_zero_completed() {
    echo "[TEST] REQ-PERSONA-004: Identity block shows 0 completed when no workflows done"
    local test_dir="$TEST_ROOT/m2_004e"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('NewUser', 'beginner', 'verbose');"

    local output
    output=$(run_briefing "$test_dir")

    assert_contains "$output" "OMEGA IDENTITY" "Identity block still appears with 0 workflows"
    assert_contains "$output" "0 completed" "Shows 0 completed"
}

test_briefing_identity_block_position_before_hotspots() {
    echo "[TEST] REQ-PERSONA-004: Identity block appears BEFORE hotspots section"
    local test_dir="$TEST_ROOT/m2_004f"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('Ivan', 'intermediate', 'balanced');"
    sqlite3 "$db" "INSERT INTO hotspots (file_path, risk_level, times_touched) VALUES ('fragile.rs', 'critical', 5);"

    local output
    output=$(run_briefing "$test_dir")

    # OMEGA IDENTITY should come before HOTSPOTS in the output
    local identity_line hotspot_line
    identity_line=$(echo "$output" | grep -n "OMEGA IDENTITY" | head -1 | cut -d: -f1)
    hotspot_line=$(echo "$output" | grep -n "HOTSPOTS" | head -1 | cut -d: -f1)

    if [ -n "$identity_line" ] && [ -n "$hotspot_line" ]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        if [ "$identity_line" -lt "$hotspot_line" ]; then
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo "  PASS: Identity block appears before hotspots"
        else
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo "  FAIL: Identity block appears before hotspots"
            echo "    Identity at line $identity_line, Hotspots at line $hotspot_line"
        fi
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: Identity block appears before hotspots"
        echo "    Could not find one or both sections in output"
        if [ "$VERBOSE" = true ]; then
            echo "    Output: $(echo "$output" | head -20)"
        fi
    fi
}

test_briefing_identity_block_position_after_header() {
    echo "[TEST] REQ-PERSONA-004: Identity block appears AFTER the header box"
    local test_dir="$TEST_ROOT/m2_004g"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('Ivan', 'intermediate', 'balanced');"

    local output
    output=$(run_briefing "$test_dir")

    local header_line identity_line
    header_line=$(echo "$output" | grep -n "INSTITUTIONAL MEMORY BRIEFING" | head -1 | cut -d: -f1)
    identity_line=$(echo "$output" | grep -n "OMEGA IDENTITY" | head -1 | cut -d: -f1)

    if [ -n "$header_line" ] && [ -n "$identity_line" ]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        if [ "$identity_line" -gt "$header_line" ]; then
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo "  PASS: Identity block appears after header box"
        else
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo "  FAIL: Identity block appears after header box"
            echo "    Header at line $header_line, Identity at line $identity_line"
        fi
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: Identity block appears after header box"
        echo "    Could not find one or both sections"
    fi
}

echo ""

# ============================================================
# Requirement: REQ-PERSONA-005 (Must)
# No-profile backward compatibility
# ============================================================

test_briefing_no_error_without_user_profile_table() {
    echo "[TEST] REQ-PERSONA-005: No error when user_profile table is missing (old DB)"
    local test_dir="$TEST_ROOT/m2_005"
    mkdir -p "$test_dir/.claude/hooks"

    # Create a DB WITHOUT the persona tables (simulate old DB)
    create_pre_persona_db "$test_dir/.claude/memory.db"
    # Drop user_profile if it happens to exist from the current schema
    sqlite3 "$test_dir/.claude/memory.db" "DROP TABLE IF EXISTS user_profile;" 2>/dev/null
    sqlite3 "$test_dir/.claude/memory.db" "DROP TABLE IF EXISTS onboarding_state;" 2>/dev/null
    sqlite3 "$test_dir/.claude/memory.db" "DROP VIEW IF EXISTS v_workflow_usage;" 2>/dev/null

    local output exit_code
    output=$(run_briefing "$test_dir")
    exit_code=$?

    assert_eq "0" "$exit_code" "briefing.sh exits 0 with no user_profile table"
    assert_not_contains "$output" "OMEGA IDENTITY" "No identity block when table missing"
    assert_not_contains "$output" "no such table: user_profile" "No user_profile table error in output"
    # The header box should still appear (existing behavior)
    assert_contains "$output" "INSTITUTIONAL MEMORY BRIEFING" "Header box still appears"
}

test_briefing_no_error_with_empty_user_profile() {
    echo "[TEST] REQ-PERSONA-005: No error when user_profile table exists but is empty"
    local test_dir="$TEST_ROOT/m2_005b"
    create_briefing_test_env "$test_dir"

    local output exit_code
    output=$(run_briefing "$test_dir")
    exit_code=$?

    assert_eq "0" "$exit_code" "briefing.sh exits 0 with empty user_profile"
    assert_not_contains "$output" "OMEGA IDENTITY:" "No identity line when profile empty"
    assert_contains "$output" "INSTITUTIONAL MEMORY BRIEFING" "Header box still appears"
}

test_briefing_existing_sections_unchanged_without_profile() {
    echo "[TEST] REQ-PERSONA-005: Existing briefing sections unaffected when no profile"
    local test_dir="$TEST_ROOT/m2_005c"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    # Add data that triggers existing sections
    sqlite3 "$db" "INSERT INTO workflow_runs (type, description) VALUES ('manual', 'test run');"
    sqlite3 "$db" "INSERT INTO hotspots (file_path, risk_level, times_touched) VALUES ('test.rs', 'critical', 3);"
    sqlite3 "$db" "INSERT INTO failed_approaches (run_id, domain, problem, approach, failure_reason) VALUES (1, 'test', 'problem', 'approach', 'reason');"

    local output
    output=$(run_briefing "$test_dir")

    assert_contains "$output" "HOTSPOTS" "Hotspots section still present"
    assert_contains "$output" "FAILED APPROACHES" "Failed approaches section still present"
    assert_contains "$output" "WORKFLOW RUNS" "Workflow runs section still present"
    assert_contains "$output" "DEBRIEF OBLIGATION" "Debrief section still present"
}

echo ""

# ============================================================
# Requirement: REQ-PERSONA-006 (Must)
# Experience auto-upgrade logic
# ============================================================

test_briefing_auto_upgrade_beginner_to_intermediate() {
    echo "[TEST] REQ-PERSONA-006: beginner -> intermediate at 10 completed workflows"
    local test_dir="$TEST_ROOT/m2_006"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level) VALUES ('Learner', 'beginner');"

    # Insert exactly 10 completed workflow runs
    for i in $(seq 1 10); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('bugfix', 'completed');"
    done

    run_briefing "$test_dir" > /dev/null 2>&1

    local level
    level=$(sqlite3 "$db" "SELECT experience_level FROM user_profile LIMIT 1;" 2>/dev/null)
    assert_eq "intermediate" "$level" "Auto-upgraded beginner to intermediate at 10 completed"
}

test_briefing_no_upgrade_beginner_at_9() {
    echo "[TEST] REQ-PERSONA-006: beginner stays beginner at 9 completed workflows"
    local test_dir="$TEST_ROOT/m2_006b"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level) VALUES ('Almost', 'beginner');"

    for i in $(seq 1 9); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('bugfix', 'completed');"
    done

    run_briefing "$test_dir" > /dev/null 2>&1

    local level
    level=$(sqlite3 "$db" "SELECT experience_level FROM user_profile LIMIT 1;" 2>/dev/null)
    assert_eq "beginner" "$level" "No upgrade at 9 completed (threshold is 10)"
}

test_briefing_auto_upgrade_intermediate_to_advanced() {
    echo "[TEST] REQ-PERSONA-006: intermediate -> advanced at 30 completed workflows"
    local test_dir="$TEST_ROOT/m2_006c"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level) VALUES ('Pro', 'intermediate');"

    for i in $(seq 1 30); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    done

    run_briefing "$test_dir" > /dev/null 2>&1

    local level
    level=$(sqlite3 "$db" "SELECT experience_level FROM user_profile LIMIT 1;" 2>/dev/null)
    assert_eq "advanced" "$level" "Auto-upgraded intermediate to advanced at 30 completed"
}

test_briefing_no_upgrade_intermediate_at_29() {
    echo "[TEST] REQ-PERSONA-006: intermediate stays intermediate at 29 completed"
    local test_dir="$TEST_ROOT/m2_006d"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level) VALUES ('Pro', 'intermediate');"

    for i in $(seq 1 29); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    done

    run_briefing "$test_dir" > /dev/null 2>&1

    local level
    level=$(sqlite3 "$db" "SELECT experience_level FROM user_profile LIMIT 1;" 2>/dev/null)
    assert_eq "intermediate" "$level" "No upgrade at 29 completed (threshold is 30)"
}

test_briefing_no_double_upgrade_beginner_to_advanced() {
    echo "[TEST] REQ-PERSONA-006: beginner does NOT jump to advanced in one session"
    local test_dir="$TEST_ROOT/m2_006e"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level) VALUES ('Jumper', 'beginner');"

    # Insert 30+ completed runs — enough for both thresholds
    for i in $(seq 1 35); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    done

    run_briefing "$test_dir" > /dev/null 2>&1

    local level
    level=$(sqlite3 "$db" "SELECT experience_level FROM user_profile LIMIT 1;" 2>/dev/null)
    assert_eq "intermediate" "$level" "beginner upgrades to intermediate, NOT advanced (no double-upgrade)"
}

test_briefing_advanced_stays_advanced() {
    echo "[TEST] REQ-PERSONA-006: advanced user is not downgraded or changed"
    local test_dir="$TEST_ROOT/m2_006f"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level) VALUES ('Expert', 'advanced');"

    # Even with 0 completed workflows, advanced should stay advanced
    run_briefing "$test_dir" > /dev/null 2>&1

    local level
    level=$(sqlite3 "$db" "SELECT experience_level FROM user_profile LIMIT 1;" 2>/dev/null)
    assert_eq "advanced" "$level" "advanced user stays advanced (no downgrade)"
}

test_briefing_upgrade_noop_without_profile() {
    echo "[TEST] REQ-PERSONA-006: Auto-upgrade is no-op when no profile exists"
    local test_dir="$TEST_ROOT/m2_006g"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    # Insert completed runs but no profile
    for i in $(seq 1 15); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('bugfix', 'completed');"
    done

    local output exit_code
    output=$(run_briefing "$test_dir")
    exit_code=$?

    assert_eq "0" "$exit_code" "briefing.sh exits 0 (upgrade noop with no profile)"
    # No user_profile rows should have been created
    local count
    count=$(sqlite3 "$db" "SELECT COUNT(*) FROM user_profile;" 2>/dev/null)
    assert_eq "0" "$count" "No phantom profile created by auto-upgrade"
}

test_briefing_upgrade_only_counts_completed() {
    echo "[TEST] REQ-PERSONA-006: Auto-upgrade only counts completed workflows"
    local test_dir="$TEST_ROOT/m2_006h"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level) VALUES ('Active', 'beginner');"

    # Insert 15 runs but only 8 completed
    for i in $(seq 1 8); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('bugfix', 'completed');"
    done
    for i in $(seq 1 4); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('bugfix', 'failed');"
    done
    for i in $(seq 1 3); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('bugfix', 'running');"
    done

    run_briefing "$test_dir" > /dev/null 2>&1

    local level
    level=$(sqlite3 "$db" "SELECT experience_level FROM user_profile LIMIT 1;" 2>/dev/null)
    assert_eq "beginner" "$level" "No upgrade: only 8 completed out of 15 total"
}

test_briefing_upgrade_reflected_in_identity_block() {
    echo "[TEST] REQ-PERSONA-006: Upgraded level shown in same session identity block"
    local test_dir="$TEST_ROOT/m2_006i"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level) VALUES ('Upgrader', 'beginner');"

    for i in $(seq 1 10); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    done

    local output
    output=$(run_briefing "$test_dir")

    # The identity block should show the NEW level, not the old one
    assert_contains "$output" "intermediate" "Identity block shows upgraded level (intermediate)"
    assert_not_contains "$output" "Experience: beginner" "Identity block does NOT show old level (beginner)"
}

echo ""

# ============================================================
# Requirement: REQ-PERSONA-009 (Should)
# last_seen auto-update
# ============================================================

test_briefing_last_seen_updated() {
    echo "[TEST] REQ-PERSONA-009: last_seen is updated during briefing"
    local test_dir="$TEST_ROOT/m2_009"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, last_seen) VALUES ('Test', '2024-01-01 00:00:00');"

    local old_seen
    old_seen=$(sqlite3 "$db" "SELECT last_seen FROM user_profile LIMIT 1;" 2>/dev/null)

    # Run briefing (which should update last_seen)
    run_briefing "$test_dir" > /dev/null 2>&1

    local new_seen
    new_seen=$(sqlite3 "$db" "SELECT last_seen FROM user_profile LIMIT 1;" 2>/dev/null)

    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$new_seen" != "$old_seen" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: last_seen was updated (was: $old_seen, now: $new_seen)"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: last_seen was NOT updated (still: $old_seen)"
    fi
}

test_briefing_last_seen_not_updated_without_profile() {
    echo "[TEST] REQ-PERSONA-009: last_seen not updated when profile is empty"
    local test_dir="$TEST_ROOT/m2_009b"
    create_briefing_test_env "$test_dir"

    local output exit_code
    output=$(run_briefing "$test_dir")
    exit_code=$?

    assert_eq "0" "$exit_code" "briefing.sh exits 0 (no profile, no last_seen update)"
}

echo ""

# ============================================================
# Requirement: REQ-PERSONA-010 (Should)
# Onboarding prompt in briefing.sh
# ============================================================

test_briefing_onboarding_prompt_when_table_empty() {
    echo "[TEST] REQ-PERSONA-010: Onboarding prompt shown when user_profile exists but empty"
    local test_dir="$TEST_ROOT/m2_010"
    create_briefing_test_env "$test_dir"

    local output
    output=$(run_briefing "$test_dir")

    assert_contains "$output" "onboard" "Onboarding prompt mentions onboard command"
}

test_briefing_onboarding_prompt_includes_manual_sql() {
    echo "[TEST] REQ-PERSONA-010: Onboarding prompt includes manual SQL alternative"
    local test_dir="$TEST_ROOT/m2_010b"
    create_briefing_test_env "$test_dir"

    local output
    output=$(run_briefing "$test_dir")

    assert_contains "$output" "sqlite3" "Onboarding prompt includes sqlite3 manual alternative"
    assert_contains "$output" "INSERT INTO user_profile" "Manual SQL shows INSERT INTO user_profile"
}

test_briefing_onboarding_prompt_not_shown_when_table_missing() {
    echo "[TEST] REQ-PERSONA-010: Onboarding prompt NOT shown when table is missing (old DB)"
    local test_dir="$TEST_ROOT/m2_010c"
    mkdir -p "$test_dir/.claude/hooks"

    # Old DB without persona tables
    create_pre_persona_db "$test_dir/.claude/memory.db"
    sqlite3 "$test_dir/.claude/memory.db" "DROP TABLE IF EXISTS user_profile;" 2>/dev/null
    sqlite3 "$test_dir/.claude/memory.db" "DROP TABLE IF EXISTS onboarding_state;" 2>/dev/null
    sqlite3 "$test_dir/.claude/memory.db" "DROP VIEW IF EXISTS v_workflow_usage;" 2>/dev/null

    local output
    output=$(run_briefing "$test_dir")

    assert_not_contains "$output" "onboard" "No onboarding prompt for pre-persona DB"
}

test_briefing_onboarding_prompt_not_shown_when_profile_exists() {
    echo "[TEST] REQ-PERSONA-010: Onboarding prompt NOT shown when profile exists"
    local test_dir="$TEST_ROOT/m2_010d"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('Ivan', 'intermediate', 'balanced');"

    local output
    output=$(run_briefing "$test_dir")

    # When profile exists, we should see identity block, NOT onboarding prompt
    assert_contains "$output" "OMEGA IDENTITY" "Identity block shown when profile exists"
    assert_not_contains "$output" "Personalize your experience" "No onboarding prompt when profile exists"
}

test_briefing_onboarding_prompt_nonblocking() {
    echo "[TEST] REQ-PERSONA-010: Onboarding prompt does not block briefing"
    local test_dir="$TEST_ROOT/m2_010e"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    # Add some data that triggers other briefing sections
    sqlite3 "$db" "INSERT INTO workflow_runs (type, description) VALUES ('manual', 'test');"

    local output
    output=$(run_briefing "$test_dir")

    # The debrief obligation should still appear after the onboarding prompt
    assert_contains "$output" "DEBRIEF OBLIGATION" "Debrief section still appears after onboarding prompt"
}

echo ""

# ############################################################
# MODULE 2: EDGE CASES AND FAILURE MODES
# ############################################################

echo "--- Module 2: Edge Cases ---"
echo ""

test_briefing_special_chars_in_user_name() {
    echo "[TEST] REQ-PERSONA-004 Edge: Special characters in user_name"
    local test_dir="$TEST_ROOT/m2_edge_chars"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    # Name with special characters (but no SQL injection)
    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('O''Brien-Smith', 'beginner', 'verbose');"

    local output exit_code
    output=$(run_briefing "$test_dir")
    exit_code=$?

    assert_eq "0" "$exit_code" "briefing.sh exits 0 with special chars in name"
    assert_contains "$output" "OMEGA IDENTITY" "Identity block appears with special-char name"
}

test_briefing_null_user_name() {
    echo "[TEST] REQ-PERSONA-004 Edge: NULL user_name defaults gracefully"
    local test_dir="$TEST_ROOT/m2_edge_null"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (experience_level, communication_style) VALUES ('beginner', 'balanced');"

    local output exit_code
    output=$(run_briefing "$test_dir")
    exit_code=$?

    assert_eq "0" "$exit_code" "briefing.sh exits 0 with NULL user_name"
    # Should show "User" or similar default, not empty or error
    assert_contains "$output" "OMEGA IDENTITY" "Identity block appears with NULL name"
}

test_briefing_no_db_file() {
    echo "[TEST] REQ-PERSONA-005 Edge: No memory.db file at all"
    local test_dir="$TEST_ROOT/m2_edge_nodb"
    mkdir -p "$test_dir/.claude/hooks"
    # Deliberately do NOT create memory.db

    local output exit_code
    output=$(run_briefing "$test_dir")
    exit_code=$?

    assert_eq "0" "$exit_code" "briefing.sh exits 0 with no DB file"
    assert_not_contains "$output" "OMEGA IDENTITY" "No identity block with no DB"
}

test_briefing_readonly_db() {
    echo "[TEST] REQ-PERSONA-006 Edge: Read-only DB does not crash briefing"
    local test_dir="$TEST_ROOT/m2_edge_readonly"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level) VALUES ('ReadOnly', 'beginner');"
    for i in $(seq 1 10); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('bugfix', 'completed');"
    done

    # Make DB read-only
    chmod 444 "$db"

    local output exit_code
    output=$(run_briefing "$test_dir")
    exit_code=$?

    # Restore permissions for cleanup
    chmod 644 "$db"

    assert_eq "0" "$exit_code" "briefing.sh exits 0 with read-only DB"
    # Identity block may or may not show, but it should not crash
}

test_briefing_multiple_profile_rows() {
    echo "[TEST] REQ-PERSONA-004 Edge: Multiple user_profile rows (uses first)"
    local test_dir="$TEST_ROOT/m2_edge_multi"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    # Insert multiple rows (shouldn't happen, but defensive test)
    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('First', 'beginner', 'verbose');"
    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('Second', 'advanced', 'terse');"

    local output exit_code
    output=$(run_briefing "$test_dir")
    exit_code=$?

    assert_eq "0" "$exit_code" "briefing.sh exits 0 with multiple profile rows"
    # Should use LIMIT 1, so it picks one (architecture says first row)
    assert_contains "$output" "OMEGA IDENTITY" "Identity block appears with multiple rows"
}

test_briefing_large_workflow_count() {
    echo "[TEST] REQ-PERSONA-004 Edge: Large number of workflow runs"
    local test_dir="$TEST_ROOT/m2_edge_large"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('PowerUser', 'advanced', 'terse');"

    # Insert 100 completed runs across 5 types
    for i in $(seq 1 40); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    done
    for i in $(seq 1 30); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('bugfix', 'completed');"
    done
    for i in $(seq 1 20); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('improve', 'completed');"
    done
    for i in $(seq 1 7); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('audit', 'completed');"
    done
    for i in $(seq 1 3); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new', 'completed');"
    done

    local output exit_code
    output=$(run_briefing "$test_dir")
    exit_code=$?

    assert_eq "0" "$exit_code" "briefing.sh exits 0 with 100 workflow runs"
    assert_contains "$output" "100 completed" "Shows 100 completed workflows"
}

echo ""

# ############################################################
# MODULE 3: CLAUDE.MD IDENTITY PROTOCOL TESTS
# ############################################################

echo "--- Module 3: CLAUDE.md Identity Protocol (Must) ---"
echo ""

# ============================================================
# Requirement: REQ-PERSONA-007 (Must)
# OMEGA Identity section in CLAUDE.md
# ============================================================

test_claudemd_identity_section_exists() {
    echo "[TEST] REQ-PERSONA-007: OMEGA Identity section exists in CLAUDE.md"
    local content
    content=$(cat "$CLAUDE_MD" 2>/dev/null)

    assert_contains "$content" "## OMEGA Identity" "CLAUDE.md has '## OMEGA Identity' section"
}

test_claudemd_override_hierarchy_present() {
    echo "[TEST] REQ-PERSONA-007: Override hierarchy is defined"
    local content
    content=$(cat "$CLAUDE_MD" 2>/dev/null)

    assert_contains "$content" "Override Hierarchy" "Override hierarchy section present"
    assert_contains "$content" "Protocol always overrides identity" "Override rule stated explicitly"
}

test_claudemd_experience_levels_defined() {
    echo "[TEST] REQ-PERSONA-007: Experience levels defined with behavior"
    local content
    content=$(cat "$CLAUDE_MD" 2>/dev/null)

    assert_contains "$content" "beginner" "beginner level defined"
    assert_contains "$content" "intermediate" "intermediate level defined"
    assert_contains "$content" "advanced" "advanced level defined"
}

test_claudemd_communication_styles_defined() {
    echo "[TEST] REQ-PERSONA-007: Communication styles defined with behavior"
    local content
    content=$(cat "$CLAUDE_MD" 2>/dev/null)

    assert_contains "$content" "verbose" "verbose style defined"
    assert_contains "$content" "balanced" "balanced style defined"
    assert_contains "$content" "terse" "terse style defined"
}

test_claudemd_carveouts_present() {
    echo "[TEST] REQ-PERSONA-007: Carve-outs listed"
    local content
    content=$(cat "$CLAUDE_MD" 2>/dev/null)

    assert_contains "$content" "Carve-outs" "Carve-outs section present"
    assert_contains "$content" "TDD enforcement" "TDD enforcement carve-out listed"
    assert_contains "$content" "read-only" "Read-only constraints carve-out listed"
    assert_contains "$content" "iteration limits" "Iteration limits carve-out listed"
    assert_contains "$content" "prerequisite gates" "Prerequisite gates carve-out listed"
}

test_claudemd_identity_section_under_40_lines() {
    echo "[TEST] REQ-PERSONA-007: OMEGA Identity section is under 40 lines"
    local content
    content=$(cat "$CLAUDE_MD" 2>/dev/null)

    # Extract lines between "## OMEGA Identity" and the next "## " heading
    local section_lines
    section_lines=$(echo "$content" | sed -n '/^## OMEGA Identity$/,/^## /{/^## OMEGA Identity$/d;/^## /d;p;}' | wc -l | tr -d ' ')

    if [ -n "$section_lines" ] && [ "$section_lines" -gt 0 ]; then
        assert_le "$section_lines" "40" "Identity section is $section_lines lines (max 40)"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: Could not extract OMEGA Identity section"
    fi
}

test_claudemd_identity_section_position() {
    echo "[TEST] REQ-PERSONA-007: OMEGA Identity section positioned correctly"
    local content
    content=$(cat "$CLAUDE_MD" 2>/dev/null)

    # Should be after "Error Handling" and before "Main Workflow"
    local identity_line main_workflow_line
    identity_line=$(echo "$content" | grep -n "## OMEGA Identity" | head -1 | cut -d: -f1)
    main_workflow_line=$(echo "$content" | grep -n "## Main Workflow" | head -1 | cut -d: -f1)

    if [ -n "$identity_line" ] && [ -n "$main_workflow_line" ]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        if [ "$identity_line" -lt "$main_workflow_line" ]; then
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo "  PASS: OMEGA Identity (line $identity_line) before Main Workflow (line $main_workflow_line)"
        else
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo "  FAIL: OMEGA Identity should be before Main Workflow"
            echo "    Identity at line $identity_line, Main Workflow at line $main_workflow_line"
        fi
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: Could not find one or both sections"
        [ -z "$identity_line" ] && echo "    Missing: ## OMEGA Identity"
        [ -z "$main_workflow_line" ] && echo "    Missing: ## Main Workflow"
    fi
}

test_claudemd_name_usage_guidance() {
    echo "[TEST] REQ-PERSONA-007: Name usage guidance present"
    local content
    content=$(cat "$CLAUDE_MD" 2>/dev/null)

    assert_contains "$content" "Name" "Name usage section present"
}

test_claudemd_no_identity_block_guidance() {
    echo "[TEST] REQ-PERSONA-007: Guidance for when no identity block exists"
    local content
    content=$(cat "$CLAUDE_MD" 2>/dev/null)

    assert_contains "$content" "No identity block" "Guidance for missing identity block"
}

echo ""

# ############################################################
# MODULE 4: ONBOARDING COMMAND TESTS
# ############################################################

echo "--- Module 4: Onboarding Command (Should) ---"
echo ""

# ============================================================
# Requirement: REQ-PERSONA-008 (Should)
# /omega:onboard command
# ============================================================

test_onboard_command_file_exists() {
    echo "[TEST] REQ-PERSONA-008: omega-onboard.md command file exists"
    assert_file_exists "$ONBOARD_CMD" "core/commands/omega-onboard.md exists"
}

test_onboard_command_has_purpose() {
    echo "[TEST] REQ-PERSONA-008: Command file has purpose section"
    if [ -f "$ONBOARD_CMD" ]; then
        local content
        content=$(cat "$ONBOARD_CMD" 2>/dev/null)
        assert_contains "$content" "Purpose" "Command has Purpose section"
    else
        skip_test "Command file does not exist yet"
    fi
}

test_onboard_command_has_three_questions() {
    echo "[TEST] REQ-PERSONA-008: Command describes 3 questions"
    if [ -f "$ONBOARD_CMD" ]; then
        local content
        content=$(cat "$ONBOARD_CMD" 2>/dev/null)
        assert_contains "$content" "name" "Command mentions name question"
        assert_contains "$content" "experience" "Command mentions experience question"
        assert_contains "$content" "communication" "Command mentions communication style question"
    else
        skip_test "Command file does not exist yet"
    fi
}

test_onboard_command_mentions_update_flag() {
    echo "[TEST] REQ-PERSONA-008: Command supports --update flag"
    if [ -f "$ONBOARD_CMD" ]; then
        local content
        content=$(cat "$ONBOARD_CMD" 2>/dev/null)
        assert_contains "$content" "--update" "Command documents --update flag"
    else
        skip_test "Command file does not exist yet"
    fi
}

test_onboard_command_creates_workflow_run() {
    echo "[TEST] REQ-PERSONA-008: Command creates workflow_run entry"
    if [ -f "$ONBOARD_CMD" ]; then
        local content
        content=$(cat "$ONBOARD_CMD" 2>/dev/null)
        assert_contains "$content" "workflow_runs" "Command references workflow_runs table"
        assert_contains "$content" "onboard" "Command uses 'onboard' type"
    else
        skip_test "Command file does not exist yet"
    fi
}

test_onboard_command_no_agent() {
    echo "[TEST] REQ-PERSONA-008: No dedicated onboarding agent created"
    local agent_file="$REAL_TOOLKIT_DIR/core/agents/onboard.md"
    local agent_file2="$REAL_TOOLKIT_DIR/core/agents/onboarding.md"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ ! -f "$agent_file" ] && [ ! -f "$agent_file2" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: No onboarding agent file (correct — stays at 14 agents)"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: Onboarding agent file should NOT exist"
    fi
}

test_onboard_command_mentions_manual_sql() {
    echo "[TEST] REQ-PERSONA-011: Onboard command documents manual SQL alternative"
    if [ -f "$ONBOARD_CMD" ]; then
        local content
        content=$(cat "$ONBOARD_CMD" 2>/dev/null)
        assert_contains "$content" "sqlite3" "Command documents manual sqlite3 alternative"
    else
        skip_test "Command file does not exist yet"
    fi
}

echo ""

# ############################################################
# INTEGRATION TESTS
# ############################################################

echo "--- Integration Tests ---"
echo ""

test_integration_schema_and_briefing_together() {
    echo "[TEST] Integration: Full flow — schema creates tables, briefing reads them"
    local test_dir="$TEST_ROOT/integration_full"
    create_briefing_test_env "$test_dir"
    local db="$test_dir/.claude/memory.db"

    # Simulate a real workflow: create profile, add workflows, run briefing
    sqlite3 "$db" "INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('Ivan', 'beginner', 'balanced');"
    for i in $(seq 1 12); do
        sqlite3 "$db" "INSERT INTO workflow_runs (type, status) VALUES ('new-feature', 'completed');"
    done

    local output
    output=$(run_briefing "$test_dir")

    # After briefing, the auto-upgrade should have fired (12 >= 10)
    local level
    level=$(sqlite3 "$db" "SELECT experience_level FROM user_profile LIMIT 1;" 2>/dev/null)

    assert_eq "intermediate" "$level" "Integration: beginner auto-upgraded to intermediate"
    assert_contains "$output" "OMEGA IDENTITY" "Integration: Identity block shown"
    assert_contains "$output" "Ivan" "Integration: User name in output"
    assert_contains "$output" "intermediate" "Integration: Upgraded level shown in output"
    assert_contains "$output" "12 completed" "Integration: Correct completed count in output"
}

test_integration_fresh_db_first_session() {
    echo "[TEST] Integration: First session with fresh DB (no profile)"
    local test_dir="$TEST_ROOT/integration_fresh"
    create_briefing_test_env "$test_dir"

    local output exit_code
    output=$(run_briefing "$test_dir")
    exit_code=$?

    assert_eq "0" "$exit_code" "First session completes without error"
    assert_contains "$output" "INSTITUTIONAL MEMORY BRIEFING" "Header still shows"
    assert_contains "$output" "DEBRIEF OBLIGATION" "Debrief still shows"
}

test_integration_pre_persona_db_unchanged() {
    echo "[TEST] Integration: Pre-persona DB produces identical output"
    local test_dir="$TEST_ROOT/integration_prepersona"
    mkdir -p "$test_dir/.claude/hooks"
    create_pre_persona_db "$test_dir/.claude/memory.db"
    local db="$test_dir/.claude/memory.db"

    # Drop persona tables to simulate truly old DB
    sqlite3 "$db" "DROP TABLE IF EXISTS user_profile;" 2>/dev/null
    sqlite3 "$db" "DROP TABLE IF EXISTS onboarding_state;" 2>/dev/null
    sqlite3 "$db" "DROP VIEW IF EXISTS v_workflow_usage;" 2>/dev/null

    local output exit_code
    output=$(run_briefing "$test_dir")
    exit_code=$?

    assert_eq "0" "$exit_code" "Pre-persona DB briefing exits 0"
    assert_not_contains "$output" "OMEGA IDENTITY" "No identity block"
    assert_not_contains "$output" "onboard" "No onboarding prompt (table missing)"
    assert_contains "$output" "INSTITUTIONAL MEMORY BRIEFING" "Header present"
    assert_contains "$output" "DEBRIEF OBLIGATION" "Debrief present"
}

echo ""

# ############################################################
# RUN ALL TESTS
# ############################################################

echo "--- Running Module 1: Schema Tests ---"
echo ""
test_schema_user_profile_table_exists
test_schema_user_profile_columns
test_schema_user_profile_experience_level_default
test_schema_user_profile_communication_style_default
test_schema_user_profile_check_experience_level_valid
test_schema_user_profile_check_experience_level_rejects_invalid
test_schema_user_profile_check_communication_style_valid
test_schema_user_profile_check_communication_style_rejects_invalid
test_schema_user_profile_created_at_default
test_schema_user_profile_last_seen_default
test_schema_user_profile_idempotent
test_schema_user_profile_null_name_allowed
echo ""
test_schema_onboarding_state_table_exists
test_schema_onboarding_state_columns
test_schema_onboarding_state_status_default
test_schema_onboarding_state_step_default
test_schema_onboarding_state_check_status_valid
test_schema_onboarding_state_check_status_rejects_invalid
test_schema_onboarding_state_data_stores_json
test_schema_onboarding_state_idempotent
echo ""
test_schema_view_exists
test_schema_view_returns_empty_on_fresh_db
test_schema_view_aggregates_by_type
test_schema_view_has_correct_columns
test_schema_view_ordered_by_completed_desc
test_schema_view_last_run_populated
test_schema_view_works_without_user_profile
test_schema_existing_tables_unaffected
echo ""

echo "--- Running Module 2: Briefing Hook Tests ---"
echo ""
test_briefing_identity_block_shown_with_profile
test_briefing_identity_block_format
test_briefing_identity_block_shows_usage_summary
test_briefing_identity_block_with_usage_breakdown
test_briefing_identity_block_zero_completed
test_briefing_identity_block_position_before_hotspots
test_briefing_identity_block_position_after_header
echo ""
test_briefing_no_error_without_user_profile_table
test_briefing_no_error_with_empty_user_profile
test_briefing_existing_sections_unchanged_without_profile
echo ""
test_briefing_auto_upgrade_beginner_to_intermediate
test_briefing_no_upgrade_beginner_at_9
test_briefing_auto_upgrade_intermediate_to_advanced
test_briefing_no_upgrade_intermediate_at_29
test_briefing_no_double_upgrade_beginner_to_advanced
test_briefing_advanced_stays_advanced
test_briefing_upgrade_noop_without_profile
test_briefing_upgrade_only_counts_completed
test_briefing_upgrade_reflected_in_identity_block
echo ""
test_briefing_last_seen_updated
test_briefing_last_seen_not_updated_without_profile
echo ""
test_briefing_onboarding_prompt_when_table_empty
test_briefing_onboarding_prompt_includes_manual_sql
test_briefing_onboarding_prompt_not_shown_when_table_missing
test_briefing_onboarding_prompt_not_shown_when_profile_exists
test_briefing_onboarding_prompt_nonblocking
echo ""
test_briefing_special_chars_in_user_name
test_briefing_null_user_name
test_briefing_no_db_file
test_briefing_readonly_db
test_briefing_multiple_profile_rows
test_briefing_large_workflow_count
echo ""

echo "--- Running Module 3: CLAUDE.md Tests ---"
echo ""
test_claudemd_identity_section_exists
test_claudemd_override_hierarchy_present
test_claudemd_experience_levels_defined
test_claudemd_communication_styles_defined
test_claudemd_carveouts_present
test_claudemd_identity_section_under_40_lines
test_claudemd_identity_section_position
test_claudemd_name_usage_guidance
test_claudemd_no_identity_block_guidance
echo ""

echo "--- Running Module 4: Onboarding Command Tests ---"
echo ""
test_onboard_command_file_exists
test_onboard_command_has_purpose
test_onboard_command_has_three_questions
test_onboard_command_mentions_update_flag
test_onboard_command_creates_workflow_run
test_onboard_command_no_agent
test_onboard_command_mentions_manual_sql
echo ""

echo "--- Running Integration Tests ---"
echo ""
test_integration_schema_and_briefing_together
test_integration_fresh_db_first_session
test_integration_pre_persona_db_unchanged
echo ""

# ============================================================
# RESULTS
# ============================================================
echo "============================================"
echo "  Results"
echo "============================================"
echo "  Total:   $TESTS_RUN"
echo "  Passed:  $TESTS_PASSED"
echo "  Failed:  $TESTS_FAILED"
echo "  Skipped: $TESTS_SKIPPED"
echo "============================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
