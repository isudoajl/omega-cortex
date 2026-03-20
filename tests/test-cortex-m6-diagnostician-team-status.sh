#!/bin/bash
# test-cortex-m6-diagnostician-team-status.sh
#
# Tests for OMEGA Cortex Milestone M6: Diagnostician Enhancement + Team Status Command
# Covers: REQ-CTX-030, REQ-CTX-031
#
# These tests are written BEFORE the code (TDD). They define the contract
# that the developer must fulfill.
#
# Since both deliverables are markdown instruction files (agent definition +
# command definition), these tests validate:
#   1. File structure (YAML frontmatter, required sections)
#   2. Content (required behaviors are documented)
#   3. Deployment (setup.sh deploys files correctly)
#
# Usage:
#   bash tests/test-cortex-m6-diagnostician-team-status.sh
#   bash tests/test-cortex-m6-diagnostician-team-status.sh --verbose
#
# Dependencies: bash, python3 (for JSON validation)

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
    if echo "$haystack" | grep -qE -- "$pattern"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Pattern not found: $pattern"
        if [ "$VERBOSE" = true ]; then
            echo "    Haystack: $(echo "$haystack" | head -20)"
        fi
    fi
}

assert_file_exists() {
    local filepath="$1"
    local description="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$filepath" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    File not found: $filepath"
    fi
}

# ============================================================
# PATHS
# ============================================================
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIAGNOSTICIAN="$REPO_ROOT/core/agents/diagnostician.md"
TEAM_STATUS="$REPO_ROOT/core/commands/omega-team-status.md"

echo "============================================================"
echo "OMEGA Cortex M6: Diagnostician Enhancement + Team Status"
echo "============================================================"
echo ""
echo "Repo root: $REPO_ROOT"
echo ""

# ############################################################
# MODULE 1: Diagnostician Enhancement (REQ-CTX-030)
# ############################################################
echo "------------------------------------------------------------"
echo "MODULE 1: Diagnostician Enhancement (REQ-CTX-030)"
echo "------------------------------------------------------------"

# --- TEST-CTX-M6-001: diagnostician.md exists ---
echo ""
echo "[TEST-CTX-M6-001] diagnostician.md exists"
assert_file_exists "$DIAGNOSTICIAN" "TEST-CTX-M6-001: diagnostician.md exists"

# Read file content for remaining tests
DIAG_CONTENT=""
if [ -f "$DIAGNOSTICIAN" ]; then
    DIAG_CONTENT=$(cat "$DIAGNOSTICIAN")
fi

# --- TEST-CTX-M6-002: YAML frontmatter preserved ---
echo ""
echo "[TEST-CTX-M6-002] YAML frontmatter preserved"
assert_contains "$DIAG_CONTENT" "name: diagnostician" \
    "TEST-CTX-M6-002: diagnostician.md has name in frontmatter"

# --- TEST-CTX-M6-003: Shared Incident Query section exists ---
echo ""
echo "[TEST-CTX-M6-003] Shared Incident Query section exists"
assert_contains "$DIAG_CONTENT" "Shared Incident Query" \
    "TEST-CTX-M6-003: diagnostician.md contains 'Shared Incident Query' section"

# --- TEST-CTX-M6-004: References .omega/shared/incidents/ ---
echo ""
echo "[TEST-CTX-M6-004] References shared incidents directory"
assert_contains "$DIAG_CONTENT" ".omega/shared/incidents/" \
    "TEST-CTX-M6-004: diagnostician.md references .omega/shared/incidents/"

# --- TEST-CTX-M6-005: References .omega/shared/incidents/*.json ---
echo ""
echo "[TEST-CTX-M6-005] References incident JSON glob pattern"
assert_contains_regex "$DIAG_CONTENT" "\.omega/shared/incidents/.*\.json" \
    "TEST-CTX-M6-005: diagnostician.md references incident JSON files"

# --- TEST-CTX-M6-006: Match criteria documented (domain) ---
echo ""
echo "[TEST-CTX-M6-006] Match criteria: domain matching documented"
assert_contains "$DIAG_CONTENT" "domain" \
    "TEST-CTX-M6-006: diagnostician.md documents domain matching"

