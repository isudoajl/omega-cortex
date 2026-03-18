# Institutional Memory Protocol

Every workflow reads from and writes to `.claude/memory.db`. This is the backpressure mechanism that prevents agents from acting in isolation. **This protocol is not optional** — it is the foundation that gives OMEGA persistent knowledge across sessions.

## DB Detection
At the start of **every session and every workflow**, check if the DB exists:

```bash
test -f .claude/memory.db && echo "DB_EXISTS" || echo "NO_DB"
```

- If `DB_EXISTS` → follow the full protocol below
- If `NO_DB` → skip memory operations gracefully, work without institutional memory

## Pipeline Start (orchestrator responsibility)
Every `/omega:*` command creates a run entry at the **very beginning**, before invoking any agent:

```bash
sqlite3 .claude/memory.db "INSERT INTO workflow_runs (type, description, scope) VALUES ('WORKFLOW_TYPE', 'USER_DESCRIPTION', 'SCOPE_OR_NULL');"
RUN_ID=$(sqlite3 .claude/memory.db "SELECT last_insert_rowid();")
```

Replace `WORKFLOW_TYPE` with: `new`, `new-feature`, `improve`, `bugfix`, `audit`, `docs`, `sync`, etc.

## Briefing (MANDATORY — before every agent starts work)
Before doing any work on a scope, the agent queries the DB. Replace `$SCOPE` with the module, domain, or file path being worked on:

```bash
# 1. HOTSPOTS — what files are fragile in my scope?
sqlite3 .claude/memory.db "SELECT file_path, risk_level, times_touched FROM hotspots WHERE file_path LIKE '%$SCOPE%' ORDER BY times_touched DESC LIMIT 5;"

# 2. FAILED APPROACHES — what already failed? DON'T repeat it.
sqlite3 .claude/memory.db "SELECT approach, failure_reason FROM failed_approaches WHERE domain LIKE '%$SCOPE%' ORDER BY id DESC LIMIT 5;"

# 3. OPEN FINDINGS — what's known to be broken?
sqlite3 .claude/memory.db "SELECT finding_id, severity, description FROM findings WHERE file_path LIKE '%$SCOPE%' AND status='open' ORDER BY severity LIMIT 10;"

# 4. ACTIVE DECISIONS — what was decided and why?
sqlite3 .claude/memory.db "SELECT decision, rationale FROM decisions WHERE domain LIKE '%$SCOPE%' AND status='active' ORDER BY id DESC LIMIT 5;"

# 5. KNOWN PATTERNS — what patterns should I follow?
sqlite3 .claude/memory.db "SELECT name, description FROM patterns WHERE domain LIKE '%$SCOPE%';"

# 6. PAST BUGS — what broke before in this area?
sqlite3 .claude/memory.db "SELECT description, root_cause, fix_description FROM bugs WHERE affected_files LIKE '%$SCOPE%' ORDER BY id DESC LIMIT 5;"
```

**How to use the results:**
- If `failed_approaches` returns results → **do NOT retry those approaches**. Start from a different angle.
- If `hotspots` shows `risk_level='high'` or `'critical'` → **be extra careful**, add more tests, review more thoroughly.
- If `findings` shows open P0/P1 → **address them** if they're in your scope.
- If `decisions` exist → **respect them** unless you have a strong reason to supersede (and document why).
- If `patterns` exist → **follow them** for consistency.

## Incremental Logging (MANDATORY — during work)
Log to memory.db **immediately after each significant action**. Do NOT batch entries for the end of your work — if context compaction occurs, batched entries are lost forever. Incremental logging IS the checkpoint mechanism.

**When to log** (within seconds of the action, not later):

| Trigger | What to INSERT |
|---------|---------------|
| After modifying a file | `changes` + `hotspots` upsert |
| After making a design/implementation decision | `decisions` |
| After an approach fails (even partially) | `failed_approaches` |
| After discovering a bug | `bugs` |
| After completing a discrete unit of work | `outcomes` (self-score) |
| After discovering a reusable pattern | `patterns` |
| After discovering a component dependency | `dependencies` |
| After defining a requirement (analyst) | `requirements` |
| After identifying a finding (reviewer/QA) | `findings` |

