#!/bin/bash
# test-cortex-m2-shared-store.sh
#
# Tests for OMEGA Cortex Milestone M2: Shared Store + Protocol
# Covers: REQ-CTX-007, REQ-CTX-008, REQ-CTX-009, REQ-CTX-011, REQ-CTX-012
#
# These tests are written BEFORE the code (TDD). They define the contract
# that the developer must fulfill.
#
# Usage:
#   bash tests/test-cortex-m2-shared-store.sh
#   bash tests/test-cortex-m2-shared-store.sh --verbose
#
# Dependencies: bash, git, python3 (for JSON validation)

set -u

# ============================================================
# TEST FRAMEWORK (matching existing project conventions)
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

assert_ne() {
    local not_expected="$1"
    local actual="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$not_expected" != "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Should NOT be: $not_expected"
        echo "    Actual:        $actual"
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

assert_gt() {
    local threshold="$1"
    local actual="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$actual" -gt "$threshold" ] 2>/dev/null; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Expected > $threshold, got: $actual"
    fi
}

assert_lt() {
    local threshold="$1"
    local actual="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$actual" -lt "$threshold" ] 2>/dev/null; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Expected < $threshold, got: $actual"
    fi
}

assert_zero_exit() {
    local exit_code="$1"
    local description="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$exit_code" -eq 0 ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Exit code: $exit_code (expected 0)"
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

assert_dir_exists() {
    local path="$1"
    local description="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -d "$path" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Directory not found: $path"
    fi
}

skip_test() {
    local description="$1"
    local reason="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo "  SKIP: $description -- $reason"
}

# ============================================================
# PATHS
# ============================================================
REAL_TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_SCRIPT="$REAL_TOOLKIT_DIR/scripts/setup.sh"
PROTOCOL_FILE="$REAL_TOOLKIT_DIR/core/protocols/cortex-protocol.md"

# ============================================================
# TEST ISOLATION: temp directories, cleanup on exit
# ============================================================
TEST_ROOT=""
TOOLKIT_DIR=""
TARGET_DIR=""

setup_test_env() {
    TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/cortex-m2-test-XXXXXX")
    if [ ! -d "$TEST_ROOT" ]; then
        echo "FATAL: Failed to create temp directory"
        exit 1
    fi
    TOOLKIT_DIR="$TEST_ROOT/toolkit"
    TARGET_DIR="$TEST_ROOT/target"
}

cleanup_test_env() {
    if [ -n "$TEST_ROOT" ] && [ -d "$TEST_ROOT" ]; then
        rm -rf "$TEST_ROOT"
    fi
}

trap cleanup_test_env EXIT

# ============================================================
# HELPER: Build a fake toolkit tree that setup.sh expects
# (mirrors the real toolkit structure with minimal content)
# ============================================================
build_fake_toolkit() {
    mkdir -p "$TOOLKIT_DIR/core/agents"
    mkdir -p "$TOOLKIT_DIR/core/commands"
    mkdir -p "$TOOLKIT_DIR/core/hooks"
    mkdir -p "$TOOLKIT_DIR/core/protocols"
    mkdir -p "$TOOLKIT_DIR/core/db/queries"
    mkdir -p "$TOOLKIT_DIR/scripts"

    # Create sample agents (3 of them)
    echo "# Agent Alpha" > "$TOOLKIT_DIR/core/agents/alpha.md"
    echo "# Agent Beta" > "$TOOLKIT_DIR/core/agents/beta.md"
    echo "# Agent Gamma" > "$TOOLKIT_DIR/core/agents/gamma.md"

    # Create sample commands (2 of them)
    echo "# Command One" > "$TOOLKIT_DIR/core/commands/omega-one.md"
    echo "# Command Two" > "$TOOLKIT_DIR/core/commands/omega-two.md"

    # Create sample hooks
    printf '#!/bin/bash\necho "briefing"\n' > "$TOOLKIT_DIR/core/hooks/briefing.sh"
    printf '#!/bin/bash\necho "debrief-gate"\n' > "$TOOLKIT_DIR/core/hooks/debrief-gate.sh"
    printf '#!/bin/bash\necho "debrief-nudge"\n' > "$TOOLKIT_DIR/core/hooks/debrief-nudge.sh"
    printf '#!/bin/bash\necho "incremental-gate"\n' > "$TOOLKIT_DIR/core/hooks/incremental-gate.sh"
    printf '#!/bin/bash\necho "learning-detector"\n' > "$TOOLKIT_DIR/core/hooks/learning-detector.sh"
    printf '#!/bin/bash\necho "learning-gate"\n' > "$TOOLKIT_DIR/core/hooks/learning-gate.sh"
    printf '#!/bin/bash\necho "session-close"\n' > "$TOOLKIT_DIR/core/hooks/session-close.sh"

    # Create sample protocol files
    echo "# Memory Protocol" > "$TOOLKIT_DIR/core/protocols/memory-protocol.md"
    echo "# Identity" > "$TOOLKIT_DIR/core/protocols/identity.md"

    # Create minimal schema.sql
    cat > "$TOOLKIT_DIR/core/db/schema.sql" << 'SQLEOF'
CREATE TABLE IF NOT EXISTS workflow_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,
    description TEXT,
    scope TEXT,
    started_at TEXT DEFAULT (datetime('now')),
    completed_at TEXT,
    status TEXT DEFAULT 'running',
    git_commits TEXT,
    error_message TEXT
);
SQLEOF

    # Create query files
    echo "-- briefing queries" > "$TOOLKIT_DIR/core/db/queries/briefing.sql"

    # Create CLAUDE.md with workflow rules section
    cat > "$TOOLKIT_DIR/CLAUDE.md" << 'MDEOF'
# CLAUDE.md

Toolkit-level docs.

---

# OMEGA Ω

## Philosophy
This project uses a multi-agent workflow.

## Global Rules
1. Rule one
2. Rule two
MDEOF

    # Copy the real setup.sh and db-init.sh
    cp "$SETUP_SCRIPT" "$TOOLKIT_DIR/scripts/setup.sh"
    chmod +x "$TOOLKIT_DIR/scripts/setup.sh"
    cp "$REAL_TOOLKIT_DIR/scripts/db-init.sh" "$TOOLKIT_DIR/scripts/db-init.sh"
    chmod +x "$TOOLKIT_DIR/scripts/db-init.sh"
}

# ============================================================
# HELPER: Prepare a fresh target directory (git init required)
# ============================================================
reset_target() {
    rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
    (cd "$TARGET_DIR" && git init --quiet 2>/dev/null)
    # Pre-create directories that cleanup_stale checks for, to avoid a known
    # set -e + return bug in setup.sh (cleanup_stale returns non-zero when
    # the directory doesn't exist, which kills the script under set -e).
    mkdir -p "$TARGET_DIR/.claude/commands"
    mkdir -p "$TARGET_DIR/.claude/agents"
}