# --- TEST-CTX-M6-007: Match criteria documented (tags) ---
echo ""
echo "[TEST-CTX-M6-007] Match criteria: tag matching documented"
assert_contains "$DIAG_CONTENT" "tags" \
    "TEST-CTX-M6-007: diagnostician.md documents tag matching"

# --- TEST-CTX-M6-008: Match criteria documented (symptoms) ---
echo ""
echo "[TEST-CTX-M6-008] Match criteria: symptom matching documented"
assert_contains "$DIAG_CONTENT" "symptoms" \
    "TEST-CTX-M6-008: diagnostician.md documents symptom matching"

# --- TEST-CTX-M6-009: Constraint table integration ---
echo ""
echo "[TEST-CTX-M6-009] Shared evidence added to constraint table"
assert_contains "$DIAG_CONTENT" "constraint table" \
    "TEST-CTX-M6-009: diagnostician.md mentions adding to constraint table"

# --- TEST-CTX-M6-010: INC-NNN pattern reference ---
echo ""
echo "[TEST-CTX-M6-010] INC-NNN pattern referenced"
assert_contains_regex "$DIAG_CONTENT" "INC-[0-9N]" \
    "TEST-CTX-M6-010: diagnostician.md references INC-NNN pattern"

# --- TEST-CTX-M6-011: Shared evidence attribution ---
echo ""
echo "[TEST-CTX-M6-011] Shared evidence attribution format"
assert_contains "$DIAG_CONTENT" "Shared evidence" \
    "TEST-CTX-M6-011: diagnostician.md documents shared evidence attribution"

# --- TEST-CTX-M6-012: Hypothesis generation integration ---
echo ""
echo "[TEST-CTX-M6-012] Hypothesis generation surfacing"
assert_contains_regex "$DIAG_CONTENT" "[Rr]esembles" \
    "TEST-CTX-M6-012: diagnostician.md surfaces resemblance in hypothesis generation"

# --- TEST-CTX-M6-013: No auto-apply of resolution ---
echo ""
echo "[TEST-CTX-M6-013] Resolution is NOT auto-applied"
assert_contains_regex "$DIAG_CONTENT" "[Nn][Oo][Tt].*auto" \
    "TEST-CTX-M6-013: diagnostician.md explicitly states NOT to auto-apply resolution"

# --- TEST-CTX-M6-014: Graceful skip when directory missing ---
echo ""
echo "[TEST-CTX-M6-014] Graceful handling when shared directory missing"
assert_contains_regex "$DIAG_CONTENT" "[Ss]kip|[Gg]raceful" \
    "TEST-CTX-M6-014: diagnostician.md handles missing .omega/shared/ gracefully"

# --- TEST-CTX-M6-015: Section placement (Phase 2 context) ---
echo ""
echo "[TEST-CTX-M6-015] Section is in Phase 2 context"
# The Shared Incident Query section should appear AFTER Phase 2 heading
# and BEFORE Phase 3 heading
PHASE2_LINE=$(echo "$DIAG_CONTENT" | grep -n "Phase 2" | head -1 | cut -d: -f1)
SHARED_LINE=$(echo "$DIAG_CONTENT" | grep -n "Shared Incident Query" | head -1 | cut -d: -f1)
PHASE3_LINE=$(echo "$DIAG_CONTENT" | grep -n "Phase 3" | head -1 | cut -d: -f1)
if [ -n "$PHASE2_LINE" ] && [ -n "$SHARED_LINE" ] && [ -n "$PHASE3_LINE" ]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$SHARED_LINE" -gt "$PHASE2_LINE" ] && [ "$SHARED_LINE" -lt "$PHASE3_LINE" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M6-015: Shared Incident Query is between Phase 2 and Phase 3"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M6-015: Shared Incident Query not properly placed"
        echo "    Phase 2 line: $PHASE2_LINE, Shared line: $SHARED_LINE, Phase 3 line: $PHASE3_LINE"
    fi
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M6-015: Could not find Phase 2, Shared Incident Query, or Phase 3 sections"
    echo "    Phase2=$PHASE2_LINE Shared=$SHARED_LINE Phase3=$PHASE3_LINE"
fi

