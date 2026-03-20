# Architecture: OMEGA Cortex -- Collective Intelligence Layer

## Scope

This architecture covers the Cortex feature across all 4 phases: Foundation (schema + shared store), Curation (curator agent + export logic), Consumption (briefing import + diagnostician enhancement), and Sync Adapters (multi-backend abstraction + cloud/self-hosted backends). It maps all 50 requirements (REQ-CTX-001 through REQ-CTX-050) to concrete modules, milestones, failure modes, and security boundaries.

## Overview

```
 DEVELOPER A (local)                        DEVELOPER B (local)
+---------------------------+              +---------------------------+
|  memory.db (personal)     |              |  memory.db (personal)     |
|  - behavioral_learnings   |              |  - behavioral_learnings   |
|  - incidents              |              |  - incidents              |
|  - hotspots, lessons...   |              |  - hotspots, lessons...   |
|  - shared_imports (track) |              |  - shared_imports (track) |
+-------------|-------------+              +-------------|-------------+
              |                                          |
         Curator Agent                              Briefing Hook
         (export)                                   (import)
              |                                          |
              v                                          ^
+-------------------------------------------------------------+
|               SYNC ADAPTER ABSTRACTION (Phase 4)             |
|   +-------------+  +-----------+  +----------+  +--------+  |
|   | Git JSONL   |  | CF D1     |  | Turso    |  | Self-  |  |
|   | (default)   |  | (cloud)   |  | (cloud)  |  | hosted |  |
|   +------+------+  +-----+-----+  +----+-----+  +---+----+  |
+----------|---------------|-------------|-------------|--------+
           |               |             |             |
           v               v             v             v
+------------------+  +----------+  +----------+  +---------+
| .omega/shared/   |  | CF D1 DB |  | Turso DB |  | Bridge  |
| (git-tracked)    |  | (HTTP)   |  | (HTTP)   |  | Server  |
|  behavioral-     |  +----------+  +----------+  | (HTTP)  |
|   learnings.jsonl|                               +---------+
|  hotspots.jsonl  |
|  lessons.jsonl   |
|  patterns.jsonl  |
|  decisions.jsonl |
|  conflicts.jsonl |
|  incidents/      |
|   INC-NNN.json   |
+------------------+
         |
    git commit/push
         |
         v
  +--------------+
  | Git Remote   |  <--- Developer B pulls
  +--------------+
```

### Hybrid Architecture

The core insight: `memory.db` stays **local** (fast, safe, no merge conflicts), while curated high-value knowledge is exported to a **shared backend** (git JSONL by default, cloud/self-hosted optionally). The separation is fundamental -- `memory.db` is the developer's personal brain; the shared store is the team's collective memory.

**Phases 1-3** implement the git JSONL backend as the default. **Phase 4** introduces a Sync Adapter abstraction that lets teams upgrade to real-time backends (Cloudflare D1, Turso, self-hosted bridge) without changing the curation or consumption logic.

### Integration with Existing OMEGA

Cortex is **non-invasive**. Every modification to existing files follows these rules:

1. **Additive only** -- new tables, new columns, new sections. No existing definitions modified.
2. **Existence-guarded** -- every new code path checks if Cortex artifacts exist before operating.
3. **Error-suppressed** -- all new operations use `2>/dev/null || true` patterns.
4. **Backward compatible** -- projects without `.omega/shared/` work identically to pre-Cortex.

---

## Modules

### Module 1: Schema + Migration

- **Responsibility**: Define the `shared_imports` table, add `contributor`/`shared_uuid`/`is_private` columns to shareable tables, create `v_shared_briefing` view, bump schema version to 1.3.0.
- **Public interface**: SQL schema definitions consumed by `db-init.sh` and all agents via sqlite3.
- **Dependencies**: None (foundational).
- **Implementation order**: 1

**Files:**
- `core/db/schema.sql` -- add `shared_imports` table, `v_shared_briefing` view, update version comment
- `core/db/migrate-1.3.0.sql` -- ALTER TABLE ADD COLUMN with existence checks for all shareable tables

**Schema additions to `core/db/schema.sql`:**

```sql
-- Version comment: 1.3.0 -- Added Cortex collective intelligence layer

-- New table: shared_imports (prevents re-import of shared entries)
CREATE TABLE IF NOT EXISTS shared_imports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    shared_uuid TEXT NOT NULL,
    category TEXT NOT NULL,        -- behavioral_learning, incident, hotspot, lesson, pattern, decision
    source_file TEXT,              -- which JSONL/JSON file it came from
    imported_at TEXT DEFAULT (datetime('now')),
    UNIQUE(shared_uuid)
);
CREATE INDEX IF NOT EXISTS idx_shared_imports_uuid ON shared_imports(shared_uuid);

-- New view: shareable behavioral learnings (high-confidence, non-private, active)
CREATE VIEW IF NOT EXISTS v_shared_briefing AS
SELECT
    id, rule, confidence, occurrences, context, source_project, contributor,
    created_at, last_reinforced
FROM behavioral_learnings
WHERE confidence >= 0.8
  AND status = 'active'
  AND COALESCE(is_private, 0) = 0
ORDER BY confidence DESC, occurrences DESC;
```

**Migration script `core/db/migrate-1.3.0.sql`:**

The migration adds columns to existing tables. SQLite does not support `ALTER TABLE ADD COLUMN IF NOT EXISTS`, so the script uses `PRAGMA table_info()` to check existence before altering. Pattern:

```sql
-- For each table+column combination:
-- 1. Check: SELECT COUNT(*) FROM pragma_table_info('table_name') WHERE name='column_name';
-- 2. If 0: ALTER TABLE table_name ADD COLUMN column_name TYPE DEFAULT value;
```

Tables and columns to add:
| Table | Column | Type | Default | Notes |
|-------|--------|------|---------|-------|
| `behavioral_learnings` | `contributor` | TEXT | NULL | Git identity string |
| `behavioral_learnings` | `shared_uuid` | TEXT | NULL | For import dedup |
| `behavioral_learnings` | `is_private` | INTEGER | 0 | Privacy marking |
| `incidents` | `contributor` | TEXT | NULL | |
| `incidents` | `shared_uuid` | TEXT | NULL | |
| `incidents` | `is_private` | INTEGER | 0 | |
| `lessons` | `contributor` | TEXT | NULL | |
| `lessons` | `shared_uuid` | TEXT | NULL | |
| `lessons` | `is_private` | INTEGER | 0 | |
| `patterns` | `contributor` | TEXT | NULL | |
| `patterns` | `shared_uuid` | TEXT | NULL | |
| `patterns` | `is_private` | INTEGER | 0 | |
| `decisions` | `contributor` | TEXT | NULL | |
| `decisions` | `shared_uuid` | TEXT | NULL | |
| `decisions` | `is_private` | INTEGER | 0 | |
| `hotspots` | `contributor` | TEXT | NULL | No `shared_uuid` (uses `file_path` as natural key) |

The migration script will be implemented in bash (called from `db-init.sh`) because SQLite's CLI cannot conditionally execute ALTER TABLE within a `.sql` file. The bash script will:
1. Query `PRAGMA table_info(table_name)` for each table.
2. Check if each column exists.
3. Execute `ALTER TABLE ADD COLUMN` only for missing columns.
4. Be fully idempotent -- safe on fresh, pre-Cortex, and already-migrated databases.

#### Failure Modes
| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| Migration fails mid-run | sqlite3 error on ALTER TABLE | Non-zero exit code from sqlite3 | Re-run migration (idempotent) | Some columns missing, curator cannot export from affected tables |
| `v_shared_briefing` view fails to create | `is_private` column not yet added | View creation error (suppressed by IF NOT EXISTS) | Run migration before schema; or view created on next db-init | View returns empty; briefing falls back to direct query |
| `shared_imports` table already exists | Re-deployment | IF NOT EXISTS prevents error | None needed | No impact |

