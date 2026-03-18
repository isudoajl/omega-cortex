-- Claude Workflow Institutional Memory Schema
-- Version: 1.2.0 — Added behavioral learnings and incident tracking
-- Every workflow execution writes to this DB. Every agent reads from it before acting.

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- ============================================================
-- WORKFLOW RUNS — every pipeline execution leaves a trace
-- ============================================================
CREATE TABLE IF NOT EXISTS workflow_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,                    -- new, new-feature, improve, bugfix, audit, docs, sync, etc.
    description TEXT,                      -- user's original description
    scope TEXT,                            -- --scope value if provided
    started_at TEXT DEFAULT (datetime('now')),
    completed_at TEXT,
    status TEXT DEFAULT 'running',         -- running, completed, failed, partial
    git_commits TEXT,                      -- JSON array of commit hashes produced
    error_message TEXT                     -- if status=failed, what went wrong
);

-- ============================================================
-- CHANGES — what files were touched and why
-- ============================================================
CREATE TABLE IF NOT EXISTS changes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL REFERENCES workflow_runs(id),
    file_path TEXT NOT NULL,
    change_type TEXT NOT NULL,             -- created, modified, deleted
    description TEXT,                      -- WHAT changed and WHY
    agent TEXT NOT NULL,                   -- which agent made this change
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_changes_file ON changes(file_path);
CREATE INDEX IF NOT EXISTS idx_changes_run ON changes(run_id);

-- ============================================================
-- DECISIONS — architectural and design decisions with rationale
-- ============================================================
CREATE TABLE IF NOT EXISTS decisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL REFERENCES workflow_runs(id),
    domain TEXT,                           -- which area/module
    decision TEXT NOT NULL,                -- what was decided
    rationale TEXT,                        -- WHY it was decided
    alternatives TEXT,                     -- JSON: what else was considered and why rejected
    confidence REAL DEFAULT 1.0,           -- 0.0-1.0, how confident in this decision
    status TEXT DEFAULT 'active',          -- active, superseded, reversed
    superseded_by INTEGER REFERENCES decisions(id),
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_decisions_domain ON decisions(domain);

-- ============================================================
-- FAILED APPROACHES — the gold mine for future problem-solving
-- ============================================================
CREATE TABLE IF NOT EXISTS failed_approaches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL REFERENCES workflow_runs(id),
    domain TEXT,                           -- which area/module
    problem TEXT NOT NULL,                 -- what was being solved
    approach TEXT NOT NULL,                -- what was tried
    failure_reason TEXT NOT NULL,          -- WHY it failed (the valuable part)
    file_paths TEXT,                       -- JSON array of files involved
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_failed_domain ON failed_approaches(domain);

-- ============================================================
-- BUGS — symptoms, root cause, fix (clusters related bugs)
-- ============================================================
CREATE TABLE IF NOT EXISTS bugs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL REFERENCES workflow_runs(id),
    description TEXT NOT NULL,
    symptoms TEXT,                         -- how it manifested (error messages, behavior)
    root_cause TEXT,                       -- what actually caused it
    fix_description TEXT,                  -- how it was fixed
    affected_files TEXT,                   -- JSON array
    related_bug_ids TEXT,                  -- JSON array — bug clusters
    created_at TEXT DEFAULT (datetime('now'))
);

-- ============================================================
-- HOTSPOTS — files that keep breaking or being touched
-- ============================================================
CREATE TABLE IF NOT EXISTS hotspots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT UNIQUE NOT NULL,
    risk_level TEXT DEFAULT 'low',         -- low, medium, high, critical
    description TEXT,                      -- why this is a hotspot
    times_touched INTEGER DEFAULT 1,
    last_incident_run INTEGER REFERENCES workflow_runs(id),
    last_updated TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_hotspots_risk ON hotspots(risk_level);

