# Institutional Memory

> The SQLite layer that gives agents persistent knowledge across sessions.

## The Problem It Solves

Every Claude Code session starts fresh without OMEGA. Context compresses, sessions end, and all accumulated understanding disappears. This means:

- **The developer tries approaches that already failed** — wasting cycles rediscovering failures
- **The reviewer doesn't know a file was flagged fragile last week** — misses recurring issues
- **The analyst re-specifies requirements that already exist** — duplicate work
- **Nobody knows why a design decision was made** — archaeology through git blame

The institutional memory eliminates this by giving every agent a queryable knowledge base that survives across all sessions.

## How It Works

```
.claude/memory.db (SQLite)
         │
    ┌────┼────────────┐
    │    │             │
BRIEFING │         CLOSE-OUT
(before) │          (after)
    │    │             │
    ▼    ▼             ▼
  Agent   Agent logs    Agent verifies
  reads   incrementally completeness,
  what's  during work   distills lessons
  known
```

**Two levels of briefing:**
1. **Session briefing** (automatic, via UserPromptSubmit hook) — injects **behavioral learnings** (meta-cognitive rules that make Claude smarter), active decisions, and open incidents. Does NOT inject bug details, hotspots, outcomes, or patterns — those are noise at session start.
2. **Agent briefing** (per agent, on-demand) — each agent queries the DB for scope-specific context (hotspots, failed approaches, findings, decisions, patterns). This is targeted and relevant to the agent's current work.

**Every agent, every time:**
1. **Session Briefing** — behavioral learnings + active decisions + open incidents injected automatically. **Automated via UserPromptSubmit hook.**
2. **Agent Briefing** — agent queries memory.db for scope-specific context before starting work (hotspots, failed approaches, findings, patterns).
3. **Work + Incremental Logging** — performs its normal job, logging to memory.db **immediately after each significant action** (file changes, decisions, failed approaches, outcomes). This is the primary data capture mechanism — it ensures data reaches the DB even if context compaction occurs mid-work.
4. **Close-Out** — lightweight verification step: checks that all incremental entries were logged, scores remaining actions, distills lessons, extracts behavioral learnings, tracks bugs as incidents. Git commits are **blocked** until at least one outcome is logged.

### Why Incremental Logging (not batched debrief)

The original protocol batched all writes at the end of each agent's work ("Debrief"). This failed when context compaction occurred mid-work: the agent lost the details of what it did, and the debrief degraded to vague summaries or was skipped entirely. The most valuable entries (failed approaches, decisions with rationale, specific outcomes) were lost because they only existed in the agent's working memory.

Incremental logging fixes this: each INSERT happens within seconds of the action it describes. If context compacts, the data is already in the DB. The close-out step becomes a verification pass, not a data dump.

### Automation via Hooks

The briefing/debrief protocol was originally voluntary — agents were told to run SQL queries, but nothing enforced it. This failed (the AI skips it under cognitive load). Two Claude Code hooks now automate the critical path:

| Hook | Event | What it does | Enforcement |
|------|-------|-------------|------------|
| `briefing.sh` | UserPromptSubmit | Queries memory.db, injects context on first prompt per session (uses session_id) | **Automatic** — AI sees it, can't skip it |
| `debrief-gate.sh` | PreToolUse (Bash) | Blocks `git commit` unless outcomes logged since session start (uses briefing timestamp) | **Blocking** — AI cannot commit without logging outcomes |
| `incremental-gate.sh` | PreToolUse (Write/Edit) | Blocks file modifications after 10 edits without outcomes logged | **Blocking** — enforces incremental logging even without commits |
| `debrief-nudge.sh` | PostToolUse | Reminds AI to log incrementally (every 5th tool call if no outcomes logged this session) | **Reminder** — periodic nudge |
| `session-close.sh` | Notification | Promotes hotspot risk levels based on touch counts | **Automatic** — runs silently |