#### Security Considerations
- **Trust boundary**: None -- schema is local-only, consumed by local agents.
- **Sensitive data**: `is_private` column enables per-entry privacy control. Private entries never leave local memory.db.
- **Attack surface**: None -- SQLite file permissions controlled by OS.

#### Performance Budget
- **Migration time**: < 2 seconds (ALTER TABLE is O(1) in SQLite for adding columns).
- **View query time**: < 100ms for tables with < 10,000 rows (typical).
- **Index on shared_uuid**: O(log n) lookup for import deduplication.

---

### Module 2: Setup + Shared Store

- **Responsibility**: Initialize `.omega/shared/` directory structure, handle gitignore configuration, update setup.sh summary output.
- **Public interface**: Directory structure created during `setup.sh` execution. `.omega/shared/` is the shared knowledge store root.
- **Dependencies**: None (can run before or after Module 1).
- **Implementation order**: 2

**Files:**
- `scripts/setup.sh` -- new section after "PROJECT STRUCTURE" for `.omega/shared/` init
- `scripts/db-init.sh` -- call migration script after running `schema.sql`

**setup.sh additions:**

1. **Directory creation** (after "PROJECT STRUCTURE" section):
   ```bash
   # .omega/shared/ — Cortex shared knowledge store
   if [ ! -d ".omega/shared" ]; then
       mkdir -p .omega/shared/incidents
       touch .omega/shared/.gitkeep
       touch .omega/shared/incidents/.gitkeep
       echo "   + .omega/shared/ initialized"
   else
       echo "   = .omega/shared/ already exists"
   fi
   ```

2. **Gitignore check** (warn if `.omega/shared/` would be gitignored):
   ```bash
   if [ -f ".gitignore" ]; then
       if grep -qE '^\\.omega/?$|^\\.omega/shared' .gitignore 2>/dev/null; then
           echo "   WARNING: .omega/shared/ may be gitignored -- Cortex requires it to be git-tracked"
       fi
   fi
   ```

3. **Cortex config gitignore** (Phase 4 prep -- `.omega/cortex-config.json` must be gitignored):
   ```bash
   # Ensure cortex-config.json is gitignored (may contain credential references)
   if [ -f ".gitignore" ]; then
       if ! grep -q 'cortex-config.json' .gitignore 2>/dev/null; then
           echo '.omega/cortex-config.json' >> .gitignore
       fi
   fi
   ```

4. **Command listing update**: Add `/omega:share` and `/omega:team-status` to the summary.

**db-init.sh additions:**

After the existing `sqlite3 "$DB_PATH" < "$SCHEMA_FILE"` line, add the migration call:
```bash
# Run Cortex migration for existing DBs (adds contributor, shared_uuid, is_private columns)
MIGRATE_SCRIPT="$SCRIPT_DIR/core/db/migrate-1.3.0.sh"
if [ -f "$MIGRATE_SCRIPT" ]; then
    bash "$MIGRATE_SCRIPT" "$DB_PATH" 2>/dev/null || true
fi
```

#### Failure Modes
| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| `.omega/shared/` creation fails | Permissions, disk full | Non-zero exit from mkdir | Manual directory creation | Curator cannot export; briefing skips import |
| `.gitignore` contains `.omega/` pattern | User or tool added it | grep check in setup.sh | WARNING message printed; user must fix manually | Shared knowledge not committed to git |
| Migration script not found | Incomplete OMEGA source | `-f` check before calling | Warning, continue without migration | New columns not added; curator cannot export from affected tables |

#### Security Considerations
- **Trust boundary**: `.omega/shared/` is git-tracked, meaning its contents are visible to anyone with repo access. This is intentional -- sharing requires visibility.
- **Sensitive data**: `.omega/cortex-config.json` is gitignored because it may reference credential environment variables.
- **Attack surface**: A malicious JSONL file committed to `.omega/shared/` could inject bad learnings. Mitigation: contributor attribution enables accountability; confidence thresholds filter low-quality entries.

#### Performance Budget
- **Directory creation**: Instantaneous.
- **Gitignore check**: < 10ms (single grep).
- **Migration call**: < 2 seconds (see Module 1).

---

### Module 3: Cortex Protocol

- **Responsibility**: Define the complete Cortex protocol reference file with @INDEX for lazy loading. Documents JSONL format, curation rules, import rules, privacy, contributor identity, conflict resolution.
- **Public interface**: `.claude/protocols/cortex-protocol.md` -- agents read specific sections via offset/limit.
- **Dependencies**: None (documentation).
- **Implementation order**: 3

**Files:**
- `core/protocols/cortex-protocol.md` -- new file

**Structure:**
```
@INDEX (lines 1-15)
  SHARED-STORE-FORMAT         17-80
  CURATION-RULES              82-130
  IMPORT-RULES                132-170
  PRIVACY                     172-195
  CONTRIBUTOR-IDENTITY        197-220
  CONFLICT-RESOLUTION         222-250
  SYNC-ADAPTERS               252-290
@/INDEX

# Cortex Protocol
[sections as indexed above]
```

Total file: under 300 lines (per REQ-CTX-012).

#### Failure Modes
| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| Protocol file not deployed | setup.sh not re-run | Agent file-read fails | Agent continues without protocol reference | Curator uses inline rules (less detailed) |
| @INDEX line ranges stale | Protocol file edited without rebuilding index | Agent reads wrong section | Run `scripts/build-protocol-index.sh` | Temporary misalignment of lazy-loaded sections |

---

### Module 4: Curator Agent

- **Responsibility**: Evaluate local memory.db entries for team relevance, export qualifying entries to the shared store, deduplicate, reinforce cross-contributor entries, detect conflicts.
- **Public interface**: Invoked by `/omega:share` command and referenced by `session-close.sh` curation trigger.
- **Dependencies**: Module 1 (schema columns), Module 2 (`.omega/shared/` directory), Module 3 (protocol reference).
- **Implementation order**: 4

**Files:**
- `core/agents/curator.md` -- new file

**Agent definition:**
```yaml
---
name: curator
description: Knowledge Curator agent that evaluates local memory.db entries for team relevance and exports qualifying entries to the shared knowledge store. Handles deduplication, cross-contributor reinforcement, and conflict detection.
tools: Read, Write, Bash, Grep, Glob
model: claude-sonnet-4-20250514
---
```

**Process:**
1. **Query memory.db** for qualifying entries across all shareable tables:
   - `behavioral_learnings`: `WHERE confidence >= 0.8 AND status = 'active' AND COALESCE(is_private, 0) = 0 AND shared_uuid IS NULL`
   - `incidents`: `WHERE status = 'resolved' AND COALESCE(is_private, 0) = 0 AND shared_uuid IS NULL`
   - `hotspots`: `WHERE risk_level IN ('medium', 'high', 'critical')`
   - `lessons`: `WHERE confidence >= 0.8 AND status = 'active' AND COALESCE(is_private, 0) = 0 AND shared_uuid IS NULL`
   - `patterns`: `WHERE COALESCE(is_private, 0) = 0`
   - `decisions`: `WHERE confidence >= 0.8 AND status = 'active' AND COALESCE(is_private, 0) = 0 AND shared_uuid IS NULL`

2. **Relevance filter** (curator evaluates each entry):
   - SHARE: technical corrections, debugging patterns, code conventions, architectural decisions
   - SKIP: personal preferences (communication style, address-as), local-only context

3. **Read existing `.omega/shared/` files** to check for duplicates.

