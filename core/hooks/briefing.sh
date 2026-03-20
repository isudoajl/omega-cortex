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

# === SECTION 2: TEAM KNOWLEDGE (shared across developers) ===
# Imports shared behavioral learnings, incidents, and hotspots from
# .omega/shared/ into the briefing. Tracks imports in shared_imports table.
SHARED_DIR="$PROJECT_DIR/.omega/shared"
HAS_TEAM_CONTENT=false

# --- Curation pending detection ---
if [ -f "$PROJECT_DIR/.claude/hooks/.curation_pending" ]; then
    PENDING_COUNT=$(cat "$PROJECT_DIR/.claude/hooks/.curation_pending" 2>/dev/null || echo "0")
    echo "NOTE: $PENDING_COUNT entries pending curation. Run /omega:share to share with team."
    echo ""
    rm -f "$PROJECT_DIR/.claude/hooks/.curation_pending"
fi

if [ -d "$SHARED_DIR" ]; then
    TEAM_OUTPUT=""

    # --- Shared Behavioral Learnings (top 10 by confidence DESC) ---
    if [ -f "$SHARED_DIR/behavioral-learnings.jsonl" ] && [ -s "$SHARED_DIR/behavioral-learnings.jsonl" ]; then
        SHARED_BL=$(CORTEX_DB_PATH="$DB_PATH" CORTEX_SHARED_BL="$SHARED_DIR/behavioral-learnings.jsonl" python3 << 'PYEOF' 2>/dev/null || true
import json, sys, subprocess, os, re

db_path = os.environ.get("CORTEX_DB_PATH", "")
shared_file = os.environ.get("CORTEX_SHARED_BL", "")

def fix_json_line(line):
    """Fix bare decimals like .81 to 0.81 for JSON compliance."""
    return re.sub(r'(?<=[\s,:])\.(\d)', r'0.\1', line)

if not shared_file or not os.path.isfile(shared_file):
    sys.exit(0)

# Check if shared_imports table exists
has_table = False
if db_path and os.path.isfile(db_path):
    try:
        r = subprocess.run(
            ["sqlite3", db_path, "SELECT 1 FROM sqlite_master WHERE type='table' AND name='shared_imports' LIMIT 1;"],
            capture_output=True, text=True, timeout=5
        )
        has_table = bool(r.stdout.strip())
    except Exception:
        pass

# Load already-imported UUIDs
imported = set()
if has_table and db_path:
    try:
        r = subprocess.run(
            ["sqlite3", db_path, "SELECT shared_uuid FROM shared_imports WHERE category='behavioral_learning';"],
            capture_output=True, text=True, timeout=5
        )
        for line in r.stdout.strip().split("\n"):
            if line.strip():
                imported.add(line.strip())
    except Exception:
        pass

# Parse JSONL (first 500 lines)
entries = []
seen_uuids = set()
try:
    with open(shared_file, "r") as f:
        for i, line in enumerate(f):
            if i >= 500:
                break
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(fix_json_line(line))
            except (json.JSONDecodeError, ValueError):
                continue
            uuid = obj.get("uuid")
            if not uuid:
                continue
            if uuid in imported or uuid in seen_uuids:
                continue
            seen_uuids.add(uuid)
            confidence = float(obj.get("confidence", 0))
            rule = obj.get("rule", "")
            contributor = obj.get("contributor") or ""
            entries.append((uuid, confidence, rule, contributor))
except Exception:
    sys.exit(0)

if not entries:
    sys.exit(0)

# Sort by confidence DESC
entries.sort(key=lambda x: x[1], reverse=True)

# Record new imports in shared_imports
if has_table and db_path:
    for uuid, conf, rule, contrib in entries:
        try:
            subprocess.run(
                ["sqlite3", db_path,
                 f"INSERT OR IGNORE INTO shared_imports (shared_uuid, category, source_file) VALUES ('{uuid}', 'behavioral_learning', 'behavioral-learnings.jsonl');"],
                capture_output=True, text=True, timeout=5
            )
        except Exception:
            pass

# Display top 10
for uuid, confidence, rule, contributor in entries[:10]:
    # Extract display name from "Name <email>" format
    name = contributor
    if "<" in contributor:
        name = contributor.split("<")[0].strip()
    if not name or name == "None":
        name = "unknown"
    print(f"  [TEAM {confidence:.1f}] {rule} (from {name})")
PYEOF
        )
        if [ -n "$SHARED_BL" ]; then
            TEAM_OUTPUT="${TEAM_OUTPUT}${SHARED_BL}"$'\n'
            HAS_TEAM_CONTENT=true
        fi
    fi

    # --- Shared Incidents (top 3 resolved, by recency) ---
    if [ -d "$SHARED_DIR/incidents" ]; then
        INCIDENT_FILES=$(find "$SHARED_DIR/incidents" -name "*.json" -type f 2>/dev/null || true)
        if [ -n "$INCIDENT_FILES" ]; then
            SHARED_INC=$(CORTEX_DB_PATH="$DB_PATH" CORTEX_INCIDENTS_DIR="$SHARED_DIR/incidents" python3 << 'PYEOF' 2>/dev/null || true
import json, sys, subprocess, os, glob

db_path = os.environ.get("CORTEX_DB_PATH", "")
incidents_dir = os.environ.get("CORTEX_INCIDENTS_DIR", "")

if not incidents_dir or not os.path.isdir(incidents_dir):
    sys.exit(0)

# Check if shared_imports table exists
has_table = False
if db_path and os.path.isfile(db_path):
    try:
        r = subprocess.run(
            ["sqlite3", db_path, "SELECT 1 FROM sqlite_master WHERE type='table' AND name='shared_imports' LIMIT 1;"],
            capture_output=True, text=True, timeout=5
        )
        has_table = bool(r.stdout.strip())
    except Exception:
        pass

# Load already-imported incident UUIDs
imported = set()
if has_table and db_path:
    try:
        r = subprocess.run(
            ["sqlite3", db_path, "SELECT shared_uuid FROM shared_imports WHERE category='incident';"],
            capture_output=True, text=True, timeout=5
        )
        for line in r.stdout.strip().split("\n"):
            if line.strip():
                imported.add(line.strip())
    except Exception:
        pass

# Parse incident JSON files
entries = []
for fpath in glob.glob(os.path.join(incidents_dir, "*.json")):
    try:
        with open(fpath, "r") as f:
            obj = json.load(f)
    except (json.JSONDecodeError, ValueError, OSError):
        continue
    incident_id = obj.get("incident_id")
    if not incident_id:
        continue
    status = obj.get("status", "")
    if status not in ("resolved", "closed"):
        continue
    if incident_id in imported:
        continue
    title = obj.get("title", "")
    contributor = obj.get("contributor") or ""
    resolved_at = obj.get("resolved_at", "")
    source_file = os.path.basename(fpath)
    entries.append((incident_id, title, contributor, resolved_at, source_file))

if not entries:
    sys.exit(0)

# Sort by resolved_at DESC
entries.sort(key=lambda x: x[3], reverse=True)

# Record new imports in shared_imports
if has_table and db_path:
    for inc_id, title, contrib, resolved_at, src in entries:
        try:
            subprocess.run(
                ["sqlite3", db_path,
                 f"INSERT OR IGNORE INTO shared_imports (shared_uuid, category, source_file) VALUES ('{inc_id}', 'incident', 'incidents/{src}');"],
                capture_output=True, text=True, timeout=5
            )
        except Exception:
            pass

# Display top 3
for inc_id, title, contributor, resolved_at, src in entries[:3]:
    name = contributor
    if "<" in contributor:
        name = contributor.split("<")[0].strip()
    if not name or name == "None":
        name = "unknown"
    print(f"  [TEAM] {inc_id}: {title} (resolved by {name})")
PYEOF
            )
            if [ -n "$SHARED_INC" ]; then
                TEAM_OUTPUT="${TEAM_OUTPUT}${SHARED_INC}"$'\n'
                HAS_TEAM_CONTENT=true
            fi
        fi
    fi

    # --- Shared Hotspots (top 5 by risk_level, NOT tracked in shared_imports) ---
    if [ -f "$SHARED_DIR/hotspots.jsonl" ] && [ -s "$SHARED_DIR/hotspots.jsonl" ]; then
        SHARED_HS=$(CORTEX_SHARED_HS="$SHARED_DIR/hotspots.jsonl" python3 << 'PYEOF' 2>/dev/null || true
import json, sys, os

shared_file = os.environ.get("CORTEX_SHARED_HS", "")

if not shared_file or not os.path.isfile(shared_file):
    sys.exit(0)

risk_order = {"critical": 4, "high": 3, "medium": 2, "low": 1}

entries = []
try:
    with open(shared_file, "r") as f:
        for i, line in enumerate(f):
            if i >= 500:
                break
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue
            file_path = obj.get("file_path", "")
            risk_level = obj.get("risk_level", "low")
            times_touched = int(obj.get("times_touched", 0))
            contributor_count = int(obj.get("contributor_count", 0))
            entries.append((file_path, risk_level, times_touched, contributor_count))
except Exception:
    sys.exit(0)

if not entries:
    sys.exit(0)

# Sort by risk_level DESC, contributor_count DESC
entries.sort(key=lambda x: (risk_order.get(x[1], 0), x[3]), reverse=True)

# Display top 5
for file_path, risk_level, times_touched, contributor_count in entries[:5]:
    print(f"  [TEAM] {file_path} -- {risk_level} risk ({contributor_count} devs, {times_touched} touches)")
PYEOF
        )
        if [ -n "$SHARED_HS" ]; then
            TEAM_OUTPUT="${TEAM_OUTPUT}${SHARED_HS}"$'\n'
            HAS_TEAM_CONTENT=true
        fi
    fi

    # Output the TEAM KNOWLEDGE section if any content was generated
    if [ "$HAS_TEAM_CONTENT" = true ] && [ -n "$TEAM_OUTPUT" ]; then
        echo "★ TEAM KNOWLEDGE (shared across developers):"
        echo "$TEAM_OUTPUT"
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
