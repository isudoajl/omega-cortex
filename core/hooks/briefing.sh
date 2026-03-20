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
        SHARED_BL=$(CORTEX_DB_PATH="$DB_PATH" CORTEX_SHARED_BL="$SHARED_DIR/behavioral-learnings.jsonl" CORTEX_PROJECT_DIR="$PROJECT_DIR" python3 << 'PYEOF' 2>/dev/null || true
import json, sys, subprocess, os, re

db_path = os.environ.get("CORTEX_DB_PATH", "")
shared_file = os.environ.get("CORTEX_SHARED_BL", "")
project_dir = os.environ.get("CORTEX_PROJECT_DIR", ".")

# Import sanitization module (deployed alongside briefing.sh)
sanitize_mod = None
try:
    hooks_dir = os.path.join(project_dir, ".claude", "hooks")
    if os.path.isfile(os.path.join(hooks_dir, "cortex_sanitize.py")):
        import importlib.util
        spec = importlib.util.spec_from_file_location("cortex_sanitize", os.path.join(hooks_dir, "cortex_sanitize.py"))
        sanitize_mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(sanitize_mod)
except Exception:
    pass

def fix_json_line(line):
    """Fix bare decimals like .81 to 0.81 for JSON compliance."""
    return re.sub(r'(?<=[\s,:])\.(\d)', r'0.\1', line)

if not shared_file or not os.path.isfile(shared_file):
    sys.exit(0)

# Load HMAC key if available (REQ-CTX-052)
cortex_key = None
key_path = os.path.join(project_dir, ".omega", ".cortex-key")
try:
    if os.path.isfile(key_path):
        with open(key_path, "r") as kf:
            cortex_key = kf.read().strip()
except Exception:
    pass

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
security_events = []  # (event_type, severity, details, entry_uuid, contributor)
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

            contributor = obj.get("contributor") or ""

            # HMAC signature verification (REQ-CTX-052)
            if cortex_key and sanitize_mod:
                sig = obj.get("signature")
                if not sig:
                    # Unsigned entry — reject when key exists
                    security_events.append(("unsigned_entry_rejected", "critical",
                        f"Unsigned entry rejected: {uuid}", uuid, contributor))
                    continue
                if not sanitize_mod.verify_entry(obj, cortex_key):
                    security_events.append(("signature_failure", "critical",
                        f"Invalid signature for entry: {uuid}", uuid, contributor))
                    continue

            seen_uuids.add(uuid)
            confidence = float(obj.get("confidence", 0))
            rule = obj.get("rule", "")
            context_field = obj.get("context", "")

            # Sanitize text fields (REQ-CTX-051, REQ-CTX-055)
            if sanitize_mod:
                rule, rule_count = sanitize_mod.sanitize_field(rule)
                context_field, ctx_count = sanitize_mod.sanitize_field(context_field)
                total_redactions = rule_count + ctx_count
                if total_redactions > 0:
                    security_events.append(("content_sanitized", "warning",
                        f"Sanitized {total_redactions} pattern(s) in behavioral learning",
                        uuid, contributor))
                if total_redactions >= 3:
                    security_events.append(("content_rejected", "critical",
                        f"Entry rejected: {total_redactions} redactions (threshold: 3)",
                        uuid, contributor))
                    continue

            entries.append((uuid, confidence, rule, contributor))
except Exception:
    sys.exit(0)

if not entries and not security_events:
    sys.exit(0)

# Log security events to cortex_security_log (REQ-CTX-060)
if security_events and sanitize_mod and db_path and os.path.isfile(db_path):
    for evt_type, sev, details, evt_uuid, evt_contrib in security_events:
        try:
            sanitize_mod.log_security_event(db_path, evt_type, sev, details,
                "behavioral-learnings.jsonl", evt_uuid, evt_contrib)
        except Exception:
            pass

if not entries:
    sys.exit(0)

# Sort by confidence DESC
entries.sort(key=lambda x: x[1], reverse=True)

# Record new imports in shared_imports (parameterized — no SQL injection)
if has_table and db_path:
    try:
        import sqlite3 as _sql
        _conn = _sql.connect(db_path)
        _cur = _conn.cursor()
        for uuid, conf, rule, contrib in entries:
            try:
                _cur.execute("INSERT OR IGNORE INTO shared_imports (shared_uuid, category, source_file) VALUES (?, ?, ?)",
                             (uuid, "behavioral_learning", "behavioral-learnings.jsonl"))
            except Exception:
                pass
        _conn.commit()
        _conn.close()
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
            SHARED_INC=$(CORTEX_DB_PATH="$DB_PATH" CORTEX_INCIDENTS_DIR="$SHARED_DIR/incidents" CORTEX_PROJECT_DIR="$PROJECT_DIR" python3 << 'PYEOF' 2>/dev/null || true
import json, sys, subprocess, os, glob

db_path = os.environ.get("CORTEX_DB_PATH", "")
incidents_dir = os.environ.get("CORTEX_INCIDENTS_DIR", "")
project_dir = os.environ.get("CORTEX_PROJECT_DIR", ".")

# Import sanitization module
sanitize_mod = None
try:
    hooks_dir = os.path.join(project_dir, ".claude", "hooks")
    if os.path.isfile(os.path.join(hooks_dir, "cortex_sanitize.py")):
        import importlib.util
        spec = importlib.util.spec_from_file_location("cortex_sanitize", os.path.join(hooks_dir, "cortex_sanitize.py"))
        sanitize_mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(sanitize_mod)
except Exception:
    pass

if not incidents_dir or not os.path.isdir(incidents_dir):
    sys.exit(0)

# Load HMAC key if available (REQ-CTX-052)
cortex_key = None
key_path = os.path.join(project_dir, ".omega", ".cortex-key")
try:
    if os.path.isfile(key_path):
        with open(key_path, "r") as kf:
            cortex_key = kf.read().strip()
except Exception:
    pass

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
security_events = []
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

    contributor = obj.get("contributor") or ""
    source_file = os.path.basename(fpath)

    # HMAC signature verification (REQ-CTX-052)
    if cortex_key and sanitize_mod:
        sig = obj.get("signature")
        if not sig:
            security_events.append(("unsigned_entry_rejected", "critical",
                f"Unsigned incident rejected: {incident_id}", incident_id, contributor))
            continue
        if not sanitize_mod.verify_entry(obj, cortex_key):
            security_events.append(("signature_failure", "critical",
                f"Invalid signature for incident: {incident_id}", incident_id, contributor))
            continue

    title = obj.get("title", "")
    description = obj.get("description", "")
    resolution = obj.get("resolution", "")

    # Sanitize text fields (REQ-CTX-051)
    if sanitize_mod:
        title, t_count = sanitize_mod.sanitize_field(title)
        description, d_count = sanitize_mod.sanitize_field(description)
        resolution, r_count = sanitize_mod.sanitize_field(resolution)
        total_redactions = t_count + d_count + r_count
        if total_redactions > 0:
            security_events.append(("content_sanitized", "warning",
                f"Sanitized {total_redactions} pattern(s) in incident {incident_id}",
                incident_id, contributor))
        if total_redactions >= 3:
            security_events.append(("content_rejected", "critical",
                f"Incident rejected: {total_redactions} redactions (threshold: 3)",
                incident_id, contributor))
            continue

    resolved_at = obj.get("resolved_at", "")
    entries.append((incident_id, title, contributor, resolved_at, source_file))

# Log security events (REQ-CTX-060)
if security_events and sanitize_mod and db_path and os.path.isfile(db_path):
    for evt_type, sev, details, evt_uuid, evt_contrib in security_events:
        try:
            sanitize_mod.log_security_event(db_path, evt_type, sev, details,
                f"incidents/{evt_uuid}.json", evt_uuid, evt_contrib)
        except Exception:
            pass

if not entries:
    sys.exit(0)

# Sort by resolved_at DESC
entries.sort(key=lambda x: x[3], reverse=True)

# Record new imports in shared_imports (parameterized — no SQL injection)
if has_table and db_path:
    try:
        import sqlite3 as _sql
        _conn = _sql.connect(db_path)
        _cur = _conn.cursor()
        for inc_id, title, contrib, resolved_at, src in entries:
            try:
                _cur.execute("INSERT OR IGNORE INTO shared_imports (shared_uuid, category, source_file) VALUES (?, ?, ?)",
                             (inc_id, "incident", f"incidents/{src}"))
            except Exception:
                pass
        _conn.commit()
        _conn.close()
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
        SHARED_HS=$(CORTEX_SHARED_HS="$SHARED_DIR/hotspots.jsonl" CORTEX_DB_PATH="$DB_PATH" CORTEX_PROJECT_DIR="$PROJECT_DIR" python3 << 'PYEOF' 2>/dev/null || true
import json, sys, os

shared_file = os.environ.get("CORTEX_SHARED_HS", "")
db_path = os.environ.get("CORTEX_DB_PATH", "")
project_dir = os.environ.get("CORTEX_PROJECT_DIR", ".")

# Import sanitization module
sanitize_mod = None
try:
    hooks_dir = os.path.join(project_dir, ".claude", "hooks")
    if os.path.isfile(os.path.join(hooks_dir, "cortex_sanitize.py")):
        import importlib.util
        spec = importlib.util.spec_from_file_location("cortex_sanitize", os.path.join(hooks_dir, "cortex_sanitize.py"))
        sanitize_mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(sanitize_mod)
except Exception:
    pass

if not shared_file or not os.path.isfile(shared_file):
    sys.exit(0)

risk_order = {"critical": 4, "high": 3, "medium": 2, "low": 1}

entries = []
security_events = []
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
            uuid = obj.get("uuid", "")
            contributor = obj.get("contributor", "")

            # Validate file path (REQ-CTX-055)
            if sanitize_mod:
                validated = sanitize_mod.validate_file_path(file_path)
                if validated == "[INVALID PATH]":
                    security_events.append(("path_traversal_blocked", "warning",
                        f"Invalid file path blocked: {file_path}", uuid, contributor))
                    file_path = validated
                else:
                    file_path = validated

            # Sanitize description field (REQ-CTX-051)
            description = obj.get("description", "")
            if sanitize_mod and description:
                description, desc_count = sanitize_mod.sanitize_field(description)
                if desc_count > 0:
                    security_events.append(("content_sanitized", "warning",
                        f"Sanitized {desc_count} pattern(s) in hotspot description",
                        uuid, contributor))

            risk_level = obj.get("risk_level", "low")
            times_touched = int(obj.get("times_touched", 0))
            contributor_count = int(obj.get("contributor_count", 0))
            entries.append((file_path, risk_level, times_touched, contributor_count))
except Exception:
    sys.exit(0)

# Log security events (REQ-CTX-060)
if security_events and sanitize_mod and db_path and os.path.isfile(db_path):
    for evt_type, sev, details, evt_uuid, evt_contrib in security_events:
        try:
            sanitize_mod.log_security_event(db_path, evt_type, sev, details,
                "hotspots.jsonl", evt_uuid, evt_contrib)
        except Exception:
            pass

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

    # --- Surface critical security events (REQ-CTX-060) ---
    SECURITY_WARNINGS=$(CORTEX_DB_PATH="$DB_PATH" python3 << 'PYEOF' 2>/dev/null || true
import sys, os, subprocess

db_path = os.environ.get("CORTEX_DB_PATH", "")
if not db_path or not os.path.isfile(db_path):
    sys.exit(0)

# Check if cortex_security_log table exists
try:
    r = subprocess.run(
        ["sqlite3", db_path, "SELECT 1 FROM sqlite_master WHERE type='table' AND name='cortex_security_log' LIMIT 1;"],
        capture_output=True, text=True, timeout=5
    )
    if not r.stdout.strip():
        sys.exit(0)
except Exception:
    sys.exit(0)

# Count critical events from last 24 hours
try:
    import sqlite3
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute(
        "SELECT event_type, COUNT(*) FROM cortex_security_log "
        "WHERE severity = 'critical' AND timestamp > datetime('now', '-24 hours') "
        "GROUP BY event_type"
    )
    rows = cur.fetchall()
    conn.close()
    if rows:
        for event_type, count in rows:
            label = event_type.replace('_', ' ')
            print(f"  [SECURITY] {count} {label} event(s) in last 24h (run /omega:team-status for details)")
except Exception:
    pass
PYEOF
    )
    if [ -n "$SECURITY_WARNINGS" ]; then
        TEAM_OUTPUT="${TEAM_OUTPUT}${SECURITY_WARNINGS}"$'\n'
        HAS_TEAM_CONTENT=true
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
echo "  2. Track bugs as incidents: INSERT INTO incidents (incident_id, title, domain, severity) VALUES ('INC-NNN', ..., 'critical|high|medium|low');"
echo "  3. Extract behavioral learnings from corrections: INSERT INTO behavioral_learnings (rule, context) VALUES (...);"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit 0