Hook scripts live in `.claude/hooks/` and are configured in `.claude/settings.json`. All are deployed automatically by `setup.sh`.

## Schema

### Tables

#### `workflow_runs` — Pipeline execution traces
Every `/workflow:*` command creates a row at start and closes it at end.

| Column | Type | Purpose |
|--------|------|---------|
| `id` | INTEGER PK | Unique run identifier, passed to all agents as `$RUN_ID` |
| `type` | TEXT | new, new-feature, improve, bugfix, audit, docs, sync, etc. |
| `description` | TEXT | User's original description |
| `scope` | TEXT | `--scope` value if provided |
| `started_at` | TEXT | Auto-set on creation |
| `completed_at` | TEXT | Set when pipeline completes or fails |
| `status` | TEXT | running → completed \| failed \| partial |
| `git_commits` | TEXT | JSON array of commit hashes produced |
| `error_message` | TEXT | What went wrong (if status=failed) |

#### `changes` — What files were touched and why
Written by: developer, architect (when updating specs/docs)

| Column | Type | Purpose |
|--------|------|---------|
| `file_path` | TEXT | Path to the changed file |
| `change_type` | TEXT | created, modified, deleted |
| `description` | TEXT | WHAT changed and WHY (the valuable part) |
| `agent` | TEXT | Which agent made the change |

#### `decisions` — Design decisions with rationale
Written by: architect, analyst, developer. Read by: all agents.

| Column | Type | Purpose |
|--------|------|---------|
| `domain` | TEXT | Area/module this decision applies to |
| `decision` | TEXT | What was decided |
| `rationale` | TEXT | WHY it was decided |
| `alternatives` | TEXT | JSON: what was considered and why rejected |
| `confidence` | REAL | 0.0–1.0 — how confident in this decision |
| `status` | TEXT | active → superseded \| reversed \| stale |
| `superseded_by` | INTEGER FK | Points to the newer decision (if superseded) |

#### `failed_approaches` — The gold mine
Written by: developer, architect. Read by: developer, architect.

| Column | Type | Purpose |
|--------|------|---------|
| `domain` | TEXT | Area/module |
| `problem` | TEXT | What was being solved |
| `approach` | TEXT | What was tried |
| `failure_reason` | TEXT | **WHY** it failed — the most valuable field in the entire DB |
| `file_paths` | TEXT | JSON array of files involved |

This table prevents the single most expensive waste in AI-assisted development: retrying approaches that already failed. When the developer's briefing returns "approach X failed because of Y", the developer skips X and starts from a better position.

#### `bugs` — Symptoms, root cause, fix
Written by: qa, developer. Read by: analyst, test-writer.

| Column | Type | Purpose |
|--------|------|---------|
| `description` | TEXT | What the bug is |
| `symptoms` | TEXT | How it manifested (error messages, behavior) |
| `root_cause` | TEXT | What actually caused it |
| `fix_description` | TEXT | How it was fixed |
| `affected_files` | TEXT | JSON array |
| `related_bug_ids` | TEXT | JSON array — bug clusters |

#### `hotspots` — Files that keep breaking
Written by: all agents. Read by: all agents.

| Column | Type | Purpose |
|--------|------|---------|
| `file_path` | TEXT UNIQUE | Path to the file |
| `risk_level` | TEXT | low → medium → high → critical (auto-promoted) |
| `times_touched` | INTEGER | Incremented every time an agent modifies this file |
| `description` | TEXT | Why this is a hotspot |

Risk levels auto-promote based on touch frequency:
- 3+ touches → medium
- 5+ touches → high
- 10+ touches → critical

#### `findings` — Reviewer/QA findings with lifecycle
Written by: reviewer, qa. Read by: developer, test-writer.

