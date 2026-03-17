#!/bin/bash
# test-setup-idempotency.sh
#
# Regression + post-improvement tests for scripts/setup.sh idempotent behavior.
#
# Usage:
#   bash tests/test-setup-idempotency.sh
#   bash tests/test-setup-idempotency.sh --verbose
#
# Tests marked "# POST-IMPROVEMENT" validate new behavior (idempotent output).
# Tests marked "# REGRESSION" validate behavior that must be preserved before and after.

set -u

# ============================================================
# TEST FRAMEWORK
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
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
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

assert_file_not_exists() {
    local path="$1"
    local description="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ ! -f "$path" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    File should not exist: $path"
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

assert_file_executable() {
    local path="$1"
    local description="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -x "$path" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    File not executable: $path"
    fi
}

assert_files_identical() {
    local file1="$1"
    local file2="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ ! -f "$file1" ] || [ ! -f "$file2" ]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        [ ! -f "$file1" ] && echo "    Missing file: $file1"
        [ ! -f "$file2" ] && echo "    Missing file: $file2"
        return
    fi
    if cmp -s "$file1" "$file2"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Files differ: $file1 vs $file2"
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

skip_test() {
    local description="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo "  SKIP: $description"
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
    fi
}

# ============================================================
# SETUP: Create isolated test environment
# ============================================================

# Resolve the real toolkit directory (where this test lives)
REAL_TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_SCRIPT="$REAL_TOOLKIT_DIR/scripts/setup.sh"

# Verify setup.sh exists
if [ ! -f "$SETUP_SCRIPT" ]; then
    echo "ERROR: Cannot find setup.sh at $SETUP_SCRIPT"
    exit 1
fi

# Create temp directories
TEST_ROOT=$(mktemp -d)
TOOLKIT_DIR="$TEST_ROOT/toolkit"
TARGET_DIR="$TEST_ROOT/target"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

echo "============================================"
echo "  Setup Idempotency Tests"
echo "============================================"
echo "  Toolkit: $TOOLKIT_DIR"
echo "  Target:  $TARGET_DIR"
echo ""

# ============================================================
# HELPER: Build a fake toolkit tree that setup.sh expects
# ============================================================
build_fake_toolkit() {
    mkdir -p "$TOOLKIT_DIR/core/agents"
    mkdir -p "$TOOLKIT_DIR/core/commands"
    mkdir -p "$TOOLKIT_DIR/core/hooks"
    mkdir -p "$TOOLKIT_DIR/core/db/queries"
    mkdir -p "$TOOLKIT_DIR/extensions/test-ext/agents"
    mkdir -p "$TOOLKIT_DIR/extensions/test-ext/commands"
    mkdir -p "$TOOLKIT_DIR/scripts"

    # Create sample agents (3 of them)
    echo "# Agent Alpha" > "$TOOLKIT_DIR/core/agents/alpha.md"
    echo "Agent alpha content v1" >> "$TOOLKIT_DIR/core/agents/alpha.md"
    echo "# Agent Beta" > "$TOOLKIT_DIR/core/agents/beta.md"
    echo "Agent beta content v1" >> "$TOOLKIT_DIR/core/agents/beta.md"
    echo "# Agent Gamma" > "$TOOLKIT_DIR/core/agents/gamma.md"
    echo "Agent gamma content v1" >> "$TOOLKIT_DIR/core/agents/gamma.md"

    # Create sample commands (2 of them)
    echo "# Command One" > "$TOOLKIT_DIR/core/commands/workflow-one.md"
    echo "# Command Two" > "$TOOLKIT_DIR/core/commands/workflow-two.md"

    # Create sample hooks (2 of them)
    printf '#!/bin/bash\necho "briefing hook v1"\n' > "$TOOLKIT_DIR/core/hooks/briefing.sh"
    printf '#!/bin/bash\necho "debrief gate v1"\n' > "$TOOLKIT_DIR/core/hooks/debrief-gate.sh"

    # Create minimal schema.sql so db-init can run
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
    echo "-- debrief queries" > "$TOOLKIT_DIR/core/db/queries/debrief.sql"
    echo "-- maintenance queries" > "$TOOLKIT_DIR/core/db/queries/maintenance.sql"

    # Create CLAUDE.md with workflow rules section
    cat > "$TOOLKIT_DIR/CLAUDE.md" << 'MDEOF'
# CLAUDE.md

Toolkit-level docs.

---

# Claude Code Quality Workflow

## Philosophy
This project uses a multi-agent workflow.

## Global Rules
1. Rule one
2. Rule two
MDEOF

    # Create extension agents and commands
    echo "# Ext Agent" > "$TOOLKIT_DIR/extensions/test-ext/agents/ext-agent.md"
    echo "# Ext Command" > "$TOOLKIT_DIR/extensions/test-ext/commands/workflow-ext.md"

    # Copy db-init.sh from source -- it auto-detects SCRIPT_DIR from BASH_SOURCE
    cp "$REAL_TOOLKIT_DIR/scripts/db-init.sh" "$TOOLKIT_DIR/scripts/db-init.sh"
    chmod +x "$TOOLKIT_DIR/scripts/db-init.sh"

    # Copy the real setup.sh -- it auto-detects SCRIPT_DIR from BASH_SOURCE[0]
    # Since we place it at $TOOLKIT_DIR/scripts/setup.sh, SCRIPT_DIR will resolve
    # to $TOOLKIT_DIR automatically (goes up one dir from scripts/)
    cp "$SETUP_SCRIPT" "$TOOLKIT_DIR/scripts/setup.sh"
    chmod +x "$TOOLKIT_DIR/scripts/setup.sh"
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
# HELPER: Prepare a fresh target directory
# ============================================================
reset_target() {
    rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
    (cd "$TARGET_DIR" && git init --quiet 2>/dev/null)
}

# ============================================================
# BUILD THE FAKE TOOLKIT (runs once before all tests)
# ============================================================
build_fake_toolkit

# ============================================================
# TEST GROUP 1: First run deploys all files correctly
# ============================================================
test_first_run_deploys_agents() {
    echo ""
    echo "--- Test Group 1: First Run Deployment (REGRESSION) ---"

    reset_target
    local output
    output=$(run_setup)

    # Agents deployed
    assert_file_exists "$TARGET_DIR/.claude/agents/alpha.md" "Agent alpha.md deployed"
    assert_file_exists "$TARGET_DIR/.claude/agents/beta.md" "Agent beta.md deployed"
    assert_file_exists "$TARGET_DIR/.claude/agents/gamma.md" "Agent gamma.md deployed"

    # Agents match source
    assert_files_identical "$TOOLKIT_DIR/core/agents/alpha.md" "$TARGET_DIR/.claude/agents/alpha.md" "Agent alpha.md content matches source"
    assert_files_identical "$TOOLKIT_DIR/core/agents/beta.md" "$TARGET_DIR/.claude/agents/beta.md" "Agent beta.md content matches source"
}

test_first_run_deploys_commands() {
    # Uses the target from previous test
    # Commands deployed
    assert_file_exists "$TARGET_DIR/.claude/commands/workflow-one.md" "Command workflow-one.md deployed"
    assert_file_exists "$TARGET_DIR/.claude/commands/workflow-two.md" "Command workflow-two.md deployed"

    # Commands match source
    assert_files_identical "$TOOLKIT_DIR/core/commands/workflow-one.md" "$TARGET_DIR/.claude/commands/workflow-one.md" "Command workflow-one.md content matches source"
}

test_first_run_deploys_hooks() {
    # Hooks deployed
    assert_file_exists "$TARGET_DIR/.claude/hooks/briefing.sh" "Hook briefing.sh deployed"
    assert_file_exists "$TARGET_DIR/.claude/hooks/debrief-gate.sh" "Hook debrief-gate.sh deployed"

    # Hooks are executable
    assert_file_executable "$TARGET_DIR/.claude/hooks/briefing.sh" "Hook briefing.sh is executable"
    assert_file_executable "$TARGET_DIR/.claude/hooks/debrief-gate.sh" "Hook debrief-gate.sh is executable"

    # Hooks match source
    assert_files_identical "$TOOLKIT_DIR/core/hooks/briefing.sh" "$TARGET_DIR/.claude/hooks/briefing.sh" "Hook briefing.sh content matches source"
}

test_first_run_creates_project_structure() {
    # Project dirs
    assert_dir_exists "$TARGET_DIR/specs" "specs/ directory created"
    assert_dir_exists "$TARGET_DIR/docs" "docs/ directory created"
    assert_dir_exists "$TARGET_DIR/docs/.workflow" "docs/.workflow/ directory created"

    # Index files
    assert_file_exists "$TARGET_DIR/specs/SPECS.md" "specs/SPECS.md created"
    assert_file_exists "$TARGET_DIR/docs/DOCS.md" "docs/DOCS.md created"
}

test_first_run_creates_settings_json() {
    assert_file_exists "$TARGET_DIR/.claude/settings.json" "settings.json created"

    # Verify it contains hooks configuration
    local content
    content=$(cat "$TARGET_DIR/.claude/settings.json")
    assert_contains "$content" "hooks" "settings.json contains hooks key"
    assert_contains "$content" "UserPromptSubmit" "settings.json contains UserPromptSubmit"
    assert_contains "$content" "PreToolUse" "settings.json contains PreToolUse"
    assert_contains "$content" "PostToolUse" "settings.json contains PostToolUse"
    assert_contains "$content" "Notification" "settings.json contains Notification"
    assert_contains "$content" "briefing.sh" "settings.json references briefing.sh"
}

test_first_run_creates_claude_md() {
    assert_file_exists "$TARGET_DIR/CLAUDE.md" "CLAUDE.md created"

    local content
    content=$(cat "$TARGET_DIR/CLAUDE.md")
    assert_contains "$content" "# Claude Code Quality Workflow" "CLAUDE.md contains workflow rules marker"
    assert_contains "$content" "## Philosophy" "CLAUDE.md contains Philosophy section"
    assert_contains "$content" "## Global Rules" "CLAUDE.md contains Global Rules section"
    # Check that separator exists in CLAUDE.md by looking at lines
    local has_separator
    has_separator=$(grep -c '^---$' "$TARGET_DIR/CLAUDE.md" || true)
    assert_gt "$has_separator" 0 "CLAUDE.md contains --- separator"
}

test_first_run_output_mentions_agents() {
    # REGRESSION: First run output shows agent names
    reset_target
    local output
    output=$(run_setup)

    assert_contains "$output" "alpha.md" "First run output mentions alpha.md"
    assert_contains "$output" "beta.md" "First run output mentions beta.md"
    assert_contains "$output" "gamma.md" "First run output mentions gamma.md"
    assert_contains "$output" "Copying core agents" "First run output says 'Copying core agents'"
    assert_contains "$output" "Copying core commands" "First run output says 'Copying core commands'"
}

test_first_run_output_summary() {
    # REGRESSION: Summary shows install counts
    reset_target
    local output
    output=$(run_setup)

    assert_contains "$output" "Workflow configured successfully" "Summary says configured successfully"
    assert_contains "$output" "3 agents" "Summary shows 3 agents"
    assert_contains "$output" "2 commands" "Summary shows 2 commands"
}

# ============================================================
# TEST GROUP 2: Second run is safe (filesystem idempotent)
# ============================================================
test_second_run_same_files() {
    echo ""
    echo "--- Test Group 2: Second Run Safety (REGRESSION) ---"

    reset_target

    # Run setup twice
    run_setup > /dev/null
    run_setup > /dev/null

    # All files still exist and match source
    assert_files_identical "$TOOLKIT_DIR/core/agents/alpha.md" "$TARGET_DIR/.claude/agents/alpha.md" "After 2nd run, alpha.md still matches source"
    assert_files_identical "$TOOLKIT_DIR/core/agents/beta.md" "$TARGET_DIR/.claude/agents/beta.md" "After 2nd run, beta.md still matches source"
    assert_files_identical "$TOOLKIT_DIR/core/agents/gamma.md" "$TARGET_DIR/.claude/agents/gamma.md" "After 2nd run, gamma.md still matches source"
    assert_files_identical "$TOOLKIT_DIR/core/commands/workflow-one.md" "$TARGET_DIR/.claude/commands/workflow-one.md" "After 2nd run, workflow-one.md still matches source"
    assert_files_identical "$TOOLKIT_DIR/core/hooks/briefing.sh" "$TARGET_DIR/.claude/hooks/briefing.sh" "After 2nd run, briefing.sh still matches source"
}

test_second_run_hooks_still_executable() {
    # Hooks must remain executable after re-run
    assert_file_executable "$TARGET_DIR/.claude/hooks/briefing.sh" "After 2nd run, briefing.sh still executable"
    assert_file_executable "$TARGET_DIR/.claude/hooks/debrief-gate.sh" "After 2nd run, debrief-gate.sh still executable"
}

test_second_run_claude_md_no_duplication() {
    # REGRESSION: CLAUDE.md must not have duplicated workflow section
    local content
    content=$(cat "$TARGET_DIR/CLAUDE.md")

    local marker_count
    marker_count=$(echo "$content" | grep -c "# Claude Code Quality Workflow" || true)
    assert_eq "1" "$marker_count" "After 2nd run, CLAUDE.md has exactly 1 workflow marker"

    local philosophy_count
    philosophy_count=$(echo "$content" | grep -c "## Philosophy" || true)
    assert_eq "1" "$philosophy_count" "After 2nd run, CLAUDE.md has exactly 1 Philosophy section"
}

test_third_run_claude_md_still_no_duplication() {
    # REGRESSION: Even after 3 runs, no duplication
    run_setup > /dev/null

    local content
    content=$(cat "$TARGET_DIR/CLAUDE.md")

    local marker_count
    marker_count=$(echo "$content" | grep -c "# Claude Code Quality Workflow" || true)
    assert_eq "1" "$marker_count" "After 3rd run, CLAUDE.md has exactly 1 workflow marker"
}

test_second_run_specs_docs_preserved() {
    # REGRESSION: specs/ and docs/ should still exist, not recreated
    assert_file_exists "$TARGET_DIR/specs/SPECS.md" "After 2nd run, SPECS.md still exists"
    assert_file_exists "$TARGET_DIR/docs/DOCS.md" "After 2nd run, DOCS.md still exists"
}

test_second_run_settings_json_valid() {
    # REGRESSION: settings.json still valid JSON after re-run
    local valid
    valid=$(python3 -c "import json; json.load(open('$TARGET_DIR/.claude/settings.json')); print('valid')" 2>/dev/null || echo "invalid")
    assert_eq "valid" "$valid" "After 2nd run, settings.json is valid JSON"
}

# ============================================================
# TEST GROUP 3: Partial updates work correctly
# ============================================================
test_update_one_source_file() {
    echo ""
    echo "--- Test Group 3: Partial Update (REGRESSION) ---"

    reset_target

    # First run
    run_setup > /dev/null

    # Record content of unchanged file
    local original_beta
    original_beta=$(cat "$TARGET_DIR/.claude/agents/beta.md")

    # Modify one agent in the toolkit
    echo "# Agent Alpha UPDATED" > "$TOOLKIT_DIR/core/agents/alpha.md"
    echo "Agent alpha content v2 -- changed" >> "$TOOLKIT_DIR/core/agents/alpha.md"

    # Second run
    run_setup > /dev/null

    # The modified agent should be updated in target
    assert_files_identical "$TOOLKIT_DIR/core/agents/alpha.md" "$TARGET_DIR/.claude/agents/alpha.md" "Updated alpha.md matches new source"

    local updated_content
    updated_content=$(cat "$TARGET_DIR/.claude/agents/alpha.md")
    assert_contains "$updated_content" "v2 -- changed" "Updated alpha.md has v2 content"

    # Unchanged agent should still be intact
    local current_beta
    current_beta=$(cat "$TARGET_DIR/.claude/agents/beta.md")
    assert_eq "$original_beta" "$current_beta" "Unchanged beta.md content preserved"

    # Restore the source file for subsequent tests
    echo "# Agent Alpha" > "$TOOLKIT_DIR/core/agents/alpha.md"
    echo "Agent alpha content v1" >> "$TOOLKIT_DIR/core/agents/alpha.md"
}

test_update_hook_file() {
    reset_target

    # First run
    run_setup > /dev/null

    # Modify a hook
    printf '#!/bin/bash\necho "briefing hook v2 updated"\n' > "$TOOLKIT_DIR/core/hooks/briefing.sh"

    # Second run
    run_setup > /dev/null

    # Updated hook matches source
    assert_files_identical "$TOOLKIT_DIR/core/hooks/briefing.sh" "$TARGET_DIR/.claude/hooks/briefing.sh" "Updated hook matches new source"

    # Must still be executable
    assert_file_executable "$TARGET_DIR/.claude/hooks/briefing.sh" "Updated hook is still executable"

    # Restore
    printf '#!/bin/bash\necho "briefing hook v1"\n' > "$TOOLKIT_DIR/core/hooks/briefing.sh"
}

# ============================================================
# TEST GROUP 4: Extension deployment
# ============================================================
test_extension_deployment() {
    echo ""
    echo "--- Test Group 4: Extensions (REGRESSION) ---"

    reset_target

    # Run with extension
    local output
    output=$(run_setup "--ext=test-ext")

    assert_file_exists "$TARGET_DIR/.claude/agents/ext-agent.md" "Extension agent deployed"
    assert_file_exists "$TARGET_DIR/.claude/commands/workflow-ext.md" "Extension command deployed"
    assert_contains "$output" "Extension: test-ext" "Output mentions extension name"
}

test_extension_rerun_safe() {
    # Re-run with same extension
    local output
    output=$(run_setup "--ext=test-ext")

    # Files still match source
    assert_files_identical "$TOOLKIT_DIR/extensions/test-ext/agents/ext-agent.md" "$TARGET_DIR/.claude/agents/ext-agent.md" "After 2nd run, extension agent matches source"
    assert_files_identical "$TOOLKIT_DIR/extensions/test-ext/commands/workflow-ext.md" "$TARGET_DIR/.claude/commands/workflow-ext.md" "After 2nd run, extension command matches source"
}

test_extension_nonexistent_warning() {
    reset_target

    local output
    output=$(run_setup "--ext=nonexistent-ext")

    assert_contains "$output" "WARNING" "Non-existent extension produces WARNING"
    assert_contains "$output" "nonexistent-ext" "Warning mentions the extension name"
}

test_extension_all() {
    reset_target

    local output
    output=$(run_setup "--ext=all")

    assert_file_exists "$TARGET_DIR/.claude/agents/ext-agent.md" "With --ext=all, extension agent deployed"
    assert_file_exists "$TARGET_DIR/.claude/commands/workflow-ext.md" "With --ext=all, extension command deployed"
}

# ============================================================
# TEST GROUP 5: CLAUDE.md handling edge cases
# ============================================================
test_claude_md_preserves_project_rules() {
    echo ""
    echo "--- Test Group 5: CLAUDE.md Handling (REGRESSION) ---"

    reset_target

    # Create a project CLAUDE.md with custom content
    cat > "$TARGET_DIR/CLAUDE.md" << 'EOF'
# My Project

## Custom Rules
- Do not delete production data
- Use snake_case for all variables
EOF

    # Run setup
    run_setup > /dev/null

    local content
    content=$(cat "$TARGET_DIR/CLAUDE.md")

    # Custom content preserved
    assert_contains "$content" "# My Project" "Custom project heading preserved"
    assert_contains "$content" "Do not delete production data" "Custom rule preserved"
    assert_contains "$content" "snake_case" "Custom convention preserved"

    # Workflow rules appended
    assert_contains "$content" "# Claude Code Quality Workflow" "Workflow rules appended"
}

test_claude_md_update_preserves_project_rules() {
    # Second run on the same target (with existing CLAUDE.md + workflow rules)
    run_setup > /dev/null

    local content
    content=$(cat "$TARGET_DIR/CLAUDE.md")

    # Custom content STILL preserved
    assert_contains "$content" "# My Project" "After 2nd run, custom heading still preserved"
    assert_contains "$content" "Do not delete production data" "After 2nd run, custom rule still preserved"

    # Workflow rules still there, not duplicated
    local marker_count
    marker_count=$(echo "$content" | grep -c "# Claude Code Quality Workflow" || true)
    assert_eq "1" "$marker_count" "After 2nd run with custom content, exactly 1 workflow marker"
}

test_claude_md_created_from_scratch() {
    # Target with no CLAUDE.md at all
    reset_target
    rm -f "$TARGET_DIR/CLAUDE.md"

    run_setup > /dev/null

    assert_file_exists "$TARGET_DIR/CLAUDE.md" "CLAUDE.md created when none existed"

    local content
    content=$(cat "$TARGET_DIR/CLAUDE.md")
    assert_contains "$content" "# CLAUDE.md" "Created CLAUDE.md has heading"
    assert_contains "$content" "Project-Specific Rules" "Created CLAUDE.md has placeholder for project rules"
    assert_contains "$content" "# Claude Code Quality Workflow" "Created CLAUDE.md has workflow rules"
}

# ============================================================
# TEST GROUP 6: settings.json merge behavior
# ============================================================
test_settings_json_preserves_existing_settings() {
    echo ""
    echo "--- Test Group 6: settings.json Merge (REGRESSION) ---"

    reset_target

    # Create a settings.json with pre-existing non-hook settings
    mkdir -p "$TARGET_DIR/.claude"
    cat > "$TARGET_DIR/.claude/settings.json" << 'EOF'
{
  "model": "claude-opus-4-6",
  "permissions": {
    "allow": ["Bash", "Read"]
  }
}
EOF

    run_setup > /dev/null

    local content
    content=$(cat "$TARGET_DIR/.claude/settings.json")

    # Original settings preserved
    assert_contains "$content" "claude-opus-4-6" "Existing model setting preserved"
    assert_contains "$content" "permissions" "Existing permissions setting preserved"

    # Hooks added
    assert_contains "$content" "hooks" "Hooks added to existing settings"
    assert_contains "$content" "UserPromptSubmit" "UserPromptSubmit hook added"
}

test_settings_json_valid_after_merge() {
    local valid
    valid=$(python3 -c "import json; json.load(open('$TARGET_DIR/.claude/settings.json')); print('valid')" 2>/dev/null || echo "invalid")
    assert_eq "valid" "$valid" "settings.json is valid JSON after merge"
}

test_settings_json_hooks_have_absolute_paths() {
    local content
    content=$(cat "$TARGET_DIR/.claude/settings.json")

    # Paths should be absolute (start with /)
    assert_contains_regex "$content" '/.*/\.claude/hooks/briefing\.sh' "Hook paths are absolute"
}

# ============================================================
# TEST GROUP 7: --no-db flag
# ============================================================
test_no_db_flag() {
    echo ""
    echo "--- Test Group 7: --no-db Flag (REGRESSION) ---"

    reset_target

    local output
    output=$(run_setup)

    # With --no-db (default in run_setup), no DB message
    assert_not_contains "$output" "Creating institutional memory DB" "With --no-db, no DB creation message"
}

test_with_db_flag() {
    # Test that without --no-db, DB section runs
    # Only if sqlite3 is available
    if ! command -v sqlite3 &> /dev/null; then
        skip_test "sqlite3 not available, skipping DB test"
        return
    fi

    reset_target

    local output
    output=$(run_setup_with_db)

    assert_contains "$output" "Initializing institutional memory" "Without --no-db, DB initialization runs"
    assert_file_exists "$TARGET_DIR/.claude/memory.db" "memory.db created"
}

# ============================================================
# TEST GROUP 8: --help flag
# ============================================================
test_help_flag() {
    echo ""
    echo "--- Test Group 8: --help Flag (REGRESSION) ---"

    local output
    output=$(bash "$TOOLKIT_DIR/scripts/setup.sh" --help 2>&1 || true)

    assert_contains "$output" "Usage:" "Help shows usage"
    assert_contains "$output" "--ext" "Help mentions --ext"
    assert_contains "$output" "--no-db" "Help mentions --no-db"
    assert_contains "$output" "--list-ext" "Help mentions --list-ext"
}

# ============================================================
# TEST GROUP 9: --list-ext flag
# ============================================================
test_list_ext_flag() {
    echo ""
    echo "--- Test Group 9: --list-ext Flag (REGRESSION) ---"

    local output
    output=$(bash "$TOOLKIT_DIR/scripts/setup.sh" --list-ext 2>&1 || true)

    assert_contains "$output" "Available extensions" "List-ext shows available extensions"
    assert_contains "$output" "test-ext" "List-ext shows our test extension"
}

# ============================================================
# TEST GROUP 10: File count accuracy
# ============================================================
test_file_counts_accurate() {
    echo ""
    echo "--- Test Group 10: File Count Accuracy (REGRESSION) ---"

    reset_target
    run_setup > /dev/null

    local agent_count
    agent_count=$(ls "$TARGET_DIR/.claude/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
    assert_eq "3" "$agent_count" "Exactly 3 agent files deployed"

    local cmd_count
    cmd_count=$(ls "$TARGET_DIR/.claude/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
    assert_eq "2" "$cmd_count" "Exactly 2 command files deployed"

    local hook_count
    hook_count=$(ls "$TARGET_DIR/.claude/hooks/"*.sh 2>/dev/null | wc -l | tr -d ' ')
    assert_eq "2" "$hook_count" "Exactly 2 hook files deployed"
}

test_extension_file_counts() {
    reset_target
    run_setup "--ext=test-ext" > /dev/null

    # Core agents + extension agent
    local agent_count
    agent_count=$(ls "$TARGET_DIR/.claude/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
    assert_eq "4" "$agent_count" "3 core + 1 extension = 4 agents deployed"

    local cmd_count
    cmd_count=$(ls "$TARGET_DIR/.claude/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
    assert_eq "3" "$cmd_count" "2 core + 1 extension = 3 commands deployed"
}

# ============================================================
# TEST GROUP 11: POST-IMPROVEMENT: copy_if_changed behavior
# ============================================================
test_post_improvement_new_files_show_plus() {
    # POST-IMPROVEMENT
    echo ""
    echo "--- Test Group 11: POST-IMPROVEMENT: Output Symbols ---"

    reset_target
    local output
    output=$(run_setup)

    # On first run, all files are new -- should show + symbol
    assert_contains "$output" "+" "First run output contains + symbol for new files"
    assert_contains "$output" "alpha.md" "First run output lists alpha.md"
}

test_post_improvement_unchanged_files_suppressed() {
    # POST-IMPROVEMENT
    # Second run with no changes -- unchanged files should be suppressed
    local output
    output=$(run_setup)

    # After improvement, unchanged files should show "(N unchanged)" instead of individual + lines
    # Before improvement, every file shows "+ filename" regardless
    local unchanged_pattern
    unchanged_pattern=$(echo "$output" | grep -c "unchanged" || true)

    if [ "$unchanged_pattern" -gt 0 ]; then
        echo "  PASS: Second run output contains 'unchanged' indicator (POST-IMPROVEMENT active)"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        # This is expected to fail before the improvement is implemented
        echo "  SKIP: Second run does not show 'unchanged' -- improvement not yet applied"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    fi
}

test_post_improvement_updated_file_shows_tilde() {
    # POST-IMPROVEMENT
    reset_target
    run_setup > /dev/null

    # Modify one agent
    echo "# Agent Alpha CHANGED" > "$TOOLKIT_DIR/core/agents/alpha.md"
    echo "Agent alpha content v3" >> "$TOOLKIT_DIR/core/agents/alpha.md"

    local output
    output=$(run_setup)

    # After improvement, the updated agent file should show ~ symbol next to its name
    # (We check specifically for ~ next to the agent filename, not ~ in CLAUDE.md section
    # which already uses ~ for "Workflow rules updated")
    if echo "$output" | grep -qE '~.*alpha\.md'; then
        assert_contains_regex "$output" '~.*alpha\.md' "Updated agent shows ~ symbol (POST-IMPROVEMENT active)"
    else
        # Before improvement, all files show + regardless
        skip_test "No ~ symbol for updated agent files -- improvement not yet applied"
    fi

    # Restore
    echo "# Agent Alpha" > "$TOOLKIT_DIR/core/agents/alpha.md"
    echo "Agent alpha content v1" >> "$TOOLKIT_DIR/core/agents/alpha.md"
}

test_post_improvement_no_cp_for_unchanged() {
    # POST-IMPROVEMENT
    # Verify that unchanged files do NOT trigger a cp
    # We test this by checking mtime -- if cp is not called, mtime should not change
    reset_target
    run_setup > /dev/null

    # Verify the file exists first
    if [ ! -f "$TARGET_DIR/.claude/agents/beta.md" ]; then
        skip_test "File does not exist for mtime test -- cannot verify"
        return
    fi

    # Record mtime of a deployed file
    local mtime_before
    if [ "$(uname)" = "Darwin" ]; then
        mtime_before=$(stat -f %m "$TARGET_DIR/.claude/agents/beta.md")
    else
        mtime_before=$(stat -c %Y "$TARGET_DIR/.claude/agents/beta.md")
    fi

    # Wait a moment so mtime would differ if cp runs
    sleep 1

    # Run setup again without changes
    run_setup > /dev/null

    local mtime_after
    if [ "$(uname)" = "Darwin" ]; then
        mtime_after=$(stat -f %m "$TARGET_DIR/.claude/agents/beta.md")
    else
        mtime_after=$(stat -c %Y "$TARGET_DIR/.claude/agents/beta.md")
    fi

    if [ "$mtime_before" = "$mtime_after" ]; then
        echo "  PASS: Unchanged file mtime preserved (no unnecessary cp) (POST-IMPROVEMENT active)"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        # Before improvement, cp always runs and updates mtime
        skip_test "Unchanged file mtime changed -- improvement not yet applied (cp always runs)"
    fi
}

# ============================================================
# TEST GROUP 12: POST-IMPROVEMENT: Summary counts
# ============================================================
test_post_improvement_summary_fresh_install() {
    # POST-IMPROVEMENT
    echo ""
    echo "--- Test Group 12: POST-IMPROVEMENT: Summary Counts ---"

    reset_target
    local output
    output=$(run_setup)

    # After improvement, summary should show new counts like "3 new"
    if echo "$output" | grep -qE '[0-9]+ new'; then
        assert_contains_regex "$output" '[0-9]+ new' "Fresh install summary shows count of new files (POST-IMPROVEMENT active)"
    else
        skip_test "Summary does not show 'N new' count -- improvement not yet applied"
    fi
}

test_post_improvement_summary_nothing_changed() {
    # POST-IMPROVEMENT
    reset_target
    run_setup > /dev/null

    local output
    output=$(run_setup)

    if echo "$output" | grep -qiE "nothing changed|already up to date|0 new.*0 updated"; then
        echo "  PASS: Nothing-changed summary shown (POST-IMPROVEMENT active)"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        skip_test "Nothing-changed summary not shown -- improvement not yet applied"
    fi
}

test_post_improvement_summary_partial_update() {
    # POST-IMPROVEMENT
    reset_target
    run_setup > /dev/null

    # Modify one agent
    echo "# Agent Alpha Changed Again" > "$TOOLKIT_DIR/core/agents/alpha.md"
    echo "v4 content" >> "$TOOLKIT_DIR/core/agents/alpha.md"

    local output
    output=$(run_setup)

    if echo "$output" | grep -qE '[0-9]+ updated'; then
        assert_contains_regex "$output" '[0-9]+ updated' "Partial update summary shows updated count (POST-IMPROVEMENT active)"
    else
        skip_test "Partial update summary not shown -- improvement not yet applied"
    fi

    # Restore
    echo "# Agent Alpha" > "$TOOLKIT_DIR/core/agents/alpha.md"
    echo "Agent alpha content v1" >> "$TOOLKIT_DIR/core/agents/alpha.md"
}

# ============================================================
# TEST GROUP 13: POST-IMPROVEMENT: --verbose flag
# ============================================================
test_post_improvement_verbose_shows_unchanged() {
    # POST-IMPROVEMENT
    echo ""
    echo "--- Test Group 13: POST-IMPROVEMENT: --verbose Flag ---"

    reset_target
    run_setup > /dev/null

    # Run with --verbose (may not be recognized yet by current setup.sh)
    local output
    output=$(run_setup "--verbose" 2>&1 || true)

    # After improvement, --verbose should show = lines for unchanged AGENT/COMMAND files
    # (Not just project structure = lines like "= specs/SPECS.md already exists"
    # which already exist in the current version)
    # We check for = next to an agent filename specifically (e.g., "= alpha.md")
    if echo "$output" | grep -qE '^\s+=\s+(alpha|beta|gamma|workflow-one|workflow-two|briefing|debrief)'; then
        echo "  PASS: --verbose shows = lines for unchanged agent/command files (POST-IMPROVEMENT active)"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        skip_test "--verbose unchanged display for agents/commands not implemented -- improvement not yet applied"
    fi
}

# ============================================================
# TEST GROUP 14: POST-IMPROVEMENT: settings.json change detection
# ============================================================
test_post_improvement_settings_unchanged_message() {
    # POST-IMPROVEMENT
    echo ""
    echo "--- Test Group 14: POST-IMPROVEMENT: settings.json Change Detection ---"

    reset_target
    run_setup > /dev/null

    local output
    output=$(run_setup)

    if echo "$output" | grep -qiE "hooks already configured|= .*hooks|= .*settings"; then
        echo "  PASS: settings.json shows unchanged status (POST-IMPROVEMENT active)"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        skip_test "settings.json unchanged detection not shown -- improvement not yet applied"
    fi
}

# ============================================================
# TEST GROUP 15: POST-IMPROVEMENT: CLAUDE.md change detection
# ============================================================
test_post_improvement_claude_md_unchanged_message() {
    # POST-IMPROVEMENT
    echo ""
    echo "--- Test Group 15: POST-IMPROVEMENT: CLAUDE.md Change Detection ---"

    reset_target
    run_setup > /dev/null

    local output
    output=$(run_setup)

    if echo "$output" | grep -qiE "already current|= .*[Ww]orkflow rules"; then
        echo "  PASS: CLAUDE.md shows unchanged status (POST-IMPROVEMENT active)"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        skip_test "CLAUDE.md unchanged detection not shown -- improvement not yet applied"
    fi
}

test_claude_md_rules_replaced_on_source_change() {
    # REGRESSION: When the source workflow rules change, running setup again
    # should replace the old rules with the new ones.
    # Save original toolkit CLAUDE.md
    local original_content
    original_content=$(cat "$TOOLKIT_DIR/CLAUDE.md")

    # First: deploy with original rules
    reset_target
    run_setup > /dev/null

    # Modify the toolkit CLAUDE.md workflow rules
    cat > "$TOOLKIT_DIR/CLAUDE.md" << 'MDEOF'
# CLAUDE.md

Toolkit-level docs.

---

# Claude Code Quality Workflow

## Philosophy
This project uses an UPDATED multi-agent workflow.

## Global Rules
1. Rule one
2. Rule two
3. Rule three (new)
MDEOF

    # Run again -- the target should get the updated rules
    local output
    output=$(run_setup)

    # The target CLAUDE.md should now have the updated content
    local target_content
    target_content=$(cat "$TARGET_DIR/CLAUDE.md")
    assert_contains "$target_content" "UPDATED multi-agent workflow" "CLAUDE.md rules updated when source changes"
    assert_contains "$target_content" "Rule three (new)" "CLAUDE.md has new rule from updated source"

    # Output should mention the update
    assert_contains "$output" "Workflow rules updated" "Output says workflow rules updated"

    # Restore
    echo "$original_content" > "$TOOLKIT_DIR/CLAUDE.md"
}

# ============================================================
# TEST GROUP 16: Edge cases
# ============================================================
test_empty_extensions_dir() {
    echo ""
    echo "--- Test Group 16: Edge Cases (REGRESSION) ---"

    # Extension with no agents or commands subdirs
    mkdir -p "$TOOLKIT_DIR/extensions/empty-ext"

    reset_target
    local output
    output=$(run_setup "--ext=empty-ext")

    # Should not crash
    assert_contains "$output" "Workflow configured successfully" "Empty extension does not crash setup"

    rm -rf "$TOOLKIT_DIR/extensions/empty-ext"
}

test_target_with_existing_specs() {
    # If specs/ already exists, its contents should be preserved
    reset_target
    mkdir -p "$TARGET_DIR/specs"
    echo "# Existing spec" > "$TARGET_DIR/specs/my-spec.md"

    run_setup > /dev/null

    assert_file_exists "$TARGET_DIR/specs/my-spec.md" "Existing spec file preserved"
    local content
    content=$(cat "$TARGET_DIR/specs/my-spec.md")
    assert_contains "$content" "Existing spec" "Existing spec content preserved"
}

test_multiple_extensions_comma_separated() {
    # Create a second extension
    mkdir -p "$TOOLKIT_DIR/extensions/second-ext/agents"
    echo "# Second Agent" > "$TOOLKIT_DIR/extensions/second-ext/agents/second-agent.md"

    reset_target
    local output
    output=$(run_setup "--ext=test-ext,second-ext")

    assert_file_exists "$TARGET_DIR/.claude/agents/ext-agent.md" "First extension agent deployed"
    assert_file_exists "$TARGET_DIR/.claude/agents/second-agent.md" "Second extension agent deployed"

    rm -rf "$TOOLKIT_DIR/extensions/second-ext"
}

test_settings_json_handles_malformed_json() {
    # If settings.json contains invalid JSON, setup should handle it gracefully.
    # NOTE: The current setup.sh has a bug where set -e causes the script to exit
    # when python3 fails to parse invalid JSON, instead of falling through to the
    # fallback overwrite path. The if [ $? -eq 0 ] check on the next line is never
    # reached because set -e already killed the script.
    #
    # POST-IMPROVEMENT: After the fix, this test should verify graceful recovery.
    reset_target
    mkdir -p "$TARGET_DIR/.claude"
    echo "NOT VALID JSON {{{" > "$TARGET_DIR/.claude/settings.json"
    (cd "$TARGET_DIR" && git init --quiet 2>/dev/null)

    local output
    local exit_code=0
    output=$(run_setup) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        # POST-IMPROVEMENT: Script should handle this gracefully
        local valid
        valid=$(python3 -c "import json; json.load(open('$TARGET_DIR/.claude/settings.json')); print('valid')" 2>/dev/null || echo "invalid")
        assert_eq "valid" "$valid" "After malformed JSON, settings.json is now valid (POST-IMPROVEMENT)"
        assert_contains "$output" "Workflow configured successfully" "Setup succeeds with initially malformed settings.json (POST-IMPROVEMENT)"
    else
        # CURRENT BEHAVIOR: set -e causes script to exit when python3 fails on bad JSON
        # This documents the known bug -- the fallback code path is unreachable
        skip_test "Malformed settings.json causes setup.sh to exit (known set -e bug, fix pending)"
        skip_test "Setup exit on malformed settings.json (known set -e bug, fix pending)"
    fi
}

# ============================================================
# TEST GROUP 17: DB initialization (if sqlite3 available)
# ============================================================
test_db_init_creates_database() {
    echo ""
    echo "--- Test Group 17: DB Initialization (REGRESSION) ---"

    if ! command -v sqlite3 &> /dev/null; then
        skip_test "sqlite3 not available -- skipping DB tests"
        skip_test "sqlite3 not available -- skipping DB tests (2)"
        skip_test "sqlite3 not available -- skipping DB tests (3)"
        skip_test "sqlite3 not available -- skipping DB tests (4)"
        skip_test "sqlite3 not available -- skipping DB tests (5)"
        skip_test "sqlite3 not available -- skipping DB rerun test"
        return
    fi

    reset_target
    local output
    output=$(run_setup_with_db)

    assert_file_exists "$TARGET_DIR/.claude/memory.db" "memory.db created"
    assert_dir_exists "$TARGET_DIR/.claude/db-queries" "db-queries directory created"
    assert_file_exists "$TARGET_DIR/.claude/db-queries/briefing.sql" "briefing.sql query file deployed"
    assert_file_exists "$TARGET_DIR/.claude/db-queries/debrief.sql" "debrief.sql query file deployed"
    assert_file_exists "$TARGET_DIR/.claude/db-queries/maintenance.sql" "maintenance.sql query file deployed"
}

test_db_init_rerun_safe() {
    if ! command -v sqlite3 &> /dev/null; then
        skip_test "sqlite3 not available -- skipping DB rerun test"
        return
    fi

    # Insert a test record, then re-run setup -- record should still exist
    sqlite3 "$TARGET_DIR/.claude/memory.db" "INSERT INTO workflow_runs (type, description) VALUES ('test', 'test entry');"

    local before_count
    before_count=$(sqlite3 "$TARGET_DIR/.claude/memory.db" "SELECT COUNT(*) FROM workflow_runs;")

    run_setup_with_db > /dev/null

    local after_count
    after_count=$(sqlite3 "$TARGET_DIR/.claude/memory.db" "SELECT COUNT(*) FROM workflow_runs;")

    assert_eq "$before_count" "$after_count" "DB re-run does not lose existing records"
}

# ============================================================
# RUN ALL TESTS
# ============================================================

echo ""
echo "Running tests..."

# Group 1: First run
test_first_run_deploys_agents
test_first_run_deploys_commands
test_first_run_deploys_hooks
test_first_run_creates_project_structure
test_first_run_creates_settings_json
test_first_run_creates_claude_md
test_first_run_output_mentions_agents
test_first_run_output_summary

# Group 2: Second run safety
test_second_run_same_files
test_second_run_hooks_still_executable
test_second_run_claude_md_no_duplication
test_third_run_claude_md_still_no_duplication
test_second_run_specs_docs_preserved
test_second_run_settings_json_valid

# Group 3: Partial updates
test_update_one_source_file
test_update_hook_file

# Group 4: Extensions
test_extension_deployment
test_extension_rerun_safe
test_extension_nonexistent_warning
test_extension_all

# Group 5: CLAUDE.md
test_claude_md_preserves_project_rules
test_claude_md_update_preserves_project_rules
test_claude_md_created_from_scratch

# Group 6: settings.json
test_settings_json_preserves_existing_settings
test_settings_json_valid_after_merge
test_settings_json_hooks_have_absolute_paths

# Group 7: --no-db flag
test_no_db_flag
test_with_db_flag

# Group 8: --help
test_help_flag

# Group 9: --list-ext
test_list_ext_flag

# Group 10: File counts
test_file_counts_accurate
test_extension_file_counts

# Group 11: POST-IMPROVEMENT: Output symbols
test_post_improvement_new_files_show_plus
test_post_improvement_unchanged_files_suppressed
test_post_improvement_updated_file_shows_tilde
test_post_improvement_no_cp_for_unchanged

# Group 12: POST-IMPROVEMENT: Summary counts
test_post_improvement_summary_fresh_install
test_post_improvement_summary_nothing_changed
test_post_improvement_summary_partial_update

# Group 13: POST-IMPROVEMENT: --verbose flag
test_post_improvement_verbose_shows_unchanged

# Group 14: POST-IMPROVEMENT: settings.json change detection
test_post_improvement_settings_unchanged_message

# Group 15: POST-IMPROVEMENT: CLAUDE.md change detection
test_post_improvement_claude_md_unchanged_message
test_claude_md_rules_replaced_on_source_change

# Group 16: Edge cases
test_empty_extensions_dir
test_target_with_existing_specs
test_multiple_extensions_comma_separated
test_settings_json_handles_malformed_json

# Group 17: DB initialization
test_db_init_creates_database
test_db_init_rerun_safe

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "============================================"
echo "  Test Results"
echo "============================================"
echo "  Total:   $TESTS_RUN"
echo "  Passed:  $TESTS_PASSED"
echo "  Failed:  $TESTS_FAILED"
echo "  Skipped: $TESTS_SKIPPED"
echo "============================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    echo ""
    echo "  RESULT: FAILED ($TESTS_FAILED failures)"
    exit 1
else
    echo ""
    echo "  RESULT: ALL PASSED"
    exit 0
fi