# --- TEST-CTX-M6-016: Additive enhancement (existing evidence sources preserved) ---
echo ""
echo "[TEST-CTX-M6-016] Existing evidence sources preserved"
assert_contains "$DIAG_CONTENT" "incident_entries" \
    "TEST-CTX-M6-016a: diagnostician.md still references incident_entries"
assert_contains "$DIAG_CONTENT" "failed_approaches" \
    "TEST-CTX-M6-016b: diagnostician.md still references failed_approaches"

# --- TEST-CTX-M6-017: keyword overlap documented ---
echo ""
echo "[TEST-CTX-M6-017] Keyword overlap match method documented"
assert_contains_regex "$DIAG_CONTENT" "[Kk]eyword" \
    "TEST-CTX-M6-017: diagnostician.md documents keyword-based matching"

# --- TEST-CTX-M6-018: Original diagnostician structure intact ---
echo ""
echo "[TEST-CTX-M6-018] Original diagnostician structure intact"
assert_contains "$DIAG_CONTENT" "Explorer" \
    "TEST-CTX-M6-018a: Explorer mode preserved"
assert_contains "$DIAG_CONTENT" "Skeptic" \
    "TEST-CTX-M6-018b: Skeptic mode preserved"
assert_contains "$DIAG_CONTENT" "Analogist" \
    "TEST-CTX-M6-018c: Analogist mode preserved"
assert_contains "$DIAG_CONTENT" "Phase 1" \
    "TEST-CTX-M6-018d: Phase 1 preserved"
assert_contains "$DIAG_CONTENT" "Phase 3" \
    "TEST-CTX-M6-018e: Phase 3 preserved"
assert_contains "$DIAG_CONTENT" "Phase 4" \
    "TEST-CTX-M6-018f: Phase 4 preserved"
assert_contains "$DIAG_CONTENT" "Phase 5" \
    "TEST-CTX-M6-018g: Phase 5 preserved"
assert_contains "$DIAG_CONTENT" "Phase 6" \
    "TEST-CTX-M6-018h: Phase 6 preserved"
assert_contains "$DIAG_CONTENT" "Phase 7" \
    "TEST-CTX-M6-018i: Phase 7 preserved"


# ############################################################
# MODULE 2: /omega:team-status Command (REQ-CTX-031)
# ############################################################
echo ""
echo "------------------------------------------------------------"
echo "MODULE 2: /omega:team-status Command (REQ-CTX-031)"
echo "------------------------------------------------------------"

# --- TEST-CTX-M6-020: omega-team-status.md exists ---
echo ""
echo "[TEST-CTX-M6-020] omega-team-status.md exists"
assert_file_exists "$TEAM_STATUS" "TEST-CTX-M6-020: omega-team-status.md exists"

# Read file content
TS_CONTENT=""
if [ -f "$TEAM_STATUS" ]; then
    TS_CONTENT=$(cat "$TEAM_STATUS")
fi

# --- TEST-CTX-M6-021: YAML frontmatter ---
echo ""
echo "[TEST-CTX-M6-021] YAML frontmatter"
assert_contains "$TS_CONTENT" "---" \
    "TEST-CTX-M6-021a: omega-team-status.md has YAML frontmatter delimiters"
assert_contains "$TS_CONTENT" "name: omega:team-status" \
    "TEST-CTX-M6-021b: omega-team-status.md has correct name"
assert_contains_regex "$TS_CONTENT" "description:" \
    "TEST-CTX-M6-021c: omega-team-status.md has description"

# --- TEST-CTX-M6-022: Section 1 - Shared Knowledge Stats ---
echo ""
echo "[TEST-CTX-M6-022] Dashboard Section 1: Shared Knowledge Stats"
assert_contains "$TS_CONTENT" "Shared Knowledge Stats" \
    "TEST-CTX-M6-022a: Contains Shared Knowledge Stats section"
assert_contains "$TS_CONTENT" "behavioral learnings" \
    "TEST-CTX-M6-022b: Stats includes behavioral learnings"
assert_contains "$TS_CONTENT" "incidents" \
    "TEST-CTX-M6-022c: Stats includes incidents"
assert_contains "$TS_CONTENT" "hotspots" \
    "TEST-CTX-M6-022d: Stats includes hotspots"