| Column | Type | Purpose |
|--------|------|---------|
| `finding_id` | TEXT | AUDIT-P0-001 format |
| `severity` | TEXT | P0, P1, P2, P3 |
| `category` | TEXT | security, performance, bug, tech-debt, etc. |
| `description` | TEXT | What's wrong |
| `file_path` | TEXT | Where it is |
| `line_range` | TEXT | e.g. "42-58" |
| `status` | TEXT | open → fixed \| wontfix \| deferred \| escalated |
| `fixed_in_run` | INTEGER FK | Which workflow run fixed it |

#### `dependencies` — Component relationships
Written by: architect, reviewer. Read by: architect, reviewer.

| Column | Type | Purpose |
|--------|------|---------|
| `source_file` | TEXT | File that depends on target |
| `target_file` | TEXT | File being depended on |
| `relationship` | TEXT | imports, calls, configures, tests |

#### `requirements` — Cross-session requirement lifecycle
Written by: analyst, test-writer, developer, qa. Read by: all agents.

| Column | Type | Purpose |
|--------|------|---------|
| `req_id` | TEXT UNIQUE | REQ-AUTH-001 format |
| `domain` | TEXT | Area/module |
| `description` | TEXT | What the requirement is |
| `priority` | TEXT | Must, Should, Could, Won't |
| `status` | TEXT | defined → tested → implemented → verified → released |
| `test_ids` | TEXT | JSON array of TEST-XXX-NNN IDs |
| `implementation_module` | TEXT | File path where implemented |

#### `patterns` — Reusable patterns discovered
Written by: developer, architect. Read by: developer, architect.

| Column | Type | Purpose |
|--------|------|---------|
| `name` | TEXT | Short pattern name |
| `description` | TEXT | What the pattern is and when to use it |
| `example_files` | TEXT | JSON array of files demonstrating it |

#### `outcomes` — Self-learning Tier 1: raw self-scored results
Written by: all pipeline agents (analyst, architect, test-writer, developer, qa, reviewer). Read by: all agents (briefing).

| Column | Type | Purpose |
|--------|------|---------|
| `agent` | TEXT | Which agent scored itself |
| `score` | INTEGER | -1 (unhelpful), 0 (neutral), +1 (helpful) |
| `domain` | TEXT | Topic/module/area |
| `action` | TEXT | What the agent did |
| `lesson` | TEXT | What was learned from the outcome |

After every significant action, agents rate their own effectiveness. The 15 most recent outcomes for a scope are injected into every future briefing, creating a feedback loop that rewards what works and penalizes what doesn't.

#### `lessons` — Self-learning Tier 2: distilled patterns from outcomes
Written by: all pipeline agents. Read by: all agents (briefing).

| Column | Type | Purpose |
|--------|------|---------|
| `domain` | TEXT | Topic/module/area |
| `content` | TEXT UNIQUE(with domain) | The distilled rule |
| `source_agent` | TEXT | Which agent first distilled this |
| `occurrences` | INTEGER | Bumped on content-match dedup |
| `confidence` | REAL | 0.0–1.0 — grows with reinforcement, decays without it |
| `status` | TEXT | active → archived \| superseded |
| `last_reinforced` | TEXT | When last dedup bump occurred |

When patterns emerge from 3+ repeated outcomes, agents distill them into permanent rules. Content-based deduplication means identical lessons bump `occurrences` instead of creating duplicates. Confidence grows with reinforcement (+0.1 per confirmation) and decays without it (-0.1 every 30 days unreinforced). Capped at 10 active lessons per domain — oldest pruned during maintenance.

#### `behavioral_learnings` — Cross-domain meta-cognitive rules
Written by: all agents (from user corrections, incident resolution, self-reflection). Read by: `briefing.sh` (session start).

| Column | Type | Purpose |
|--------|------|---------|
| `rule` | TEXT UNIQUE | The behavioral rule itself (actionable, imperative) |
| `context` | TEXT | What situation/incident taught this rule |
| `source_project` | TEXT | Which project this was learned in |
| `confidence` | REAL | 0.0–1.0 — grows with reinforcement, decays without it |
| `occurrences` | INTEGER | How many times reinforced |
| `status` | TEXT | active → superseded \| archived |

