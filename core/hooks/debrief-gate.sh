#!/bin/bash
# ============================================================
# DEBRIEF GATE — PreToolUse hook (matcher: Bash)
# Blocks git commits unless the AI has logged at least one
# outcome (self-score) in this session. Forces debrief before
# the most consequential action: committing code.
# ============================================================

# Read hook input from stdin
INPUT=$(cat)

# Extract the command from the JSON input
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# Only gate git commits — let everything else through immediately
case "$COMMAND" in
    *"git commit"*)
        ;;
    *)
        exit 0
        ;;
esac

# --- This is a git commit. Check if debrief was done. ---

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DB_PATH="$PROJECT_DIR/.claude/memory.db"

# If no DB, allow the commit (project may not use institutional memory)
if [ ! -f "$DB_PATH" ]; then
    exit 0
fi

# Check if any outcomes were logged today (evidence of self-scoring)
TODAY=$(date -u +"%Y-%m-%d")
OUTCOME_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM outcomes WHERE created_at >= '$TODAY';" 2>/dev/null || echo "0")

if [ "$OUTCOME_COUNT" -gt 0 ]; then
    # Debrief happened — allow the commit
    exit 0
fi

# Check if a workflow_run exists for today (at minimum, session was registered)
RUN_EXISTS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM workflow_runs WHERE started_at >= '$TODAY';" 2>/dev/null || echo "0")

if [ "$RUN_EXISTS" -eq 0 ]; then
    # No workflow_run AND no outcomes — full debrief missing
    echo "COMMIT BLOCKED — DEBRIEF REQUIRED"
    echo ""
    echo "You have not logged any debrief for this session. Before committing, you MUST:"
    echo ""
    echo "  1. Register this session:"
    echo "     sqlite3 .claude/memory.db \"INSERT INTO workflow_runs (type, description) VALUES ('manual', 'description');\""
    echo "     RUN_ID=\$(sqlite3 .claude/memory.db \"SELECT last_insert_rowid();\")"
    echo ""
    echo "  2. Self-score your significant actions:"
    echo "     sqlite3 .claude/memory.db \"INSERT INTO outcomes (run_id, agent, score, domain, action, lesson) VALUES (\$RUN_ID, 'developer', 1, 'domain', 'what you did', 'what you learned');\""
    echo ""
    echo "  3. Log changes, decisions, and failed approaches"
    echo ""
    echo "  4. Then retry the commit."
    exit 2
fi

# workflow_run exists but no outcomes — partial debrief
echo "COMMIT BLOCKED — SELF-SCORING REQUIRED"
echo ""
echo "You registered a workflow_run but logged zero outcomes (self-scores)."
echo "Before committing, score at least your most significant actions:"
echo ""
echo "  sqlite3 .claude/memory.db \"INSERT INTO outcomes (run_id, agent, score, domain, action, lesson) VALUES (\$RUN_ID, 'developer', 1, 'domain', 'what you did', 'what you learned');\""
echo ""
echo "Score: +1 (worked well), 0 (unremarkable), -1 (failed/excessive iteration)"
echo "Then retry the commit."
exit 2
