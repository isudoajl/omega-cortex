#!/bin/bash
# ============================================================
# DEBRIEF NUDGE — PostToolUse hook
# After tool executions, checks if debrief is overdue.
# Throttled: only reminds every 5th tool call to avoid noise.
# ============================================================

# Consume stdin (hook receives JSON input)
cat > /dev/null

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DB_PATH="$PROJECT_DIR/.claude/memory.db"
COUNTER_FILE="$PROJECT_DIR/.claude/hooks/.nudge_counter"

# If no DB, stay silent
if [ ! -f "$DB_PATH" ]; then
    exit 0
fi

# Check if outcomes were logged today — if yes, debrief is done, stay silent
TODAY=$(date -u +"%Y-%m-%d")
OUTCOME_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM outcomes WHERE created_at >= '$TODAY';" 2>/dev/null || echo "0")

if [ "$OUTCOME_COUNT" -gt 0 ]; then
    # Debrief happened — reset counter and stay silent
    rm -f "$COUNTER_FILE" 2>/dev/null
    exit 0
fi

# Increment tool call counter
mkdir -p "$(dirname "$COUNTER_FILE")"
if [ -f "$COUNTER_FILE" ]; then
    COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
    COUNT=$((COUNT + 1))
else
    COUNT=1
fi
echo "$COUNT" > "$COUNTER_FILE"

# Only nudge every 5th tool call (not every one — that's too noisy)
if [ $((COUNT % 5)) -ne 0 ]; then
    exit 0
fi

# Output nudge — this gets injected into Claude's context
echo ""
echo "[DEBRIEF REMINDER: $COUNT tool calls without self-scoring any outcomes. Run your debrief before this session ends. Git commits will be blocked until you do.]"

exit 0