-- ============================================================
-- FINDINGS — reviewer/QA findings that persist across sessions
-- ============================================================
CREATE TABLE IF NOT EXISTS findings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL REFERENCES workflow_runs(id),
    finding_id TEXT,                       -- AUDIT-P0-001 format
    severity TEXT NOT NULL,                -- P0, P1, P2, P3
    category TEXT,                         -- security, performance, bug, tech-debt, etc.
    description TEXT NOT NULL,
    file_path TEXT,
    line_range TEXT,                       -- e.g. "42-58"
    status TEXT DEFAULT 'open',            -- open, fixed, wontfix, deferred, escalated
    fixed_in_run INTEGER REFERENCES workflow_runs(id),
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_findings_status ON findings(status);
CREATE INDEX IF NOT EXISTS idx_findings_file ON findings(file_path);
CREATE INDEX IF NOT EXISTS idx_findings_severity ON findings(severity);

-- ============================================================
-- DEPENDENCIES — component relationships discovered during work
-- ============================================================
CREATE TABLE IF NOT EXISTS dependencies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_file TEXT NOT NULL,
    target_file TEXT NOT NULL,
    relationship TEXT NOT NULL,            -- imports, calls, configures, tests
    discovered_run INTEGER REFERENCES workflow_runs(id),
    created_at TEXT DEFAULT (datetime('now')),
    UNIQUE(source_file, target_file, relationship)
);

-- ============================================================
-- REQUIREMENTS — traceability across sessions
-- ============================================================
CREATE TABLE IF NOT EXISTS requirements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL REFERENCES workflow_runs(id),
    req_id TEXT UNIQUE NOT NULL,           -- REQ-AUTH-001 format
    domain TEXT,
    description TEXT NOT NULL,
    priority TEXT NOT NULL,                -- Must, Should, Could, Won't
    status TEXT DEFAULT 'defined',         -- defined, tested, implemented, verified, released
    test_ids TEXT,                         -- JSON array of TEST-XXX-NNN IDs
    implementation_module TEXT,            -- file_path where implemented
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_requirements_domain ON requirements(domain);
CREATE INDEX IF NOT EXISTS idx_requirements_status ON requirements(status);

-- ============================================================
-- PATTERNS — successful patterns discovered that should be reused
-- ============================================================
CREATE TABLE IF NOT EXISTS patterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL REFERENCES workflow_runs(id),
    domain TEXT,
    name TEXT NOT NULL,                    -- short pattern name
    description TEXT NOT NULL,             -- what the pattern is
    example_files TEXT,                    -- JSON array of files demonstrating it
    created_at TEXT DEFAULT (datetime('now'))
);

-- ============================================================
-- OUTCOMES — Tier 1 self-learning: raw self-scored results
-- ============================================================
CREATE TABLE IF NOT EXISTS outcomes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER REFERENCES workflow_runs(id),
    agent TEXT NOT NULL,                   -- which agent scored itself
    score INTEGER NOT NULL CHECK(score IN (-1, 0, 1)),  -- -1 unhelpful, 0 neutral, +1 helpful
    domain TEXT,                           -- topic/module/area
    action TEXT NOT NULL,                  -- what the agent did
    lesson TEXT NOT NULL,                  -- what was learned from the outcome
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_outcomes_domain ON outcomes(domain);
CREATE INDEX IF NOT EXISTS idx_outcomes_agent ON outcomes(agent);
CREATE INDEX IF NOT EXISTS idx_outcomes_score ON outcomes(score);

-- ============================================================
-- LESSONS — Tier 2 self-learning: distilled patterns from outcomes
-- ============================================================
CREATE TABLE IF NOT EXISTS lessons (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    domain TEXT NOT NULL,
    content TEXT NOT NULL,                  -- the distilled rule
    source_agent TEXT,                      -- which agent first distilled this
    occurrences INTEGER DEFAULT 1,          -- bumped on content-match dedup
    confidence REAL DEFAULT 0.5,            -- 0.0-1.0, grows with reinforcement
    status TEXT DEFAULT 'active',           -- active, archived, superseded
    created_at TEXT DEFAULT (datetime('now')),
    last_reinforced TEXT DEFAULT (datetime('now')),
    UNIQUE(domain, content)                -- content-based deduplication
);