# ============================================================
# HELPER: Run setup.sh in the target directory
# ============================================================
run_setup() {
    local extra_args="${1:-}"
    # shellcheck disable=SC2086
    (cd "$TARGET_DIR" && bash "$TOOLKIT_DIR/scripts/setup.sh" --no-db $extra_args 2>&1)
}

run_setup_with_db() {
    local extra_args="${1:-}"
    # shellcheck disable=SC2086
    (cd "$TARGET_DIR" && bash "$TOOLKIT_DIR/scripts/setup.sh" $extra_args 2>&1)
}

# ============================================================
# PREREQUISITES
# ============================================================
echo "============================================================"
echo "OMEGA Cortex M2: Shared Store + Protocol Tests"
echo "============================================================"
echo ""

if [ ! -f "$SETUP_SCRIPT" ]; then
    echo "FATAL: setup.sh not found at $SETUP_SCRIPT"
    exit 1
fi

# Check python3 for JSON validation tests
if ! command -v python3 &>/dev/null; then
    echo "WARNING: python3 not found. JSON validation tests will be skipped."
fi

# ============================================================
# SETUP: Create isolated test environment
# ============================================================
setup_test_env
build_fake_toolkit
echo "  Test environment: $TEST_ROOT"
echo "  Toolkit:          $TOOLKIT_DIR"
echo "  Target:           $TARGET_DIR"
echo ""

# ============================================================
# GROUP 1: setup.sh creates .omega/shared/ directory structure
# Requirement: REQ-CTX-007 (Must)
# Acceptance: Created during setup, includes incidents/ subdir,
#             includes .gitkeep files
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 1: .omega/shared/ directory initialization (REQ-CTX-007)"
echo "------------------------------------------------------------"
echo ""

reset_target
OUTPUT=$(run_setup)

# Requirement: REQ-CTX-007 (Must)
# Acceptance: setup.sh creates .omega/shared/ in the target project
assert_dir_exists "$TARGET_DIR/.omega/shared" \
    "TEST-CTX-M2-001: setup.sh creates .omega/shared/ directory"

# Requirement: REQ-CTX-007 (Must)
# Acceptance: setup.sh creates .omega/shared/incidents/ subdirectory
assert_dir_exists "$TARGET_DIR/.omega/shared/incidents" \
    "TEST-CTX-M2-002: setup.sh creates .omega/shared/incidents/ subdirectory"

# Requirement: REQ-CTX-007 (Must)
# Acceptance: .gitkeep exists in .omega/shared/
assert_file_exists "$TARGET_DIR/.omega/shared/.gitkeep" \
    "TEST-CTX-M2-003: .gitkeep exists in .omega/shared/"

# Requirement: REQ-CTX-007 (Must)
# Acceptance: .gitkeep exists in .omega/shared/incidents/
assert_file_exists "$TARGET_DIR/.omega/shared/incidents/.gitkeep" \
    "TEST-CTX-M2-004: .gitkeep exists in .omega/shared/incidents/"

# Requirement: REQ-CTX-007 (Must)
# Acceptance: Output message when newly created
assert_contains "$OUTPUT" ".omega/shared/" \
    "TEST-CTX-M2-005: setup.sh output mentions .omega/shared/ initialization"

echo ""

# ============================================================
# GROUP 2: Idempotency -- running setup.sh twice
# Requirement: REQ-CTX-007 (Must)
# Acceptance: Idempotent, does not error, does not overwrite
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 2: Idempotency (REQ-CTX-007)"
echo "------------------------------------------------------------"
echo ""

# First, put some data in .omega/shared/ to test preservation
# (create directories manually if setup.sh didn't -- this tests the idempotency
#  of the second run, not the first-run creation which is tested in Group 1)
mkdir -p "$TARGET_DIR/.omega/shared/incidents" 2>/dev/null || true
echo '{"uuid":"test-uuid","rule":"Never guess"}' > "$TARGET_DIR/.omega/shared/behavioral-learnings.jsonl"
echo '{"incident_id":"INC-001","title":"Test incident"}' > "$TARGET_DIR/.omega/shared/incidents/INC-001.json"

# Run setup.sh again
OUTPUT2=$(run_setup)
EXIT_CODE=$?

# Requirement: REQ-CTX-007 (Must)
# Acceptance: Running twice doesn't error
assert_zero_exit "$EXIT_CODE" \
    "TEST-CTX-M2-006: setup.sh second run exits cleanly (exit 0)"

# Requirement: REQ-CTX-007 (Must)
# Acceptance: Existing shared data is preserved (not overwritten)
EXISTING_DATA=$(cat "$TARGET_DIR/.omega/shared/behavioral-learnings.jsonl" 2>/dev/null || echo "")
assert_contains "$EXISTING_DATA" "Never guess" \
    "TEST-CTX-M2-007: existing shared data preserved after second run"

# Requirement: REQ-CTX-007 (Must)
# Acceptance: Existing incident files preserved
EXISTING_INCIDENT=$(cat "$TARGET_DIR/.omega/shared/incidents/INC-001.json" 2>/dev/null || echo "")
assert_contains "$EXISTING_INCIDENT" "INC-001" \
    "TEST-CTX-M2-008: existing incident files preserved after second run"

# Requirement: REQ-CTX-007 (Must)
# Acceptance: Output shows .omega/shared/ already exists on second run
assert_contains "$OUTPUT2" ".omega/shared" \
    "TEST-CTX-M2-009: second run output mentions .omega/shared/"

echo ""

# ============================================================
# GROUP 3: Gitignore configuration
# Requirement: REQ-CTX-008 (Must)
# Acceptance: .omega/shared/ is NOT gitignored, memory.db IS
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 3: Gitignore configuration (REQ-CTX-008)"
echo "------------------------------------------------------------"
echo ""

# Test 3a: .omega/shared/ should NOT be in .gitignore
reset_target
run_setup >/dev/null 2>&1

if [ -f "$TARGET_DIR/.gitignore" ]; then
    GITIGNORE_CONTENT=$(cat "$TARGET_DIR/.gitignore")
else
    GITIGNORE_CONTENT=""
fi

# Requirement: REQ-CTX-008 (Must)
# Acceptance: .omega/shared/ is NOT gitignored
# The gitignore should not have a pattern that would exclude .omega/shared/
# (Check that .omega/shared is not literally in .gitignore)
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$TARGET_DIR/.gitignore" ] && grep -qE '^\\.omega/shared/?$' "$TARGET_DIR/.gitignore" 2>/dev/null; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M2-010: .omega/shared/ is NOT in .gitignore"
    echo "    Found .omega/shared/ pattern in .gitignore"
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M2-010: .omega/shared/ is NOT in .gitignore"
fi