Unlike domain-specific `lessons`, behavioral learnings are about HOW Claude should think and work — they apply across all domains and projects. They are injected at the start of every session to make Claude progressively smarter.

#### `incidents` — Structured bug tracking with ticket numbers
Written by: developer, diagnostician, qa. Read by: all agents (on-demand).

| Column | Type | Purpose |
|--------|------|---------|
| `incident_id` | TEXT UNIQUE | INC-001 format |
| `title` | TEXT | Short description |
| `domain` | TEXT | Area/module affected |
| `status` | TEXT | open → investigating → resolved → closed |
| `description` | TEXT | Full description |
| `symptoms` | TEXT | How it manifests |
| `root_cause` | TEXT | What caused it (filled on resolution) |
| `resolution` | TEXT | How it was fixed (filled on resolution) |
| `affected_files` | TEXT | JSON array |
| `related_incidents` | TEXT | JSON array of related INC-NNN |
| `tags` | TEXT | JSON array of searchable keywords |

Each bug gets a ticket number and all related knowledge lives under it, replacing scattered `bugs` and `failed_approaches` entries for bug tracking.

#### `incident_entries` — Chronological log under each incident
Written by: all agents. Read by: all agents (on-demand).

| Column | Type | Purpose |
|--------|------|---------|
| `incident_id` | TEXT | References incidents.incident_id |
| `entry_type` | TEXT | attempt, discovery, clue, hypothesis, note, resolution |
| `content` | TEXT | What was tried/discovered/noted |
| `result` | TEXT | worked, failed, partial (for attempts); NULL otherwise |
| `agent` | TEXT | Which agent made this entry |

Full protocol: `.claude/protocols/incident-protocol.md`

#### `decay_log` — Memory evolution audit trail
Written by: maintenance queries. Read by: maintenance queries.

| Column | Type | Purpose |
|--------|------|---------|
| `entity_type` | TEXT | decision, approach, finding, hotspot, pattern, lesson |
| `entity_id` | INTEGER | ID of the entity being decayed |
| `action` | TEXT | archived, confidence_decayed, promoted, stale_flagged |
| `reason` | TEXT | Why the decay happened |

#### `user_profile` — Per-project identity (single row by convention)
Written by: `/workflow:onboard` command. Read by: `briefing.sh`.

| Column | Type | Purpose |
|--------|------|---------|
| `user_name` | TEXT | How the user wants to be addressed (nullable) |
| `experience_level` | TEXT | beginner, intermediate, advanced (CHECK constrained) |
| `communication_style` | TEXT | verbose, balanced, terse (CHECK constrained) |
| `created_at` | TEXT | Auto-set on creation |
| `last_seen` | TEXT | Updated by `briefing.sh` on every session |

Single-row by convention, not by constraint. The onboarding command uses `INSERT OR REPLACE` to maintain one row. Experience level auto-upgrades during briefing: beginner to intermediate at 10 completed workflows, intermediate to advanced at 30.

#### `onboarding_state` — Tracks onboarding flow progress
Written by: `/workflow:onboard` command. Read by: `/workflow:onboard` (for resume).

| Column | Type | Purpose |
|--------|------|---------|
| `step` | TEXT | Current step (defaults to 'not_started') |
| `status` | TEXT | not_started, in_progress, completed (CHECK constrained) |
| `data` | TEXT | JSON blob for partial answers (enables resume) |
| `started_at` | TEXT | When onboarding was started |
| `completed_at` | TEXT | When onboarding was completed |

Enables resumability: if the user quits mid-onboard, partial answers are preserved in the `data` JSON field and the next invocation resumes from the last incomplete step.

### Views

#### `v_file_briefing`
Composite view: for any file, shows its hotspot risk, open findings count, recent failures, and recent decisions. This is the primary briefing view — one query gives an agent everything it needs about a file.

