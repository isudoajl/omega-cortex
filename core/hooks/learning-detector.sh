#!/bin/bash
# ============================================================
# BEHAVIORAL LEARNING DETECTOR — UserPromptSubmit hook
# Fires on EVERY user message. Three jobs:
# 1. Detect correction patterns → write to .corrections_pending
# 2. Check if pending corrections were resolved → clear if so
# 3. Escalate unresolved corrections with increasing urgency
#
# Works with learning-gate.sh (PreToolUse) which blocks git
# commits until corrections are saved as behavioral learnings.
# ============================================================

INPUT=$(cat)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DB_PATH="$PROJECT_DIR/.claude/memory.db"
PENDING_FILE="$PROJECT_DIR/.claude/hooks/.corrections_pending"

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
    # No prompt text — still check for resolved corrections
    if [ -f "$PENDING_FILE" ] && [ -s "$PENDING_FILE" ]; then
        EARLIEST_PENDING=$(head -1 "$PENDING_FILE" | cut -d'|' -f1)
        NEW_LEARNINGS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM behavioral_learnings WHERE created_at >= datetime('$EARLIEST_PENDING', 'unixepoch');" 2>/dev/null || echo "0")
        if [ "$NEW_LEARNINGS" -gt 0 ]; then
            rm -f "$PENDING_FILE"
        fi
    fi
    exit 0
fi

# --- CHECK FOR RESOLVED CORRECTIONS ---
# If there are pending corrections, check if they were resolved
if [ -f "$PENDING_FILE" ] && [ -s "$PENDING_FILE" ]; then
    EARLIEST_PENDING=$(head -1 "$PENDING_FILE" | cut -d'|' -f1)

    # Check if any behavioral_learnings were inserted after the pending timestamp
    NEW_LEARNINGS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM behavioral_learnings WHERE created_at >= datetime('$EARLIEST_PENDING', 'unixepoch');" 2>/dev/null || echo "0")

    if [ "$NEW_LEARNINGS" -gt 0 ]; then
        # Corrections were resolved — clear pending
        rm -f "$PENDING_FILE"
    fi
fi

# --- CORRECTION PATTERN DETECTION ---
# Two-signal approach: requires BOTH a correction indicator AND an instruction.
# This reduces false positives vs single-keyword matching.

DETECTED=0

# Pattern 1: Negation + instruction verb
# "don't guess", "stop assuming", "never answer without checking", "don't read entire files"
if echo "$PROMPT" | grep -qiE "(don't|dont|do not|stop|never|quit) .*(guess|assume|answer|respond|claim|say|give|skip|ignore|rush|read|waste)"; then
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
if echo "$PROMPT" | grep -qiE "(you didn't|you didnt|you did not|you forgot to) .*(check|verify|analyze|read|look|test|calculate|confirm|save)"; then
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

# --- TRACK NEW DETECTIONS ---
if [ "$DETECTED" -eq 1 ]; then
    mkdir -p "$(dirname "$PENDING_FILE")"
    # Append: unix_timestamp|snippet (first 80 chars of prompt)
    SNIPPET=$(echo "$PROMPT" | head -c 80 | tr '\n' ' ')
    echo "$(date +%s)|$SNIPPET" >> "$PENDING_FILE"
fi

# --- OUTPUT ---
# If there are pending corrections (new or old), output a reminder
if [ -f "$PENDING_FILE" ] && [ -s "$PENDING_FILE" ]; then
    PENDING_COUNT=$(wc -l < "$PENDING_FILE" | tr -d ' ')
    OLDEST_TS=$(head -1 "$PENDING_FILE" | cut -d'|' -f1)
    OLDEST_SNIPPET=$(head -1 "$PENDING_FILE" | cut -d'|' -f2-)
    NOW=$(date +%s)
    AGE=$(( (NOW - OLDEST_TS) / 60 ))

    if [ "$DETECTED" -eq 1 ]; then
        # New detection — strong reminder
        echo ""
        echo "⚠️  BEHAVIORAL LEARNING DETECTED — SAVE IT NOW"
        echo "  The user is correcting your approach. This must be saved as a behavioral learning."
        echo "  Pending corrections: $PENDING_COUNT (oldest: ${AGE}m ago)"
        echo "  Original: \"$OLDEST_SNIPPET\""
        echo ""
        echo "  REQUIRED ACTION (do this BEFORE any other work):"
        echo "  sqlite3 .claude/memory.db \"INSERT INTO behavioral_learnings (rule, context) VALUES ('THE_RULE_HERE', 'What triggered this correction') ON CONFLICT(rule) DO UPDATE SET occurrences = occurrences + 1, confidence = MIN(1.0, confidence + 0.1), last_reinforced = datetime('now');\""
        echo ""
        echo "  ❌ Git commits are BLOCKED until this is resolved."
    else
        # No new detection, but pending corrections exist — escalate
        echo ""
        echo "⚠️  UNRESOLVED CORRECTION (${AGE}m ago, $PENDING_COUNT pending)"
        echo "  \"$OLDEST_SNIPPET\""
        echo "  Save as behavioral_learning BEFORE continuing other work."
        echo "  sqlite3 .claude/memory.db \"INSERT INTO behavioral_learnings (rule, context) VALUES ('RULE', 'CONTEXT') ON CONFLICT(rule) DO UPDATE SET occurrences = occurrences + 1, confidence = MIN(1.0, confidence + 0.1), last_reinforced = datetime('now');\""
        echo "  ❌ Git commits BLOCKED until resolved."
    fi
fi

exit 0