CREATE INDEX IF NOT EXISTS idx_lessons_domain ON lessons(domain);
CREATE INDEX IF NOT EXISTS idx_lessons_status ON lessons(status);

-- ============================================================
-- BEHAVIORAL LEARNINGS — cross-domain meta-cognitive rules
-- These are injected at session start to make agents smarter.
-- Unlike lessons (domain-specific patterns), these are about
-- HOW to think and work, not WHAT works in a specific domain.
-- ============================================================
CREATE TABLE IF NOT EXISTS behavioral_learnings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule TEXT NOT NULL,                    -- The behavioral rule itself (actionable, imperative)
    context TEXT,                          -- What incident/situation taught this rule
    source_project TEXT,                   -- Which project this was learned in
    confidence REAL DEFAULT 0.5,           -- 0.0-1.0, grows with reinforcement
    occurrences INTEGER DEFAULT 1,         -- How many times reinforced
    status TEXT DEFAULT 'active',          -- active, superseded, archived
    created_at TEXT DEFAULT (datetime('now')),
    last_reinforced TEXT DEFAULT (datetime('now')),
    UNIQUE(rule)                           -- Content-based dedup
);

CREATE INDEX IF NOT EXISTS idx_behavioral_status ON behavioral_learnings(status);
CREATE INDEX IF NOT EXISTS idx_behavioral_confidence ON behavioral_learnings(confidence);

-- ============================================================
-- INCIDENTS — structured bug tracking with ticket numbers
-- Each bug gets a ticket (INC-001) and all related knowledge
-- (attempts, discoveries, clues, resolution) lives under it.
-- Replaces scattered bugs/failed_approaches for bug tracking.
-- ============================================================
CREATE TABLE IF NOT EXISTS incidents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    incident_id TEXT UNIQUE NOT NULL,      -- INC-001 format
    title TEXT NOT NULL,                   -- Short description
    domain TEXT,                           -- Area/module affected
    status TEXT DEFAULT 'open',            -- open, investigating, resolved, closed
    description TEXT,                      -- Full description of the issue
    symptoms TEXT,                         -- How it manifests (error messages, behavior)
    root_cause TEXT,                       -- What actually caused it (filled on resolution)
    resolution TEXT,                       -- How it was fixed (filled on resolution)
    affected_files TEXT,                   -- JSON array of file paths
    related_incidents TEXT,                -- JSON array of related INC-NNN
    tags TEXT,                             -- JSON array of searchable keywords
    run_id INTEGER REFERENCES workflow_runs(id),
    created_at TEXT DEFAULT (datetime('now')),
    resolved_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_incidents_status ON incidents(status);
CREATE INDEX IF NOT EXISTS idx_incidents_domain ON incidents(domain);

-- ============================================================
-- INCIDENT ENTRIES — chronological log under each incident
-- Every attempt, discovery, clue, and note is an entry.
-- This creates a searchable knowledge base per bug.
-- ============================================================
CREATE TABLE IF NOT EXISTS incident_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    incident_id TEXT NOT NULL,             -- References incidents.incident_id
    entry_type TEXT NOT NULL,              -- attempt, discovery, clue, hypothesis, note, resolution
    content TEXT NOT NULL,                 -- What was tried/discovered/noted
    result TEXT,                           -- worked, failed, partial (for attempts); NULL for non-attempts
    agent TEXT,                            -- Which agent made this entry
    run_id INTEGER REFERENCES workflow_runs(id),
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_incident_entries_incident ON incident_entries(incident_id);
CREATE INDEX IF NOT EXISTS idx_incident_entries_type ON incident_entries(entry_type);