4. **Deduplication + reinforcement**:
   - Compute `content_hash` (SHA-256 of content field).
   - If `content_hash` match in JSONL: reinforce (bump occurrences, update confidence, add contributor).
   - If same UUID but different hash: update (content changed).
   - If no match: append new entry.

5. **Cross-contributor reinforcement**:
   - Different contributor reinforcing same entry: `confidence += 0.2` (vs normal `+0.1`).
   - 3+ unique contributors: `confidence = 1.0` (maximum -- team consensus).

6. **Conflict detection**:
   - Compare new entry against existing entries in same category.
   - Flag contradictions in `.omega/shared/conflicts.jsonl`.

7. **Record `shared_uuid`** back to local memory.db for each exported entry.

8. **Report**: summary of what was shared, skipped, reinforced, and any conflicts.

**JSONL read/write logic:**

The curator uses `python3` for JSONL manipulation (bash cannot parse JSON reliably). Pattern:

```python
# Read: load all lines, parse each as JSON object
# Modify: update matching entry or append new entry
# Write: overwrite file with all lines (atomic via write-to-temp + rename)
```

For incident JSON files: read entire JSON, merge entries, write entire JSON.

#### Failure Modes
| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| `.omega/shared/` does not exist | setup.sh not run | Directory check before export | Create directory automatically | No impact -- curator creates it |
| JSONL file malformed | Bad git merge | python3 JSON parse exception | Skip malformed lines, log warning | Some existing entries not considered for dedup |
| sqlite3 query fails | DB locked, corrupted | Non-zero exit code | Log error, skip that table | Partial export (entries from failed table not shared) |
| Content hash collision | SHA-256 collision (astronomically unlikely) | Two different entries with same hash | Append as new entry (hash collision treated as dedup) | Negligible risk |
| Curator over-shares | Threshold too low | Review via `/omega:share --dry-run` | Adjust threshold, mark entries `is_private = 1` | Noise in shared store |

#### Security Considerations
- **Trust boundary**: Curator reads local memory.db (trusted) and writes to `.omega/shared/` (team-visible). The confidence threshold (0.8) acts as a quality gate.
- **Sensitive data**: `is_private` column prevents sensitive entries from being exported. Curator MUST check `is_private = 0` before exporting.
- **Attack surface**: A compromised memory.db could export malicious learnings. Mitigation: contributor attribution, confidence thresholds, and `/omega:team-status` for visibility.

#### Performance Budget
- **Curation evaluation**: < 30 seconds total (Sonnet model, structured evaluation).
- **JSONL file read**: < 1 second per file (hundreds of lines typical).
- **SHA-256 computation**: < 10ms per entry.
- **Total export operation**: < 45 seconds.

---

### Module 5: Share Command

- **Responsibility**: Provide manual trigger for curator evaluation and export. Show what was shared, skipped, reinforced, and conflicts detected.
- **Public interface**: `/omega:share` slash command. Flags: `--force`, `--dry-run`.
- **Dependencies**: Module 4 (curator agent).
- **Implementation order**: 5

**Files:**
- `core/commands/omega-share.md` -- new file

**Command flow:**
1. Create `workflow_runs` entry with `type='share'`.
2. Invoke curator agent with share directive.
3. Curator performs full evaluation and export.
4. Output summary table.
5. Close `workflow_runs` entry.

Flags:
- `--force`: Share entries below confidence threshold (overrides >= 0.8).
- `--dry-run`: Show what WOULD be shared without writing to `.omega/shared/`.

#### Failure Modes
| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| Curator agent invocation fails | Model unavailable | Non-zero exit | Retry or report error | Nothing shared |
| Partial export | Some tables fail, others succeed | Curator reports per-table status | Re-run `/omega:share` | Incomplete sharing (safe -- idempotent) |

---

### Module 6: Session Close Curation Trigger

- **Responsibility**: At session close, check if new shareable entries exist and flag for curation.
- **Public interface**: Enhanced `session-close.sh` hook.
- **Dependencies**: Module 1 (schema columns for query).
- **Implementation order**: 6

**Files:**
- `core/hooks/session-close.sh` -- modified

**Implementation:**

Since bash hooks cannot spawn Claude agent subprocesses, the session-close hook writes a `.curation_pending` flag file that the next session's briefing detects:

```bash
# After hotspot promotion, check for pending curation
SHARED_DIR="$PROJECT_DIR/.omega/shared"
if [ -d "$SHARED_DIR" ]; then
    PENDING=$(sqlite3 "$DB_PATH" "
        SELECT COUNT(*) FROM behavioral_learnings
        WHERE confidence >= 0.8 AND status = 'active'
          AND COALESCE(is_private, 0) = 0
          AND shared_uuid IS NULL;
    " 2>/dev/null || echo "0")
    PENDING_INC=$(sqlite3 "$DB_PATH" "
        SELECT COUNT(*) FROM incidents
        WHERE status = 'resolved'
          AND COALESCE(is_private, 0) = 0
          AND shared_uuid IS NULL;
    " 2>/dev/null || echo "0")
    TOTAL_PENDING=$((PENDING + PENDING_INC))
    if [ "$TOTAL_PENDING" -gt 0 ] 2>/dev/null; then
        echo "$TOTAL_PENDING" > "$PROJECT_DIR/.claude/hooks/.curation_pending"
    fi
fi
```

The briefing hook (Module 8) detects this flag and recommends `/omega:share`.

#### Failure Modes
| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| sqlite3 query fails | DB locked | Error suppressed by `|| echo "0"` | Flag not written | No curation reminder -- developer can still manually run `/omega:share` |
| Flag file write fails | Permissions | Error on echo redirect | Silent -- no curation reminder | No impact on session close |

---

### Module 7: Briefing Import

- **Responsibility**: At session start, import shared knowledge from `.omega/shared/` into local memory.db, inject top entries into session context.
- **Public interface**: Enhanced `briefing.sh` hook. New section between BEHAVIORAL LEARNINGS and OPEN INCIDENTS.
- **Dependencies**: Module 1 (shared_imports table), Module 2 (`.omega/shared/` directory).
- **Implementation order**: 7

**Files:**
- `core/hooks/briefing.sh` -- modified

**New section placement**: After the existing "BEHAVIORAL LEARNINGS" section (line 118) and before "OPEN INCIDENTS" section (line 128).

**Implementation:**

```bash
# === SECTION 2: TEAM KNOWLEDGE (shared across developers) ===
SHARED_DIR="$PROJECT_DIR/.omega/shared"
if [ -d "$SHARED_DIR" ]; then
    # Check for curation pending flag
    if [ -f "$PROJECT_DIR/.claude/hooks/.curation_pending" ]; then
        PENDING_COUNT=$(cat "$PROJECT_DIR/.claude/hooks/.curation_pending" 2>/dev/null || echo "0")
        echo "NOTE: $PENDING_COUNT entries pending curation. Run /omega:share to share with team."
        echo ""
        rm -f "$PROJECT_DIR/.claude/hooks/.curation_pending"
    fi

    # Import and display shared behavioral learnings
    if [ -f "$SHARED_DIR/behavioral-learnings.jsonl" ]; then
        SHARED_BL=$(python3 << 'PYEOF' 2>/dev/null || true
import json, sys, subprocess
# ... parse JSONL, filter by shared_imports, inject top 10
PYEOF
        )
        if [ -n "$SHARED_BL" ]; then
            echo "TEAM KNOWLEDGE (shared across developers):"
            echo "$SHARED_BL"
            echo ""
        fi
    fi

    # Import and display shared incidents (top 3)
    # Import and display shared hotspots (top 5)
    # [similar pattern for each category]
fi
```

