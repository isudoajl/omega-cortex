#!/bin/bash
# ============================================================
# BEHAVIORAL LEARNING DETECTOR — UserPromptSubmit hook
# Fires on EVERY user message. Detects correction patterns
# and reminds Claude to save to behavioral_learnings table.
# Unlike briefing.sh, this is NOT session-gated — it runs
# on every prompt to catch corrections whenever they happen.
# ============================================================

INPUT=$(cat)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DB_PATH="$PROJECT_DIR/.claude/memory.db"

# No DB → silent exit
if [ ! -f "$DB_PATH" ]; then
    exit 0
fi

# Check if behavioral_learnings table exists (backward compatibility)
TABLE_EXISTS=$(sqlite3 "$DB_PATH" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='behavioral_learnings' LIMIT 1;" 2>/dev/null || true)
if [ -z "$TABLE_EXISTS" ]; then
    exit 0
fi

# Extract user's prompt
PROMPT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt','').lower())" 2>/dev/null || echo "")

if [ -z "$PROMPT" ]; then
    exit 0
fi

# --- CORRECTION PATTERN DETECTION ---
# Two-signal approach: requires BOTH a correction indicator AND an instruction.
# This reduces false positives vs single-keyword matching.

DETECTED=0

# Pattern 1: Negation + instruction verb
# "don't guess", "stop assuming", "never answer without checking"
if echo "$PROMPT" | grep -qiE "(don't|dont|do not|stop|never|quit) .*(guess|assume|answer|respond|claim|say|give|skip|ignore|rush)"; then
    DETECTED=1
fi

# Pattern 2: "from now on" / "going forward" / "in the future"
if echo "$PROMPT" | grep -qiE "(from now on|going forward|in the future|from here on)"; then
    DETECTED=1
fi

# Pattern 3: "you should always" / "you must always" / "always ... before"
if echo "$PROMPT" | grep -qiE "(you should always|you must always|always .* before|always .* first)"; then
    DETECTED=1
fi

# Pattern 4: "you didn't" + action verb (pointing out a mistake)
if echo "$PROMPT" | grep -qiE "(you didn't|you didnt|you did not|you forgot to) .*(check|verify|analyze|read|look|test|calculate|confirm)"; then
    DETECTED=1
fi

# Pattern 5: Explicit backpressure / analysis requests
if echo "$PROMPT" | grep -qiE "(without (evidence|proof|checking|verifying|analyzing)|backpressure|minimum analysis|think before|analyze before)"; then
    DETECTED=1
fi

# Pattern 6: Challenge + correction ("is that hard?" / "really?" + correction)
if echo "$PROMPT" | grep -qiE "(is (that|this) hard|are you sure|really\?|think again|reconsider)"; then
    DETECTED=1
fi

# --- OUTPUT ---
if [ "$DETECTED" -eq 1 ]; then
    echo ""
    echo "[BEHAVIORAL LEARNING SIGNAL: The user appears to be correcting your approach. If this is about HOW you should reason or work (not a user preference like name/style), save it as a behavioral learning:"
    echo "  sqlite3 .claude/memory.db \"INSERT INTO behavioral_learnings (rule, context) VALUES ('THE_RULE_HERE', 'What triggered this correction') ON CONFLICT(rule) DO UPDATE SET occurrences = occurrences + 1, confidence = MIN(1.0, confidence + 0.1), last_reinforced = datetime('now');\""
    echo "  Behavioral = about reasoning/analysis process. NOT behavioral = preferences (name, style, language).]"
fi

exit 0