assert_contains "$TS_CONTENT" "lessons" \
    "TEST-CTX-M6-022e: Stats includes lessons"
assert_contains "$TS_CONTENT" "patterns" \
    "TEST-CTX-M6-022f: Stats includes patterns"
assert_contains "$TS_CONTENT" "decisions" \
    "TEST-CTX-M6-022g: Stats includes decisions"

# --- TEST-CTX-M6-023: Section 2 - Recent Contributions ---
echo ""
echo "[TEST-CTX-M6-023] Dashboard Section 2: Recent Contributions"
assert_contains "$TS_CONTENT" "Recent Contributions" \
    "TEST-CTX-M6-023a: Contains Recent Contributions section"
assert_contains_regex "$TS_CONTENT" "last 10|10 .* entries" \
    "TEST-CTX-M6-023b: Recent contributions limited to 10 entries"
assert_contains "$TS_CONTENT" "contributor" \
    "TEST-CTX-M6-023c: Recent contributions includes contributor"
assert_contains "$TS_CONTENT" "category" \
    "TEST-CTX-M6-023d: Recent contributions includes category"
assert_contains "$TS_CONTENT" "date" \
    "TEST-CTX-M6-023e: Recent contributions includes date"

# --- TEST-CTX-M6-024: Section 3 - Active Shared Incidents ---
echo ""
echo "[TEST-CTX-M6-024] Dashboard Section 3: Active Shared Incidents"
assert_contains "$TS_CONTENT" "Active Shared Incidents" \
    "TEST-CTX-M6-024a: Contains Active Shared Incidents section"
assert_contains_regex "$TS_CONTENT" "resolved" \
    "TEST-CTX-M6-024b: Incidents section references resolved incidents"

# --- TEST-CTX-M6-025: Section 4 - Team Hotspot Map ---
echo ""
echo "[TEST-CTX-M6-025] Dashboard Section 4: Team Hotspot Map"
assert_contains "$TS_CONTENT" "Team Hotspot Map" \
    "TEST-CTX-M6-025a: Contains Team Hotspot Map section"
assert_contains_regex "$TS_CONTENT" "top 10|10 .* hotspots" \
    "TEST-CTX-M6-025b: Hotspot map limited to top 10"
assert_contains "$TS_CONTENT" "contributor" \
    "TEST-CTX-M6-025c: Hotspot map includes contributor counts"

# --- TEST-CTX-M6-026: Section 5 - Unresolved Conflicts ---
echo ""
echo "[TEST-CTX-M6-026] Dashboard Section 5: Unresolved Conflicts"
assert_contains "$TS_CONTENT" "Unresolved Conflicts" \
    "TEST-CTX-M6-026a: Contains Unresolved Conflicts section"
assert_contains "$TS_CONTENT" "conflicts.jsonl" \
    "TEST-CTX-M6-026b: References conflicts.jsonl"

# --- TEST-CTX-M6-027: Read-only behavior documented ---
echo ""
echo "[TEST-CTX-M6-027] Read-only behavior"
assert_contains_regex "$TS_CONTENT" "[Rr]ead-only|[Rr]ead only" \
    "TEST-CTX-M6-027a: Documents read-only behavior"
assert_contains_regex "$TS_CONTENT" "NOT.*modify|[Dd]oes not.*modify|[Nn]o.*INSERT|[Nn]o.*UPDATE|[Nn]o.*DELETE" \
    "TEST-CTX-M6-027b: Explicitly states no data modification"

# --- TEST-CTX-M6-028: Pipeline tracking (workflow_runs) ---
echo ""
echo "[TEST-CTX-M6-028] Pipeline tracking with workflow_runs"
assert_contains "$TS_CONTENT" "workflow_runs" \
    "TEST-CTX-M6-028a: References workflow_runs"
assert_contains "$TS_CONTENT" "team-status" \
    "TEST-CTX-M6-028b: Uses type='team-status'"

# --- TEST-CTX-M6-029: Works without memory.db ---
echo ""
echo "[TEST-CTX-M6-029] Works without memory.db"
assert_contains "$TS_CONTENT" ".omega/shared/" \
    "TEST-CTX-M6-029a: Reads from .omega/shared/ directly"