#### `v_open_findings`
All open findings sorted by severity. Used by reviewer briefing and developer to check what's still broken.

#### `v_domain_health`
Per-domain summary: open findings, failed approaches, max risk level. High-level health dashboard.

#### `v_recent_activity`
Last 20 workflow runs with counts of files changed, findings produced, and bugs found.

#### `v_recent_outcomes`
Last 50 outcomes with agent, score, domain, action, lesson, and workflow context. Used by briefing to inject the 15 most recent outcomes for a scope.

#### `v_active_lessons`
All active lessons sorted by confidence, with a `strength` classification: strong (5+ occurrences), moderate (3+), emerging (<3). Used by briefing to inject distilled rules.

#### `v_domain_learning`
Per-domain learning health: total outcomes, positive/neutral/negative counts, average score, and active lesson count. Used for monitoring self-learning effectiveness.

#### `v_workflow_usage`
Workflow usage summary: aggregates `workflow_runs` by type, showing total runs, completed runs, and last run date. Feeds the OMEGA Identity block in briefing and experience auto-upgrade tracking. Ordered by `completed_runs DESC`. Has no dependency on `user_profile` — works regardless of whether a profile exists.

#### `v_behavioral_briefing`
Active behavioral learnings sorted by confidence. Used by `briefing.sh` to inject meta-cognitive rules at session start.

#### `v_incident_search`
All incidents sorted by status (open first), with entry count. Used for searching incidents by domain, symptoms, or tags.

#### `v_incident_timeline`
Full chronological view of an incident's entries (attempts, discoveries, resolution). Used for reviewing the complete history of a bug investigation.

## Briefing Queries by Agent

### Developer
```sql
-- Don't repeat failures
SELECT approach, failure_reason FROM failed_approaches
WHERE domain LIKE '%scheduler%' ORDER BY id DESC LIMIT 5;

-- Know the hotspots
SELECT file_path, risk_level, times_touched FROM hotspots
WHERE file_path LIKE '%scheduler%' ORDER BY times_touched DESC LIMIT 5;

-- Follow established patterns
SELECT name, description FROM patterns WHERE domain LIKE '%scheduler%';
```

### Reviewer
```sql
-- Full hotspot map
SELECT file_path, risk_level, times_touched FROM hotspots
ORDER BY times_touched DESC LIMIT 15;

-- Check if old findings are still open
SELECT finding_id, severity, description, file_path FROM findings
WHERE status='open' ORDER BY severity LIMIT 15;

-- Understand blast radius
SELECT source_file, target_file, relationship FROM dependencies
WHERE source_file LIKE '%scheduler%' OR target_file LIKE '%scheduler%';
```

### Analyst
```sql
-- Past bugs inform impact analysis
SELECT description, root_cause FROM bugs
WHERE affected_files LIKE '%scheduler%' ORDER BY id DESC LIMIT 5;

-- Don't re-specify existing requirements
SELECT req_id, description, priority, status FROM requirements
WHERE domain LIKE '%scheduler%';
```

### Test Writer
```sql
-- Write regression tests for past bugs
SELECT description, symptoms, root_cause FROM bugs
WHERE affected_files LIKE '%scheduler%' ORDER BY id DESC LIMIT 5;

-- Cover open findings
SELECT finding_id, description, file_path FROM findings
WHERE file_path LIKE '%scheduler%' AND status='open';
```

### Self-Learning (all agents)
```sql
-- Inject recent outcomes (what worked, what didn't)
SELECT agent, score, action, lesson FROM outcomes
WHERE domain LIKE '%scheduler%' ORDER BY id DESC LIMIT 15;

-- Inject active lessons (distilled rules)
SELECT content, occurrences, confidence FROM lessons
WHERE domain LIKE '%scheduler%' AND status='active' ORDER BY confidence DESC;

-- Check domain learning health
SELECT domain, avg_score, positive, negative, active_lessons
FROM v_domain_learning WHERE domain LIKE '%scheduler%';
```

