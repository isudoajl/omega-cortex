#!/bin/bash
# ============================================================
# SESSION CLOSE — SessionEnd hook
# Closes any open workflow_runs and runs maintenance queries.
# Runs async so it doesn't block the session from ending.
# ============================================================

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DB_PATH="$PROJECT_DIR/.claude/memory.db"

# Graceful exit if no DB
if [ ! -f "$DB_PATH" ]; then
    exit 0
fi

# Close any workflow_runs still marked as 'running'
sqlite3 "$DB_PATH" "UPDATE workflow_runs SET status='partial', completed_at=datetime('now'), error_message='Session ended before debrief completed' WHERE status='running';" 2>/dev/null || true

# Run lightweight maintenance: promote hotspot risk levels
sqlite3 "$DB_PATH" "UPDATE hotspots SET risk_level = 'critical' WHERE times_touched >= 10 AND risk_level != 'critical';" 2>/dev/null || true
sqlite3 "$DB_PATH" "UPDATE hotspots SET risk_level = 'high' WHERE times_touched >= 5 AND times_touched < 10 AND risk_level NOT IN ('critical', 'high');" 2>/dev/null || true
sqlite3 "$DB_PATH" "UPDATE hotspots SET risk_level = 'medium' WHERE times_touched >= 3 AND times_touched < 5 AND risk_level NOT IN ('critical', 'high', 'medium');" 2>/dev/null || true

exit 0