**Import logic** (python3 inline script):
1. Read JSONL file line by line.
2. Parse each line as JSON.
3. Check `shared_imports` table for UUID -- skip if already imported.
4. For new entries: INSERT into `shared_imports`, optionally INSERT into local table.
5. Return top N entries formatted for display.

**Token budget enforcement:**
- Behavioral learnings: LIMIT 10 (by confidence DESC)
- Incidents: LIMIT 3 (by resolved_at DESC)
- Hotspots: LIMIT 5 (by risk_level DESC, contributor_count DESC)
- Total section header + entries: estimated 200-400 tokens

**Display format:**
```
TEAM KNOWLEDGE (shared across developers):
  [TEAM 0.9] Never mock the database in integration tests (from Developer A)
  [TEAM 0.8] Always check WAL mode before concurrent writes (from Developer B)

  [TEAM] INC-042: Race condition in auth module (resolved by Developer A)

  [TEAM] payments/processor.rs -- high risk (3 devs, 12 touches)
```

#### Failure Modes
| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| python3 JSONL parsing fails | Malformed JSONL (bad git merge) | Python exception caught in try/except | Skip malformed lines, continue with valid entries | Partial import -- some entries missed |
| `shared_imports` table does not exist | Pre-migration DB | sqlite3 error on INSERT | Error suppressed; entries not tracked as imported | Re-import on next session (duplicate display, not harmful) |
| JSONL file very large (> 1MB) | Team accumulated many entries | Slow parsing within 30s timeout | Hard cap: only read first 500 lines | Older entries not imported in this session |
| `.omega/shared/` does not exist | Project not using Cortex | `-d` check on directory | Skip entire section | No impact -- pre-Cortex behavior |

#### Security Considerations
- **Trust boundary**: `.omega/shared/` contents come from git (team-contributed). They are parsed as JSON -- no code execution.
- **Injection risk**: JSONL entries are displayed as text in the briefing. A malicious entry could contain prompt injection. Mitigation: entries are structured data fields (`rule`, `context`), not free-form instructions. Contributor attribution provides accountability.

#### Performance Budget
- **JSONL parsing**: < 2 seconds for typical files (< 500 entries).
- **sqlite3 import tracking**: < 1 second (INSERT per new entry, with UNIQUE constraint).
- **Total shared import section**: < 5 seconds (within 30-second hook timeout).
- **JSONL file size warnings**: warn at > 1MB, skip at > 5MB.

---

### Module 8: Diagnostician Enhancement

- **Responsibility**: During Phase 2 (Evidence Assembly), query shared incidents for pattern matching against current investigation.
- **Public interface**: Enhanced diagnostician agent definition.
- **Dependencies**: Module 2 (`.omega/shared/incidents/` directory).
- **Implementation order**: 8

**Files:**
- `core/agents/diagnostician.md` -- modified

**New step in Phase 2 (Evidence Assembly)**, after loading prior system model:

```markdown
### Shared Incident Query (Cortex)

If `.omega/shared/incidents/` exists and contains incident files:
1. Read each `INC-NNN.json` file.
2. Compare symptoms, domain, and tags against current investigation.
3. Match criteria: same domain, overlapping tags, similar symptoms (keyword overlap).
4. If match found: add to constraint table as shared evidence.
5. Surface in hypothesis generation: "This resembles INC-042 -- see resolution."
6. Do NOT auto-apply the resolution -- evaluate relevance first.
```

This is additive -- a new step after existing evidence sources. It does not replace `incident_entries` or `failed_approaches` queries.

#### Failure Modes
| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| `.omega/shared/incidents/` does not exist | No shared incidents | Directory check | Skip shared query | No impact -- existing diagnosis flow unchanged |
| Incident JSON malformed | Bad edit or merge | JSON parse error | Skip that file, continue | One shared incident unavailable |
| False match | Similar symptoms, different root cause | Diagnostician evaluates relevance | Treat as suggestive, not prescriptive | Wasted investigation time (low risk) |

---

### Module 9: Team Status Command

- **Responsibility**: Dashboard showing shared knowledge statistics, recent contributions, active incidents, team hotspot map, unresolved conflicts.
- **Public interface**: `/omega:team-status` slash command.
- **Dependencies**: Module 2 (`.omega/shared/` directory), Module 7 (shared data available).
- **Implementation order**: 9

**Files:**
- `core/commands/omega-team-status.md` -- new file

**Dashboard sections:**
1. **Shared Knowledge Stats**: counts per category (N behavioral learnings, N incidents, etc.)
2. **Recent Contributions**: last 10 shared entries with contributor, category, date
3. **Active Shared Incidents**: resolved incidents available to team
4. **Team Hotspot Map**: top 10 shared hotspots with contributor counts
5. **Unresolved Conflicts**: entries from `conflicts.jsonl`

Read-only command -- no INSERT/UPDATE/DELETE. Creates `workflow_runs` entry with `type='team-status'`.

---

### Module 10: Documentation + CLAUDE.md

- **Responsibility**: Update all documentation files to reflect Cortex feature.
- **Public interface**: Documentation files.
- **Dependencies**: All previous modules (documents what they do).
- **Implementation order**: 10

**Files:**
- `CLAUDE.md` -- one-line Cortex pointer in "Institutional Memory" section
- `docs/architecture.md` -- new "Cortex: Collective Intelligence Layer" section
- `docs/agent-inventory.md` -- curator agent entry
- `README.md` -- feature description, command listing
- `core/protocols/memory-protocol.md` -- new "Shared Knowledge" section
- `scripts/setup.sh` -- command listing update

**CLAUDE.md addition** (under "Institutional Memory", after the Cortex protocol pointer rule):
```
**Cortex (team knowledge):** Read @INDEX of `.claude/protocols/cortex-protocol.md` for shared knowledge rules.
```

This is under 100 characters. The 10,000 character CLAUDE.md limit is preserved.

---

### Module 11: Sync Adapter Abstraction

- **Responsibility**: Define the adapter interface that all backends implement. Refactor Phase 1-3 git JSONL logic into the first adapter implementation.
- **Public interface**: Adapter interface specification in `core/protocols/sync-adapters.md`. Git JSONL adapter is the default.
- **Dependencies**: Modules 4, 7 (curator and briefing logic to refactor into adapter pattern).
- **Implementation order**: 11

**Files:**
- `core/protocols/sync-adapters.md` -- new file (adapter interface spec with @INDEX)
- Curator agent updated to route through adapter abstraction
- Briefing hook updated to import through adapter abstraction

**Adapter Interface:**
```
export(entries: Entry[]) -> ExportResult
import(since: Timestamp) -> Entry[]
status() -> BackendStats
health() -> bool
```

**Backend selection**: Read `.omega/cortex-config.json`. If absent, default to `git-jsonl`.

**Config format** (`.omega/cortex-config.json`):
```json
{
  "backend": "git-jsonl",
  "last_sync_timestamp": "2026-03-20T15:00:00Z"
}
```

**Git JSONL adapter** (refactored default):
- `export()`: writes to `.omega/shared/` JSONL/JSON files (unchanged behavior)
- `import()`: reads from `.omega/shared/` files (unchanged behavior)
- `status()`: counts entries per JSONL file
- `health()`: checks `.omega/shared/` exists and is writable

---

### Module 12: Cortex Config Command

- **Responsibility**: Interactive configuration for sync backend selection with health check validation.
- **Public interface**: `/omega:cortex-config` slash command.
- **Dependencies**: Module 11 (sync adapter abstraction).
- **Implementation order**: 12

**Files:**
- `core/commands/omega-cortex-config.md` -- new file

**Flow:**
1. Select backend type (git, cloudflare-d1, turso, self-hosted).
2. Enter backend-specific configuration.
3. Run health check (validates connectivity).
4. Save to `.omega/cortex-config.json`.