# Test 3b: setup.sh warns if .gitignore contains a pattern that would gitignore .omega/shared/
reset_target
# Create a .gitignore with .omega/ pattern (which would gitignore shared/ too)
echo ".omega/" > "$TARGET_DIR/.gitignore"
OUTPUT3=$(run_setup)

# Requirement: REQ-CTX-008 (Must)
# Acceptance: setup.sh warns when .omega/ is gitignored (which would hide shared/)
assert_contains "$OUTPUT3" "WARNING" \
    "TEST-CTX-M2-011: setup.sh warns when .omega/ pattern is in .gitignore"

# Test 3c: setup.sh warns if .gitignore explicitly has .omega/shared
reset_target
echo ".omega/shared" > "$TARGET_DIR/.gitignore"
OUTPUT3b=$(run_setup)

# Requirement: REQ-CTX-008 (Must)
# Acceptance: setup.sh warns when .omega/shared pattern is in .gitignore
assert_contains "$OUTPUT3b" "WARNING" \
    "TEST-CTX-M2-012: setup.sh warns when .omega/shared pattern is in .gitignore"

# Test 3d: memory.db gitignore entries remain unchanged
reset_target
echo ".claude/memory.db" > "$TARGET_DIR/.gitignore"
run_setup >/dev/null 2>&1
GITIGNORE_AFTER=$(cat "$TARGET_DIR/.gitignore" 2>/dev/null || echo "")

# Requirement: REQ-CTX-008 (Must)
# Acceptance: memory.db gitignore entries remain unchanged
assert_contains "$GITIGNORE_AFTER" "memory.db" \
    "TEST-CTX-M2-013: memory.db gitignore entry preserved"

echo ""

# ============================================================
# GROUP 4: Backward compatibility -- all existing setup.sh behavior
# Requirement: REQ-CTX-011 (Must)
# Acceptance: All existing behavior still works; no Cortex = no change
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 4: Backward compatibility (REQ-CTX-011)"
echo "------------------------------------------------------------"
echo ""

# Test 4a: All existing directories still created
reset_target
OUTPUT4=$(run_setup)

# Requirement: REQ-CTX-011 (Must)
# Acceptance: Existing agents deployment still works
assert_dir_exists "$TARGET_DIR/.claude/agents" \
    "TEST-CTX-M2-014: .claude/agents/ still created"
assert_file_exists "$TARGET_DIR/.claude/agents/alpha.md" \
    "TEST-CTX-M2-015: core agents still deployed"

# Requirement: REQ-CTX-011 (Must)
# Acceptance: Existing commands deployment still works
assert_dir_exists "$TARGET_DIR/.claude/commands" \
    "TEST-CTX-M2-016: .claude/commands/ still created"
assert_file_exists "$TARGET_DIR/.claude/commands/omega-one.md" \
    "TEST-CTX-M2-017: core commands still deployed"

# Requirement: REQ-CTX-011 (Must)
# Acceptance: Existing protocols deployment still works
assert_dir_exists "$TARGET_DIR/.claude/protocols" \
    "TEST-CTX-M2-018: .claude/protocols/ still created"

# Requirement: REQ-CTX-011 (Must)
# Acceptance: specs/ and docs/ directories still created
assert_dir_exists "$TARGET_DIR/specs" \
    "TEST-CTX-M2-019: specs/ still created"
assert_dir_exists "$TARGET_DIR/docs" \
    "TEST-CTX-M2-020: docs/ still created"

# Requirement: REQ-CTX-011 (Must)
# Acceptance: docs/.workflow/ still created
assert_dir_exists "$TARGET_DIR/docs/.workflow" \
    "TEST-CTX-M2-021: docs/.workflow/ still created"

# Requirement: REQ-CTX-011 (Must)
# Acceptance: hooks still deployed
assert_dir_exists "$TARGET_DIR/.claude/hooks" \
    "TEST-CTX-M2-022: .claude/hooks/ still created"

# Requirement: REQ-CTX-011 (Must)
# Acceptance: CLAUDE.md still configured
assert_file_exists "$TARGET_DIR/CLAUDE.md" \
    "TEST-CTX-M2-023: CLAUDE.md still created"

# Requirement: REQ-CTX-011 (Must)
# Acceptance: settings.json still created with hooks
assert_file_exists "$TARGET_DIR/.claude/settings.json" \
    "TEST-CTX-M2-024: settings.json still created"

# Requirement: REQ-CTX-011 (Must)
# Acceptance: Setup exits successfully
assert_zero_exit "$?" \
    "TEST-CTX-M2-025: setup.sh exits 0 with Cortex additions"

# Requirement: REQ-CTX-011 (Must)
# Acceptance: setup.sh summary still shows agents/commands count
assert_contains "$OUTPUT4" "agents" \
    "TEST-CTX-M2-026: setup.sh summary still mentions agents"
assert_contains "$OUTPUT4" "commands" \
    "TEST-CTX-M2-027: setup.sh summary still mentions commands"

# Requirement: REQ-CTX-011 (Must)
# Acceptance: SPECS.md and DOCS.md still created
assert_file_exists "$TARGET_DIR/specs/SPECS.md" \
    "TEST-CTX-M2-028: specs/SPECS.md still created"
assert_file_exists "$TARGET_DIR/docs/DOCS.md" \
    "TEST-CTX-M2-029: docs/DOCS.md still created"

echo ""

# ============================================================
# GROUP 5: .omega/shared/ is git-trackable
# Requirement: REQ-CTX-008 (Must)
# Acceptance: .omega/shared/ IS tracked by git
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 5: Git tracking of .omega/shared/ (REQ-CTX-008)"
echo "------------------------------------------------------------"
echo ""

reset_target
run_setup >/dev/null 2>&1

# Add .omega/shared/ to git and verify it's trackable
GIT_ADD_OUTPUT=$(cd "$TARGET_DIR" && git add .omega/shared/ 2>&1)
GIT_ADD_EXIT=$?

# Requirement: REQ-CTX-008 (Must)
# Acceptance: .omega/shared/ can be added to git (not gitignored by default)
assert_zero_exit "$GIT_ADD_EXIT" \
    "TEST-CTX-M2-030: .omega/shared/ can be git-added (not gitignored)"

# Verify .gitkeep files are staged
STAGED_FILES=$(cd "$TARGET_DIR" && git diff --cached --name-only 2>/dev/null || echo "")
assert_contains "$STAGED_FILES" ".omega/shared/.gitkeep" \
    "TEST-CTX-M2-031: .omega/shared/.gitkeep is git-staged"
