# Incident Tracking Protocol

Incidents are the structured way to track bugs in OMEGA. Each bug gets a ticket number (INC-NNN) and all related knowledge — attempts, discoveries, clues, resolution — lives under it. This replaces scattered `bugs` and `failed_approaches` entries for bug tracking.

## When to Create an Incident

- A bug is reported or discovered during work
- A test fails unexpectedly
- Behavior deviates from specs
- A user reports something broken

**Not** for: general failed approaches during feature development (those stay in `failed_approaches`). Incidents are for **bugs**, not for "I tried approach A and it didn't work for this feature."

## Creating an Incident

```bash
# 1. Get next incident number
NEXT_ID=$(sqlite3 .claude/memory.db "SELECT 'INC-' || printf('%03d', COALESCE(MAX(CAST(SUBSTR(incident_id, 5) AS INTEGER)), 0) + 1) FROM incidents;")

# 2. Create the incident
sqlite3 .claude/memory.db "INSERT INTO incidents (incident_id, title, domain, description, symptoms, run_id)
VALUES ('$NEXT_ID', 'Short title', 'domain/module', 'Full description of the bug', 'Error messages, unexpected behavior seen', $RUN_ID);"
```

## Adding Entries to an Incident

Every attempt, discovery, clue, or note gets logged as an entry:

```bash
# After trying something (attempt)
sqlite3 .claude/memory.db "INSERT INTO incident_entries (incident_id, entry_type, content, result, agent, run_id)
VALUES ('INC-001', 'attempt', 'What was tried and how', 'failed', 'developer', $RUN_ID);"

# After discovering something relevant (discovery)
sqlite3 .claude/memory.db "INSERT INTO incident_entries (incident_id, entry_type, content, result, agent, run_id)
VALUES ('INC-001', 'discovery', 'What was found — e.g., connection pool was exhausted', NULL, 'diagnostician', $RUN_ID);"

# After forming a hypothesis (hypothesis)
sqlite3 .claude/memory.db "INSERT INTO incident_entries (incident_id, entry_type, content, result, agent, run_id)
VALUES ('INC-001', 'hypothesis', 'Theory about root cause — e.g., DNS resolution blocking event loop', NULL, 'diagnostician', $RUN_ID);"

# A clue that might be relevant (clue)
sqlite3 .claude/memory.db "INSERT INTO incident_entries (incident_id, entry_type, content, result, agent, run_id)
VALUES ('INC-001', 'clue', 'Observation that might help — e.g., only fails under concurrent load', NULL, 'developer', $RUN_ID);"

# General note (note)
sqlite3 .claude/memory.db "INSERT INTO incident_entries (incident_id, entry_type, content, result, agent, run_id)
VALUES ('INC-001', 'note', 'Context, discussion, or reference', NULL, 'manual', $RUN_ID);"
```

**Entry types:**
| Type | When | `result` field |
|------|------|---------------|
| `attempt` | After trying a fix or approach | `worked`, `failed`, `partial` |
| `discovery` | After finding relevant information | NULL |
| `hypothesis` | After forming a theory about root cause | NULL |
| `clue` | After observing something potentially relevant | NULL |
| `note` | General context, references, discussion | NULL |
| `resolution` | When the fix is confirmed | `worked` |

## Resolving an Incident

```bash
# 1. Log the resolution entry
sqlite3 .claude/memory.db "INSERT INTO incident_entries (incident_id, entry_type, content, result, agent, run_id)
VALUES ('INC-001', 'resolution', 'What fixed it — e.g., made DNS lookups async, nodes now handle 50+ concurrent syncs', 'worked', 'developer', $RUN_ID);"

# 2. Update the incident status with root cause and resolution
sqlite3 .claude/memory.db "UPDATE incidents SET
    status='resolved',
    root_cause='DNS resolution was blocking the event loop',
    resolution='Made DNS lookups async using tokio::spawn',
    resolved_at=datetime('now')
WHERE incident_id='INC-001';"
```

## Closing an Incident

Close after resolution is verified in production or after QA confirms:

```bash
sqlite3 .claude/memory.db "UPDATE incidents SET status='closed' WHERE incident_id='INC-001';"
```

## Querying Incidents

```bash
# Full timeline of an incident (all attempts, discoveries, resolution)
sqlite3 -header -column .claude/memory.db "SELECT entry_type, content, result, agent, created_at FROM incident_entries WHERE incident_id='INC-001' ORDER BY id;"

# Search incidents by domain
sqlite3 -header -column .claude/memory.db "SELECT incident_id, title, status FROM incidents WHERE domain LIKE '%p2p%';"

# Search by symptoms
sqlite3 -header -column .claude/memory.db "SELECT incident_id, title, symptoms FROM incidents WHERE symptoms LIKE '%timeout%';"

# Search by tags
sqlite3 -header -column .claude/memory.db "SELECT incident_id, title, status FROM incidents WHERE tags LIKE '%concurrency%';"

# All open incidents
sqlite3 -header -column .claude/memory.db "SELECT incident_id, title, status, domain FROM incidents WHERE status IN ('open', 'investigating') ORDER BY id DESC;"

# Failed attempts for a specific incident
sqlite3 -header -column .claude/memory.db "SELECT content, result FROM incident_entries WHERE incident_id='INC-001' AND entry_type='attempt' AND result='failed';"
```

## Linking Related Incidents

```bash
# Link INC-003 as related to INC-001
sqlite3 .claude/memory.db "UPDATE incidents SET related_incidents=json_insert(COALESCE(related_incidents, '[]'), '$[#]', 'INC-003') WHERE incident_id='INC-001';"
```

## Extracting Behavioral Learnings from Incidents

When an incident is resolved, always ask: **"Did this teach us a behavioral rule — something about HOW Claude should think or work?"**

If yes, extract it:

```bash
sqlite3 .claude/memory.db "INSERT INTO behavioral_learnings (rule, context)
VALUES (
    'Always verify technical claims with evidence before stating them — do not answer reflexively',
    'Learned from INC-001: Claude claimed 10 stress nodes was trivial without analyzing resource impact'
) ON CONFLICT(rule) DO UPDATE SET
    occurrences = occurrences + 1,
    confidence = MIN(1.0, confidence + 0.1),
    last_reinforced = datetime('now');"
```

**Behavioral learnings are NOT about the bug itself.** They are about HOW Claude should behave differently to prevent similar mistakes. The bug knowledge stays in the incident; the meta-cognitive rule goes into behavioral_learnings.

Examples:
- Bug: "Claude said 10 nodes is nothing without calculating" → Learning: "Always calculate resource impact, never estimate by feel"
- Bug: "Claude retried the same approach 3 times" → Learning: "After 2 failures of the same approach, stop and reassess strategy"
- Bug: "Claude missed a race condition" → Learning: "When working with concurrent code, enumerate all shared state access points before modifying"

## Tagging Incidents

Tags enable searching across incidents by topic:

```bash
sqlite3 .claude/memory.db "UPDATE incidents SET tags='[\"concurrency\", \"p2p\", \"timeout\"]' WHERE incident_id='INC-001';"
```
