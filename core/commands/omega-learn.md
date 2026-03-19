---
name: omega:learn
description: "Manually teach OMEGA a behavioral learning. Usage: /omega:learn \"rule\" or /omega:learn --list to see current learnings."
---

# Workflow: Learn

## Purpose
Manually insert, reinforce, or list behavioral learnings — the cross-domain meta-cognitive rules that are injected at every session start. Use this when you want to teach OMEGA something without waiting for the correction detection loop.

## Flags
- `--list` — show all active behavioral learnings with confidence and occurrences
- `--remove "rule fragment"` — supersede a learning that no longer applies

## No Agent Required
This command operates directly without a dedicated agent.

## Pipeline Tracking
Lightweight — no workflow_runs entry needed for learn commands.

## Flow

### If `--list`
```bash
sqlite3 -header -column .claude/memory.db "SELECT id, rule, confidence, occurrences, context, created_at FROM behavioral_learnings WHERE status='active' ORDER BY confidence DESC, occurrences DESC;"
```
Display the results in a formatted table. If empty, say "No behavioral learnings yet."

### If `--remove "fragment"`
Find the matching learning:
```bash
sqlite3 .claude/memory.db "SELECT id, rule FROM behavioral_learnings WHERE status='active' AND rule LIKE '%fragment%';"
```
- If exactly one match: supersede it: `UPDATE behavioral_learnings SET status='superseded' WHERE id=?;`
- If multiple matches: show them all and ask the user which one to remove
- If no match: say "No active learning matches that fragment."

### If argument is a rule (default)
The user provides the rule as the argument. Ask ONE follow-up question: "What context triggered this?" (optional — user can skip).

Then insert:
```bash
sqlite3 .claude/memory.db "INSERT INTO behavioral_learnings (rule, context) VALUES ('RULE', 'CONTEXT') ON CONFLICT(rule) DO UPDATE SET occurrences = occurrences + 1, confidence = MIN(1.0, confidence + 0.1), last_reinforced = datetime('now');"
```

If the rule already existed (ON CONFLICT fired), inform the user it was reinforced with the new confidence.

Confirm with: "Learned. This will be injected at the start of every future session."

### Clear pending corrections
After inserting a learning, check if `.claude/hooks/.corrections_pending` exists and clear it — this learning may resolve pending corrections tracked by the learning-detector hook.

## Manual Alternative
```bash
sqlite3 .claude/memory.db "INSERT INTO behavioral_learnings (rule, context) VALUES ('Always X before Y', 'Learned from incident Z') ON CONFLICT(rule) DO UPDATE SET occurrences = occurrences + 1, confidence = MIN(1.0, confidence + 0.1), last_reinforced = datetime('now');"
```