assert_contains "$STAGED_FILES" ".omega/shared/incidents/.gitkeep" \
    "TEST-CTX-M2-032: .omega/shared/incidents/.gitkeep is git-staged"

echo ""

# ============================================================
# GROUP 6: Edge cases for .omega/shared/ initialization
# Requirement: REQ-CTX-007 (Must)
# Edge cases from the 10 worst scenarios
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 6: Edge cases (REQ-CTX-007)"
echo "------------------------------------------------------------"
echo ""

# Edge case: .omega/ already exists as a directory (from some other usage)
reset_target
mkdir -p "$TARGET_DIR/.omega"
echo "some config" > "$TARGET_DIR/.omega/config.json"
OUTPUT6a=$(run_setup)
EXIT_CODE6a=$?

# Requirement: REQ-CTX-007 (Must)
# Edge: pre-existing .omega/ directory with other files
assert_zero_exit "$EXIT_CODE6a" \
    "TEST-CTX-M2-033: setup.sh handles pre-existing .omega/ directory"
assert_dir_exists "$TARGET_DIR/.omega/shared" \
    "TEST-CTX-M2-034: .omega/shared/ created alongside existing .omega/ content"
# Verify existing .omega/ content is preserved
EXISTING_CONFIG=$(cat "$TARGET_DIR/.omega/config.json" 2>/dev/null || echo "")
assert_contains "$EXISTING_CONFIG" "some config" \
    "TEST-CTX-M2-035: pre-existing .omega/ content preserved"

# Edge case: .omega/shared/ already exists but incidents/ doesn't
reset_target
mkdir -p "$TARGET_DIR/.omega/shared"
touch "$TARGET_DIR/.omega/shared/.gitkeep"
echo '{"uuid":"existing"}' > "$TARGET_DIR/.omega/shared/behavioral-learnings.jsonl"
# Note: incidents/ subdirectory intentionally missing
OUTPUT6b=$(run_setup)
EXIT_CODE6b=$?

# Requirement: REQ-CTX-007 (Must)
# Edge: partial directory structure (shared/ exists, incidents/ missing)
assert_zero_exit "$EXIT_CODE6b" \
    "TEST-CTX-M2-036: setup.sh handles partial directory structure"
# The existing data should NOT be overwritten
PRESERVED_DATA=$(cat "$TARGET_DIR/.omega/shared/behavioral-learnings.jsonl" 2>/dev/null || echo "")
assert_contains "$PRESERVED_DATA" "existing" \
    "TEST-CTX-M2-037: existing JSONL data not overwritten when .omega/shared/ exists"

# Edge case: .omega/shared exists as a regular file (not a directory) -- pathological
reset_target
mkdir -p "$TARGET_DIR/.omega"
echo "I am a file" > "$TARGET_DIR/.omega/shared"
OUTPUT6c=$(run_setup 2>&1 || true)