-- ============================================================
-- DECAY LOG — tracks how the memory evolves over time
-- ============================================================
CREATE TABLE IF NOT EXISTS decay_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT NOT NULL,             -- decision, approach, finding, hotspot, pattern
    entity_id INTEGER NOT NULL,
    action TEXT NOT NULL,                  -- archived, confidence_decayed, promoted, stale_flagged
    reason TEXT,
    run_id INTEGER REFERENCES workflow_runs(id),
    created_at TEXT DEFAULT (datetime('now'))
);

-- ============================================================
-- USER PROFILE — per-project identity (single row by convention)
-- ============================================================
CREATE TABLE IF NOT EXISTS user_profile (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_name TEXT,
    experience_level TEXT DEFAULT 'beginner'
        CHECK(experience_level IN ('beginner', 'intermediate', 'advanced')),
    communication_style TEXT DEFAULT 'balanced'
        CHECK(communication_style IN ('verbose', 'balanced', 'terse')),
    created_at TEXT DEFAULT (datetime('now')),
    last_seen TEXT DEFAULT (datetime('now'))
);

-- ============================================================
-- ONBOARDING STATE — tracks onboarding flow progress
-- ============================================================
CREATE TABLE IF NOT EXISTS onboarding_state (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    step TEXT DEFAULT 'not_started',
    status TEXT DEFAULT 'not_started'
        CHECK(status IN ('not_started', 'in_progress', 'completed')),
    data TEXT,                              -- JSON blob for partial state
    started_at TEXT,
    completed_at TEXT
);

-- ============================================================
-- VIEWS — pre-built queries agents use frequently
-- ============================================================

-- Briefing view: what an agent needs before touching a file
CREATE VIEW IF NOT EXISTS v_file_briefing AS
SELECT
    h.file_path,
    h.risk_level,
    h.times_touched,
    h.description as hotspot_reason,
    (SELECT COUNT(*) FROM findings f
     WHERE f.file_path = h.file_path AND f.status = 'open') as open_findings,
    (SELECT GROUP_CONCAT(fa.approach || ' -> FAILED: ' || fa.failure_reason, ' | ')
     FROM failed_approaches fa
     WHERE fa.file_paths LIKE '%' || h.file_path || '%'
     ORDER BY fa.id DESC LIMIT 3) as recent_failures,
    (SELECT GROUP_CONCAT(d.decision || ' (' || d.rationale || ')', ' | ')
     FROM decisions d
     WHERE d.domain LIKE '%' || h.file_path || '%'
     ORDER BY d.id DESC LIMIT 3) as recent_decisions
FROM hotspots h;

-- Active findings by severity
CREATE VIEW IF NOT EXISTS v_open_findings AS
SELECT
    finding_id, severity, category, description, file_path, line_range, status,
    (SELECT w.type || ': ' || w.description FROM workflow_runs w WHERE w.id = f.run_id) as discovered_in
FROM findings f
WHERE f.status = 'open'
ORDER BY
    CASE f.severity WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 END;

-- Domain health overview
CREATE VIEW IF NOT EXISTS v_domain_health AS
SELECT
    domain,
    COUNT(DISTINCT CASE WHEN status = 'open' THEN f_id END) as open_findings,
    COUNT(DISTINCT CASE WHEN outcome = 'failed' THEN fa_id END) as failed_approaches,
    MAX(h_risk) as max_risk
FROM (
    SELECT
        COALESCE(f.file_path, fa.domain, h.file_path) as domain,
        f.id as f_id, f.status,
        fa.id as fa_id, fa.id IS NOT NULL as outcome,
        h.risk_level as h_risk
    FROM findings f
    LEFT JOIN failed_approaches fa ON fa.domain = f.file_path
    LEFT JOIN hotspots h ON h.file_path = f.file_path
)
GROUP BY domain;

-- Learning context: recent outcomes + active lessons for a scope
-- Usage: SELECT * FROM v_recent_outcomes WHERE domain LIKE '%scheduler%';
CREATE VIEW IF NOT EXISTS v_recent_outcomes AS
SELECT
    o.agent, o.score, o.domain, o.action, o.lesson, o.created_at,
    (SELECT w.type || ': ' || w.description FROM workflow_runs w WHERE w.id = o.run_id) as workflow_context
