#!/bin/bash
# migrate-1.5.0.sh — Cortex security hardening: add cortex_security_log table
#
# Creates the cortex_security_log table for security audit logging.
# Part of M12: Import Hardening + Entry Signing.
#
# Usage: bash core/db/migrate-1.5.0.sh [db_path]
#   db_path defaults to .claude/memory.db
#
# IDEMPOTENT: Safe to run multiple times. Uses CREATE TABLE IF NOT EXISTS.

set -e

DB="${1:-.claude/memory.db}"

if [ ! -f "$DB" ]; then
    echo "  migrate-1.5.0: DB not found at $DB — skipping migration"
    exit 0
fi

if ! command -v sqlite3 &>/dev/null; then
    echo "  migrate-1.5.0: sqlite3 not found — skipping migration"
    exit 0
fi

# --- Create cortex_security_log table ---
sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS cortex_security_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,
    severity TEXT NOT NULL CHECK(severity IN ('info', 'warning', 'critical')),
    details TEXT,
    source_file TEXT,
    entry_uuid TEXT,
    contributor TEXT,
    timestamp TEXT DEFAULT (datetime('now'))
);"

echo "  migrate-1.5.0: Migration complete for $DB"
