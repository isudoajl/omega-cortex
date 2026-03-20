#!/bin/bash
# ============================================================
# SESSION CLEANUP — Notification hook
# Cleans up session flag files and promotes hotspot risk levels.
# Runs on notifications (closest event to session lifecycle).
# ============================================================

# Consume stdin (hook receives JSON input)
cat > /dev/null

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DB_PATH="$PROJECT_DIR/.claude/memory.db"

# Graceful exit if no DB
if [ ! -f "$DB_PATH" ]; then
    exit 0
fi

# Promote hotspot risk levels based on touch counts
sqlite3 "$DB_PATH" "UPDATE hotspots SET risk_level = 'critical' WHERE times_touched >= 10 AND risk_level != 'critical';" 2>/dev/null || true
sqlite3 "$DB_PATH" "UPDATE hotspots SET risk_level = 'high' WHERE times_touched >= 5 AND times_touched < 10 AND risk_level NOT IN ('critical', 'high');" 2>/dev/null || true
sqlite3 "$DB_PATH" "UPDATE hotspots SET risk_level = 'medium' WHERE times_touched >= 3 AND times_touched < 5 AND risk_level NOT IN ('critical', 'high', 'medium');" 2>/dev/null || true

# --- Cortex: Check for pending curation ---
# Detect unsared high-confidence behavioral_learnings and resolved incidents.
# If found, write a .curation_pending flag for the next session's briefing to detect.
# Bash hooks cannot spawn Claude agents, so we flag instead of curating directly.
PENDING_BL=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM behavioral_learnings WHERE confidence >= 0.8 AND status = 'active' AND COALESCE(is_private, 0) = 0 AND shared_uuid IS NULL;" 2>/dev/null || echo "0")
PENDING_INC=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM incidents WHERE status = 'resolved' AND COALESCE(is_private, 0) = 0 AND shared_uuid IS NULL;" 2>/dev/null || echo "0")

PENDING_TOTAL=$(( ${PENDING_BL:-0} + ${PENDING_INC:-0} ))

if [ "$PENDING_TOTAL" -gt 0 ]; then
    mkdir -p "$PROJECT_DIR/.claude/hooks" 2>/dev/null || true
    echo "$PENDING_TOTAL entries pending curation ($PENDING_BL behavioral learnings, $PENDING_INC incidents)" > "$PROJECT_DIR/.claude/hooks/.curation_pending"
fi

exit 0