```bash
# AFTER MODIFYING A FILE — log immediately
sqlite3 .claude/memory.db "INSERT INTO changes (run_id, file_path, change_type, description, agent) VALUES ($RUN_ID, 'path/to/file.rs', 'modified', 'What changed and WHY', 'developer');"
sqlite3 .claude/memory.db "INSERT INTO hotspots (file_path, times_touched, description) VALUES ('path/to/file.rs', 1, 'Why it was touched') ON CONFLICT(file_path) DO UPDATE SET times_touched = times_touched + 1, last_updated = datetime('now');"

# AFTER A DECISION — log immediately
sqlite3 .claude/memory.db "INSERT INTO decisions (run_id, domain, decision, rationale, alternatives, confidence) VALUES ($RUN_ID, 'module-name', 'What was decided', 'Why this choice', '[\"rejected alternative 1: reason\", \"rejected alternative 2: reason\"]', 0.9);"

# AFTER A FAILED APPROACH — log immediately (THE MOST VALUABLE ENTRY)
sqlite3 .claude/memory.db "INSERT INTO failed_approaches (run_id, domain, problem, approach, failure_reason, file_paths) VALUES ($RUN_ID, 'module-name', 'What I was trying to solve', 'What I tried', 'Why it did not work', '[\"file1.rs\", \"file2.rs\"]');"

# AFTER FINDING A BUG — log immediately
sqlite3 .claude/memory.db "INSERT INTO bugs (run_id, description, symptoms, root_cause, fix_description, affected_files) VALUES ($RUN_ID, 'Bug description', 'Error messages or behavior seen', 'Root cause', 'How it was fixed', '[\"files\"]');"

# AFTER COMPLETING A UNIT OF WORK — self-score immediately
sqlite3 .claude/memory.db "INSERT INTO outcomes (run_id, agent, score, domain, action, lesson) VALUES ($RUN_ID, 'AGENT_NAME', SCORE, 'domain', 'What I did', 'What I learned');"

# AFTER IDENTIFYING A FINDING (reviewer/QA) — log immediately
sqlite3 .claude/memory.db "INSERT INTO findings (run_id, finding_id, severity, category, description, file_path, line_range) VALUES ($RUN_ID, 'AUDIT-P1-001', 'P1', 'bug', 'Description', 'file_path', '42-58');"

# AFTER DEFINING A REQUIREMENT (analyst) — log immediately
sqlite3 .claude/memory.db "INSERT OR IGNORE INTO requirements (run_id, req_id, domain, description, priority) VALUES ($RUN_ID, 'REQ-XXX-001', 'domain', 'Requirement description', 'Must');"

# AFTER DISCOVERING A PATTERN — log immediately
sqlite3 .claude/memory.db "INSERT INTO patterns (run_id, domain, name, description, example_files) VALUES ($RUN_ID, 'domain', 'Pattern name', 'When and how to use it', '[\"example_files\"]');"

# AFTER DISCOVERING A DEPENDENCY — log immediately
sqlite3 .claude/memory.db "INSERT OR IGNORE INTO dependencies (source_file, target_file, relationship, discovered_run) VALUES ('caller.rs', 'callee.rs', 'calls', $RUN_ID);"
```

**Rules for incremental logging:**
- Log **immediately** — each INSERT happens within seconds of the action it describes
- Log **every** file change, not just the important ones
- Log **every** failed approach, even small ones — these are the most valuable entries in the entire DB
- Log decisions with the **alternatives you rejected and why** — future sessions need to know what was considered
- If a DB write fails, **log the error and continue working** — never block work for a failed INSERT
- If you don't have a `$RUN_ID`, get it: `sqlite3 .claude/memory.db "SELECT MAX(id) FROM workflow_runs;"`

## Close-Out (MANDATORY — when agent completes or stops)
When your work is complete (or when stopping due to context budget / errors), run a lightweight verification:

1. **Verify completeness** — review what you logged incrementally. Are there any file changes, decisions, or failed approaches you forgot to log? Insert them now.
2. **Final self-scoring** — score any remaining significant actions you haven't yet scored.
3. **Check for lesson distillation** — do 3+ recent outcomes share a theme? If so, distill a lesson (see Self-Learning below).
4. **Reinforce/supersede lessons** — if you confirmed an existing lesson, reinforce it. If one no longer applies, supersede it.
5. **Extract behavioral learnings** — did the user correct your approach? Did you discover something about HOW to work better? If so, extract a behavioral learning (see Behavioral Learnings below).
6. **Track bugs as incidents** — if bugs were encountered, ensure they have incident tickets (see Incident Protocol).

If context is tight, the close-out can be minimal — the important data was already logged incrementally. At minimum, ensure at least one outcome is logged (required for git commits).

## Pipeline End (orchestrator responsibility)
When the workflow completes or fails:

```bash
# On success
sqlite3 .claude/memory.db "UPDATE workflow_runs SET status='completed', completed_at=datetime('now'), git_commits='[\"commit_hash1\", \"commit_hash2\"]' WHERE id=$RUN_ID;"

# On failure
sqlite3 .claude/memory.db "UPDATE workflow_runs SET status='failed', completed_at=datetime('now'), error_message='What failed and why' WHERE id=$RUN_ID;"

# On partial (context budget hit, will resume)
sqlite3 .claude/memory.db "UPDATE workflow_runs SET status='partial', completed_at=datetime('now'), error_message='Context budget reached at step X' WHERE id=$RUN_ID;"
```

## Non-Pipeline Sessions
When working **outside** a formal `/omega:*` command (e.g., user asks for a quick fix, a one-off question, or manual work):

1. **Still check the DB** — run the briefing queries for the area you're working on
2. **Still write back** — create a workflow_run with type `'manual'` and log what you did
3. The point is that **no work goes unrecorded**, even informal work

```bash
sqlite3 .claude/memory.db "INSERT INTO workflow_runs (type, description) VALUES ('manual', 'Quick fix for X');"
RUN_ID=$(sqlite3 .claude/memory.db "SELECT last_insert_rowid();")
# ... do work, run briefing, log incrementally, close out ...
sqlite3 .claude/memory.db "UPDATE workflow_runs SET status='completed', completed_at=datetime('now') WHERE id=$RUN_ID;"
```

## Self-Learning (Outcome Scoring + Lesson Distillation)

The institutional memory evaluates *how well things worked* and distills patterns for future sessions. Two-tier reward-based learning loop.

### Tier 1: Outcomes (Working Memory)

**Immediately after** every significant action, the agent self-scores:

```bash
sqlite3 .claude/memory.db "INSERT INTO outcomes (run_id, agent, score, domain, action, lesson) VALUES ($RUN_ID, 'AGENT_NAME', SCORE, 'DOMAIN', 'What I did', 'What I learned from doing it');"
```

**Scoring guide:**
| Score | Meaning | When to use |
|-------|---------|-------------|
| **+1** | Helpful | Approach succeeded cleanly, minimal iteration, good result worth repeating |
| **0** | Neutral | Worked but unremarkable, nothing to learn from this |
| **-1** | Unhelpful | Approach failed, required excessive iteration, hit walls, produced suboptimal result |

**Rules:**
- Score **every significant action**, not just the final result
- Be **honest** — a -1 is more valuable than a false +1
- Include **specific context** in the lesson text, not vague statements
- Bad: `"it worked"` → Good: `"Option<T> pattern avoided unwrap panic in concurrent queue access"`
- The `lesson` field must be **transferable insight** — something a future agent would act *differently* on. Narrating what you did ("I used rsync to deploy") is episodic, not a lesson. If there's no transfer value, leave the lesson field as an empty string or a dash.

**During briefing**, inject recent outcomes:
```bash
sqlite3 .claude/memory.db "SELECT agent, score, action, lesson FROM outcomes WHERE domain LIKE '%$SCOPE%' ORDER BY id DESC LIMIT 15;"
```

**How to use outcomes in briefing:**
- If recent outcomes show repeated -1 scores for an approach → **avoid that approach**
- If recent outcomes show +1 for a technique → **prefer that technique**
- If the domain's average score is negative → **slow down, be extra careful, consider asking for help**

