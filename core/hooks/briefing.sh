#!/bin/bash
# ============================================================
# OMEGA SESSION BRIEFING — UserPromptSubmit hook
# Injects behavioral learnings + key context into Claude Code
# sessions. Fires ONCE per session (tracked by session_id).
#
# Philosophy: Session start = make Claude smarter.
# Only inject what changes HOW Claude thinks and works.
# Bug details, hotspots, outcomes = on-demand agent queries.
# ============================================================

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DB_PATH="$PROJECT_DIR/.claude/memory.db"
BRIEFING_FLAG="$PROJECT_DIR/.claude/hooks/.briefing_done"

# Read session_id from stdin JSON to detect new sessions
INPUT=$(cat)
CURRENT_SESSION=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || echo "")

# Only brief once per session — skip if same session already briefed
if [ -f "$BRIEFING_FLAG" ]; then
    STORED_DATA=$(cat "$BRIEFING_FLAG" 2>/dev/null || echo "")
    STORED_SESSION=$(echo "$STORED_DATA" | cut -d'|' -f1)
    if [ "$CURRENT_SESSION" = "$STORED_SESSION" ] && [ -n "$CURRENT_SESSION" ]; then
        exit 0
    fi
fi

# New session — store session_id and timestamp, proceed with briefing
mkdir -p "$(dirname "$BRIEFING_FLAG")"
BRIEFING_TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S")
echo "${CURRENT_SESSION}|${BRIEFING_TIMESTAMP}" > "$BRIEFING_FLAG"

# Graceful exit if no DB
if [ ! -f "$DB_PATH" ]; then
    exit 0
fi

# Helper: run query, suppress errors, return empty on failure
query() {
    sqlite3 -header -column "$DB_PATH" "$1" 2>/dev/null || true
}

# Helper: run query and check if it returned results
query_has_results() {
    local result
    result=$(sqlite3 "$DB_PATH" "$1" 2>/dev/null || true)
    if [ -n "$result" ]; then
        return 0
    else
        return 1
    fi
}

# Helper: check if a table exists (for backward compatibility)
table_exists() {
    local result
    result=$(sqlite3 "$DB_PATH" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='$1' LIMIT 1;" 2>/dev/null || true)
    [ -n "$result" ]
}

echo "╔══════════════════════════════════════════════════════════╗"
echo "║              OMEGA SESSION BRIEFING                     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# --- OMEGA IDENTITY ---
PROFILE_TABLE_EXISTS=$(sqlite3 "$DB_PATH" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='user_profile' LIMIT 1;" 2>/dev/null || true)

if [ -n "$PROFILE_TABLE_EXISTS" ]; then
    PROFILE_ROW=$(sqlite3 -separator '|' "$DB_PATH" "SELECT user_name, experience_level, communication_style FROM user_profile LIMIT 1;" 2>/dev/null || true)

    if [ -n "$PROFILE_ROW" ]; then
        USER_NAME=$(echo "$PROFILE_ROW" | cut -d'|' -f1)
        EXP_LEVEL=$(echo "$PROFILE_ROW" | cut -d'|' -f2)
        COMM_STYLE=$(echo "$PROFILE_ROW" | cut -d'|' -f3)

        # Experience auto-upgrade (fire-and-forget)
        COMPLETED_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM workflow_runs WHERE status='completed';" 2>/dev/null || echo "0")
        if [ "$EXP_LEVEL" = "intermediate" ] && [ "$COMPLETED_COUNT" -ge 30 ] 2>/dev/null; then
            sqlite3 "$DB_PATH" "UPDATE user_profile SET experience_level='advanced';" 2>/dev/null || true
            EXP_LEVEL="advanced"
        elif [ "$EXP_LEVEL" = "beginner" ] && [ "$COMPLETED_COUNT" -ge 10 ] 2>/dev/null; then
            sqlite3 "$DB_PATH" "UPDATE user_profile SET experience_level='intermediate';" 2>/dev/null || true
            EXP_LEVEL="intermediate"
        fi

        # Update last_seen (fire-and-forget)
        sqlite3 "$DB_PATH" "UPDATE user_profile SET last_seen=datetime('now');" 2>/dev/null || true

        # Build compact usage summary
        USAGE_SUMMARY=$(sqlite3 "$DB_PATH" "SELECT SUM(completed_runs) FROM v_workflow_usage;" 2>/dev/null || echo "0")
        USAGE_BREAKDOWN=$(sqlite3 -separator '' "$DB_PATH" "SELECT completed_runs || ' ' || type FROM v_workflow_usage WHERE completed_runs > 0 ORDER BY completed_runs DESC LIMIT 4;" 2>/dev/null || true)
        USAGE_LINE=""
        if [ -n "$USAGE_BREAKDOWN" ]; then
            USAGE_LINE=$(echo "$USAGE_BREAKDOWN" | paste -sd',' - | sed 's/,/, /g')
            USAGE_LINE=" ($USAGE_LINE)"
        fi

        echo "OMEGA IDENTITY: ${USER_NAME:-User} | Experience: $EXP_LEVEL | Style: $COMM_STYLE | Workflows: ${USAGE_SUMMARY:-0} completed${USAGE_LINE}"
        echo ""
    else
        echo "Welcome to OMEGA. Personalize your experience: /omega:onboard"
        echo "  Or set manually: sqlite3 .claude/memory.db \"INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('Your Name', 'beginner', 'balanced');\""
        echo ""
    fi
fi

# === SECTION 1: BEHAVIORAL LEARNINGS ===
# The main content. These are meta-cognitive rules that make Claude
# a better agent — learned from real interactions across sessions.
if table_exists "behavioral_learnings"; then
    if query_has_results "SELECT 1 FROM behavioral_learnings WHERE status='active' LIMIT 1;"; then
        echo "★ BEHAVIORAL LEARNINGS (apply these — they make you a better agent):"
        sqlite3 "$DB_PATH" "SELECT '  [' || printf('%.1f', confidence) || '] ' || rule FROM behavioral_learnings WHERE status='active' ORDER BY confidence DESC, occurrences DESC LIMIT 15;" 2>/dev/null || true
        echo ""
    fi
fi

# === DECISIONS — NOT injected at session start ===
# Active decisions are queried on-demand by agents during their
# scope-specific briefing, not at session start. They accumulate
# project-specific implementation details that are noise at session level.

# === SECTION 3: OPEN INCIDENTS ===
# Active bug investigations — just summary, not full detail.
# Full incident details are queried on-demand during work.
if table_exists "incidents"; then
    if query_has_results "SELECT 1 FROM incidents WHERE status IN ('open', 'investigating') LIMIT 1;"; then
        echo "▲ OPEN INCIDENTS (active bug investigations):"
        query "SELECT incident_id, title, status, domain FROM incidents WHERE status IN ('open', 'investigating') ORDER BY id DESC LIMIT 10;"
        echo ""
    fi
fi

# === OBLIGATIONS ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SESSION OBLIGATIONS:"
echo "  1. Log outcomes incrementally (INSERT INTO outcomes). Git commits blocked without them."
echo "  2. Track bugs as incidents: INSERT INTO incidents (incident_id, title, domain) VALUES ('INC-NNN', ...);"
echo "  3. Extract behavioral learnings from corrections: INSERT INTO behavioral_learnings (rule, context) VALUES (...);"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit 0
