# Institutional Memory

> The SQLite layer that gives agents persistent knowledge across sessions.

## The Problem It Solves

Every Claude Code session starts fresh. Context compresses, sessions end, and all accumulated understanding disappears. This means:

- **The developer tries approaches that already failed** — wasting cycles rediscovering failures
- **The reviewer doesn't know a file was flagged fragile last week** — misses recurring issues
- **The analyst re-specifies requirements that already exist** — duplicate work
- **Nobody knows why a design decision was made** — archaeology through git blame

The institutional memory eliminates this by giving every agent a queryable knowledge base that survives across all sessions.

## How It Works

```
.claude/memory.db (SQLite)
         │
    ┌────┴────┐
    │         │
 BRIEFING   DEBRIEF
 (before)   (after)
    │         │
    ▼         ▼
  Agent reads    Agent writes
  what's known   what it learned
```

**Every agent, every time:**
1. **Briefing** — queries the DB for context relevant to its scope (hotspots, failed approaches, open findings, decisions, patterns)
2. **Work** — performs its normal job, informed by the briefing
3. **Debrief** — writes back what it learned (changes, decisions, failures, bugs, findings, patterns)

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

#### `decay_log` — Memory evolution audit trail
Written by: maintenance queries. Read by: maintenance queries.

| Column | Type | Purpose |
|--------|------|---------|
| `entity_type` | TEXT | decision, approach, finding, hotspot, pattern |
| `entity_id` | INTEGER | ID of the entity being decayed |
| `action` | TEXT | archived, confidence_decayed, promoted, stale_flagged |
| `reason` | TEXT | Why the decay happened |

### Views

#### `v_file_briefing`
Composite view: for any file, shows its hotspot risk, open findings count, recent failures, and recent decisions. This is the primary briefing view — one query gives an agent everything it needs about a file.

#### `v_open_findings`
All open findings sorted by severity. Used by reviewer briefing and developer to check what's still broken.

#### `v_domain_health`
Per-domain summary: open findings, failed approaches, max risk level. High-level health dashboard.

#### `v_recent_activity`
Last 20 workflow runs with counts of files changed, findings produced, and bugs found.

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

## Debrief Templates

### Developer debrief
```sql
-- Log file change
INSERT INTO changes (run_id, file_path, change_type, description, agent)
VALUES (42, 'src/scheduler.rs', 'modified', 'Added null check for empty queue', 'developer');

-- Log failed approach (THE MOST IMPORTANT DEBRIEF)
INSERT INTO failed_approaches (run_id, domain, problem, approach, failure_reason, file_paths)
VALUES (42, 'scheduler', 'Empty queue crash', '.is_empty() guard before .pop()',
  'Race condition: queue empties between check and pop in concurrent context',
  '["src/scheduler.rs"]');

-- Update hotspot
INSERT INTO hotspots (file_path, times_touched) VALUES ('src/scheduler.rs', 1)
ON CONFLICT(file_path) DO UPDATE SET times_touched = times_touched + 1, last_updated = datetime('now');
```

### Reviewer debrief
```sql
-- Log finding
INSERT INTO findings (run_id, finding_id, severity, category, description, file_path, line_range)
VALUES (42, 'AUDIT-P1-003', 'P1', 'bug', 'Race condition in dequeue', 'src/scheduler.rs', '140-155');

-- Promote hotspot risk
UPDATE hotspots SET risk_level='high', description='Race condition under concurrent access'
WHERE file_path='src/scheduler.rs';
```

## Decay Mechanics

Memory without forgetting becomes noise. Three mechanisms keep the DB healthy:

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

## Git Integration

SQLite binary files don't diff in git. Mitigations:
- The DB is in `.claude/` which most projects `.gitignore`
- If versioning is needed, periodic `sqlite3 .claude/memory.db .dump > .claude/memory-dump.sql` creates a diffable snapshot
- The schema itself (`core/db/schema.sql`) is versioned in the toolkit repo
- `db-init.sh` uses `CREATE TABLE IF NOT EXISTS` — safe to re-run for schema migrations

## Limitations and Future Work

**Current limitations:**
- Agents must manually construct SQL queries — no abstraction layer
- No automated decay (maintenance queries must be run manually or by a scheduled workflow)
- No cross-project memory (each project has its own DB)
- `$RUN_ID` passing relies on orchestrator convention, not enforcement

**Potential future additions:**
- A `workflow:memory-health` command that runs maintenance queries
- Cross-project pattern sharing (export patterns from one project, import to another)
- Automated decay via a post-workflow hook
- A `workflow:memory-query` command for ad-hoc DB queries
