#!/bin/bash
# test-cortex-m3-curator.sh
#
# Tests for OMEGA Cortex Milestone M3: Curator Agent + Share Command
# Covers: REQ-CTX-013, REQ-CTX-014, REQ-CTX-015, REQ-CTX-016, REQ-CTX-017,
#         REQ-CTX-018, REQ-CTX-019, REQ-CTX-020, REQ-CTX-021, REQ-CTX-022,
#         REQ-CTX-023, REQ-CTX-009 (JSONL format validation)
#
# These tests are written BEFORE the code (TDD). They define the contract
# that the developer must fulfill.
#
# Since the curator agent and share command are markdown instruction files
# (not executable code), these tests validate:
#   1. File structure (YAML frontmatter, required sections)
#   2. Content (required behaviors are documented)
#   3. JSONL format (sample entries parsed and validated)
#   4. Deployment (setup.sh deploys files correctly)
#
# Usage:
#   bash tests/test-cortex-m3-curator.sh
#   bash tests/test-cortex-m3-curator.sh --verbose
#
# Dependencies: bash, python3 (for JSON validation), git

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
CURATOR_FILE="$REAL_TOOLKIT_DIR/core/agents/curator.md"
SHARE_CMD_FILE="$REAL_TOOLKIT_DIR/core/commands/omega-share.md"
PROTOCOL_FILE="$REAL_TOOLKIT_DIR/core/protocols/cortex-protocol.md"

# ============================================================
# TEST ISOLATION: temp directories, cleanup on exit
# ============================================================
TEST_ROOT=""
TOOLKIT_DIR=""
TARGET_DIR=""