**Flags:**
- `--show`: display current configuration (masks token env var names).

---

### Module 13: Sync Middleware Pipeline

- **Responsibility**: Sit between curator output and adapter input. Handle format transformation, batching, retry, conflict pre-check, offline caching.
- **Public interface**: Middleware pipeline invoked by curator before adapter calls.
- **Dependencies**: Module 11 (adapter interface).
- **Implementation order**: 13

**Implementation details:**

The middleware is implemented as logic within the curator agent (not a separate file). When the curator exports:

1. **Format transformation**: Convert memory.db rows to adapter entry format (JSON objects).
2. **Batching**: Group entries by category for efficient API calls.
3. **Conflict pre-check**: Verify no `content_hash` collision before export.
4. **Retry on failure**: Max 3 retries with exponential backoff (1s, 2s, 4s).
5. **Offline cache**: If backend unavailable, write to `.omega/.pending-exports.jsonl` (gitignored).

**Pending exports** (`.omega/.pending-exports.jsonl`):
- Each line: `{"category": "...", "entry": {...}, "backend": "...", "queued_at": "..."}`
- On next session/share: flush pending exports to backend.
- File is gitignored (local-only, transient).

#### Failure Modes
| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| Backend unavailable | Network down, service outage | HTTP timeout or connection refused | Cache in `.pending-exports.jsonl`, retry next session | No data loss -- exports queued locally |
| Retry exhausted (3x) | Persistent backend failure | All 3 attempts fail | Cache locally, log warning | Entries queued for next attempt |
| Pending exports file corrupted | Disk issue | JSON parse error on flush | Skip corrupted lines, process valid ones | Some entries lost (re-curation recovers them) |

---

### Module 14: Cloudflare D1 Adapter

- **Responsibility**: Connect to Cloudflare D1 via REST API for real-time sync.
- **Public interface**: Implements adapter interface for D1 backend.
- **Dependencies**: Module 11 (adapter abstraction), Module 12 (config command for setup).
- **Implementation order**: 14

**Configuration:**
```json
{
  "backend": "cloudflare-d1",
  "account_id": "...",
  "database_id": "...",
  "api_token_env": "OMEGA_CORTEX_CF_TOKEN"
}
```

**API token**: Read from environment variable `$OMEGA_CORTEX_CF_TOKEN`. NEVER stored in config file.

**D1 tables** (mirror JSONL structure):
- `shared_behavioral_learnings`
- `shared_incidents`
- `shared_incident_entries`
- `shared_hotspots`
- `shared_lessons`
- `shared_patterns`
- `shared_decisions`

**HTTP calls via `curl`** -- no additional runtime dependencies.

**D1 schema provisioning** (REQ-CTX-049): `/omega:cortex-config` for D1 auto-provisions tables via D1 API.

---

### Module 15: Self-Hosted Bridge + Adapter

- **Responsibility**: Provide a self-hosted HTTP bridge server and corresponding adapter for teams wanting full data sovereignty.
- **Public interface**: `extensions/cortex-bridge/` -- Python FastAPI server. Self-hosted adapter implements adapter interface.
- **Dependencies**: Module 11 (adapter abstraction).
- **Implementation order**: 15

**Files:**
- `extensions/cortex-bridge/main.py` -- FastAPI application
- `extensions/cortex-bridge/requirements.txt` -- `fastapi`, `uvicorn`, `aiosqlite`
- `extensions/cortex-bridge/Dockerfile`
- `extensions/cortex-bridge/docker-compose.yml`
- `extensions/cortex-bridge/README.md`

**Endpoints:**
- `POST /api/export` -- receive entries from curator
- `GET /api/import?since=TIMESTAMP` -- return entries after timestamp
- `GET /api/health` -- returns 200 OK
- `GET /api/status` -- returns category counts

**Authentication**: Bearer token from `CORTEX_BRIDGE_TOKEN` env var.

**Storage**: SQLite by default (file path configurable), PostgreSQL optional.

**Configuration:**
```json
{
  "backend": "self-hosted",
  "endpoint_url": "https://my-vps:8443/cortex",
  "auth_token_env": "OMEGA_CORTEX_BRIDGE_TOKEN"
}
```

---

## JSONL Format Specification

This is the contract. All producers (curator) and consumers (briefing hook, diagnostician, team-status) must conform.

### Common Fields (all JSONL entries)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `uuid` | string (UUID v4) | Yes | Unique identifier for this entry |
| `contributor` | string | Yes | Git identity: `"Name <email>"` |
| `source_project` | string | Yes | Project name (basename of git root) |
| `created_at` | string (ISO 8601) | Yes | When originally created |
| `confidence` | float (0.0-1.0) | Yes | Confidence level |
| `occurrences` | integer | Yes | How many times reinforced |
| `content_hash` | string (SHA-256) | Yes | Hash of content field(s) for deduplication |
| `contributors` | array of strings | No | All contributors who reinforced this entry |

### `behavioral-learnings.jsonl`

Additional fields:
| Field | Type | Description |
|-------|------|-------------|
| `rule` | string | The behavioral rule (actionable, imperative) |
| `context` | string | What situation taught this rule |
| `status` | string | `active`, `superseded`, `archived` |

Content hash computed from: SHA-256 of `rule` field.

Example entry:
```json
{"uuid": "a1b2c3d4-...", "contributor": "Ivan Lozada <ilozada@me.com>", "source_project": "omega", "created_at": "2026-03-20T10:00:00Z", "confidence": 0.9, "occurrences": 3, "content_hash": "abc123...", "contributors": ["Ivan Lozada <ilozada@me.com>", "Dev B <b@x.com>"], "rule": "Never mock the database in integration tests", "context": "INC-042: mocked DB hid a race condition", "status": "active"}
```

### `hotspots.jsonl`

Additional fields:
| Field | Type | Description |
|-------|------|-------------|
| `file_path` | string | File that is a hotspot |
| `risk_level` | string | `low`, `medium`, `high`, `critical` |
| `times_touched` | integer | Aggregate touch count |
| `description` | string | Why this is a hotspot |
| `contributor_count` | integer | Number of unique contributors |
| `cross_contributor_alert` | boolean | True if 2+ contributors flagged this file |

Content hash computed from: SHA-256 of `file_path`.

No UUID -- `file_path` is the natural key. Entries are stateful (merged on every export, re-read on every import).

### `lessons.jsonl`

Additional fields:
| Field | Type | Description |
|-------|------|-------------|
| `domain` | string | Area/module |
| `content` | string | The distilled rule |
| `source_agent` | string | Which agent first distilled this |

Content hash computed from: SHA-256 of `domain` + `content`.

### `patterns.jsonl`

Additional fields:
| Field | Type | Description |
|-------|------|-------------|
| `domain` | string | Area/module |
| `name` | string | Short pattern name |
| `description` | string | What the pattern is |
| `example_files` | array of strings | Files demonstrating it |

Content hash computed from: SHA-256 of `domain` + `name` + `description`.

### `decisions.jsonl`

Additional fields:
| Field | Type | Description |
|-------|------|-------------|
| `domain` | string | Area/module |
| `decision` | string | What was decided |
| `rationale` | string | Why |
| `alternatives` | string (JSON) | What else was considered |

Content hash computed from: SHA-256 of `domain` + `decision`.

### `conflicts.jsonl`

| Field | Type | Description |
|-------|------|-------------|
| `uuid` | string (UUID v4) | Conflict identifier |
| `type` | string | `contradiction` |
| `entry_a_uuid` | string | First conflicting entry UUID |
| `entry_b_uuid` | string | Second conflicting entry UUID |
| `category` | string | Which JSONL category the conflict is in |
| `description` | string | What contradicts |
| `contributor` | string | Who detected it |
| `created_at` | string (ISO 8601) | When detected |
| `status` | string | `unresolved`, `resolved` |