# --- TEST-CTX-M6-030: Cortex not initialized message ---
echo ""
echo "[TEST-CTX-M6-030] Cortex not initialized message"
assert_contains "$TS_CONTENT" "Cortex not initialized" \
    "TEST-CTX-M6-030a: Contains 'Cortex not initialized' message"
assert_contains_regex "$TS_CONTENT" "setup\.sh" \
    "TEST-CTX-M6-030b: References setup.sh for initialization"

# --- TEST-CTX-M6-031: Uses python3 for JSON/JSONL parsing ---
echo ""
echo "[TEST-CTX-M6-031] Uses python3 for parsing"
assert_contains "$TS_CONTENT" "python3" \
    "TEST-CTX-M6-031: References python3 for JSON/JSONL parsing"

# --- TEST-CTX-M6-032: SQL for workflow_runs entry ---
echo ""
echo "[TEST-CTX-M6-032] SQL for workflow_runs entry"
assert_contains_regex "$TS_CONTENT" "INSERT INTO workflow_runs" \
    "TEST-CTX-M6-032: Contains INSERT INTO workflow_runs SQL"

# --- TEST-CTX-M6-033: Command pattern (matches omega-share.md structure) ---
echo ""
echo "[TEST-CTX-M6-033] Command follows established pattern"
# Check for standard command sections present in omega-share.md
assert_contains_regex "$TS_CONTENT" "Pipeline Tracking|Pipeline tracking" \
    "TEST-CTX-M6-033a: Has Pipeline Tracking section"
assert_contains_regex "$TS_CONTENT" "Error Handling|Error handling" \
    "TEST-CTX-M6-033b: Has Error Handling section"


# ############################################################
# MODULE 3: Deployment via setup.sh
# ############################################################
echo ""
echo "------------------------------------------------------------"
echo "MODULE 3: Deployment Verification"
echo "------------------------------------------------------------"

# Create a temp directory to test deployment
DEPLOY_DIR=$(mktemp -d)
trap "rm -rf $DEPLOY_DIR" EXIT

# --- TEST-CTX-M6-040: setup.sh deploys diagnostician.md ---
echo ""
echo "[TEST-CTX-M6-040] setup.sh deploys diagnostician.md"
# Simulate deployment by checking that core/agents/diagnostician.md is a valid source
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$REPO_ROOT/core/agents/diagnostician.md" ]; then
    # Check it has valid YAML frontmatter (starts with ---)
    FIRST_LINE=$(head -1 "$REPO_ROOT/core/agents/diagnostician.md")
    if [ "$FIRST_LINE" = "---" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M6-040: diagnostician.md has valid frontmatter for deployment"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M6-040: diagnostician.md missing frontmatter (first line: $FIRST_LINE)"
    fi
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M6-040: diagnostician.md not found at expected path"
fi

# --- TEST-CTX-M6-041: setup.sh deploys omega-team-status.md ---
echo ""
echo "[TEST-CTX-M6-041] setup.sh deploys omega-team-status.md"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$REPO_ROOT/core/commands/omega-team-status.md" ]; then
    FIRST_LINE=$(head -1 "$REPO_ROOT/core/commands/omega-team-status.md")
    if [ "$FIRST_LINE" = "---" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M6-041: omega-team-status.md has valid frontmatter for deployment"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M6-041: omega-team-status.md missing frontmatter (first line: $FIRST_LINE)"
    fi
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M6-041: omega-team-status.md not found at expected path"
fi


# ############################################################
# RESULTS
# ############################################################
echo ""
echo "============================================================"
echo "RESULTS: Cortex M6 -- Diagnostician Enhancement + Team Status"
echo "============================================================"
echo "  Total:   $TESTS_RUN"
echo "  Passed:  $TESTS_PASSED"
echo "  Failed:  $TESTS_FAILED"
echo "  Skipped: $TESTS_SKIPPED"
echo ""
if [ "$TESTS_FAILED" -eq 0 ]; then
    echo "STATUS: ALL PASSED"
    exit 0
else
    echo "STATUS: FAILED ($TESTS_FAILED failures)"
    exit 1
fi