**How agents use learning context:**
- Outcomes with +1 → prefer that technique
- Outcomes with -1 → avoid that approach
- Lessons with confidence ≥0.8 → treat as established rules
- Lessons with confidence ≥0.5 → strong guidance, follow unless specific reason not to
- Lessons with confidence <0.5 → emerging patterns, consider but don't blindly follow
- Negative average domain score → slow down, be extra careful

## Incremental Logging Templates

All entries are logged **immediately after the action**, not batched at the end.

### Developer — after each module
```sql
-- Log file change — immediately after modifying
INSERT INTO changes (run_id, file_path, change_type, description, agent)
VALUES (42, 'src/scheduler.rs', 'modified', 'Added null check for empty queue', 'developer');

-- Log failed approach — immediately after failure (THE MOST VALUABLE ENTRY)
INSERT INTO failed_approaches (run_id, domain, problem, approach, failure_reason, file_paths)
VALUES (42, 'scheduler', 'Empty queue crash', '.is_empty() guard before .pop()',
  'Race condition: queue empties between check and pop in concurrent context',
  '["src/scheduler.rs"]');

-- Update hotspot — immediately after modifying
INSERT INTO hotspots (file_path, times_touched) VALUES ('src/scheduler.rs', 1)
ON CONFLICT(file_path) DO UPDATE SET times_touched = times_touched + 1, last_updated = datetime('now');

-- Self-score module — immediately after module passes tests
INSERT INTO outcomes (run_id, agent, score, domain, action, lesson)
VALUES (42, 'developer', 1, 'scheduler',
  'Used Option<T> for queue access',
  'Option<T> pattern avoided unwrap panic in concurrent context');
```

### Reviewer — after each module reviewed
```sql
-- Log finding — immediately after identifying
INSERT INTO findings (run_id, finding_id, severity, category, description, file_path, line_range)
VALUES (42, 'AUDIT-P1-003', 'P1', 'bug', 'Race condition in dequeue', 'src/scheduler.rs', '140-155');

-- Promote hotspot risk — immediately after flagging
UPDATE hotspots SET risk_level='high', description='Race condition under concurrent access'
WHERE file_path='src/scheduler.rs';
```

### Close-Out — lesson distillation (all agents)
```sql
-- Check for lesson distillation opportunity (3+ outcomes with same theme?)
SELECT score, action, lesson FROM outcomes
WHERE domain = 'scheduler' AND agent = 'developer' ORDER BY id DESC LIMIT 10;

-- Distill a lesson (content-based dedup bumps occurrences automatically)
INSERT INTO lessons (domain, content, source_agent)
VALUES ('scheduler',
  'Always use Option<T> for container access in concurrent contexts — unwrap causes panics under race conditions',
  'developer')
ON CONFLICT(domain, content) DO UPDATE SET
  occurrences = occurrences + 1,
  confidence = MIN(1.0, confidence + 0.1),
  last_reinforced = datetime('now');

-- Reinforce an existing lesson you confirmed during work
UPDATE lessons SET occurrences = occurrences + 1,
  confidence = MIN(1.0, confidence + 0.1),
  last_reinforced = datetime('now')
WHERE domain = 'scheduler' AND content LIKE '%Option<T>%';

-- Supersede a lesson that no longer applies
UPDATE lessons SET status = 'superseded'
WHERE domain = 'scheduler' AND content LIKE '%outdated pattern%';
```

## The Learning Loop

```
Session starts → briefing injects behavioral learnings (meta-cognitive rules)
  → Agent starts → queries memory.db for scope-specific context
  → Agent works → logs changes, decisions, failures, outcomes, incidents INCREMENTALLY
  → Agent close-out: distills lessons, extracts behavioral learnings, tracks bugs as incidents
  → Next session starts → gets updated behavioral learnings (Claude is now smarter)
```

### Three Tiers of Learning