### Tier 2: Lessons (Long-Term Memory)

When patterns emerge from repeated outcomes, distill them into **permanent rules**:

```bash
sqlite3 .claude/memory.db "INSERT INTO lessons (domain, content, source_agent) VALUES ('DOMAIN', 'The distilled rule', 'AGENT_NAME') ON CONFLICT(domain, content) DO UPDATE SET occurrences = occurrences + 1, confidence = MIN(1.0, confidence + 0.1), last_reinforced = datetime('now');"
```

**When to distill a lesson:**
- You notice **3+ outcomes in the same domain** sharing a theme
- You confirm an approach that **consistently works** (+1) or **consistently fails** (-1)
- You discover a **non-obvious pattern** that future agents would benefit from
- **Episodic filter (apply before every distillation):** ask "Would a future Claude, reading this cold, make a *better decision* because of it?" If the answer is "it would know what happened" rather than "it would act differently" — skip distillation. Episodic logs belong in `outcomes.action`, not in lessons.

**Lesson constraints:**
- **Cap of 10 active lessons per domain** — oldest/lowest-confidence pruned during maintenance
- **Content-based dedup** — if the exact lesson already exists, occurrences bumps automatically
- **Confidence grows** with reinforcement (+0.1 per confirmation, max 1.0)
- **Confidence decays** without reinforcement (-0.1 every 30 days unreinforced)

**During briefing**, inject active lessons:
```bash
sqlite3 .claude/memory.db "SELECT content, occurrences, confidence FROM lessons WHERE domain LIKE '%$SCOPE%' AND status='active' ORDER BY confidence DESC;"
```

**How to use lessons in briefing:**
- Lessons with `confidence >= 0.8` → **treat as established rules**, follow them
- Lessons with `confidence >= 0.5` → **strong guidance**, follow unless you have specific reason not to
- Lessons with `confidence < 0.5` → **emerging patterns**, consider but don't blindly follow
- If a lesson no longer applies → **supersede it**: `UPDATE lessons SET status='superseded' WHERE ...`

### The Loop

```
Agent starts → briefing injects outcomes + lessons
  → Agent works → logs changes, decisions, failures, outcomes INCREMENTALLY
  → Agent close-out: verifies completeness, distills lessons, reinforces/supersedes
  → Next agent (or next session) gets updated context
```

### Self-Learning at Close-Out

```bash
# 1. CHECK FOR DISTILLATION — do recent outcomes suggest a pattern?
sqlite3 .claude/memory.db "SELECT score, action, lesson FROM outcomes WHERE domain='DOMAIN' AND agent='AGENT' ORDER BY id DESC LIMIT 10;"
# If 3+ share a theme → distill:

# 2. DISTILL LESSON (only if pattern detected)
sqlite3 .claude/memory.db "INSERT INTO lessons (domain, content, source_agent) VALUES ('domain', 'The pattern rule', 'agent') ON CONFLICT(domain, content) DO UPDATE SET occurrences = occurrences + 1, confidence = MIN(1.0, confidence + 0.1), last_reinforced = datetime('now');"

# 3. REINFORCE existing lessons you confirmed during work
sqlite3 .claude/memory.db "UPDATE lessons SET occurrences = occurrences + 1, confidence = MIN(1.0, confidence + 0.1), last_reinforced = datetime('now') WHERE domain='domain' AND content LIKE '%pattern%';"

# 4. SUPERSEDE lessons that no longer apply
sqlite3 .claude/memory.db "UPDATE lessons SET status='superseded' WHERE domain='domain' AND content LIKE '%outdated pattern%';"
```

## Behavioral Learnings (Session-Level Intelligence)

Behavioral learnings are **cross-domain meta-cognitive rules** about HOW Claude should think and work. Unlike domain-specific lessons, these apply to ALL work across ALL projects. They are injected at the start of every session via the briefing hook.

**What qualifies as a behavioral learning:**
- Rules about Claude's reasoning process: "Always verify claims with evidence"
- Rules about interaction quality: "When a user challenges your answer, re-analyze rather than defend"
- Rules about analysis discipline: "Calculate resource impact, never estimate by feel"
- Rules about work patterns: "After 2 failures of the same approach, stop and reassess"