### Incident Files (`.omega/shared/incidents/INC-NNN.json`)

Full JSON object (NOT JSONL -- one file per incident):

```json
{
  "incident_id": "INC-042",
  "title": "Race condition in auth module",
  "domain": "auth",
  "status": "resolved",
  "description": "...",
  "symptoms": "Intermittent 401 errors under load",
  "root_cause": "Shared mutex not held during token refresh",
  "resolution": "Wrapped token refresh in exclusive lock",
  "affected_files": ["backend/src/auth/token.rs", "backend/src/auth/middleware.rs"],
  "tags": ["race-condition", "auth", "concurrency"],
  "contributor": "Ivan Lozada <ilozada@me.com>",
  "source_project": "omega",
  "created_at": "2026-03-15T09:00:00Z",
  "resolved_at": "2026-03-15T14:30:00Z",
  "entries": [
    {
      "entry_type": "attempt",
      "content": "Added retry logic to token refresh",
      "result": "failed",
      "agent": "developer",
      "created_at": "2026-03-15T09:30:00Z"
    },
    {
      "entry_type": "discovery",
      "content": "Token refresh is not protected by mutex",
      "result": null,
      "agent": "diagnostician",
      "created_at": "2026-03-15T11:00:00Z"
    },
    {
      "entry_type": "resolution",
      "content": "Wrapped token refresh in exclusive lock",
      "result": "worked",
      "agent": "developer",
      "created_at": "2026-03-15T14:30:00Z"
    }
  ]
}
```

---

## Failure Modes (System-Level)

| Scenario | Affected Modules | Detection | Recovery Strategy | Degraded Behavior |
|----------|-----------------|-----------|-------------------|-------------------|
| `.omega/shared/` does not exist | Curator, Briefing, Diagnostician, Team Status | Directory existence check | Curator creates it; Briefing/Diagnostician skip import; Team Status reports "not initialized" | Local-only OMEGA (pre-Cortex behavior) |
| JSONL file malformed (bad git merge) | Briefing, Curator, Team Status | python3 JSON parse exception | Skip malformed lines, process valid ones; log warning | Partial import -- some entries missed |
| Cloud backend unreachable | Curator (export), Briefing (import) | HTTP timeout (5s) or connection refused | Export: cache in `.pending-exports.jsonl`; Import: fall back to `.omega/shared/` files, then local-only | Delayed sync; local knowledge still functional |
| Migration fails on existing DB | Schema, Curator, Briefing | ALTER TABLE error (suppressed) | Re-run `db-init.sh`; columns missing but existing features work | Cortex columns absent; curator cannot export; briefing skips import |
| Two developers share simultaneously (JSONL merge conflict) | Curator | Git merge conflict on same JSONL line | Manual resolution (each line is self-contained JSON); append-only design minimizes conflicts | Resolved as standard git merge conflict |
| Curator over-shares (noise) | Team via Briefing | Review via `/omega:share --dry-run` | Adjust threshold; mark entries `is_private = 1`; archive bad entries | Team receives low-quality learnings (mitigated by contributor attribution) |
| Curator under-shares (value locked) | Team via Briefing | Check via `/omega:team-status` | Lower threshold; use `/omega:share --force` | Team misses valuable knowledge (manual sharing as fallback) |
| briefing.sh exceeds 30s timeout | Briefing | Hook timeout (Claude Code kills hook) | Reduce JSONL file size; briefing continues without shared section | Session starts without shared knowledge -- local knowledge still injected |
| Pending exports file grows unbounded | Middleware (offline) | File size check | Flush on next successful connection; warn user | Exports accumulate locally until backend available |

---

## Security Model

### Trust Boundaries

1. **Local memory.db -> Shared store**: The curator is the gatekeeper. It evaluates entries before exporting. The `is_private` column and confidence threshold act as gates.
2. **Shared store -> Local memory.db**: The briefing hook imports entries from `.omega/shared/`. These come from git (team-contributed). No code execution -- data is parsed as JSON.
3. **Local -> Cloud/Self-hosted backend**: API tokens authenticate requests. Tokens stored in environment variables, never in files. HTTPS required for cloud backends.
4. **Bridge server -> Clients**: Bearer token authentication. Rate limiting (100 req/min). TLS via reverse proxy.

### Data Classification

| Data | Classification | Storage | Access Control |
|------|---------------|---------|---------------|
| Behavioral learnings | Internal | memory.db (local) + JSONL (shared) | `is_private` column; git access |
| Incident details | Internal | memory.db (local) + JSON (shared) | `is_private` column; git access |
| Hotspot data | Internal | memory.db (local) + JSONL (shared) | Git access |
| API tokens | Secret | Environment variables only | OS-level env var access |
| `cortex-config.json` | Confidential | `.omega/cortex-config.json` (gitignored) | File permissions |
| Contributor identity | Public within team | JSONL entries + memory.db | Derived from `git config` |

### Attack Surface

1. **Malicious JSONL entry in git**: Risk: prompt injection via `rule` or `context` field. Mitigation: entries are structured data, not executable instructions; contributor attribution enables accountability; confidence thresholds filter unproven entries.
2. **Bridge server exposed to internet**: Risk: unauthorized access, data exfiltration. Mitigation: Bearer token auth, rate limiting, TLS via reverse proxy, CORS disabled.
3. **API token leakage**: Risk: token stored in config file accidentally committed. Mitigation: config file gitignored; tokens stored as env var references (`api_token_env`), not values.
4. **Denial of service on briefing**: Risk: large JSONL file slows session start. Mitigation: hard caps (500 lines processed, 5s timeout), file size warnings.

---

## Graceful Degradation

| Dependency | Normal Behavior | Degraded Behavior | User Impact |
|-----------|----------------|-------------------|-------------|
| `.omega/shared/` directory | Full Cortex: export + import | Skip all Cortex operations | Local-only OMEGA (pre-Cortex behavior) |
| python3 | JSONL parsing, UUID generation | Briefing skips shared import | Shared knowledge not injected (local behavioral learnings still work) |
| Cloud backend (D1/Turso/Self-hosted) | Real-time sync | Cache exports locally; fall back to git JSONL files for import | Delayed sync; no data loss |
| `cortex-config.json` | Backend-specific adapter | Default to git JSONL adapter | Git-based sharing (zero config) |
| `shared_imports` table | Incremental import tracking | Re-import all entries each session | Duplicate processing (not duplicate display -- dedup at display) |
| Contributor identity (`git config`) | Named attribution | Default to "Unknown" | Entries shared without named contributor |

---

## Performance Budgets

| Operation | Latency (p50) | Latency (p99) | Memory | Notes |
|-----------|---------------|---------------|--------|-------|
| Briefing shared import | 1s | 4s | < 10MB | Must complete within 30s hook timeout; target < 5s |
| Curator evaluation | 10s | 25s | < 50MB | Sonnet model; structured evaluation |
| Cloud sync (per operation) | 0.5s | 4s | < 5MB | HTTP call via curl; 5s timeout |
| JSONL file parse (500 lines) | 0.1s | 0.5s | < 5MB | python3 inline |
| SHA-256 content hash | < 1ms | < 5ms | negligible | Per entry |
| Migration (all tables) | 0.5s | 1.5s | < 1MB | ALTER TABLE is O(1) in SQLite |
| JSONL file size | -- | -- | warn > 1MB | Archive at > 5MB |

---

## Data Flow

### Export Flow (Curator -> Backend)