| Tier | Table | Scope | Injected at session start? |
|------|-------|-------|---------------------------|
| **Behavioral Learnings** | `behavioral_learnings` | Cross-domain, meta-cognitive | **YES** — the main session briefing content |
| **Lessons** | `lessons` | Domain-specific patterns | No — agent queries on-demand |
| **Outcomes** | `outcomes` | Raw self-scored actions | No — used for lesson distillation |

**Behavioral learnings** make Claude smarter over time. They are about HOW Claude should think and work. Example: "Always verify technical claims with evidence before stating them." These are extracted from user corrections, incident resolutions, and self-reflection.

**Lessons** are domain-specific patterns. Example: "Use Option<T> for container access in concurrent Rust code." These are distilled from 3+ similar outcomes.

**Outcomes** are raw self-scored actions. They feed lesson distillation but are not injected at session start.

### Incident Tracking (Bug Knowledge Base)

Bugs are tracked as **incidents** (INC-NNN) with structured entries. Each incident has a timeline of attempts, discoveries, clues, and resolution. This replaces scattered `bugs` entries with a searchable knowledge base organized by ticket number.

Full protocol: `.claude/protocols/incident-protocol.md`

**Cross-agent learning**: The developer's -1 score on a retry-heavy module informs the architect to design smaller milestones next time. When an incident is resolved, the agent extracts a behavioral learning if the bug revealed a flaw in Claude's reasoning process.

## Decay Mechanics

Memory without forgetting becomes noise. Four mechanisms keep the DB healthy:

### 1. Stale Detection
Decisions that haven't been reinforced (no related changes) for 30+ days are flagged as `stale`. Agents see stale decisions in briefings but treat them as potentially outdated.

### 2. Archival
Resolved findings (fixed/wontfix) older than 90 days are logged in `decay_log` as archived. They remain queryable but don't appear in standard briefing views.

### 3. Risk Promotion
Hotspot risk levels auto-escalate based on `times_touched`:
- 3+ → medium
- 5+ → high
- 10+ → critical

This ensures frequently-broken files get progressively more attention.

### 4. Self-Learning Decay
The self-learning tables have their own decay mechanics:
- **Outcome archival**: Raw outcomes older than 60 days are deleted — they should have been distilled into lessons by then
- **Lesson confidence decay**: Lessons not reinforced in 30+ days lose 0.1 confidence — ensuring stale rules fade
- **Lesson cap**: Maximum 10 active lessons per domain — when exceeded, lowest-confidence lessons are archived
- **Zero-confidence archival**: Lessons that decay to ≤0.1 confidence and haven't been reinforced in 60+ days are archived

## Git Integration

SQLite binary files don't diff in git. Mitigations:
- The DB is in `.claude/` which most projects `.gitignore`
- If versioning is needed, periodic `sqlite3 .claude/memory.db .dump > .claude/memory-dump.sql` creates a diffable snapshot
- The schema itself (`core/db/schema.sql`) is versioned in the toolkit repo
- `db-init.sh` uses `CREATE TABLE IF NOT EXISTS` — safe to re-run for schema migrations

## Limitations and Future Work

**Current limitations:**
- Incremental logging requires AI cooperation, but git commits are blocked without at least one outcome (enforced via PreToolUse hook)
- Agents must manually construct SQL queries — no abstraction layer
- No automated decay beyond hotspot promotion (maintenance queries must be run manually or by a scheduled workflow)
- No cross-project memory (each project has its own DB)
- `$RUN_ID` passing relies on orchestrator convention, not enforcement

**Potential future additions:**
- A `workflow:memory-health` command that runs maintenance queries + self-learning health stats
- Cross-project pattern sharing (export patterns and lessons from one project, import to another)
- Automated decay via a post-workflow hook
- A `workflow:memory-query` command for ad-hoc DB queries
- A `/learning` command to inspect outcomes and lessons (similar to OMEGA's /learning)
