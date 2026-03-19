#!/bin/bash
# ============================================================
# BEHAVIORAL LEARNING GATE — PreToolUse hook (matcher: Bash)
# Blocks git commits if there are unresolved corrections that
# haven't been saved as behavioral learnings.
#
# Works with learning-detector.sh (UserPromptSubmit) which
# detects corrections and writes to .corrections_pending.
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

# --- This is a git commit. Check for unresolved corrections. ---

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DB_PATH="$PROJECT_DIR/.claude/memory.db"
PENDING_FILE="$PROJECT_DIR/.claude/hooks/.corrections_pending"

# No DB → allow
if [ ! -f "$DB_PATH" ]; then
    exit 0
fi

# No pending file or empty → allow
if [ ! -f "$PENDING_FILE" ] || [ ! -s "$PENDING_FILE" ]; then
    exit 0
fi

# One last check: maybe the corrections were resolved since the last prompt
EARLIEST_PENDING=$(head -1 "$PENDING_FILE" | cut -d'|' -f1)
NEW_LEARNINGS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM behavioral_learnings WHERE created_at >= datetime('$EARLIEST_PENDING', 'unixepoch');" 2>/dev/null || echo "0")

if [ "$NEW_LEARNINGS" -gt 0 ]; then
    # Resolved — clear pending and allow commit
    rm -f "$PENDING_FILE"
    exit 0
fi

# --- BLOCKED ---
PENDING_COUNT=$(wc -l < "$PENDING_FILE" | tr -d ' ')

echo "❌ COMMIT BLOCKED — UNRESOLVED BEHAVIORAL CORRECTIONS"
echo ""
echo "$PENDING_COUNT correction(s) detected but NOT saved as behavioral learnings:"
echo ""

while IFS='|' read -r ts snippet; do
    NOW=$(date +%s)
    AGE=$(( (NOW - ts) / 60 ))
    echo "  • (${AGE}m ago) \"$snippet\""
done < "$PENDING_FILE"

echo ""
echo "REQUIRED: Save each correction as a behavioral learning FIRST:"
echo "  sqlite3 .claude/memory.db \"INSERT INTO behavioral_learnings (rule, context)"
echo "    VALUES ('THE_RULE', 'What triggered this correction')"
echo "    ON CONFLICT(rule) DO UPDATE SET occurrences = occurrences + 1,"
echo "    confidence = MIN(1.0, confidence + 0.1), last_reinforced = datetime('now');\""
echo ""
echo "Then retry the commit."
exit 2