```
memory.db (qualifying entries)
    |
    v
Curator Agent (relevance filter + dedup)
    |
    v
Sync Middleware (format + batch + retry)
    |
    v
Adapter (git-jsonl / cloudflare-d1 / self-hosted)
    |
    v
Backend (.omega/shared/ OR cloud DB OR bridge server)
```

### Import Flow (Backend -> Briefing)

```
Backend (.omega/shared/ OR cloud DB OR bridge server)
    |
    v
Adapter (read via file I/O or HTTP GET)
    |
    v
Briefing Hook (filter by shared_imports table)
    |
    v
Local memory.db (INSERT new entries)
    |
    v
Session Context (inject top N entries into Claude's context)
```

### Curation Trigger Flow

```
Session close
    |
    v
session-close.sh (check for pending entries)
    |
    v
.curation_pending flag file
    |
    v
Next session briefing.sh (detect flag, recommend /omega:share)
    |
    v
User runs /omega:share (or ignores)
    |
    v
Curator Agent evaluates and exports
```

---

## Design Decisions

| Decision | Alternatives Considered | Justification |
|----------|------------------------|---------------|
| JSONL format for shared store | JSON array file, SQLite shared DB, MessagePack | JSONL: line-level git merges, append-only, human-readable, one entry per line minimizes merge conflicts |
| `.omega/shared/` namespace | `.claude/shared/`, `shared-knowledge/`, `.cortex/` | `.omega/` is consistent with OMEGA branding; `.claude/` is deployment artifacts; dotfile hides from casual listings |
| Curation trigger via flag file | Spawn Claude agent from bash hook, cron job | Bash hooks cannot spawn Claude agent subprocesses; flag file is simple, reliable, non-blocking |
| python3 for JSONL parsing | jq, bash string manipulation, Node.js | python3 already a dependency (briefing.sh line 18); jq not universally installed; bash cannot parse JSON reliably |
| SHA-256 for content hash | MD5, UUID comparison only | SHA-256 is collision-resistant standard; UUID alone doesn't detect content changes |
| Confidence >= 0.8 threshold | 0.7, 0.9, no threshold | Conservative start; better to under-share than over-share; trivially adjustable in curator agent |
| Adapter abstraction (Phase 4) | Hardcode each backend, plugin system | Clean separation: curator and briefing are adapter-agnostic; new backends added without modifying core logic |
| `cortex-config.json` gitignored | Checked into git, env vars only | May contain credential references (env var names); team members may use different backends |
| Separate incident files (not JSONL) | All incidents in one JSONL | Incidents are complex (nested entries array); individual files enable selective read; natural key is `incident_id` |
| Curator uses Sonnet (not Opus) | Opus for all, Haiku for speed | Curation is structured evaluation (confidence check, dedup, relevance filter) -- not deep reasoning. Sonnet is appropriate and cost-effective |

---

## External Dependencies

- `python3` -- JSONL parsing, UUID generation (already a dependency via briefing.sh)
- `sqlite3` -- database queries (already a dependency)
- `curl` -- HTTP calls for cloud/self-hosted backends (Phase 4; universally available)
- `uuidgen` or `python3 uuid` -- UUID v4 generation (macOS standard; python3 fallback)
- `shasum` or `python3 hashlib` -- SHA-256 content hashing (macOS standard; python3 fallback)
- `fastapi`, `uvicorn`, `aiosqlite` -- bridge server only (Phase 4, optional extension)

---

## Milestones

| ID | Name | Scope (Modules) | Scope (Requirements) | Est. Size | Dependencies | Phase |
|----|------|-----------------|---------------------|-----------|-------------|-------|
| M1 | Schema + Migration | Module 1 (schema.sql, migrate-1.3.0.sh), Module 2 (db-init.sh changes) | REQ-CTX-001 to REQ-CTX-006, REQ-CTX-010 | M | None | 1 |
| M2 | Shared Store + Protocol | Module 2 (setup.sh changes), Module 3 (cortex-protocol.md) | REQ-CTX-007, REQ-CTX-008, REQ-CTX-009, REQ-CTX-011, REQ-CTX-012 | M | None | 1 |
| M3 | Curator Agent + Share Command | Module 4 (curator.md), Module 5 (omega-share.md) | REQ-CTX-013 to REQ-CTX-023 | L | M1, M2 | 2 |
| M4 | Session Close Curation Trigger | Module 6 (session-close.sh) | REQ-CTX-024 | S | M1 | 2 |
| M5 | Briefing Import + Shared Tracking | Module 7 (briefing.sh) | REQ-CTX-025 to REQ-CTX-029, REQ-CTX-032 | L | M1, M2 | 3 |
| M6 | Diagnostician + Team Status | Module 8 (diagnostician.md), Module 9 (omega-team-status.md) | REQ-CTX-030, REQ-CTX-031 | M | M2 | 3 |
| M7 | Documentation + CLAUDE.md | Module 10 (all docs) | REQ-CTX-033, REQ-CTX-034, REQ-CTX-035 | S | M1-M6 | 3 |
| M8 | Sync Adapter Abstraction + Git Adapter | Module 11 (sync-adapters.md, refactored git adapter) | REQ-CTX-039, REQ-CTX-040 | M | M3, M5 | 4 |
| M9 | Cloud Adapter + Config Command | Module 12 (omega-cortex-config.md), Module 14 (D1 adapter) | REQ-CTX-041, REQ-CTX-042, REQ-CTX-044, REQ-CTX-049 | L | M8 | 4 |
| M10 | Middleware + Offline Resilience | Module 13 (sync middleware) | REQ-CTX-045, REQ-CTX-046, REQ-CTX-047, REQ-CTX-048 | M | M8 | 4 |
| M11 | Self-Hosted Bridge + Adapter | Module 15 (cortex-bridge/) | REQ-CTX-043, REQ-CTX-050 | L | M8 | 4 |

### Milestone Dependency Graph

```
Phase 1:  M1 ────┐
                  │
          M2 ────┤
                  │
Phase 2:  M3 ◄───┤ (depends on M1, M2)
          M4 ◄───┘ (depends on M1)
                  │
Phase 3:  M5 ◄───┤ (depends on M1, M2)
          M6 ◄───┤ (depends on M2)
          M7 ◄───┘ (depends on M1-M6)
                  │
Phase 4:  M8 ◄───┤ (depends on M3, M5)
          M9 ◄───┤ (depends on M8)
          M10 ◄──┤ (depends on M8)
          M11 ◄──┘ (depends on M8)
```

### Phase Boundaries

- **Phase 1 complete**: M1 + M2. Schema ready, shared store initialized, protocol documented. Zero behavioral change.
- **Phase 2 complete**: M3 + M4. Curator agent operational, `/omega:share` command available, session-close trigger active. `.omega/shared/` files start appearing.
- **Phase 3 complete**: M5 + M6 + M7. Briefing imports shared knowledge, diagnostician queries shared incidents, team status dashboard available, all docs updated. **End-user value delivered.**
- **Phase 4 complete**: M8 + M9 + M10 + M11. Multi-backend sync operational, cloud and self-hosted options available, offline resilience, migration command.

### Won't (Deferred)

| Requirement | Status | Note |
|-------------|--------|------|
| REQ-CTX-036 | Won't | Shared knowledge decay -- deferred to v2 |
| REQ-CTX-037 | Won't | Cross-project sharing -- out of scope |
| REQ-CTX-038 | Won't | `/omega:resolve-conflicts` -- deferred to v2 |

---

## Requirement Traceability