**What does NOT qualify:**
- Domain-specific patterns: "Use Option<T> in Rust concurrent code" → this is a `lesson`
- Project-specific conventions: "Deploy via rsync" → this is a `pattern`
- Bug details: "setup.sh fails with sed" → this is an `incident`

### When to Create a Behavioral Learning

1. **User correction** (strongest signal): The user says "don't do X" or "you should always Y" and the insight is about HOW Claude works, not domain-specific.
2. **Incident resolution**: Resolving an incident reveals a flaw in Claude's reasoning process.
3. **Self-reflection**: You notice you made an avoidable mistake and can articulate a rule to prevent it.

### How to Create/Reinforce

```bash
# Create a new behavioral learning
sqlite3 .claude/memory.db "INSERT INTO behavioral_learnings (rule, context)
VALUES (
    'Always verify technical claims with evidence before stating them',
    'Learned from INC-001: claimed 10 stress nodes was trivial without calculating resource impact'
) ON CONFLICT(rule) DO UPDATE SET
    occurrences = occurrences + 1,
    confidence = MIN(1.0, confidence + 0.1),
    last_reinforced = datetime('now');"

# Reinforce an existing learning
sqlite3 .claude/memory.db "UPDATE behavioral_learnings SET
    occurrences = occurrences + 1,
    confidence = MIN(1.0, confidence + 0.1),
    last_reinforced = datetime('now')
WHERE rule LIKE '%verify%claims%';"

# Supersede a learning that no longer applies
sqlite3 .claude/memory.db "UPDATE behavioral_learnings SET status='superseded' WHERE rule LIKE '%outdated rule%';"
```

### Confidence Mechanics
- Starts at **0.5** (emerging)
- Grows **+0.1** per reinforcement (max 1.0)
- Decays **-0.1** every 30 days unreinforced
- At **0.8+**: treat as established rule — follow always
- At **0.5-0.7**: strong guidance — follow unless specific reason not to
- Below **0.5**: emerging — consider but don't blindly follow

## Incident Tracking (Bug Knowledge Base)

Incidents replace scattered `bugs` table entries with a structured ticket system. Each bug gets a ticket number (INC-NNN) and all related knowledge lives under it.

**Full protocol:** Read `.claude/protocols/incident-protocol.md` for create/update/resolve/query procedures.

**Core rules:**
- Every bug gets an incident ticket (INC-NNN)
- Every attempt, discovery, and clue is logged as an incident entry
- On resolution, always ask: "Does this teach us a behavioral rule?"
- Incidents are NOT injected in full at session start — only titles/status appear in the briefing
- Full incident details are queried on-demand when working in the relevant domain

### Quick Reference

```bash
# Get next incident ID
NEXT_ID=$(sqlite3 .claude/memory.db "SELECT 'INC-' || printf('%03d', COALESCE(MAX(CAST(SUBSTR(incident_id, 5) AS INTEGER)), 0) + 1) FROM incidents;")

# Create incident
sqlite3 .claude/memory.db "INSERT INTO incidents (incident_id, title, domain, description, symptoms, run_id) VALUES ('$NEXT_ID', 'title', 'domain', 'description', 'symptoms', $RUN_ID);"

# Log an attempt
sqlite3 .claude/memory.db "INSERT INTO incident_entries (incident_id, entry_type, content, result, agent, run_id) VALUES ('INC-001', 'attempt', 'What was tried', 'failed', 'developer', $RUN_ID);"

# Resolve incident
sqlite3 .claude/memory.db "UPDATE incidents SET status='resolved', root_cause='...', resolution='...', resolved_at=datetime('now') WHERE incident_id='INC-001';"
```

## Error Handling
- If `sqlite3` command fails → **log the error but continue working**. Never block work because the DB is inaccessible.
- If a query returns empty results → that's normal for new projects. Proceed without institutional context.
- If the DB is corrupted → inform the user, suggest re-initializing with `bash scripts/db-init.sh`.