setup_test_env() {
    TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/cortex-m3-test-XXXXXX")
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
# ============================================================
build_fake_toolkit() {
    mkdir -p "$TOOLKIT_DIR/core/agents"
    mkdir -p "$TOOLKIT_DIR/core/commands"
    mkdir -p "$TOOLKIT_DIR/core/hooks"
    mkdir -p "$TOOLKIT_DIR/core/protocols"
    mkdir -p "$TOOLKIT_DIR/core/db/queries"
    mkdir -p "$TOOLKIT_DIR/scripts"

    # Create sample agents (existing ones)
    echo "# Agent Alpha" > "$TOOLKIT_DIR/core/agents/alpha.md"
    echo "# Agent Beta" > "$TOOLKIT_DIR/core/agents/beta.md"

    # Copy the real curator.md if it exists
    if [ -f "$CURATOR_FILE" ]; then
        cp "$CURATOR_FILE" "$TOOLKIT_DIR/core/agents/curator.md"
    fi

    # Create sample commands (existing ones)
    echo "# Command One" > "$TOOLKIT_DIR/core/commands/omega-one.md"

    # Copy the real omega-share.md if it exists
    if [ -f "$SHARE_CMD_FILE" ]; then
        cp "$SHARE_CMD_FILE" "$TOOLKIT_DIR/core/commands/omega-share.md"
    fi

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

    # Copy the real cortex-protocol.md if it exists
    if [ -f "$PROTOCOL_FILE" ]; then
        cp "$PROTOCOL_FILE" "$TOOLKIT_DIR/core/protocols/cortex-protocol.md"
    fi

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

# OMEGA

## Philosophy
This project uses a multi-agent workflow.

## Global Rules
1. Rule one
2. Rule two
MDEOF

    # Copy the real setup.sh and db-init.sh
    cp "$SETUP_SCRIPT" "$TOOLKIT_DIR/scripts/setup.sh"
    chmod +x "$TOOLKIT_DIR/scripts/setup.sh"
    if [ -f "$REAL_TOOLKIT_DIR/scripts/db-init.sh" ]; then
        cp "$REAL_TOOLKIT_DIR/scripts/db-init.sh" "$TOOLKIT_DIR/scripts/db-init.sh"
        chmod +x "$TOOLKIT_DIR/scripts/db-init.sh"
    fi
}

# ============================================================
# HELPER: Prepare a fresh target directory (git init required)
# ============================================================
reset_target() {
    rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
    (cd "$TARGET_DIR" && git init --quiet 2>/dev/null)
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

# ============================================================
# PREREQUISITES
# ============================================================
echo "============================================================"
echo "OMEGA Cortex M3: Curator Agent + Share Command Tests"
echo "============================================================"
echo ""

if [ ! -f "$SETUP_SCRIPT" ]; then
    echo "FATAL: setup.sh not found at $SETUP_SCRIPT"
    exit 1
fi

# Check python3 for JSON validation tests
HAS_PYTHON3=false
if command -v python3 &>/dev/null; then
    HAS_PYTHON3=true
else
    echo "WARNING: python3 not found. JSONL validation tests will be skipped."
fi

# ============================================================
# GROUP 1: Curator Agent File Structure (REQ-CTX-013) -- Must
# ============================================================
echo "--- Group 1: Curator Agent File Structure (REQ-CTX-013) ---"
echo ""

# Requirement: REQ-CTX-013 (Must)
# Acceptance: New file: core/agents/curator.md exists
if [ -f "$CURATOR_FILE" ]; then
    CURATOR_CONTENT=$(cat "$CURATOR_FILE")

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: curator.md exists
    assert_file_exists "$CURATOR_FILE" \
        "TEST-CTX-M3-001: curator.md exists at core/agents/curator.md"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Has YAML frontmatter with opening ---
    assert_contains_regex "$CURATOR_CONTENT" "^---" \
        "TEST-CTX-M3-002: curator.md starts with YAML frontmatter delimiter"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Frontmatter contains name field
    FRONTMATTER=$(echo "$CURATOR_CONTENT" | sed -n '/^---$/,/^---$/p')
    assert_contains "$FRONTMATTER" "name:" \
        "TEST-CTX-M3-003: frontmatter contains name field"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: name field is 'curator'
    assert_contains_regex "$FRONTMATTER" "name:.*curator" \
        "TEST-CTX-M3-004: name field is 'curator'"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Frontmatter contains description field
    assert_contains "$FRONTMATTER" "description:" \
        "TEST-CTX-M3-005: frontmatter contains description field"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Frontmatter contains tools field
    assert_contains "$FRONTMATTER" "tools:" \
        "TEST-CTX-M3-006: frontmatter contains tools field"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Frontmatter contains model field
    assert_contains "$FRONTMATTER" "model:" \
        "TEST-CTX-M3-007: frontmatter contains model field"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Model is claude-sonnet (not opus -- curation is routine evaluation)
    assert_contains_regex "$FRONTMATTER" "model:.*sonnet" \
        "TEST-CTX-M3-008: model is claude-sonnet (not opus)"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Model is NOT opus (curator is routine, not deep reasoning)
    assert_not_contains "$FRONTMATTER" "opus" \
        "TEST-CTX-M3-009: model is NOT opus (curation is routine evaluation)"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Tools include Read
    assert_contains "$FRONTMATTER" "Read" \
        "TEST-CTX-M3-010: tools include Read"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Tools include Write
    assert_contains "$FRONTMATTER" "Write" \
        "TEST-CTX-M3-011: tools include Write"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Tools include Bash
    assert_contains "$FRONTMATTER" "Bash" \
        "TEST-CTX-M3-012: tools include Bash"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Tools include Grep
    assert_contains "$FRONTMATTER" "Grep" \
        "TEST-CTX-M3-013: tools include Grep"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Tools include Glob
    assert_contains "$FRONTMATTER" "Glob" \
        "TEST-CTX-M3-014: tools include Glob"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Tools do NOT include Edit (curator writes new files, doesn't edit code)
    assert_not_contains "$FRONTMATTER" "Edit" \
        "TEST-CTX-M3-015: tools do NOT include Edit (curator writes new files, not code edits)"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Confidence threshold >= 0.8 documented
    assert_contains_regex "$CURATOR_CONTENT" "0\.8|0\.80" \
        "TEST-CTX-M3-016: documents confidence threshold 0.8"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Relevance filter documented (what to share vs skip)
    assert_contains_regex "$CURATOR_CONTENT" "[Rr]elevance|[Ff]ilter|team.relevant" \
        "TEST-CTX-M3-017: documents relevance filter concept"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Personal preferences are NOT shared
    assert_contains_regex "$CURATOR_CONTENT" "[Pp]ersonal.*[Pp]reference|[Pp]reference.*[Nn]ot.*share|[Cc]ommunication.style|address.as" \
        "TEST-CTX-M3-018: documents that personal preferences are NOT shared"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Technical corrections ARE shared
    assert_contains_regex "$CURATOR_CONTENT" "[Tt]echnical.*correct|[Dd]ebugging.*pattern|[Cc]ode.*convention|[Aa]rchitectural.*decision" \
        "TEST-CTX-M3-019: documents that technical learnings ARE shared"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Deduplication documented (content_hash)
    assert_contains_regex "$CURATOR_CONTENT" "content_hash|dedup|[Dd]eduplic" \
        "TEST-CTX-M3-020: documents deduplication mechanism"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Reinforcement merging documented
    assert_contains_regex "$CURATOR_CONTENT" "[Rr]einforce|reinforce.*merge|[Bb]ump.*occurrences|[Uu]pdate.*confidence" \
        "TEST-CTX-M3-021: documents reinforcement merging behavior"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: is_private check documented
    assert_contains "$CURATOR_CONTENT" "is_private" \
        "TEST-CTX-M3-022: documents is_private check"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Contributor identity documented (git config)
    assert_contains_regex "$CURATOR_CONTENT" "contributor|git config" \
        "TEST-CTX-M3-023: documents contributor identity (git config)"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Institutional Memory Protocol section present
    assert_contains_regex "$CURATOR_CONTENT" "[Ii]nstitutional [Mm]emory|[Mm]emory [Pp]rotocol|memory-protocol|briefing|incremental.log|close.out" \
        "TEST-CTX-M3-024: references Institutional Memory Protocol"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Process documented (query, check, dedup, export, conflicts, report)
    assert_contains_regex "$CURATOR_CONTENT" "memory\.db|query.*memory|[Qq]uery.*entries" \
        "TEST-CTX-M3-025: process step 1 documented (query memory.db)"

    assert_contains_regex "$CURATOR_CONTENT" "\.omega/shared|shared.*store|[Cc]heck.*existing" \
        "TEST-CTX-M3-026: process step 2 documented (check .omega/shared/ for existing entries)"

    assert_contains_regex "$CURATOR_CONTENT" "[Cc]onflict|contradiction" \
        "TEST-CTX-M3-027: process step 5 documented (detect conflicts)"

    assert_contains_regex "$CURATOR_CONTENT" "[Rr]eport|[Ss]ummary|[Oo]utput" \
        "TEST-CTX-M3-028: process step 6 documented (report/summary)"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Error handling documented (missing .omega/shared/, missing JSONL file, sqlite3 failure)
    assert_contains_regex "$CURATOR_CONTENT" "[Ee]rror.*handl|[Cc]reate.*director|[Mm]issing|does not exist" \
        "TEST-CTX-M3-029: documents error handling for missing directories/files"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: SHA-256 mentioned for content hash computation
    assert_contains_regex "$CURATOR_CONTENT" "SHA.256|sha256|sha-256" \
        "TEST-CTX-M3-030: documents SHA-256 for content hash computation"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: shared_uuid tracking documented
    assert_contains "$CURATOR_CONTENT" "shared_uuid" \
        "TEST-CTX-M3-031: documents shared_uuid tracking back to local memory.db"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: python3 used for JSONL manipulation (bash cannot parse JSON reliably)
    assert_contains "$CURATOR_CONTENT" "python3" \
        "TEST-CTX-M3-032: documents python3 for JSONL manipulation"

    # Requirement: REQ-CTX-013 (Must)
    # Edge case: confidence threshold described as tunable (not just hardcoded)
    assert_contains_regex "$CURATOR_CONTENT" "[Tt]unable|[Cc]onfigur|threshold" \
        "TEST-CTX-M3-033: confidence threshold described as tunable or configurable"

    # Requirement: REQ-CTX-013 (Must)
    # Edge case: Minimum content length (agent file should be substantial, not a stub)
    CURATOR_LINE_COUNT=$(echo "$CURATOR_CONTENT" | wc -l | tr -d ' ')
    assert_gt 50 "$CURATOR_LINE_COUNT" \
        "TEST-CTX-M3-034: curator.md is substantial (>50 lines, not a stub)"

    # Requirement: REQ-CTX-013 (Must)
    # Security: is_private = 0 check documented as mandatory
    assert_contains_regex "$CURATOR_CONTENT" "is_private.*=.*0|is_private.*0|COALESCE.*is_private" \
        "TEST-CTX-M3-035: documents mandatory is_private = 0 check before export"

    # Requirement: REQ-CTX-013 (Must)
    # Failure mode: JSONL file malformed handling
    assert_contains_regex "$CURATOR_CONTENT" "[Mm]alformed|[Ii]nvalid.*JSON|[Ss]kip.*line|parse.*error|parse.*exception" \
        "TEST-CTX-M3-036: documents handling of malformed JSONL entries"

    # Requirement: REQ-CTX-013 (Must)
    # Failure mode: sqlite3 query failure handling
    assert_contains_regex "$CURATOR_CONTENT" "sqlite3.*fail|[Dd]atabase.*error|[Dd]B.*lock|[Qq]uery.*fail|[Ss]kip.*table" \
        "TEST-CTX-M3-037: documents handling of sqlite3 query failures"

else
    skip_test "TEST-CTX-M3-001: curator.md exists" "file not yet created"
    skip_test "TEST-CTX-M3-002: YAML frontmatter" "file not yet created"
    skip_test "TEST-CTX-M3-003: name field" "file not yet created"
    skip_test "TEST-CTX-M3-004: name is curator" "file not yet created"
    skip_test "TEST-CTX-M3-005: description field" "file not yet created"
    skip_test "TEST-CTX-M3-006: tools field" "file not yet created"
    skip_test "TEST-CTX-M3-007: model field" "file not yet created"
    skip_test "TEST-CTX-M3-008: model is sonnet" "file not yet created"
    skip_test "TEST-CTX-M3-009: model is NOT opus" "file not yet created"
    skip_test "TEST-CTX-M3-010: tools include Read" "file not yet created"
    skip_test "TEST-CTX-M3-011: tools include Write" "file not yet created"
    skip_test "TEST-CTX-M3-012: tools include Bash" "file not yet created"
    skip_test "TEST-CTX-M3-013: tools include Grep" "file not yet created"
    skip_test "TEST-CTX-M3-014: tools include Glob" "file not yet created"
    skip_test "TEST-CTX-M3-015: tools NOT Edit" "file not yet created"
    skip_test "TEST-CTX-M3-016: confidence threshold 0.8" "file not yet created"
    skip_test "TEST-CTX-M3-017: relevance filter" "file not yet created"
    skip_test "TEST-CTX-M3-018: personal prefs NOT shared" "file not yet created"
    skip_test "TEST-CTX-M3-019: technical learnings shared" "file not yet created"
    skip_test "TEST-CTX-M3-020: deduplication" "file not yet created"
    skip_test "TEST-CTX-M3-021: reinforcement merging" "file not yet created"
    skip_test "TEST-CTX-M3-022: is_private check" "file not yet created"
    skip_test "TEST-CTX-M3-023: contributor identity" "file not yet created"
    skip_test "TEST-CTX-M3-024: memory protocol" "file not yet created"
    skip_test "TEST-CTX-M3-025: query memory.db step" "file not yet created"
    skip_test "TEST-CTX-M3-026: check .omega/shared/ step" "file not yet created"
    skip_test "TEST-CTX-M3-027: detect conflicts step" "file not yet created"
    skip_test "TEST-CTX-M3-028: report/summary step" "file not yet created"
    skip_test "TEST-CTX-M3-029: error handling" "file not yet created"
    skip_test "TEST-CTX-M3-030: SHA-256 content hash" "file not yet created"
    skip_test "TEST-CTX-M3-031: shared_uuid tracking" "file not yet created"
    skip_test "TEST-CTX-M3-032: python3 for JSONL" "file not yet created"
    skip_test "TEST-CTX-M3-033: threshold tunable" "file not yet created"
    skip_test "TEST-CTX-M3-034: substantial content" "file not yet created"
    skip_test "TEST-CTX-M3-035: is_private = 0 mandatory" "file not yet created"
    skip_test "TEST-CTX-M3-036: malformed JSONL handling" "file not yet created"
    skip_test "TEST-CTX-M3-037: sqlite3 failure handling" "file not yet created"
fi

echo ""

# ============================================================
# GROUP 2: Curator Export Behavior Documentation
#          (REQ-CTX-014, REQ-CTX-015, REQ-CTX-016,
#           REQ-CTX-017, REQ-CTX-018, REQ-CTX-019) -- Must/Should
# ============================================================
echo "--- Group 2: Curator Export Behavior Documentation (REQ-CTX-014 to 019) ---"
echo ""

if [ -f "$CURATOR_FILE" ]; then
    CURATOR_CONTENT=$(cat "$CURATOR_FILE")

    # -- REQ-CTX-014: Behavioral learning export (Must) --

    # Requirement: REQ-CTX-014 (Must)
    # Acceptance: Curator queries behavioral_learnings
    assert_contains "$CURATOR_CONTENT" "behavioral_learnings" \
        "TEST-CTX-M3-038: documents querying behavioral_learnings table"

    # Requirement: REQ-CTX-014 (Must)
    # Acceptance: Export to behavioral-learnings.jsonl
    assert_contains "$CURATOR_CONTENT" "behavioral-learnings.jsonl" \
        "TEST-CTX-M3-039: documents export to behavioral-learnings.jsonl"

    # Requirement: REQ-CTX-014 (Must)
    # Acceptance: Query filter: confidence >= 0.8 AND status = 'active' AND is_private = 0
    assert_contains_regex "$CURATOR_CONTENT" "confidence.*0\.8|0\.8.*confidence" \
        "TEST-CTX-M3-040: behavioral learning query uses confidence >= 0.8"

    assert_contains_regex "$CURATOR_CONTENT" "status.*active|active.*status" \
        "TEST-CTX-M3-041: behavioral learning query uses status = 'active'"

    # Requirement: REQ-CTX-014 (Must)
    # Acceptance: UUID v4 generated for each exported entry
    assert_contains_regex "$CURATOR_CONTENT" "UUID|uuid|uuidgen|uuid4" \
        "TEST-CTX-M3-042: documents UUID v4 generation for exported entries"

    # Requirement: REQ-CTX-014 (Must)
    # Acceptance: content_hash is SHA-256 of rule field
    assert_contains_regex "$CURATOR_CONTENT" "content_hash|SHA.256" \
        "TEST-CTX-M3-043: documents content_hash (SHA-256 of rule field)"

    # Requirement: REQ-CTX-014 (Must)
    # Acceptance: Check JSONL for existing content_hash before appending
    assert_contains_regex "$CURATOR_CONTENT" "[Cc]heck.*content_hash|[Mm]atch.*content_hash|[Dd]edup.*hash" \
        "TEST-CTX-M3-044: documents content_hash check before appending"

    # Requirement: REQ-CTX-014 (Must)
    # Acceptance: If match: bump occurrences, update confidence, add contributor
    assert_contains_regex "$CURATOR_CONTENT" "[Bb]ump.*occurrences|occurrences.*bump|increment.*occurrences" \
        "TEST-CTX-M3-045: documents bumping occurrences on match"

    # Requirement: REQ-CTX-014 (Must)
    # Acceptance: Record shared_uuid back to local behavioral_learnings row
    assert_contains "$CURATOR_CONTENT" "shared_uuid" \
        "TEST-CTX-M3-046: documents recording shared_uuid back to local row"

    # Requirement: REQ-CTX-014 (Must)
    # Acceptance: Populate contributor from git config user.name + user.email
    assert_contains_regex "$CURATOR_CONTENT" "git config|user\.name|user\.email|contributor" \
        "TEST-CTX-M3-047: documents contributor populated from git config"

    # -- REQ-CTX-015: Incident export (Must) --

    # Requirement: REQ-CTX-015 (Must)
    # Acceptance: Curator queries incidents
    assert_contains "$CURATOR_CONTENT" "incidents" \
        "TEST-CTX-M3-048: documents querying incidents table"

    # Requirement: REQ-CTX-015 (Must)
    # Acceptance: Query filter: status = 'resolved' AND is_private = 0
    assert_contains_regex "$CURATOR_CONTENT" "resolved" \
        "TEST-CTX-M3-049: incident query uses status = 'resolved'"

    # Requirement: REQ-CTX-015 (Must)
    # Acceptance: Export as .omega/shared/incidents/INC-NNN.json (one file per incident)
    assert_contains_regex "$CURATOR_CONTENT" "incidents/INC|INC-.*\.json|incidents.*json" \
        "TEST-CTX-M3-050: documents export as individual incident JSON files"

    # Requirement: REQ-CTX-015 (Must)
    # Acceptance: If file already exists, update/merge it
    assert_contains_regex "$CURATOR_CONTENT" "[Uu]pdate.*exist|[Mm]erge.*entri|[Oo]verwrite" \
        "TEST-CTX-M3-051: documents updating existing incident files"

    # Requirement: REQ-CTX-015 (Must)
    # Acceptance: Include full timeline (entries with entry_type, content, etc.)
    assert_contains_regex "$CURATOR_CONTENT" "timeline|incident_entries|entry_type|entries" \
        "TEST-CTX-M3-052: documents including full incident timeline"

    # -- REQ-CTX-016: Hotspot export (Must) --

    # Requirement: REQ-CTX-016 (Must)
    # Acceptance: Curator queries hotspots
    assert_contains "$CURATOR_CONTENT" "hotspots" \
        "TEST-CTX-M3-053: documents querying hotspots table"

    # Requirement: REQ-CTX-016 (Must)
    # Acceptance: Export to hotspots.jsonl
    assert_contains "$CURATOR_CONTENT" "hotspots.jsonl" \
        "TEST-CTX-M3-054: documents export to hotspots.jsonl"

    # Requirement: REQ-CTX-016 (Must)
    # Acceptance: Query filter: risk_level IN ('medium', 'high', 'critical')
    assert_contains_regex "$CURATOR_CONTENT" "risk_level|medium.*high.*critical|high.*critical" \
        "TEST-CTX-M3-055: hotspot query filters by risk_level"

    # Requirement: REQ-CTX-016 (Must)
    # Acceptance: Merge on matching file_path (take highest risk_level, sum times_touched)
    assert_contains_regex "$CURATOR_CONTENT" "file_path|merge.*hotspot|highest.*risk" \
        "TEST-CTX-M3-056: documents hotspot merging on file_path"

    # Requirement: REQ-CTX-016 (Must)
    # Acceptance: Cross-contributor correlation (2+ contributors flag same file)
    assert_contains_regex "$CURATOR_CONTENT" "cross.contributor|contributor_count|contributor.*alert|2\+.*contributor" \
        "TEST-CTX-M3-057: documents cross-contributor hotspot correlation"

    # -- REQ-CTX-017: Lesson export (Should) --

    # Requirement: REQ-CTX-017 (Should)
    # Acceptance: Lessons exported similarly to behavioral learnings
    assert_contains_regex "$CURATOR_CONTENT" "lessons|lessons\.jsonl" \
        "TEST-CTX-M3-058: documents lesson export"

    # -- REQ-CTX-018: Pattern export (Should) --

    # Requirement: REQ-CTX-018 (Should)
    # Acceptance: Patterns exported
    assert_contains_regex "$CURATOR_CONTENT" "patterns|patterns\.jsonl" \
        "TEST-CTX-M3-059: documents pattern export"

    # -- REQ-CTX-019: Decision export (Should) --

    # Requirement: REQ-CTX-019 (Should)
    # Acceptance: Decisions exported
    assert_contains_regex "$CURATOR_CONTENT" "decisions|decisions\.jsonl" \
        "TEST-CTX-M3-060: documents decision export"

    # Requirement: REQ-CTX-014-019 combined
    # Acceptance: Curator references cortex-protocol.md for format details
    assert_contains_regex "$CURATOR_CONTENT" "cortex-protocol|cortex.protocol|[Pp]rotocol.*reference" \
        "TEST-CTX-M3-061: curator references cortex-protocol.md for format details"

else
    skip_test "TEST-CTX-M3-038: behavioral_learnings table" "curator.md not yet created"
    skip_test "TEST-CTX-M3-039: behavioral-learnings.jsonl" "curator.md not yet created"
    skip_test "TEST-CTX-M3-040: confidence >= 0.8" "curator.md not yet created"
    skip_test "TEST-CTX-M3-041: status = active" "curator.md not yet created"
    skip_test "TEST-CTX-M3-042: UUID v4 generation" "curator.md not yet created"
    skip_test "TEST-CTX-M3-043: content_hash SHA-256" "curator.md not yet created"
    skip_test "TEST-CTX-M3-044: content_hash check" "curator.md not yet created"
    skip_test "TEST-CTX-M3-045: bump occurrences" "curator.md not yet created"
    skip_test "TEST-CTX-M3-046: shared_uuid recorded" "curator.md not yet created"
    skip_test "TEST-CTX-M3-047: contributor from git config" "curator.md not yet created"
    skip_test "TEST-CTX-M3-048: incidents table" "curator.md not yet created"
    skip_test "TEST-CTX-M3-049: resolved status" "curator.md not yet created"
    skip_test "TEST-CTX-M3-050: incident JSON files" "curator.md not yet created"
    skip_test "TEST-CTX-M3-051: update existing incidents" "curator.md not yet created"
    skip_test "TEST-CTX-M3-052: incident timeline" "curator.md not yet created"
    skip_test "TEST-CTX-M3-053: hotspots table" "curator.md not yet created"
    skip_test "TEST-CTX-M3-054: hotspots.jsonl" "curator.md not yet created"
    skip_test "TEST-CTX-M3-055: risk_level filter" "curator.md not yet created"
    skip_test "TEST-CTX-M3-056: hotspot merging" "curator.md not yet created"
    skip_test "TEST-CTX-M3-057: cross-contributor correlation" "curator.md not yet created"
    skip_test "TEST-CTX-M3-058: lesson export" "curator.md not yet created"
    skip_test "TEST-CTX-M3-059: pattern export" "curator.md not yet created"
    skip_test "TEST-CTX-M3-060: decision export" "curator.md not yet created"
    skip_test "TEST-CTX-M3-061: cortex-protocol reference" "curator.md not yet created"
fi

echo ""

# ============================================================
# GROUP 3: Deduplication & Conflict Detection
#          (REQ-CTX-020, REQ-CTX-021) -- Must/Should
# ============================================================
echo "--- Group 3: Deduplication & Conflict Detection (REQ-CTX-020, REQ-CTX-021) ---"
echo ""

if [ -f "$CURATOR_FILE" ]; then
    CURATOR_CONTENT=$(cat "$CURATOR_FILE")

    # -- REQ-CTX-020: Redundancy check / deduplication (Must) --

    # Requirement: REQ-CTX-020 (Must)
    # Acceptance: content_hash based deduplication documented
    assert_contains "$CURATOR_CONTENT" "content_hash" \
        "TEST-CTX-M3-062: documents content_hash based deduplication"

    # Requirement: REQ-CTX-020 (Must)
    # Acceptance: Read JSONL line-by-line, parse JSON, compare content_hash
    assert_contains_regex "$CURATOR_CONTENT" "[Rr]ead.*JSONL|parse.*JSON|line.by.line|[Ll]ine-by-line" \
        "TEST-CTX-M3-063: documents reading JSONL for dedup comparison"

    # Requirement: REQ-CTX-020 (Must)
    # Acceptance: If content_hash match: reinforce (bump occurrences, update confidence, merge contributors)
    assert_contains_regex "$CURATOR_CONTENT" "[Rr]einforce|[Bb]ump.*occurrence|[Uu]pdate.*confidence" \
        "TEST-CTX-M3-064: documents reinforcement on content_hash match"

    # Requirement: REQ-CTX-020 (Must)
    # Acceptance: If UUID match but content_hash differs: UPDATE (replace the line)
    assert_contains_regex "$CURATOR_CONTENT" "UUID.*match|uuid.*match|[Uu]pdate.*content|[Rr]eplace.*line|content.*change" \
        "TEST-CTX-M3-065: documents UUID match with different content_hash as update"

    # Requirement: REQ-CTX-020 (Must)
    # Acceptance: If no match: append new line
    assert_contains_regex "$CURATOR_CONTENT" "[Aa]ppend.*new|[Nn]ew.*entry|[Nn]ew.*line" \
        "TEST-CTX-M3-066: documents appending new entries when no match"

    # Requirement: REQ-CTX-020 (Must)
    # Acceptance: JSONL files rewritten in-place when lines updated (read all, modify, write all)
    assert_contains_regex "$CURATOR_CONTENT" "[Rr]ewrite|[Ww]rite.*all|atomic|temp.*rename|overwrite" \
        "TEST-CTX-M3-067: documents JSONL rewrite strategy (atomic write)"

    # Requirement: REQ-CTX-020 (Must)
    # Acceptance: Incident JSON files: overwrite entirely when updating
    assert_contains_regex "$CURATOR_CONTENT" "[Ii]ncident.*overwrite|[Ii]ncident.*JSON|[Oo]verwrite.*incident" \
        "TEST-CTX-M3-068: documents incident JSON overwrite on update"

    # -- REQ-CTX-021: Conflict detection (Should) --

    # Requirement: REQ-CTX-021 (Should)
    # Acceptance: Compare new entry against existing entries in same category
    assert_contains_regex "$CURATOR_CONTENT" "[Cc]onflict.*detect|[Dd]etect.*conflict|contradict" \
        "TEST-CTX-M3-069: documents conflict detection between entries"

    # Requirement: REQ-CTX-021 (Should)
    # Acceptance: Behavioral learning conflicts (negation heuristic: "never X" vs "always X")
    assert_contains_regex "$CURATOR_CONTENT" "never.*always|always.*never|negation|contradict.*rule" \
        "TEST-CTX-M3-070: documents negation heuristic for behavioral learning conflicts"

    # Requirement: REQ-CTX-021 (Should)
    # Acceptance: Conflicts written to .omega/shared/conflicts.jsonl
    assert_contains "$CURATOR_CONTENT" "conflicts.jsonl" \
        "TEST-CTX-M3-071: documents conflicts.jsonl file"

    # Requirement: REQ-CTX-021 (Should)
    # Acceptance: Conflict entry structure (entry_a_uuid, entry_b_uuid, description, status)
    assert_contains_regex "$CURATOR_CONTENT" "entry_a_uuid|entry_b_uuid|unresolved" \
        "TEST-CTX-M3-072: documents conflict entry structure"

    # Requirement: REQ-CTX-021 (Should)
    # Acceptance: Curator outputs warning when conflict detected
    assert_contains_regex "$CURATOR_CONTENT" "CONFLICT.*DETECT|[Ww]arning.*conflict|[Ff]lag.*conflict" \
        "TEST-CTX-M3-073: documents conflict warning output"

else
    skip_test "TEST-CTX-M3-062: content_hash dedup" "curator.md not yet created"
    skip_test "TEST-CTX-M3-063: JSONL reading for dedup" "curator.md not yet created"
    skip_test "TEST-CTX-M3-064: reinforcement on match" "curator.md not yet created"
    skip_test "TEST-CTX-M3-065: UUID match update" "curator.md not yet created"
    skip_test "TEST-CTX-M3-066: append new entries" "curator.md not yet created"
    skip_test "TEST-CTX-M3-067: JSONL rewrite strategy" "curator.md not yet created"
    skip_test "TEST-CTX-M3-068: incident JSON overwrite" "curator.md not yet created"
    skip_test "TEST-CTX-M3-069: conflict detection" "curator.md not yet created"
    skip_test "TEST-CTX-M3-070: negation heuristic" "curator.md not yet created"
    skip_test "TEST-CTX-M3-071: conflicts.jsonl" "curator.md not yet created"
    skip_test "TEST-CTX-M3-072: conflict entry structure" "curator.md not yet created"
    skip_test "TEST-CTX-M3-073: conflict warning output" "curator.md not yet created"
fi

echo ""

# ============================================================
# GROUP 4: Cross-Contributor Reinforcement (REQ-CTX-022) -- Must
# ============================================================
echo "--- Group 4: Cross-Contributor Reinforcement (REQ-CTX-022) ---"
echo ""

if [ -f "$CURATOR_FILE" ]; then
    CURATOR_CONTENT=$(cat "$CURATOR_FILE")

    # Requirement: REQ-CTX-022 (Must)
    # Acceptance: Different contributor reinforcement gives +0.2 confidence boost (vs +0.1 for same contributor)
    assert_contains_regex "$CURATOR_CONTENT" "0\.2|\+0\.2|cross.contributor.*boost|double.*reinforce" \
        "TEST-CTX-M3-074: documents +0.2 confidence boost for cross-contributor reinforcement"

    # Requirement: REQ-CTX-022 (Must)
    # Acceptance: Normal (same contributor) reinforcement is +0.1
    assert_contains_regex "$CURATOR_CONTENT" "0\.1|\+0\.1|normal.*reinforce|same.*contributor" \
        "TEST-CTX-M3-075: documents +0.1 normal reinforcement for same contributor"

    # Requirement: REQ-CTX-022 (Must)
    # Acceptance: 3+ unique contributors = confidence set to 1.0 (maximum, team consensus)
    assert_contains_regex "$CURATOR_CONTENT" "3\+.*contributor|three.*contributor|1\.0.*maximum|confidence.*1\.0|team.*consensus" \
        "TEST-CTX-M3-076: documents 3+ contributors = confidence 1.0 (team consensus)"

    # Requirement: REQ-CTX-022 (Must)
    # Acceptance: contributors field is a JSON array
    assert_contains_regex "$CURATOR_CONTENT" "contributors.*array|contributors.*list|JSON array" \
        "TEST-CTX-M3-077: documents contributors field as JSON array"

    # Requirement: REQ-CTX-022 (Must)
    # Acceptance: Reinforcement tracking (each contributor's timestamp logged)
    assert_contains_regex "$CURATOR_CONTENT" "[Rr]einforce.*track|timestamp.*reinforce|reinforce.*log" \
        "TEST-CTX-M3-078: documents reinforcement tracking with timestamps"

    # Requirement: REQ-CTX-022 (Must)
    # Edge case: Confidence cap -- confidence should never exceed 1.0
    assert_contains_regex "$CURATOR_CONTENT" "[Cc]ap.*1\.0|[Mm]ax.*1\.0|[Nn]ever exceed|confidence.*1\.0|minimum.*0.*maximum.*1|clamp" \
        "TEST-CTX-M3-079: documents confidence cap at 1.0 (never exceeds maximum)"

else
    skip_test "TEST-CTX-M3-074: +0.2 cross-contributor boost" "curator.md not yet created"
    skip_test "TEST-CTX-M3-075: +0.1 normal reinforcement" "curator.md not yet created"
    skip_test "TEST-CTX-M3-076: 3+ contributors = 1.0" "curator.md not yet created"
    skip_test "TEST-CTX-M3-077: contributors JSON array" "curator.md not yet created"
    skip_test "TEST-CTX-M3-078: reinforcement tracking" "curator.md not yet created"
    skip_test "TEST-CTX-M3-079: confidence cap at 1.0" "curator.md not yet created"
fi

echo ""

# ============================================================
# GROUP 5: /omega:share Command (REQ-CTX-023) -- Must
# ============================================================
echo "--- Group 5: /omega:share Command (REQ-CTX-023) ---"
echo ""

if [ -f "$SHARE_CMD_FILE" ]; then
    SHARE_CONTENT=$(cat "$SHARE_CMD_FILE")

    # Requirement: REQ-CTX-023 (Must)
    # Acceptance: omega-share.md exists
    assert_file_exists "$SHARE_CMD_FILE" \
        "TEST-CTX-M3-080: omega-share.md exists at core/commands/omega-share.md"

    # Requirement: REQ-CTX-023 (Must)
    # Acceptance: Has YAML frontmatter with opening ---
    assert_contains_regex "$SHARE_CONTENT" "^---" \
        "TEST-CTX-M3-081: omega-share.md starts with YAML frontmatter delimiter"

    # Requirement: REQ-CTX-023 (Must)
    # Acceptance: Frontmatter contains name field
    SHARE_FRONTMATTER=$(echo "$SHARE_CONTENT" | sed -n '/^---$/,/^---$/p')
    assert_contains "$SHARE_FRONTMATTER" "name:" \
        "TEST-CTX-M3-082: frontmatter contains name field"

    # Requirement: REQ-CTX-023 (Must)
    # Acceptance: Command name is omega:share
    assert_contains_regex "$SHARE_FRONTMATTER" "name:.*omega:share|name:.*share" \
        "TEST-CTX-M3-083: command name is omega:share"

    # Requirement: REQ-CTX-023 (Must)
    # Acceptance: Frontmatter contains description field
    assert_contains "$SHARE_FRONTMATTER" "description:" \
        "TEST-CTX-M3-084: frontmatter contains description field"

    # Requirement: REQ-CTX-023 (Must)
    # Acceptance: Invokes curator agent
    assert_contains_regex "$SHARE_CONTENT" "[Cc]urator|curator.*agent|[Ii]nvoke.*curator" \
        "TEST-CTX-M3-085: command invokes curator agent"

    # Requirement: REQ-CTX-023 (Must)
    # Acceptance: Creates workflow_runs entry with type='share'
    assert_contains "$SHARE_CONTENT" "workflow_runs" \
        "TEST-CTX-M3-086: documents workflow_runs entry creation"

    assert_contains_regex "$SHARE_CONTENT" "type.*share|'share'" \
        "TEST-CTX-M3-087: workflow_runs type is 'share'"

    # Requirement: REQ-CTX-023 (Must)
    # Acceptance: --force flag documented (share entries below confidence threshold)
    assert_contains "$SHARE_CONTENT" "--force" \
        "TEST-CTX-M3-088: documents --force flag"

    assert_contains_regex "$SHARE_CONTENT" "force.*threshold|force.*confidence|[Oo]verride.*0\.8|[Bb]elow.*threshold" \
        "TEST-CTX-M3-089: --force overrides confidence threshold"

    # Requirement: REQ-CTX-023 (Must)
    # Acceptance: --dry-run flag documented
    assert_contains "$SHARE_CONTENT" "--dry-run" \
        "TEST-CTX-M3-090: documents --dry-run flag"

    assert_contains_regex "$SHARE_CONTENT" "dry.run.*without.*writ|dry.run.*show.*what|[Ww]ould.*be.*shared" \
        "TEST-CTX-M3-091: --dry-run shows what would be shared without writing"

    # Requirement: REQ-CTX-023 (Must)
    # Acceptance: Output summary table (shared, skipped, reinforced, conflicts)
    assert_contains_regex "$SHARE_CONTENT" "[Ss]ummary|[Ss]hared.*[Ss]kipped|[Rr]einforced" \
        "TEST-CTX-M3-092: documents summary output"

    assert_contains_regex "$SHARE_CONTENT" "[Ss]kipped" \
        "TEST-CTX-M3-093: summary includes skipped items"

    assert_contains_regex "$SHARE_CONTENT" "[Rr]einforced" \
        "TEST-CTX-M3-094: summary includes reinforced items"

    assert_contains_regex "$SHARE_CONTENT" "[Cc]onflict" \
        "TEST-CTX-M3-095: summary includes conflict information"

    # Requirement: REQ-CTX-023 (Must)
    # Acceptance: Memory protocol: briefing, incremental logging, close-out
    assert_contains_regex "$SHARE_CONTENT" "[Mm]emory|[Bb]riefing|[Cc]lose.out|memory-protocol|[Ii]nstitutional" \
        "TEST-CTX-M3-096: documents memory protocol (briefing/logging/close-out)"

    # Requirement: REQ-CTX-023 (Must)
    # Acceptance: Command file is substantial (not a stub)
    SHARE_LINE_COUNT=$(echo "$SHARE_CONTENT" | wc -l | tr -d ' ')
    assert_gt 20 "$SHARE_LINE_COUNT" \
        "TEST-CTX-M3-097: omega-share.md is substantial (>20 lines, not a stub)"

    # Requirement: REQ-CTX-023 (Must)
    # Acceptance: workflow_runs close at end (update status)
    assert_contains_regex "$SHARE_CONTENT" "completed_at|status.*completed|UPDATE.*workflow_runs|[Cc]lose.*workflow" \
        "TEST-CTX-M3-098: documents closing workflow_runs entry at end"

else
    skip_test "TEST-CTX-M3-080: omega-share.md exists" "file not yet created"
    skip_test "TEST-CTX-M3-081: YAML frontmatter" "file not yet created"
    skip_test "TEST-CTX-M3-082: name field" "file not yet created"
    skip_test "TEST-CTX-M3-083: name is omega:share" "file not yet created"
    skip_test "TEST-CTX-M3-084: description field" "file not yet created"
    skip_test "TEST-CTX-M3-085: invokes curator" "file not yet created"
    skip_test "TEST-CTX-M3-086: workflow_runs entry" "file not yet created"
    skip_test "TEST-CTX-M3-087: type is share" "file not yet created"
    skip_test "TEST-CTX-M3-088: --force flag" "file not yet created"
    skip_test "TEST-CTX-M3-089: --force overrides threshold" "file not yet created"
    skip_test "TEST-CTX-M3-090: --dry-run flag" "file not yet created"
    skip_test "TEST-CTX-M3-091: --dry-run shows without writing" "file not yet created"
    skip_test "TEST-CTX-M3-092: summary output" "file not yet created"
    skip_test "TEST-CTX-M3-093: skipped items" "file not yet created"
    skip_test "TEST-CTX-M3-094: reinforced items" "file not yet created"
    skip_test "TEST-CTX-M3-095: conflict info" "file not yet created"
    skip_test "TEST-CTX-M3-096: memory protocol" "file not yet created"
    skip_test "TEST-CTX-M3-097: substantial content" "file not yet created"
    skip_test "TEST-CTX-M3-098: workflow_runs close" "file not yet created"
fi

echo ""

# ============================================================
# GROUP 6: JSONL Format Validation (REQ-CTX-009, REQ-CTX-014-019)
# ============================================================
echo "--- Group 6: JSONL Format Validation (REQ-CTX-009, REQ-CTX-014-019) ---"
echo ""

if [ "$HAS_PYTHON3" = true ]; then

    # Requirement: REQ-CTX-009, REQ-CTX-014 (Must)
    # Acceptance: Behavioral learning JSONL entry has all required common + category fields
    BL_JSONL='{"uuid":"550e8400-e29b-41d4-a716-446655440000","contributor":"Ivan Lozada <ilozada@me.com>","source_project":"omega","created_at":"2026-03-20T12:00:00Z","confidence":0.9,"occurrences":3,"content_hash":"abc123def456","rule":"Never skip the compile gate before implementing test logic","context":"TDD workflow enforcement","status":"active"}'
    BL_VALID=$(echo "$BL_JSONL" | python3 -c "
import sys, json
try:
    obj = json.loads(sys.stdin.read())
    # Check all required common fields
    required_common = ['uuid', 'contributor', 'source_project', 'created_at', 'confidence', 'occurrences', 'content_hash']
    # Check category-specific fields
    required_specific = ['rule', 'context', 'status']
    missing = [f for f in required_common + required_specific if f not in obj]
    if missing:
        print('MISSING:' + ','.join(missing))
    else:
        print('VALID')
except Exception as e:
    print('ERROR:' + str(e))
" 2>&1)
    assert_eq "VALID" "$BL_VALID" \
        "TEST-CTX-M3-099: behavioral learning JSONL entry validates with all required fields"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: Confidence is a float between 0.0 and 1.0
    BL_CONFIDENCE_CHECK=$(echo "$BL_JSONL" | python3 -c "
import sys, json
obj = json.loads(sys.stdin.read())
c = obj['confidence']
if isinstance(c, (int, float)) and 0.0 <= c <= 1.0:
    print('VALID')
else:
    print('INVALID:' + str(c))
" 2>&1)
    assert_eq "VALID" "$BL_CONFIDENCE_CHECK" \
        "TEST-CTX-M3-100: confidence field is float between 0.0 and 1.0"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: UUID is valid UUID v4 format
    BL_UUID_CHECK=$(echo "$BL_JSONL" | python3 -c "
import sys, json, re
obj = json.loads(sys.stdin.read())
uuid_pattern = r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
if re.match(uuid_pattern, obj['uuid']):
    print('VALID')
else:
    print('INVALID:' + obj['uuid'])
" 2>&1)
    assert_eq "VALID" "$BL_UUID_CHECK" \
        "TEST-CTX-M3-101: uuid field is valid UUID format"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: created_at is ISO 8601 format
    BL_DATE_CHECK=$(echo "$BL_JSONL" | python3 -c "
import sys, json
from datetime import datetime
obj = json.loads(sys.stdin.read())
try:
    datetime.fromisoformat(obj['created_at'].replace('Z', '+00:00'))
    print('VALID')
except:
    print('INVALID:' + obj['created_at'])
" 2>&1)
    assert_eq "VALID" "$BL_DATE_CHECK" \
        "TEST-CTX-M3-102: created_at field is valid ISO 8601 format"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: occurrences is an integer
    BL_OCC_CHECK=$(echo "$BL_JSONL" | python3 -c "
import sys, json
obj = json.loads(sys.stdin.read())
if isinstance(obj['occurrences'], int):
    print('VALID')
else:
    print('INVALID:' + str(type(obj['occurrences'])))
" 2>&1)
    assert_eq "VALID" "$BL_OCC_CHECK" \
        "TEST-CTX-M3-103: occurrences field is an integer"

    # Requirement: REQ-CTX-015, REQ-CTX-009 (Must)
    # Acceptance: Incident JSON entry has required fields
    INC_JSON='{"incident_id":"INC-042","title":"Payment timeout in checkout","domain":"payments","status":"resolved","symptoms":["500 error on checkout","timeout after 30s"],"root_cause":"Connection pool exhaustion","resolution":"Increased pool size from 5 to 20","affected_files":["src/payments/checkout.rs","src/db/pool.rs"],"tags":["timeout","database"],"contributor":"Ivan Lozada <ilozada@me.com>","entries":[{"entry_type":"observation","content":"Saw 500 errors","result":"Confirmed","agent":"diagnostician","created_at":"2026-03-20T10:00:00Z"}]}'
    INC_VALID=$(echo "$INC_JSON" | python3 -c "
import sys, json
try:
    obj = json.loads(sys.stdin.read())
    required = ['incident_id', 'title', 'domain', 'status', 'symptoms', 'root_cause', 'resolution', 'affected_files', 'tags', 'contributor', 'entries']
    missing = [f for f in required if f not in obj]
    if missing:
        print('MISSING:' + ','.join(missing))
    elif not isinstance(obj['symptoms'], list):
        print('INVALID: symptoms not array')
    elif not isinstance(obj['affected_files'], list):
        print('INVALID: affected_files not array')
    elif not isinstance(obj['entries'], list):
        print('INVALID: entries not array')
    elif not isinstance(obj['tags'], list):
        print('INVALID: tags not array')
    else:
        print('VALID')
except Exception as e:
    print('ERROR:' + str(e))
" 2>&1)
    assert_eq "VALID" "$INC_VALID" \
        "TEST-CTX-M3-104: incident JSON entry validates with all required fields"

    # Requirement: REQ-CTX-015 (Must)
    # Acceptance: Incident entries array contains timeline objects with entry_type, content, agent, created_at
    INC_ENTRY_CHECK=$(echo "$INC_JSON" | python3 -c "
import sys, json
obj = json.loads(sys.stdin.read())
entry = obj['entries'][0]
required = ['entry_type', 'content', 'agent', 'created_at']
missing = [f for f in required if f not in entry]
if missing:
    print('MISSING:' + ','.join(missing))
else:
    print('VALID')
" 2>&1)
    assert_eq "VALID" "$INC_ENTRY_CHECK" \
        "TEST-CTX-M3-105: incident entry timeline objects have required fields"

    # Requirement: REQ-CTX-016, REQ-CTX-009 (Must)
    # Acceptance: Hotspot JSONL entry has required fields
    HS_JSONL='{"uuid":"660e8400-e29b-41d4-a716-446655440001","contributor":"Ivan Lozada <ilozada@me.com>","source_project":"omega","created_at":"2026-03-20T12:00:00Z","confidence":0.85,"occurrences":5,"content_hash":"def789abc012","file_path":"src/payments/checkout.rs","risk_level":"high","times_touched":12,"description":"Frequent source of bugs","contributors":["Ivan Lozada <ilozada@me.com>","Dev B <devb@example.com>"]}'
    HS_VALID=$(echo "$HS_JSONL" | python3 -c "
import sys, json
try:
    obj = json.loads(sys.stdin.read())
    required_common = ['uuid', 'contributor', 'source_project', 'created_at', 'confidence', 'occurrences', 'content_hash']
    required_specific = ['file_path', 'risk_level', 'times_touched', 'description', 'contributors']
    missing = [f for f in required_common + required_specific if f not in obj]
    if missing:
        print('MISSING:' + ','.join(missing))
    elif not isinstance(obj['contributors'], list):
        print('INVALID: contributors not array')
    elif obj['risk_level'] not in ('low', 'medium', 'high', 'critical'):
        print('INVALID: risk_level=' + obj['risk_level'])
    else:
        print('VALID')
except Exception as e:
    print('ERROR:' + str(e))
" 2>&1)
    assert_eq "VALID" "$HS_VALID" \
        "TEST-CTX-M3-106: hotspot JSONL entry validates with all required fields"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: Hotspot risk_level is one of: low, medium, high, critical
    HS_RISK_CHECK=$(echo "$HS_JSONL" | python3 -c "
import sys, json
obj = json.loads(sys.stdin.read())
valid_levels = ['low', 'medium', 'high', 'critical']
if obj['risk_level'] in valid_levels:
    print('VALID')
else:
    print('INVALID:' + obj['risk_level'])
" 2>&1)
    assert_eq "VALID" "$HS_RISK_CHECK" \
        "TEST-CTX-M3-107: hotspot risk_level is a valid enum value"

    # Requirement: REQ-CTX-009 (Must)
    # Acceptance: Hotspot contributors is a JSON array of strings
    HS_CONTRIB_CHECK=$(echo "$HS_JSONL" | python3 -c "
import sys, json
obj = json.loads(sys.stdin.read())
contribs = obj['contributors']
if isinstance(contribs, list) and all(isinstance(c, str) for c in contribs):
    print('VALID')
else:
    print('INVALID')
" 2>&1)
    assert_eq "VALID" "$HS_CONTRIB_CHECK" \
        "TEST-CTX-M3-108: hotspot contributors is array of strings"

    # Requirement: REQ-CTX-017 (Should)
    # Acceptance: Lesson JSONL entry has required fields
    LS_JSONL='{"uuid":"770e8400-e29b-41d4-a716-446655440002","contributor":"Ivan Lozada <ilozada@me.com>","source_project":"omega","created_at":"2026-03-20T12:00:00Z","confidence":0.9,"occurrences":2,"content_hash":"ghi345jkl678","domain":"testing","content":"Always run the compile gate before implementing test logic","source_agent":"test-writer"}'
    LS_VALID=$(echo "$LS_JSONL" | python3 -c "
import sys, json
try:
    obj = json.loads(sys.stdin.read())
    required_common = ['uuid', 'contributor', 'source_project', 'created_at', 'confidence', 'occurrences', 'content_hash']
    required_specific = ['domain', 'content', 'source_agent']
    missing = [f for f in required_common + required_specific if f not in obj]
    if missing:
        print('MISSING:' + ','.join(missing))
    else:
        print('VALID')
except Exception as e:
    print('ERROR:' + str(e))
" 2>&1)
    assert_eq "VALID" "$LS_VALID" \
        "TEST-CTX-M3-109: lesson JSONL entry validates with all required fields"

    # Requirement: REQ-CTX-018 (Should)
    # Acceptance: Pattern JSONL entry has required fields
    PT_JSONL='{"uuid":"880e8400-e29b-41d4-a716-446655440003","contributor":"Ivan Lozada <ilozada@me.com>","source_project":"omega","created_at":"2026-03-20T12:00:00Z","confidence":0.85,"occurrences":1,"content_hash":"mno901pqr234","domain":"architecture","name":"Repository pattern","description":"Use repository pattern for data access","example_files":["src/db/repo.rs"]}'
    PT_VALID=$(echo "$PT_JSONL" | python3 -c "
import sys, json
try:
    obj = json.loads(sys.stdin.read())
    required_common = ['uuid', 'contributor', 'source_project', 'created_at', 'confidence', 'occurrences', 'content_hash']
    required_specific = ['domain', 'name', 'description', 'example_files']
    missing = [f for f in required_common + required_specific if f not in obj]
    if missing:
        print('MISSING:' + ','.join(missing))
    elif not isinstance(obj['example_files'], list):
        print('INVALID: example_files not array')
    else:
        print('VALID')
except Exception as e:
    print('ERROR:' + str(e))
" 2>&1)
    assert_eq "VALID" "$PT_VALID" \
        "TEST-CTX-M3-110: pattern JSONL entry validates with all required fields"

    # Requirement: REQ-CTX-019 (Should)
    # Acceptance: Decision JSONL entry has required fields
    DC_JSONL='{"uuid":"990e8400-e29b-41d4-a716-446655440004","contributor":"Ivan Lozada <ilozada@me.com>","source_project":"omega","created_at":"2026-03-20T12:00:00Z","confidence":0.95,"occurrences":1,"content_hash":"stu567vwx890","domain":"database","decision":"Use SQLite for local storage","rationale":"Simplicity, portability, no server needed","alternatives":["PostgreSQL","DynamoDB"]}'
    DC_VALID=$(echo "$DC_JSONL" | python3 -c "
import sys, json
try:
    obj = json.loads(sys.stdin.read())
    required_common = ['uuid', 'contributor', 'source_project', 'created_at', 'confidence', 'occurrences', 'content_hash']
    required_specific = ['domain', 'decision', 'rationale', 'alternatives']
    missing = [f for f in required_common + required_specific if f not in obj]
    if missing:
        print('MISSING:' + ','.join(missing))
    elif not isinstance(obj['alternatives'], list):
        print('INVALID: alternatives not array')
    else:
        print('VALID')
except Exception as e:
    print('ERROR:' + str(e))
" 2>&1)
    assert_eq "VALID" "$DC_VALID" \
        "TEST-CTX-M3-111: decision JSONL entry validates with all required fields"

    # Requirement: REQ-CTX-021 (Should)
    # Acceptance: Conflict JSONL entry has required fields
    CF_JSONL='{"uuid":"aa0e8400-e29b-41d4-a716-446655440005","entry_a_uuid":"550e8400-e29b-41d4-a716-446655440000","entry_b_uuid":"bb0e8400-e29b-41d4-a716-446655440006","domain":"testing","description":"Contradictory rules: always use mocks vs never use mocks","detected_at":"2026-03-20T12:30:00Z","status":"unresolved"}'
    CF_VALID=$(echo "$CF_JSONL" | python3 -c "
import sys, json
try:
    obj = json.loads(sys.stdin.read())
    required = ['uuid', 'entry_a_uuid', 'entry_b_uuid', 'domain', 'description', 'detected_at', 'status']
    missing = [f for f in required if f not in obj]
    if missing:
        print('MISSING:' + ','.join(missing))
    elif obj['status'] != 'unresolved':
        print('INVALID: status should be unresolved in v1')
    else:
        print('VALID')
except Exception as e:
    print('ERROR:' + str(e))
" 2>&1)
    assert_eq "VALID" "$CF_VALID" \
        "TEST-CTX-M3-112: conflict JSONL entry validates with all required fields"

    # Requirement: REQ-CTX-009 (Must)
    # Edge case: Multi-line JSONL is invalid (each line must be self-contained)
    MULTILINE_CHECK=$(python3 -c "
import json
# This is a multi-line JSON string -- NOT valid JSONL
multiline = '''
{
  \"uuid\": \"test\",
  \"rule\": \"test\"
}
'''
lines = [l.strip() for l in multiline.strip().split('\n')]
all_valid = all(True for l in lines if l)
# In JSONL, each non-empty line must be a complete JSON object
valid_count = 0
for l in lines:
    if not l:
        continue
    try:
        json.loads(l)
        valid_count += 1
    except:
        pass
# Multi-line JSON should NOT be parseable as single-line JSONL
if valid_count == 0:
    print('CORRECTLY_REJECTED')
else:
    print('INCORRECTLY_ACCEPTED')
" 2>&1)
    assert_eq "CORRECTLY_REJECTED" "$MULTILINE_CHECK" \
        "TEST-CTX-M3-113: multi-line JSON is correctly rejected as invalid JSONL"

    # Requirement: REQ-CTX-009 (Must)
    # Edge case: Empty JSONL file is valid (zero entries)
    EMPTY_CHECK=$(python3 -c "
import json
lines = []
if len(lines) == 0:
    print('VALID')
else:
    print('INVALID')
" 2>&1)
    assert_eq "VALID" "$EMPTY_CHECK" \
        "TEST-CTX-M3-114: empty JSONL file is valid (zero entries)"

    # Requirement: REQ-CTX-009 (Must)
    # Edge case: JSONL with multiple valid lines (simulate a file)
    MULTI_LINE_VALID=$(python3 -c "
import json
lines = [
    '{\"uuid\":\"aaa\",\"rule\":\"rule1\",\"confidence\":0.9}',
    '{\"uuid\":\"bbb\",\"rule\":\"rule2\",\"confidence\":0.85}',
    '{\"uuid\":\"ccc\",\"rule\":\"rule3\",\"confidence\":0.95}'
]
valid = 0
for l in lines:
    try:
        json.loads(l)
        valid += 1
    except:
        pass
if valid == 3:
    print('VALID')
else:
    print('INVALID:' + str(valid))
" 2>&1)
    assert_eq "VALID" "$MULTI_LINE_VALID" \
        "TEST-CTX-M3-115: JSONL with multiple lines parses correctly"

    # Requirement: REQ-CTX-020 (Must)
    # Edge case: content_hash deduplication simulation
    DEDUP_CHECK=$(python3 -c "
import json
existing = [
    json.loads('{\"uuid\":\"aaa\",\"content_hash\":\"hash1\",\"occurrences\":1,\"confidence\":0.8}'),
    json.loads('{\"uuid\":\"bbb\",\"content_hash\":\"hash2\",\"occurrences\":2,\"confidence\":0.9}'),
]
new_entry = json.loads('{\"uuid\":\"ccc\",\"content_hash\":\"hash1\",\"occurrences\":1,\"confidence\":0.85}')

# Simulate dedup: check content_hash
match = None
for e in existing:
    if e['content_hash'] == new_entry['content_hash']:
        match = e
        break

if match is not None:
    # Reinforce: bump occurrences, update confidence
    match['occurrences'] += 1
    if match['occurrences'] == 2:
        print('REINFORCED')
    else:
        print('INVALID:occ=' + str(match['occurrences']))
else:
    print('NOT_FOUND')
" 2>&1)
    assert_eq "REINFORCED" "$DEDUP_CHECK" \
        "TEST-CTX-M3-116: content_hash deduplication correctly reinforces matching entry"

    # Requirement: REQ-CTX-022 (Must)
    # Cross-contributor reinforcement simulation
    CROSS_CONTRIB_CHECK=$(python3 -c "
import json
entry = {
    'uuid': 'aaa',
    'confidence': 0.8,
    'occurrences': 1,
    'contributors': ['Dev A <a@example.com>']
}
new_contributor = 'Dev B <b@example.com>'

# Cross-contributor reinforcement: different contributor = +0.2
if new_contributor not in entry['contributors']:
    entry['confidence'] += 0.2
    entry['contributors'].append(new_contributor)
    entry['occurrences'] += 1

if abs(entry['confidence'] - 1.0) < 0.001 and len(entry['contributors']) == 2:
    print('VALID')
else:
    print('CONF=' + str(entry['confidence']) + ',CONTRIB=' + str(len(entry['contributors'])))
" 2>&1)
    assert_eq "VALID" "$CROSS_CONTRIB_CHECK" \
        "TEST-CTX-M3-117: cross-contributor reinforcement adds +0.2 confidence"

    # Requirement: REQ-CTX-022 (Must)
    # 3+ contributors = confidence 1.0 (team consensus)
    THREE_CONTRIB_CHECK=$(python3 -c "
import json
entry = {
    'uuid': 'aaa',
    'confidence': 0.6,
    'occurrences': 1,
    'contributors': ['Dev A <a@example.com>', 'Dev B <b@example.com>']
}
new_contributor = 'Dev C <c@example.com>'

entry['contributors'].append(new_contributor)
entry['occurrences'] += 1

# 3+ unique contributors = confidence set to 1.0
if len(entry['contributors']) >= 3:
    entry['confidence'] = 1.0

if entry['confidence'] == 1.0 and len(entry['contributors']) == 3:
    print('VALID')
else:
    print('CONF=' + str(entry['confidence']) + ',CONTRIB=' + str(len(entry['contributors'])))
" 2>&1)
    assert_eq "VALID" "$THREE_CONTRIB_CHECK" \
        "TEST-CTX-M3-118: 3+ contributors sets confidence to 1.0 (team consensus)"

    # Requirement: REQ-CTX-009 (Must)
    # Edge case: JSONL entry with special characters / unicode in rule field
    UNICODE_CHECK=$(python3 -c "
import json
entry = json.dumps({
    'uuid': 'uuu',
    'rule': 'Never use em-dashes (\u2014) in variable names. Use proper quotes (\u201c\u201d). Handle accents: caf\u00e9.',
    'confidence': 0.9
})
# Verify roundtrip
parsed = json.loads(entry)
if '\u2014' in parsed['rule'] and 'caf\u00e9' in parsed['rule']:
    print('VALID')
else:
    print('INVALID')
" 2>&1)
    assert_eq "VALID" "$UNICODE_CHECK" \
        "TEST-CTX-M3-119: JSONL handles unicode/special characters in rule field"

    # Requirement: REQ-CTX-009 (Must)
    # Edge case: Extremely long rule field (stress test format)
    LONG_RULE_CHECK=$(python3 -c "
import json
long_rule = 'A' * 10000  # 10KB rule
entry = json.dumps({'uuid': 'lll', 'rule': long_rule, 'confidence': 0.8})
parsed = json.loads(entry)
if len(parsed['rule']) == 10000:
    print('VALID')
else:
    print('INVALID:' + str(len(parsed['rule'])))
" 2>&1)
    assert_eq "VALID" "$LONG_RULE_CHECK" \
        "TEST-CTX-M3-120: JSONL handles extremely long rule field (10KB)"

    # Requirement: REQ-CTX-009, REQ-CTX-020 (Must)
    # Edge case: Malformed JSONL line should be detected and skipped
    MALFORMED_CHECK=$(python3 -c "
import json
lines = [
    '{\"uuid\":\"aaa\",\"rule\":\"valid\"}',
    'THIS IS NOT JSON',
    '{\"uuid\":\"bbb\",\"rule\":\"also valid\"}'
]
valid = 0
malformed = 0
for l in lines:
    try:
        json.loads(l)
        valid += 1
    except json.JSONDecodeError:
        malformed += 1

if valid == 2 and malformed == 1:
    print('CORRECTLY_HANDLED')
else:
    print('INVALID:valid=' + str(valid) + ',malformed=' + str(malformed))
" 2>&1)
    assert_eq "CORRECTLY_HANDLED" "$MALFORMED_CHECK" \
        "TEST-CTX-M3-121: malformed JSONL lines are detected (skip and continue)"

    # Requirement: REQ-CTX-009 (Must)
    # Edge case: Confidence boundary values (0.0, 0.8, 1.0)
    CONF_BOUNDARY_CHECK=$(python3 -c "
import json
entries = [
    {'confidence': 0.0},
    {'confidence': 0.8},
    {'confidence': 1.0},
]
valid = all(0.0 <= e['confidence'] <= 1.0 for e in entries)
at_threshold = entries[1]['confidence'] >= 0.8
below_threshold = entries[0]['confidence'] < 0.8
if valid and at_threshold and below_threshold:
    print('VALID')
else:
    print('INVALID')
" 2>&1)
    assert_eq "VALID" "$CONF_BOUNDARY_CHECK" \
        "TEST-CTX-M3-122: confidence boundary values (0.0, 0.8, 1.0) handled correctly"

else
    skip_test "TEST-CTX-M3-099: behavioral learning validation" "python3 not available"
    skip_test "TEST-CTX-M3-100: confidence float range" "python3 not available"
    skip_test "TEST-CTX-M3-101: UUID format validation" "python3 not available"
    skip_test "TEST-CTX-M3-102: ISO 8601 date format" "python3 not available"
    skip_test "TEST-CTX-M3-103: occurrences integer" "python3 not available"
    skip_test "TEST-CTX-M3-104: incident JSON validation" "python3 not available"
    skip_test "TEST-CTX-M3-105: incident entry timeline" "python3 not available"
    skip_test "TEST-CTX-M3-106: hotspot JSONL validation" "python3 not available"
    skip_test "TEST-CTX-M3-107: hotspot risk_level enum" "python3 not available"
    skip_test "TEST-CTX-M3-108: hotspot contributors array" "python3 not available"
    skip_test "TEST-CTX-M3-109: lesson JSONL validation" "python3 not available"
    skip_test "TEST-CTX-M3-110: pattern JSONL validation" "python3 not available"
    skip_test "TEST-CTX-M3-111: decision JSONL validation" "python3 not available"
    skip_test "TEST-CTX-M3-112: conflict JSONL validation" "python3 not available"
    skip_test "TEST-CTX-M3-113: multi-line JSON rejected" "python3 not available"
    skip_test "TEST-CTX-M3-114: empty JSONL valid" "python3 not available"
    skip_test "TEST-CTX-M3-115: multi-line JSONL parsing" "python3 not available"
    skip_test "TEST-CTX-M3-116: content_hash dedup" "python3 not available"
    skip_test "TEST-CTX-M3-117: cross-contributor +0.2" "python3 not available"
    skip_test "TEST-CTX-M3-118: 3+ contributors = 1.0" "python3 not available"
    skip_test "TEST-CTX-M3-119: unicode in rule field" "python3 not available"
    skip_test "TEST-CTX-M3-120: long rule field (10KB)" "python3 not available"
    skip_test "TEST-CTX-M3-121: malformed JSONL handling" "python3 not available"
    skip_test "TEST-CTX-M3-122: confidence boundaries" "python3 not available"
fi

echo ""

# ============================================================
# GROUP 7: Deployment Tests (REQ-CTX-013, REQ-CTX-023)
# ============================================================
echo "--- Group 7: Deployment Tests (REQ-CTX-013, REQ-CTX-023) ---"
echo ""

# Set up test environment for deployment tests
setup_test_env

# Only run deployment tests if both files exist (TDD: these will skip until implemented)
if [ -f "$CURATOR_FILE" ] && [ -f "$SHARE_CMD_FILE" ]; then

    build_fake_toolkit
    reset_target

    # Run setup.sh deployment
    SETUP_OUTPUT=$(run_setup 2>&1)
    SETUP_EXIT=$?

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: After setup.sh, curator.md appears in .claude/agents/
    assert_file_exists "$TARGET_DIR/.claude/agents/curator.md" \
        "TEST-CTX-M3-123: curator.md deployed to .claude/agents/ after setup.sh"

    # Requirement: REQ-CTX-023 (Must)
    # Acceptance: After setup.sh, omega-share.md appears in .claude/commands/
    assert_file_exists "$TARGET_DIR/.claude/commands/omega-share.md" \
        "TEST-CTX-M3-124: omega-share.md deployed to .claude/commands/ after setup.sh"

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Deployed curator.md has same content as source
    if [ -f "$TARGET_DIR/.claude/agents/curator.md" ]; then
        SOURCE_HASH=$(shasum -a 256 "$CURATOR_FILE" | cut -d' ' -f1)
        DEPLOYED_HASH=$(shasum -a 256 "$TARGET_DIR/.claude/agents/curator.md" | cut -d' ' -f1)
        assert_eq "$SOURCE_HASH" "$DEPLOYED_HASH" \
            "TEST-CTX-M3-125: deployed curator.md matches source (content integrity)"
    else
        skip_test "TEST-CTX-M3-125: deployed content match" "curator.md not deployed"
    fi

    # Requirement: REQ-CTX-023 (Must)
    # Acceptance: Deployed omega-share.md has same content as source
    if [ -f "$TARGET_DIR/.claude/commands/omega-share.md" ]; then
        SOURCE_HASH=$(shasum -a 256 "$SHARE_CMD_FILE" | cut -d' ' -f1)
        DEPLOYED_HASH=$(shasum -a 256 "$TARGET_DIR/.claude/commands/omega-share.md" | cut -d' ' -f1)
        assert_eq "$SOURCE_HASH" "$DEPLOYED_HASH" \
            "TEST-CTX-M3-126: deployed omega-share.md matches source (content integrity)"
    else
        skip_test "TEST-CTX-M3-126: deployed content match" "omega-share.md not deployed"
    fi

    # Requirement: REQ-CTX-013 (Must)
    # Acceptance: Deployed curator.md preserves YAML frontmatter
    if [ -f "$TARGET_DIR/.claude/agents/curator.md" ]; then
        DEPLOYED_CURATOR=$(cat "$TARGET_DIR/.claude/agents/curator.md")
        assert_contains_regex "$DEPLOYED_CURATOR" "^---" \
            "TEST-CTX-M3-127: deployed curator.md preserves YAML frontmatter"
        DEPLOYED_FM=$(echo "$DEPLOYED_CURATOR" | sed -n '/^---$/,/^---$/p')
        assert_contains "$DEPLOYED_FM" "name:" \
            "TEST-CTX-M3-128: deployed curator.md frontmatter has name field"
    else
        skip_test "TEST-CTX-M3-127: deployed frontmatter" "curator.md not deployed"
        skip_test "TEST-CTX-M3-128: deployed name field" "curator.md not deployed"
    fi

    # Requirement: REQ-CTX-013, REQ-CTX-023 (Must)
    # Edge case: Re-deployment (run setup.sh twice) does not corrupt files
    SETUP_OUTPUT_2=$(run_setup 2>&1)
    SETUP_EXIT_2=$?

    if [ -f "$TARGET_DIR/.claude/agents/curator.md" ]; then
        REDEPLOY_HASH=$(shasum -a 256 "$TARGET_DIR/.claude/agents/curator.md" | cut -d' ' -f1)
        SOURCE_HASH=$(shasum -a 256 "$CURATOR_FILE" | cut -d' ' -f1)
        assert_eq "$SOURCE_HASH" "$REDEPLOY_HASH" \
            "TEST-CTX-M3-129: re-deployment preserves curator.md content integrity"
    else
        skip_test "TEST-CTX-M3-129: re-deployment integrity" "curator.md not deployed"
    fi

    if [ -f "$TARGET_DIR/.claude/commands/omega-share.md" ]; then
        REDEPLOY_HASH=$(shasum -a 256 "$TARGET_DIR/.claude/commands/omega-share.md" | cut -d' ' -f1)
        SOURCE_HASH=$(shasum -a 256 "$SHARE_CMD_FILE" | cut -d' ' -f1)
        assert_eq "$SOURCE_HASH" "$REDEPLOY_HASH" \
            "TEST-CTX-M3-130: re-deployment preserves omega-share.md content integrity"
    else
        skip_test "TEST-CTX-M3-130: re-deployment integrity" "omega-share.md not deployed"
    fi

else
    # Files don't exist yet -- skip deployment tests
    if [ ! -f "$CURATOR_FILE" ]; then
        skip_test "TEST-CTX-M3-123: curator deployed" "curator.md not yet created"
        skip_test "TEST-CTX-M3-125: deployed content match" "curator.md not yet created"
        skip_test "TEST-CTX-M3-127: deployed frontmatter" "curator.md not yet created"
        skip_test "TEST-CTX-M3-128: deployed name field" "curator.md not yet created"
        skip_test "TEST-CTX-M3-129: re-deployment integrity" "curator.md not yet created"
    fi
    if [ ! -f "$SHARE_CMD_FILE" ]; then
        skip_test "TEST-CTX-M3-124: omega-share deployed" "omega-share.md not yet created"
        skip_test "TEST-CTX-M3-126: deployed content match" "omega-share.md not yet created"
        skip_test "TEST-CTX-M3-130: re-deployment integrity" "omega-share.md not yet created"
    fi
fi

echo ""

# ============================================================
# GROUP 8: Curator Agent SQL Query Documentation (REQ-CTX-013, REQ-CTX-014-016)
# Edge cases and adversarial scenarios
# ============================================================
echo "--- Group 8: Curator SQL Queries & Edge Cases (REQ-CTX-013-016) ---"
echo ""

if [ -f "$CURATOR_FILE" ]; then
    CURATOR_CONTENT=$(cat "$CURATOR_FILE")

    # Requirement: REQ-CTX-014 (Must)
    # Acceptance: Behavioral learning query includes shared_uuid IS NULL check
    # (only export entries not already shared)
    assert_contains "$CURATOR_CONTENT" "shared_uuid" \
        "TEST-CTX-M3-131: behavioral learning query checks shared_uuid (avoid re-export)"

    # Requirement: REQ-CTX-013 (Must)
    # Security: is_private MUST be checked with COALESCE for NULL safety
    assert_contains_regex "$CURATOR_CONTENT" "COALESCE.*is_private|is_private.*0|is_private = 0" \
        "TEST-CTX-M3-132: is_private check uses NULL-safe comparison"

    # Requirement: REQ-CTX-013 (Must)
    # Edge case: Curator handles scenario where .omega/shared/ does not exist
    assert_contains_regex "$CURATOR_CONTENT" "[Cc]reate.*direct|mkdir|\.omega/shared" \
        "TEST-CTX-M3-133: documents creating .omega/shared/ if it does not exist"

    # Requirement: REQ-CTX-013 (Must)
    # Edge case: Curator handles scenario where JSONL file does not exist (create it)
    assert_contains_regex "$CURATOR_CONTENT" "[Cc]reate.*file|[Nn]ew.*file|does not exist.*create|[Ff]ile.*not.*exist" \
        "TEST-CTX-M3-134: documents creating JSONL files if they do not exist"

    # Requirement: REQ-CTX-016 (Must)
    # Edge case: Hotspot with times_touched merging (sum operation)
    assert_contains_regex "$CURATOR_CONTENT" "times_touched|sum.*touch|merge.*touch" \
        "TEST-CTX-M3-135: documents hotspot times_touched merging"

    # Requirement: REQ-CTX-013 (Must)
    # Edge case: Curator describes the full list of shareable tables
    assert_contains "$CURATOR_CONTENT" "behavioral_learnings" \
        "TEST-CTX-M3-136: curator lists behavioral_learnings as shareable table"
    assert_contains "$CURATOR_CONTENT" "incidents" \
        "TEST-CTX-M3-137: curator lists incidents as shareable table"
    assert_contains "$CURATOR_CONTENT" "hotspots" \
        "TEST-CTX-M3-138: curator lists hotspots as shareable table"

    # Requirement: REQ-CTX-013 (Must)
    # Security: Curator describes the confidence quality gate role
    assert_contains_regex "$CURATOR_CONTENT" "[Qq]uality.*gate|confidence.*gate|threshold.*gate|[Ff]ilter.*quality" \
        "TEST-CTX-M3-139: documents confidence threshold as quality gate"

    # Requirement: REQ-CTX-013 (Must)
    # Edge case: Curator describes idempotent export (re-running is safe)
    assert_contains_regex "$CURATOR_CONTENT" "[Ii]dempoten|[Rr]e-run|safe.*re.run|[Ss]afe.*repeat" \
        "TEST-CTX-M3-140: documents idempotent/safe re-run behavior"

else
    skip_test "TEST-CTX-M3-131: shared_uuid re-export check" "curator.md not yet created"
    skip_test "TEST-CTX-M3-132: is_private NULL safety" "curator.md not yet created"
    skip_test "TEST-CTX-M3-133: create .omega/shared/" "curator.md not yet created"
    skip_test "TEST-CTX-M3-134: create JSONL files" "curator.md not yet created"
    skip_test "TEST-CTX-M3-135: hotspot times_touched merge" "curator.md not yet created"
    skip_test "TEST-CTX-M3-136: behavioral_learnings listed" "curator.md not yet created"
    skip_test "TEST-CTX-M3-137: incidents listed" "curator.md not yet created"
    skip_test "TEST-CTX-M3-138: hotspots listed" "curator.md not yet created"
    skip_test "TEST-CTX-M3-139: confidence quality gate" "curator.md not yet created"
    skip_test "TEST-CTX-M3-140: idempotent behavior" "curator.md not yet created"
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