| Requirement ID | Phase | Architecture Section | Module(s) | Milestone | Test IDs |
|---------------|-------|---------------------|-----------|-----------|----------|
| REQ-CTX-001 | 1 | Module 1: Schema + Migration | `core/db/schema.sql` | M1 | TEST-CTX-M1-001, TEST-CTX-M1-002, TEST-CTX-M1-003, TEST-CTX-M1-124-*, TEST-CTX-M1-125-* |
| REQ-CTX-002 | 1 | Module 1: Schema + Migration | `core/db/schema.sql` | M1 | TEST-CTX-M1-004 to 011, TEST-CTX-M1-083 to 091, TEST-CTX-M1-114 to 116, TEST-CTX-M1-120, TEST-CTX-M1-122, TEST-CTX-M1-123 |
| REQ-CTX-003 | 1 | Module 1: Schema + Migration | `core/db/migrate-1.3.0.sh` | M1 | TEST-CTX-M1-013 to 018, TEST-CTX-M1-037 to 042, TEST-CTX-M1-080 to 082, TEST-CTX-M1-117, TEST-CTX-M1-118 |
| REQ-CTX-004 | 1 | Module 1: Schema + Migration | `core/db/migrate-1.3.0.sh` | M1 | TEST-CTX-M1-019 to 024, TEST-CTX-M1-043 to 048, TEST-CTX-M1-057, TEST-CTX-M1-059 |
| REQ-CTX-005 | 1 | Module 1: Schema + Migration | `core/db/migrate-1.3.0.sh` | M1 | TEST-CTX-M1-025 to 032, TEST-CTX-M1-049 to 053, TEST-CTX-M1-055, TEST-CTX-M1-060, TEST-CTX-M1-119 |
| REQ-CTX-006 | 1 | Module 1: Schema + Migration | `scripts/db-init.sh`, `core/db/migrate-1.3.0.sh` | M1 | TEST-CTX-M1-036, TEST-CTX-M1-061 to 068, TEST-CTX-M1-069 to 082, TEST-CTX-M1-108 to 113 |
| REQ-CTX-007 | 1 | Module 2: Setup + Shared Store | `scripts/setup.sh` | M2 | TEST-CTX-M2-001 to 009, M2-033 to 038, M2-091, M2-092 |
| REQ-CTX-008 | 1 | Module 2: Setup + Shared Store | `scripts/setup.sh` | M2 | TEST-CTX-M2-010 to 013, M2-030 to 032, M2-093, M2-094, M2-096, M2-097 |
| REQ-CTX-009 | 1 | Module 3: Cortex Protocol | `core/protocols/cortex-protocol.md` | M2 | TEST-CTX-M2-055 to 078 |
| REQ-CTX-010 | 1 | Module 1: Schema + Migration | `core/db/schema.sql` | M1 | TEST-CTX-M1-012, TEST-CTX-M1-092 to 107, TEST-CTX-M1-121 |
| REQ-CTX-011 | 1 | All Modules | All modified files | M2 | TEST-CTX-M2-014 to 029, M2-088 to 090, M2-095 |
| REQ-CTX-012 | 1 | Module 3: Cortex Protocol | `core/protocols/cortex-protocol.md` | M2 | TEST-CTX-M2-039 to 054, M2-079 to 087, M2-098, M2-099 |
| REQ-CTX-013 | 2 | Module 4: Curator Agent | `core/agents/curator.md` | M3 | |
| REQ-CTX-014 | 2 | Module 4: Curator Agent | `core/agents/curator.md` | M3 | |
| REQ-CTX-015 | 2 | Module 4: Curator Agent | `core/agents/curator.md` | M3 | |
| REQ-CTX-016 | 2 | Module 4: Curator Agent | `core/agents/curator.md` | M3 | |
| REQ-CTX-017 | 2 | Module 4: Curator Agent | `core/agents/curator.md` | M3 | |
| REQ-CTX-018 | 2 | Module 4: Curator Agent | `core/agents/curator.md` | M3 | |
| REQ-CTX-019 | 2 | Module 4: Curator Agent | `core/agents/curator.md` | M3 | |
| REQ-CTX-020 | 2 | Module 4: Curator Agent | `core/agents/curator.md` | M3 | |
| REQ-CTX-021 | 2 | Module 4: Curator Agent | `core/agents/curator.md` | M3 | |
| REQ-CTX-022 | 2 | Module 4: Curator Agent | `core/agents/curator.md` | M3 | |
| REQ-CTX-023 | 2 | Module 5: Share Command | `core/commands/omega-share.md` | M3 | |
| REQ-CTX-024 | 2 | Module 6: Session Close Trigger | `core/hooks/session-close.sh` | M4 | |
| REQ-CTX-025 | 3 | Module 7: Briefing Import | `core/hooks/briefing.sh` | M5 | |
| REQ-CTX-026 | 3 | Module 7: Briefing Import | `core/hooks/briefing.sh` | M5 | |
| REQ-CTX-027 | 3 | Module 7: Briefing Import | `core/hooks/briefing.sh` | M5 | |
| REQ-CTX-028 | 3 | Module 7: Briefing Import | `core/hooks/briefing.sh` | M5 | |
| REQ-CTX-029 | 3 | Module 7: Briefing Import | `core/hooks/briefing.sh` | M5 | |
| REQ-CTX-030 | 3 | Module 8: Diagnostician Enhancement | `core/agents/diagnostician.md` | M6 | |
| REQ-CTX-031 | 3 | Module 9: Team Status Command | `core/commands/omega-team-status.md` | M6 | |
| REQ-CTX-032 | 3 | Module 7: Briefing Import | All shared entry producers/consumers | M5 | |
| REQ-CTX-033 | 3 | Module 10: Documentation | `CLAUDE.md` | M7 | |
| REQ-CTX-034 | 3 | Module 10: Documentation | `docs/architecture.md`, `docs/agent-inventory.md`, `README.md`, `core/protocols/memory-protocol.md` | M7 | |
| REQ-CTX-035 | 3 | Module 10: Documentation | `scripts/setup.sh` | M7 | |
| REQ-CTX-036 | -- | N/A (Won't) | N/A | -- | |
| REQ-CTX-037 | -- | N/A (Won't) | N/A | -- | |
| REQ-CTX-038 | -- | N/A (Won't) | N/A | -- | |
| REQ-CTX-039 | 4 | Module 11: Sync Adapter Abstraction | `core/protocols/sync-adapters.md` | M8 | |
| REQ-CTX-040 | 4 | Module 11: Sync Adapter Abstraction | Git JSONL adapter (refactored) | M8 | |
| REQ-CTX-041 | 4 | Module 14: Cloudflare D1 Adapter | D1 adapter logic in curator/briefing | M9 | |
| REQ-CTX-042 | 4 | Module 14: Cloudflare D1 Adapter | Turso adapter logic | M9 | |
| REQ-CTX-043 | 4 | Module 15: Self-Hosted Bridge | Self-hosted adapter + bridge server | M11 | |
| REQ-CTX-044 | 4 | Module 12: Cortex Config Command | `core/commands/omega-cortex-config.md` | M9 | |
| REQ-CTX-045 | 4 | Module 13: Sync Middleware | Middleware pipeline in curator | M10 | |
| REQ-CTX-046 | 4 | Module 13: Sync Middleware | `core/hooks/briefing.sh` (cloud pull) | M10 | |
| REQ-CTX-047 | 4 | Module 13: Sync Middleware | All adapters | M10 | |
| REQ-CTX-048 | 4 | Module 12: Cortex Config Command | Backend migration logic | M10 | |
| REQ-CTX-049 | 4 | Module 14: Cloudflare D1 Adapter | D1 schema provisioning | M9 | |
| REQ-CTX-050 | 4 | Module 15: Self-Hosted Bridge | `extensions/cortex-bridge/` | M11 | |
