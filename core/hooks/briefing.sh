#!/bin/bash
# ============================================================
# AUTOMATIC BRIEFING — UserPromptSubmit hook
# Injects institutional memory + self-learning context into
# Claude Code sessions. Uses a flag file to only fire ONCE
# per session (not on every user message).
# Output goes to stdout → injected into Claude's context.
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

echo "╔══════════════════════════════════════════════════════════╗"
echo "║           INSTITUTIONAL MEMORY BRIEFING                 ║"
echo "║     Loaded automatically — do NOT skip this context     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# --- OMEGA IDENTITY ---
# Check if user_profile table exists (backward compatibility)
PROFILE_TABLE_EXISTS=$(sqlite3 "$DB_PATH" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='user_profile' LIMIT 1;" 2>/dev/null || true)

if [ -n "$PROFILE_TABLE_EXISTS" ]; then
    # Query profile
    PROFILE_ROW=$(sqlite3 -separator '|' "$DB_PATH" "SELECT user_name, experience_level, communication_style FROM user_profile LIMIT 1;" 2>/dev/null || true)

    if [ -n "$PROFILE_ROW" ]; then
        # Parse profile fields
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

        # Output identity block
        echo "OMEGA IDENTITY: ${USER_NAME:-User} | Experience: $EXP_LEVEL | Style: $COMM_STYLE | Workflows: ${USAGE_SUMMARY:-0} completed${USAGE_LINE}"
        echo ""
    else
        # Table exists but no profile row -- show onboarding prompt
        echo "Welcome to OMEGA. Personalize your experience: /workflow:onboard"
        echo "  Or set manually: sqlite3 .claude/memory.db \"INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('Your Name', 'beginner', 'balanced');\""
        echo ""
    fi
fi

# --- CRITICAL HOTSPOTS ---
if query_has_results "SELECT 1 FROM hotspots WHERE risk_level IN ('high', 'critical') LIMIT 1;"; then
    echo "⚠ HOTSPOTS (fragile files — be extra careful):"
    query "SELECT file_path, risk_level, times_touched FROM hotspots WHERE risk_level IN ('high', 'critical') ORDER BY times_touched DESC LIMIT 10;"
    echo ""
fi

# --- FAILED APPROACHES ---
if query_has_results "SELECT 1 FROM failed_approaches LIMIT 1;"; then
    echo "✗ FAILED APPROACHES (do NOT retry these):"
    query "SELECT domain, approach, failure_reason FROM failed_approaches ORDER BY id DESC LIMIT 5;"
    echo ""
fi

# --- OPEN FINDINGS ---
if query_has_results "SELECT 1 FROM findings WHERE status='open' LIMIT 1;"; then
    echo "⊘ OPEN FINDINGS (known issues):"
    query "SELECT finding_id, severity, description, file_path FROM findings WHERE status='open' ORDER BY CASE severity WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 END LIMIT 10;"
    echo ""
fi

# --- ACTIVE DECISIONS ---
if query_has_results "SELECT 1 FROM decisions WHERE status='active' LIMIT 1;"; then
    echo "◉ ACTIVE DECISIONS (respect these unless you have strong reason to supersede):"
    query "SELECT domain, decision, rationale FROM decisions WHERE status='active' ORDER BY id DESC LIMIT 5;"
    echo ""
fi

# --- KNOWN PATTERNS ---
if query_has_results "SELECT 1 FROM patterns LIMIT 1;"; then
    echo "≡ PATTERNS (follow these for consistency):"
    query "SELECT domain, name, description FROM patterns ORDER BY id DESC LIMIT 5;"
    echo ""
fi

# --- SELF-LEARNING: RECENT OUTCOMES ---
if query_has_results "SELECT 1 FROM outcomes LIMIT 1;"; then
    echo "↻ RECENT OUTCOMES (what worked +1, what didn't -1):"
    query "SELECT agent, score, domain, action, lesson FROM outcomes ORDER BY id DESC LIMIT 15;"
    echo ""
fi

# --- SELF-LEARNING: ACTIVE LESSONS ---
if query_has_results "SELECT 1 FROM lessons WHERE status='active' LIMIT 1;"; then
    echo "★ ACTIVE LESSONS (distilled rules — follow high-confidence ones):"
    query "SELECT domain, content, occurrences, confidence FROM lessons WHERE status='active' ORDER BY confidence DESC, occurrences DESC LIMIT 10;"
    echo ""
fi

# --- RECENT WORKFLOW ACTIVITY ---
if query_has_results "SELECT 1 FROM workflow_runs ORDER BY id DESC LIMIT 1;"; then
    echo "⟳ LAST 5 WORKFLOW RUNS:"
    query "SELECT id, type, description, status, started_at FROM workflow_runs ORDER BY id DESC LIMIT 5;"
    echo ""
fi

# --- DEBRIEF OBLIGATION ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "DEBRIEF OBLIGATION: Before this session ends, you MUST:"
echo "  1. Create a workflow_run: INSERT INTO workflow_runs (type, description) VALUES ('manual', '...');"
echo "     RUN_ID=\$(sqlite3 .claude/memory.db \"SELECT last_insert_rowid();\")"
echo "  2. Log changes, decisions, failed approaches to memory.db"
echo "  3. Self-score your significant actions (INSERT INTO outcomes)"
echo "  4. Check for lesson distillation (3+ outcomes with same pattern)"
echo "  5. Close the run: UPDATE workflow_runs SET status='completed', completed_at=datetime('now') WHERE id=\$RUN_ID;"
echo "  NOTE: Git commits will be BLOCKED until you self-score at least one outcome."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit 0