FROM outcomes o
ORDER BY o.id DESC
LIMIT 50;

-- Active lessons with reinforcement strength
CREATE VIEW IF NOT EXISTS v_active_lessons AS
SELECT
    l.domain, l.content, l.source_agent, l.occurrences, l.confidence,
    l.created_at, l.last_reinforced,
    CASE
        WHEN l.occurrences >= 5 THEN 'strong'
        WHEN l.occurrences >= 3 THEN 'moderate'
        ELSE 'emerging'
    END as strength
FROM lessons l
WHERE l.status = 'active'
ORDER BY l.confidence DESC, l.occurrences DESC;

-- Domain learning health: outcomes + lessons per domain
CREATE VIEW IF NOT EXISTS v_domain_learning AS
SELECT
    domain,
    COUNT(*) as total_outcomes,
    SUM(CASE WHEN score = 1 THEN 1 ELSE 0 END) as positive,
    SUM(CASE WHEN score = 0 THEN 1 ELSE 0 END) as neutral,
    SUM(CASE WHEN score = -1 THEN 1 ELSE 0 END) as negative,
    ROUND(AVG(score), 2) as avg_score,
    (SELECT COUNT(*) FROM lessons l WHERE l.domain = o.domain AND l.status = 'active') as active_lessons
FROM outcomes o
GROUP BY domain
ORDER BY total_outcomes DESC;

-- Recent workflow activity
CREATE VIEW IF NOT EXISTS v_recent_activity AS
SELECT
    w.id, w.type, w.description, w.scope, w.status, w.started_at, w.completed_at,
    (SELECT COUNT(*) FROM changes c WHERE c.run_id = w.id) as files_changed,
    (SELECT COUNT(*) FROM findings f WHERE f.run_id = w.id) as findings_produced,
    (SELECT COUNT(*) FROM bugs b WHERE b.run_id = w.id) as bugs_found
FROM workflow_runs w
ORDER BY w.id DESC
LIMIT 20;

-- Workflow usage summary — feeds identity block and experience tracking
CREATE VIEW IF NOT EXISTS v_workflow_usage AS
SELECT
    type,
    COUNT(*) as total_runs,
    SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed_runs,
    MAX(started_at) as last_run
FROM workflow_runs
GROUP BY type
ORDER BY completed_runs DESC;

-- Behavioral learnings for session briefing (sorted by confidence)
CREATE VIEW IF NOT EXISTS v_behavioral_briefing AS
SELECT
    rule, confidence, occurrences, context, source_project
FROM behavioral_learnings
WHERE status = 'active'
ORDER BY confidence DESC, occurrences DESC
LIMIT 20;

-- Incident search: search across title, description, symptoms, entries
CREATE VIEW IF NOT EXISTS v_incident_search AS
SELECT
    i.incident_id, i.title, i.domain, i.status,
    i.description, i.symptoms, i.root_cause, i.resolution,
    i.tags,
    (SELECT COUNT(*) FROM incident_entries e WHERE e.incident_id = i.incident_id) as entry_count,
    i.created_at, i.resolved_at
FROM incidents i
ORDER BY
    CASE i.status WHEN 'open' THEN 0 WHEN 'investigating' THEN 1 WHEN 'resolved' THEN 2 WHEN 'closed' THEN 3 END,
    i.id DESC;

-- Incident timeline: full chronological view of an incident's entries
CREATE VIEW IF NOT EXISTS v_incident_timeline AS
SELECT
    e.incident_id,
    i.title as incident_title,
    e.entry_type,
    e.content,
    e.result,
    e.agent,
    e.created_at
FROM incident_entries e
JOIN incidents i ON i.incident_id = e.incident_id
ORDER BY e.incident_id, e.id ASC;