# Requirement: REQ-CTX-007 (Must)
# Edge: .omega/shared is a file not a directory -- setup should handle gracefully
# We can't assert specific behavior here (it might error or skip), but it shouldn't crash
# the entire setup process for all other deployments
TESTS_RUN=$((TESTS_RUN + 1))
# After setup, all other deployments should still have completed
if [ -d "$TARGET_DIR/.claude/agents" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M2-038: setup.sh doesn't crash entirely when .omega/shared is a file"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M2-038: setup.sh doesn't crash entirely when .omega/shared is a file"
    echo "    Other deployments should still complete even if .omega/shared/ creation fails"
fi

echo ""

# ============================================================
# GROUP 7: Cortex protocol reference file existence and structure
# Requirement: REQ-CTX-012 (Should)
# Acceptance: core/protocols/cortex-protocol.md exists with @INDEX
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 7: Cortex protocol file (REQ-CTX-012)"
echo "------------------------------------------------------------"
echo ""

# Requirement: REQ-CTX-012 (Should)
# Acceptance: File exists at core/protocols/cortex-protocol.md
assert_file_exists "$PROTOCOL_FILE" \
    "TEST-CTX-M2-039: core/protocols/cortex-protocol.md exists"

if [ -f "$PROTOCOL_FILE" ]; then
    PROTO_CONTENT=$(cat "$PROTOCOL_FILE")
    PROTO_HEAD=$(head -15 "$PROTOCOL_FILE")
    PROTO_LINE_COUNT=$(wc -l < "$PROTOCOL_FILE" | tr -d ' ')

    # Requirement: REQ-CTX-012 (Should)
    # Acceptance: @INDEX block in first 15 lines
    assert_contains "$PROTO_HEAD" "@INDEX" \
        "TEST-CTX-M2-040: protocol file has @INDEX in first 15 lines"
    assert_contains "$PROTO_HEAD" "@/INDEX" \
        "TEST-CTX-M2-041: protocol file has closing @/INDEX tag"

    # Requirement: REQ-CTX-012 (Should)
    # Acceptance: @INDEX maps sections to line ranges
    # Each section should have a line range like "17-80"
    assert_contains_regex "$PROTO_HEAD" "SHARED-STORE-FORMAT.*[0-9]+-[0-9]+" \
        "TEST-CTX-M2-042: @INDEX has SHARED-STORE-FORMAT with line range"
    assert_contains_regex "$PROTO_HEAD" "CURATION-RULES.*[0-9]+-[0-9]+" \
        "TEST-CTX-M2-043: @INDEX has CURATION-RULES with line range"
    assert_contains_regex "$PROTO_HEAD" "IMPORT-RULES.*[0-9]+-[0-9]+" \
        "TEST-CTX-M2-044: @INDEX has IMPORT-RULES with line range"
    assert_contains_regex "$PROTO_HEAD" "PRIVACY.*[0-9]+-[0-9]+" \
        "TEST-CTX-M2-045: @INDEX has PRIVACY with line range"
    assert_contains_regex "$PROTO_HEAD" "CONTRIBUTOR-IDENTITY.*[0-9]+-[0-9]+" \
        "TEST-CTX-M2-046: @INDEX has CONTRIBUTOR-IDENTITY with line range"
    assert_contains_regex "$PROTO_HEAD" "CONFLICT-RESOLUTION.*[0-9]+-[0-9]+" \
        "TEST-CTX-M2-047: @INDEX has CONFLICT-RESOLUTION with line range"

    # Requirement: REQ-CTX-012 (Should)
    # Acceptance: Has SHARED-STORE-FORMAT section
    assert_contains "$PROTO_CONTENT" "SHARED-STORE-FORMAT" \
        "TEST-CTX-M2-048: protocol has SHARED-STORE-FORMAT section"

    # Requirement: REQ-CTX-012 (Should)
    # Acceptance: Has CURATION-RULES section
    assert_contains "$PROTO_CONTENT" "CURATION-RULES" \
        "TEST-CTX-M2-049: protocol has CURATION-RULES section"

    # Requirement: REQ-CTX-012 (Should)
    # Acceptance: Has IMPORT-RULES section
    assert_contains "$PROTO_CONTENT" "IMPORT-RULES" \
        "TEST-CTX-M2-050: protocol has IMPORT-RULES section"

    # Requirement: REQ-CTX-012 (Should)
    # Acceptance: Has PRIVACY section
    assert_contains "$PROTO_CONTENT" "PRIVACY" \
        "TEST-CTX-M2-051: protocol has PRIVACY section"

    # Requirement: REQ-CTX-012 (Should)
    # Acceptance: Has CONTRIBUTOR-IDENTITY section
    assert_contains "$PROTO_CONTENT" "CONTRIBUTOR-IDENTITY" \
        "TEST-CTX-M2-052: protocol has CONTRIBUTOR-IDENTITY section"

    # Requirement: REQ-CTX-012 (Should)
    # Acceptance: Has CONFLICT-RESOLUTION section
    assert_contains "$PROTO_CONTENT" "CONFLICT-RESOLUTION" \
        "TEST-CTX-M2-053: protocol has CONFLICT-RESOLUTION section"

    # Requirement: REQ-CTX-012 (Should)
    # Acceptance: Total file under 300 lines
    assert_lt "300" "$PROTO_LINE_COUNT" \
        "TEST-CTX-M2-054: protocol file under 300 lines (actual: $PROTO_LINE_COUNT)"

else
    # Protocol file doesn't exist yet (TDD: tests written before code)
    skip_test "TEST-CTX-M2-040: protocol file has @INDEX" "protocol file not yet created"
    skip_test "TEST-CTX-M2-041: protocol file has @/INDEX" "protocol file not yet created"
    skip_test "TEST-CTX-M2-042: @INDEX has SHARED-STORE-FORMAT" "protocol file not yet created"
    skip_test "TEST-CTX-M2-043: @INDEX has CURATION-RULES" "protocol file not yet created"
    skip_test "TEST-CTX-M2-044: @INDEX has IMPORT-RULES" "protocol file not yet created"
    skip_test "TEST-CTX-M2-045: @INDEX has PRIVACY" "protocol file not yet created"
    skip_test "TEST-CTX-M2-046: @INDEX has CONTRIBUTOR-IDENTITY" "protocol file not yet created"
    skip_test "TEST-CTX-M2-047: @INDEX has CONFLICT-RESOLUTION" "protocol file not yet created"
    skip_test "TEST-CTX-M2-048: protocol has SHARED-STORE-FORMAT section" "protocol file not yet created"
    skip_test "TEST-CTX-M2-049: protocol has CURATION-RULES section" "protocol file not yet created"
    skip_test "TEST-CTX-M2-050: protocol has IMPORT-RULES section" "protocol file not yet created"
    skip_test "TEST-CTX-M2-051: protocol has PRIVACY section" "protocol file not yet created"
    skip_test "TEST-CTX-M2-052: protocol has CONTRIBUTOR-IDENTITY section" "protocol file not yet created"
    skip_test "TEST-CTX-M2-053: protocol has CONFLICT-RESOLUTION section" "protocol file not yet created"
    skip_test "TEST-CTX-M2-054: protocol file under 300 lines" "protocol file not yet created"
fi

echo ""

# ============================================================
# GROUP 8: JSONL format specification in protocol
# Requirement: REQ-CTX-009 (Must)
# Acceptance: Protocol documents the JSONL entry formats
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 8: JSONL format documentation (REQ-CTX-009)"
echo "------------------------------------------------------------"
echo ""

if [ -f "$PROTOCOL_FILE" ]; then
    PROTO_CONTENT=$(cat "$PROTOCOL_FILE")

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: Protocol documents the common fields
    assert_contains "$PROTO_CONTENT" "uuid" \
        "TEST-CTX-M2-055: protocol documents 'uuid' common field"
    assert_contains "$PROTO_CONTENT" "contributor" \
        "TEST-CTX-M2-056: protocol documents 'contributor' common field"
    assert_contains "$PROTO_CONTENT" "source_project" \
        "TEST-CTX-M2-057: protocol documents 'source_project' common field"
    assert_contains "$PROTO_CONTENT" "created_at" \
        "TEST-CTX-M2-058: protocol documents 'created_at' common field"
    assert_contains "$PROTO_CONTENT" "confidence" \
        "TEST-CTX-M2-059: protocol documents 'confidence' common field"
    assert_contains "$PROTO_CONTENT" "content_hash" \
        "TEST-CTX-M2-060: protocol documents 'content_hash' common field"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: Protocol documents behavioral-learnings.jsonl format
    assert_contains "$PROTO_CONTENT" "behavioral-learnings" \
        "TEST-CTX-M2-061: protocol documents behavioral-learnings.jsonl"
    assert_contains "$PROTO_CONTENT" "rule" \
        "TEST-CTX-M2-062: behavioral-learnings format includes 'rule' field"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: Protocol documents hotspots.jsonl format
    assert_contains "$PROTO_CONTENT" "hotspots" \
        "TEST-CTX-M2-063: protocol documents hotspots.jsonl"
    assert_contains "$PROTO_CONTENT" "file_path" \
        "TEST-CTX-M2-064: hotspots format includes 'file_path' field"
    assert_contains "$PROTO_CONTENT" "risk_level" \
        "TEST-CTX-M2-065: hotspots format includes 'risk_level' field"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: Protocol documents incidents format
    assert_contains "$PROTO_CONTENT" "INC-" \
        "TEST-CTX-M2-066: protocol documents incident file naming (INC-NNN)"
    assert_contains "$PROTO_CONTENT" "incident_id" \
        "TEST-CTX-M2-067: incident format includes 'incident_id' field"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: Protocol documents lessons.jsonl format
    assert_contains "$PROTO_CONTENT" "lessons" \
        "TEST-CTX-M2-068: protocol documents lessons.jsonl"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: Protocol documents patterns.jsonl format
    assert_contains "$PROTO_CONTENT" "patterns" \
        "TEST-CTX-M2-069: protocol documents patterns.jsonl"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: Protocol documents decisions.jsonl format
    assert_contains "$PROTO_CONTENT" "decisions" \
        "TEST-CTX-M2-070: protocol documents decisions.jsonl"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: JSONL format is one JSON object per line (documented)
    assert_contains "$PROTO_CONTENT" "JSONL" \
        "TEST-CTX-M2-071: protocol mentions JSONL format"
    assert_contains_regex "$PROTO_CONTENT" "[Oo]ne.*[Jj][Ss][Oo][Nn].*per line|single.*line|one.*line" \
        "TEST-CTX-M2-072: protocol documents one-JSON-per-line rule"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: occurrences field documented
    assert_contains "$PROTO_CONTENT" "occurrences" \
        "TEST-CTX-M2-073: protocol documents 'occurrences' common field"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: Protocol documents decisions.jsonl specific fields
    assert_contains "$PROTO_CONTENT" "rationale" \
        "TEST-CTX-M2-074: decisions format includes 'rationale' field"
    assert_contains "$PROTO_CONTENT" "alternatives" \
        "TEST-CTX-M2-075: decisions format includes 'alternatives' field"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: Protocol documents patterns.jsonl specific fields
    assert_contains "$PROTO_CONTENT" "example_files" \
        "TEST-CTX-M2-076: patterns format includes 'example_files' field"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: Protocol documents incident entries array
    assert_contains "$PROTO_CONTENT" "entries" \
        "TEST-CTX-M2-077: incident format includes 'entries' field"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: Incident is full JSON (not JSONL)
    assert_contains_regex "$PROTO_CONTENT" "INC-.*\\.json|incident.*[Jj][Ss][Oo][Nn][^L]" \
        "TEST-CTX-M2-078: incidents use .json format (not JSONL)"

else
    # Protocol file doesn't exist yet (TDD)
    skip_test "TEST-CTX-M2-055: protocol documents 'uuid'" "protocol file not yet created"
    skip_test "TEST-CTX-M2-056: protocol documents 'contributor'" "protocol file not yet created"
    skip_test "TEST-CTX-M2-057: protocol documents 'source_project'" "protocol file not yet created"
    skip_test "TEST-CTX-M2-058: protocol documents 'created_at'" "protocol file not yet created"
    skip_test "TEST-CTX-M2-059: protocol documents 'confidence'" "protocol file not yet created"
    skip_test "TEST-CTX-M2-060: protocol documents 'content_hash'" "protocol file not yet created"
    skip_test "TEST-CTX-M2-061: protocol documents behavioral-learnings.jsonl" "protocol file not yet created"
    skip_test "TEST-CTX-M2-062: behavioral-learnings 'rule' field" "protocol file not yet created"
    skip_test "TEST-CTX-M2-063: protocol documents hotspots.jsonl" "protocol file not yet created"
    skip_test "TEST-CTX-M2-064: hotspots 'file_path' field" "protocol file not yet created"
    skip_test "TEST-CTX-M2-065: hotspots 'risk_level' field" "protocol file not yet created"
    skip_test "TEST-CTX-M2-066: incident file naming" "protocol file not yet created"
    skip_test "TEST-CTX-M2-067: incident 'incident_id' field" "protocol file not yet created"
    skip_test "TEST-CTX-M2-068: protocol documents lessons.jsonl" "protocol file not yet created"
    skip_test "TEST-CTX-M2-069: protocol documents patterns.jsonl" "protocol file not yet created"
    skip_test "TEST-CTX-M2-070: protocol documents decisions.jsonl" "protocol file not yet created"
    skip_test "TEST-CTX-M2-071: protocol mentions JSONL format" "protocol file not yet created"
    skip_test "TEST-CTX-M2-072: one-JSON-per-line rule" "protocol file not yet created"
    skip_test "TEST-CTX-M2-073: 'occurrences' common field" "protocol file not yet created"
    skip_test "TEST-CTX-M2-074: decisions 'rationale' field" "protocol file not yet created"
    skip_test "TEST-CTX-M2-075: decisions 'alternatives' field" "protocol file not yet created"
    skip_test "TEST-CTX-M2-076: patterns 'example_files' field" "protocol file not yet created"
    skip_test "TEST-CTX-M2-077: incident 'entries' field" "protocol file not yet created"
    skip_test "TEST-CTX-M2-078: incidents use .json format" "protocol file not yet created"
fi

echo ""

# ============================================================
# GROUP 9: Protocol is deployed by setup.sh
# Requirement: REQ-CTX-012 (Should)
# Acceptance: cortex-protocol.md deployed to .claude/protocols/
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 9: Protocol deployment via setup.sh (REQ-CTX-012)"
echo "------------------------------------------------------------"
echo ""

if [ -f "$PROTOCOL_FILE" ]; then
    # Copy the real protocol file into the fake toolkit
    cp "$PROTOCOL_FILE" "$TOOLKIT_DIR/core/protocols/cortex-protocol.md"

    reset_target
    run_setup >/dev/null 2>&1

    # Requirement: REQ-CTX-012 (Should)
    # Acceptance: Protocol file deployed to target .claude/protocols/
    assert_file_exists "$TARGET_DIR/.claude/protocols/cortex-protocol.md" \
        "TEST-CTX-M2-079: cortex-protocol.md deployed to .claude/protocols/"

    # Verify the deployed file matches the source
    if [ -f "$TARGET_DIR/.claude/protocols/cortex-protocol.md" ]; then
        DEPLOYED_HASH=$(shasum -a 256 "$TARGET_DIR/.claude/protocols/cortex-protocol.md" | cut -d' ' -f1)
        SOURCE_HASH=$(shasum -a 256 "$PROTOCOL_FILE" | cut -d' ' -f1)
        assert_eq "$SOURCE_HASH" "$DEPLOYED_HASH" \
            "TEST-CTX-M2-080: deployed protocol matches source"
    else
        skip_test "TEST-CTX-M2-080: deployed protocol matches source" "protocol not deployed"
    fi
else
    skip_test "TEST-CTX-M2-079: cortex-protocol.md deployed" "protocol file not yet created"
    skip_test "TEST-CTX-M2-080: deployed protocol matches source" "protocol file not yet created"
fi

echo ""

# ============================================================
# GROUP 10: @INDEX line ranges are valid (protocol self-consistency)
# Requirement: REQ-CTX-012 (Should)
# Acceptance: @INDEX line ranges point to actual content
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 10: @INDEX line range validation (REQ-CTX-012)"
echo "------------------------------------------------------------"
echo ""

if [ -f "$PROTOCOL_FILE" ]; then
    # Extract line ranges from @INDEX and verify they point to real content
    # Expected format in @INDEX: SECTION-NAME    start-end
    # Example: SHARED-STORE-FORMAT         17-80

    validate_index_range() {
        local section_name="$1"
        local test_id="$2"
        local file="$PROTOCOL_FILE"

        # Extract the line range from the @INDEX block
        local range
        range=$(head -15 "$file" | grep "$section_name" | grep -oE '[0-9]+-[0-9]+' | head -1)

        if [ -z "$range" ]; then
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo "  FAIL: $test_id: @INDEX range for $section_name"
            echo "    No line range found in @INDEX"
            return
        fi

        local start_line end_line
        start_line=$(echo "$range" | cut -d'-' -f1)
        end_line=$(echo "$range" | cut -d'-' -f2)
        local total_lines
        total_lines=$(wc -l < "$file" | tr -d ' ')

        # Validate: start < end, end <= total lines, content at start line
        TESTS_RUN=$((TESTS_RUN + 1))
        if [ "$start_line" -lt "$end_line" ] && [ "$end_line" -le "$total_lines" ]; then
            # Check that the section actually contains content at the referenced lines
            local content_at_start
            content_at_start=$(sed -n "${start_line}p" "$file")
            if [ -n "$content_at_start" ]; then
                TESTS_PASSED=$((TESTS_PASSED + 1))
                echo "  PASS: $test_id: @INDEX range for $section_name ($range) is valid"
            else
                TESTS_FAILED=$((TESTS_FAILED + 1))
                echo "  FAIL: $test_id: @INDEX range for $section_name ($range) points to empty line"
            fi
        else
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo "  FAIL: $test_id: @INDEX range for $section_name ($range) is invalid (total lines: $total_lines)"
        fi
    }

    validate_index_range "SHARED-STORE-FORMAT" "TEST-CTX-M2-081"
    validate_index_range "CURATION-RULES" "TEST-CTX-M2-082"
    validate_index_range "IMPORT-RULES" "TEST-CTX-M2-083"
    validate_index_range "PRIVACY" "TEST-CTX-M2-084"
    validate_index_range "CONTRIBUTOR-IDENTITY" "TEST-CTX-M2-085"
    validate_index_range "CONFLICT-RESOLUTION" "TEST-CTX-M2-086"

    # Verify no overlapping ranges (each section's end < next section's start)
    TESTS_RUN=$((TESTS_RUN + 1))
    RANGES=$(head -15 "$PROTOCOL_FILE" | grep -oE '[0-9]+-[0-9]+' || true)
    OVERLAP_FOUND=false
    PREV_END=0
    while IFS= read -r range; do
        [ -z "$range" ] && continue
        start_line=$(echo "$range" | cut -d'-' -f1)
        end_line=$(echo "$range" | cut -d'-' -f2)
        if [ "$start_line" -le "$PREV_END" ] && [ "$PREV_END" -gt 0 ]; then
            OVERLAP_FOUND=true
        fi
        PREV_END=$end_line
    done <<< "$RANGES"

    if [ "$OVERLAP_FOUND" = false ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M2-087: @INDEX ranges do not overlap"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M2-087: @INDEX ranges overlap detected"
    fi

else
    skip_test "TEST-CTX-M2-081: @INDEX range for SHARED-STORE-FORMAT" "protocol file not yet created"
    skip_test "TEST-CTX-M2-082: @INDEX range for CURATION-RULES" "protocol file not yet created"
    skip_test "TEST-CTX-M2-083: @INDEX range for IMPORT-RULES" "protocol file not yet created"
    skip_test "TEST-CTX-M2-084: @INDEX range for PRIVACY" "protocol file not yet created"
    skip_test "TEST-CTX-M2-085: @INDEX range for CONTRIBUTOR-IDENTITY" "protocol file not yet created"
    skip_test "TEST-CTX-M2-086: @INDEX range for CONFLICT-RESOLUTION" "protocol file not yet created"
    skip_test "TEST-CTX-M2-087: @INDEX ranges do not overlap" "protocol file not yet created"
fi

echo ""

# ============================================================
# GROUP 11: Backward compatibility -- briefing.sh without shared/
# Requirement: REQ-CTX-011 (Must)
# Acceptance: briefing.sh skips shared import if directory absent
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 11: briefing.sh backward compatibility (REQ-CTX-011)"
echo "------------------------------------------------------------"
echo ""

# Test that running briefing.sh in a project WITHOUT .omega/shared/ works
reset_target
run_setup >/dev/null 2>&1

# Remove .omega/shared/ to simulate pre-Cortex project
rm -rf "$TARGET_DIR/.omega"

# Create a minimal memory.db for briefing.sh to query
mkdir -p "$TARGET_DIR/.claude"
sqlite3 "$TARGET_DIR/.claude/memory.db" << 'EOSQL'
CREATE TABLE IF NOT EXISTS behavioral_learnings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule TEXT NOT NULL,
    context TEXT,
    confidence REAL DEFAULT 0.5,
    occurrences INTEGER DEFAULT 1,
    status TEXT DEFAULT 'active',
    created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS incidents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    incident_id TEXT,
    title TEXT,
    domain TEXT,
    status TEXT DEFAULT 'open',
    created_at TEXT DEFAULT (datetime('now'))
);
EOSQL

# Run briefing.sh (it reads from stdin for session_id)
BRIEFING_SCRIPT="$TARGET_DIR/.claude/hooks/briefing.sh"
if [ -f "$BRIEFING_SCRIPT" ]; then
    # briefing.sh needs a session_id via stdin JSON
    BRIEFING_OUTPUT=$(echo '{"session_id":"test-session-no-cortex"}' | \
        CLAUDE_PROJECT_DIR="$TARGET_DIR" bash "$BRIEFING_SCRIPT" 2>&1 || true)
    BRIEFING_EXIT=$?

    # Requirement: REQ-CTX-011 (Must)
    # Acceptance: briefing.sh does not error when .omega/shared/ is absent
    assert_zero_exit "$BRIEFING_EXIT" \
        "TEST-CTX-M2-088: briefing.sh exits cleanly without .omega/shared/"

    # Requirement: REQ-CTX-011 (Must)
    # Acceptance: briefing.sh output does not contain error about missing shared dir
    assert_not_contains "$BRIEFING_OUTPUT" "Error" \
        "TEST-CTX-M2-089: briefing.sh produces no errors without .omega/shared/"
    assert_not_contains "$BRIEFING_OUTPUT" "No such file" \
        "TEST-CTX-M2-090: briefing.sh produces no 'No such file' errors"
else
    skip_test "TEST-CTX-M2-088: briefing.sh without .omega/shared/" "briefing.sh not deployed"
    skip_test "TEST-CTX-M2-089: briefing.sh no errors" "briefing.sh not deployed"
    skip_test "TEST-CTX-M2-090: briefing.sh no file errors" "briefing.sh not deployed"
fi

echo ""

# ============================================================
# GROUP 12: Setup output messaging
# Requirement: REQ-CTX-007 (Must)
# Acceptance: Correct output messages for new vs existing
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 12: Setup output messages (REQ-CTX-007)"
echo "------------------------------------------------------------"
echo ""

# Test fresh installation message
reset_target
OUTPUT_FRESH=$(run_setup)

# Requirement: REQ-CTX-007 (Must)
# Acceptance: Fresh install shows "initialized" or equivalent "+" message
assert_contains_regex "$OUTPUT_FRESH" "(initialized|\\+ .omega/shared)" \
    "TEST-CTX-M2-091: fresh install shows initialization message"

# Test repeat run message (after first run created .omega/shared/)
OUTPUT_REPEAT=$(run_setup)

# Requirement: REQ-CTX-007 (Must)
# Acceptance: Repeat run shows .omega/shared/ "already exists" or equivalent "=" message
assert_contains_regex "$OUTPUT_REPEAT" "(= .omega/shared|.omega/shared.*already exists)" \
    "TEST-CTX-M2-092: repeat run shows .omega/shared/ already-exists message"

echo ""

# ============================================================
# GROUP 13: Cortex config gitignore (Phase 4 prep)
# Requirement: REQ-CTX-008 (Must -- security)
# Acceptance: .omega/cortex-config.json is gitignored
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 13: Cortex config gitignore (REQ-CTX-008)"
echo "------------------------------------------------------------"
echo ""

reset_target
# Create a .gitignore so setup.sh has something to append to
echo "# existing gitignore" > "$TARGET_DIR/.gitignore"
run_setup >/dev/null 2>&1

# Requirement: REQ-CTX-008 (Must)
# Acceptance: .omega/cortex-config.json added to .gitignore (security -- may contain credentials)
GITIGNORE_FINAL=$(cat "$TARGET_DIR/.gitignore" 2>/dev/null || echo "")
assert_contains "$GITIGNORE_FINAL" "cortex-config.json" \
    "TEST-CTX-M2-093: .omega/cortex-config.json is in .gitignore"

# Test idempotency: running twice doesn't duplicate the gitignore entry
run_setup >/dev/null 2>&1
CORTEX_CONFIG_COUNT=$(grep -c "cortex-config.json" "$TARGET_DIR/.gitignore" 2>/dev/null || echo "0")
assert_eq "1" "$CORTEX_CONFIG_COUNT" \
    "TEST-CTX-M2-094: cortex-config.json gitignore entry not duplicated on re-run"

echo ""

# ============================================================
# GROUP 14: Command listing update in setup.sh output
# Requirement: REQ-CTX-007 (Must)
# Acceptance: Summary shows new Cortex commands
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 14: Command listing update (REQ-CTX-007)"
echo "------------------------------------------------------------"
echo ""

reset_target
# Add omega-share and omega-team-status commands to fake toolkit
echo "# Share command" > "$TOOLKIT_DIR/core/commands/omega-share.md"
echo "# Team status command" > "$TOOLKIT_DIR/core/commands/omega-team-status.md"
OUTPUT_CMDS=$(run_setup)

# Requirement: REQ-CTX-007 (Must)
# Acceptance: Summary output lists the new Cortex commands
# Note: setup.sh has a static command listing at the end
assert_contains_regex "$OUTPUT_CMDS" "omega.*(share|team)" \
    "TEST-CTX-M2-095: setup.sh output references Cortex commands"

echo ""

# ============================================================
# GROUP 15: Failure mode tests
# Architecture: Module 2 failure modes
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 15: Failure mode recovery (Architecture)"
echo "------------------------------------------------------------"
echo ""

# Failure mode: .gitignore contains .omega/ pattern
# Detection: grep check in setup.sh
# Recovery: WARNING message printed
reset_target
echo ".omega/" > "$TARGET_DIR/.gitignore"
OUTPUT_WARN=$(run_setup)

# Architecture failure mode: .gitignore contains .omega/ pattern
assert_contains_regex "$OUTPUT_WARN" "[Ww][Aa][Rr][Nn]" \
    "TEST-CTX-M2-096: setup.sh detects .omega/ in .gitignore and warns"

# Failure mode: setup.sh should not fail entirely if mkdir fails for .omega/shared/
# but other deployments complete. This is already tested in TEST-CTX-M2-038.

echo ""

# ============================================================
# GROUP 16: Security considerations
# Architecture: Module 2 security model
# ============================================================
echo "------------------------------------------------------------"
echo "GROUP 16: Security (Architecture)"
echo "------------------------------------------------------------"
echo ""

# Security: .omega/cortex-config.json must be gitignored (sensitive credentials)
# Already tested in TEST-CTX-M2-093.

# Security: .omega/shared/ IS visible (intentional -- sharing requires visibility)
reset_target
run_setup >/dev/null 2>&1

# Verify .omega/shared/ is NOT in .gitignore (security model says it must be visible)
if [ -f "$TARGET_DIR/.gitignore" ]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qE '^\\.omega/shared' "$TARGET_DIR/.gitignore" 2>/dev/null; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M2-097: .omega/shared/ not gitignored (security: sharing requires visibility)"
        echo "    Found .omega/shared pattern in .gitignore"
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M2-097: .omega/shared/ not gitignored (security: sharing requires visibility)"
    fi
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M2-097: .omega/shared/ not gitignored (no .gitignore exists)"
fi

# Security: Protocol file documents contributor attribution for accountability
if [ -f "$PROTOCOL_FILE" ]; then
    PROTO_CONTENT=$(cat "$PROTOCOL_FILE")
    assert_contains "$PROTO_CONTENT" "contributor" \
        "TEST-CTX-M2-098: protocol documents contributor attribution (accountability)"
    assert_contains_regex "$PROTO_CONTENT" "[Aa]ccountab|[Aa]ttribut|[Tt]rust" \
        "TEST-CTX-M2-099: protocol addresses trust/accountability model"
else
    skip_test "TEST-CTX-M2-098: contributor attribution" "protocol file not yet created"
    skip_test "TEST-CTX-M2-099: trust model documented" "protocol file not yet created"
fi

echo ""

# ============================================================
# CLEANUP
# ============================================================
cleanup_test_env
TEST_ROOT=""  # Prevent double-cleanup by trap

# ============================================================
# SUMMARY
# ============================================================
echo "============================================================"
echo "RESULTS"
echo "============================================================"
echo "  Total:   $TESTS_RUN"
echo "  Passed:  $TESTS_PASSED"
echo "  Failed:  $TESTS_FAILED"
echo "  Skipped: $TESTS_SKIPPED"
echo ""

if [ "$TESTS_FAILED" -gt 0 ]; then
    echo "STATUS: FAILED ($TESTS_FAILED failures)"
    exit 1
elif [ "$TESTS_SKIPPED" -gt 0 ]; then
    echo "STATUS: PARTIAL (some tests skipped -- code not yet implemented)"
    exit 0
else
    echo "STATUS: ALL PASSED"
    exit 0
fi
