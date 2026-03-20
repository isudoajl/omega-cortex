# Requirements: OMEGA Cortex -- Collective Intelligence Layer

## Scope
**Domains/modules/files affected:**

### New Files
| File | Purpose |
|------|---------|
| `core/agents/curator.md` | Knowledge Curator agent definition |
| `core/commands/omega-share.md` | Manual share trigger command |
| `core/commands/omega-team-status.md` | Team knowledge dashboard command |
| `core/protocols/cortex-protocol.md` | Full Cortex protocol reference (lazy-loaded) |

### Modified Files
| File | What Changes |
|------|-------------|
| `core/db/schema.sql` | Version bump to 1.3.0; new `shared_imports` table; `ALTER TABLE ADD COLUMN` migration script for `contributor`, `shared_uuid`, `is_private` on shareable tables; new `v_shared_briefing` view |
| `core/hooks/briefing.sh` | New section: shared knowledge import (behavioral learnings + incidents + hotspots from `.omega/shared/`) |
| `core/hooks/session-close.sh` | Curator trigger: invoke knowledge curation evaluation at session close |
| `scripts/setup.sh` | Initialize `.omega/shared/` directory; `.omega/shared/incidents/` subdirectory; summary output updates |
| `scripts/db-init.sh` | Run migration script for new columns on existing DBs |
| `CLAUDE.md` | Cortex protocol pointer (one line, under "Institutional Memory") |
| `README.md` | Cortex feature description, new commands listing |
| `docs/architecture.md` | Cortex architecture section (hybrid local+shared model) |
| `docs/agent-inventory.md` | Curator agent entry |
| `core/agents/diagnostician.md` | Query shared incidents during evidence assembly (Phase 2 of diagnosis process) |
| `core/protocols/memory-protocol.md` | Add "Shared Knowledge" section with export/import rules |

## Summary (plain language)
OMEGA currently works as an isolated brain per developer -- every learning, incident resolution, behavioral correction, and hotspot stays locked in one developer's local `memory.db`. When a new developer joins (or the same developer sets up on a new machine), they start from zero. Every re-learned lesson costs API tokens and time.

Cortex transforms OMEGA into a collective intelligence system. When a developer resolves a hard bug, corrects Claude's behavior, or discovers a fragile area, that knowledge automatically propagates to every team member through git. The architecture is hybrid: `memory.db` stays local (fast, safe), while curated high-value knowledge is exported to `.omega/shared/` files (git-tracked, JSONL format). A new Knowledge Curator agent filters signal from noise, and the existing briefing hook imports shared knowledge at session start.

The #1 use case: when a new team member runs `setup.sh`, they inherit the entire team's accumulated intelligence on day one.

## User Stories
- As a developer whose cousin is joining the project, I want my accumulated learnings, incident resolutions, and behavioral corrections to be available to my cousin on day one so that they do not waste API tokens re-learning what I already paid to learn.
- As a new team member running `setup.sh` for the first time, I want to inherit the team's collective intelligence immediately so that OMEGA is as smart for me as it is for the developer who has been using it for months.
- As a developer who just resolved a hard bug (INC-042), I want that incident's full diagnostic trail to be available to my teammates so that if they encounter similar symptoms, the diagnostician can reference my resolution instead of starting from scratch.
- As a developer who corrected Claude ("never mock the database in integration tests"), I want that behavioral learning to propagate to all team members so that every developer's test-writer already knows the rule.
- As a team lead, I want to see which areas of the codebase are causing problems across the entire team (shared hotspot map) so that I can prioritize refactoring.
- As a solo developer working across multiple machines, I want my learnings to sync via git so that I have continuity across environments.
- As an existing OMEGA user who does NOT want Cortex, I want everything to work exactly as before with zero degradation.

## Open Questions Resolved

### Q1: Shared directory naming
**Decision:** `.omega/shared/`
**Rationale:** Consistent with OMEGA branding. Dotfile convention hides it from casual directory listings. Distinct from `.claude/` (which is deployment artifacts). The `.omega/` prefix creates a clear namespace for team-level OMEGA artifacts, separate from the per-developer `.claude/` namespace.

### Q2: Curator trigger mechanism
**Decision:** Session close-out (via `session-close.sh` Notification hook)
**Rationale:** This is the most natural trigger point. Work is complete, knowledge has been logged to memory.db, and the developer is about to leave. The Notification hook already fires on session lifecycle events. The curator evaluation runs as a lightweight check -- if nothing qualifies for sharing, it exits silently. Manual trigger via `/omega:share` remains as a supplement for force-sharing or reviewing what would be shared.

### Q3: Contributor identity
**Decision:** `git config user.name` + `git config user.email`
**Rationale:** Universally available on every machine with git. No OMEGA-specific configuration needed. Already used for git commits, so it is the identity the team recognizes. Stored as `"Name <email>"` format in the `contributor` field.

### Q4: Privacy marking
**Decision:** `is_private INTEGER DEFAULT 0` column on shareable tables
**Rationale:** Simple, explicit, per-entry control. A developer can mark specific entries as private (e.g., personal behavioral corrections) and the curator will skip them. Default is 0 (not private) -- sharing is opt-out, not opt-in, because the value proposition requires most knowledge to flow.

### Q5: Briefing token budget cap (from evaluation conditions)
**Decision:** Hard caps per category at session briefing:
- Top 10 shared behavioral learnings (by confidence DESC)
- Top 3 shared resolved incidents (by relevance to current scope, or most recent if no scope)
- Top 5 shared hotspots (by risk_level DESC, contributor_count DESC)
**Rationale:** The current briefing injects up to 15 local behavioral learnings + 10 open incidents. Adding shared knowledge must not exceed the 60% context budget. These caps ensure the shared injection adds approximately 200-400 tokens (similar to the existing identity block + behavioral learnings combined). The caps can be tuned based on real usage.

### Q6: Curator confidence threshold (from evaluation conditions)
**Decision:** Confidence >= 0.8 for v1
**Rationale:** Conservative start. Better to under-share than over-share. The user accepted this condition explicitly. Entries below 0.8 need more local reinforcement before team promotion. The threshold is a single constant in the curator agent definition, trivially adjustable in future versions.

## Phased Delivery

The feature is organized into 3 independently deployable phases. Each phase goes through the full OMEGA pipeline (analyst -> architect -> test-writer -> developer -> QA -> reviewer) and is committed independently.

### Phase 1: Foundation
Schema additions, shared knowledge store directory structure, setup.sh initialization, export/import plumbing. **Zero behavioral change** -- existing OMEGA behavior is identical. This phase establishes the infrastructure that Phases 2 and 3 build on.

### Phase 2: Curation
Curator agent definition, `/omega:share` command, session-close.sh curator trigger. This phase adds the **intelligence layer** that evaluates and exports knowledge. After this phase, `.omega/shared/` files start appearing in the repository.

### Phase 3: Consumption
Briefing hook shared knowledge import, diagnostician enhancement for shared incidents, `/omega:team-status` dashboard command. This phase delivers **end-user value** -- developers see shared knowledge in their sessions.

### Phase 4: Sync Adapters (Real-Time Backends)
Multi-backend sync architecture. The curator's output flows through a **Sync Adapter** abstraction that can target different backends: git JSONL (default, from Phases 1-3), cloud database (Cloudflare D1, Turso), or self-hosted database (VPS SQLite/PostgreSQL over HTTP). This phase transforms Cortex from "git-based sharing" into a **multi-backend collective intelligence platform** with real-time sync capability.

```
Local memory.db --> Curator Agent --> Sync Adapter --> Backend
                                           |
                                 +---------+---------+
                                 |         |         |
                              Git JSONL  Cloud DB   Self-hosted
                              (default)  (CF D1,    (VPS SQLite/
                              zero-infra  Turso)    PostgreSQL)
```

## Requirements

### Phase 1: Foundation

| ID | Requirement | Priority | Acceptance Criteria |
|----|------------|----------|-------------------|
| REQ-CTX-001 | Schema version bump to 1.3.0 | Must | - [ ] Version comment updated in `core/db/schema.sql` line 2 |
| REQ-CTX-002 | `shared_imports` table in schema.sql | Must | - [ ] CREATE TABLE IF NOT EXISTS with uuid tracking<br>- [ ] Prevents re-import of shared entries |
| REQ-CTX-003 | `contributor` column on shareable tables | Must | - [ ] Added via migration script to: `behavioral_learnings`, `incidents`, `lessons`, `patterns`, `decisions`, `hotspots`<br>- [ ] NULL-safe (existing rows get NULL) |
| REQ-CTX-004 | `shared_uuid` column on shareable tables | Must | - [ ] Added to: `behavioral_learnings`, `incidents`, `lessons`, `patterns`, `decisions`<br>- [ ] Used for deduplication during import |
| REQ-CTX-005 | `is_private` column on shareable tables | Must | - [ ] Added to: `behavioral_learnings`, `incidents`, `lessons`, `patterns`, `decisions`<br>- [ ] DEFAULT 0 (not private) |
| REQ-CTX-006 | Migration script for existing DBs | Must | - [ ] ALTER TABLE ADD COLUMN with existence checks<br>- [ ] Idempotent (safe to re-run)<br>- [ ] Existing data preserved |
| REQ-CTX-007 | `.omega/shared/` directory initialization in setup.sh | Must | - [ ] Created during setup<br>- [ ] Includes `incidents/` subdirectory<br>- [ ] Includes `.gitkeep` files |
| REQ-CTX-008 | `.omega/shared/` gitignore configuration | Must | - [ ] `.omega/shared/` is NOT gitignored (tracked by git)<br>- [ ] `memory.db` remains gitignored<br>- [ ] Target project `.gitignore` updated by setup.sh if needed |
| REQ-CTX-009 | JSONL entry format specification | Must | - [ ] Each entry is one JSON object per line<br>- [ ] Required fields: `uuid`, `contributor`, `source_project`, `created_at`, `confidence`, `content_hash`<br>- [ ] Category-specific fields documented |
| REQ-CTX-010 | `v_shared_briefing` view for shareable entries | Should | - [ ] View selects high-confidence, non-private entries ready for sharing<br>- [ ] Confidence >= 0.8, status = 'active', is_private = 0 |
| REQ-CTX-011 | Backward compatibility: no Cortex = no change | Must | - [ ] Projects without `.omega/shared/` work identically to pre-Cortex<br>- [ ] briefing.sh skips shared import if directory absent<br>- [ ] All 15 existing agents unaffected |
| REQ-CTX-012 | `core/protocols/cortex-protocol.md` reference file | Should | - [ ] Full Cortex protocol documentation<br>- [ ] @INDEX block for lazy loading<br>- [ ] Covers: JSONL format, curation rules, import rules, privacy, contributor identity |

### Phase 2: Curation

| ID | Requirement | Priority | Acceptance Criteria |
|----|------------|----------|-------------------|
| REQ-CTX-013 | Curator agent definition (`core/agents/curator.md`) | Must | - [ ] Agent file with YAML frontmatter<br>- [ ] Relevance filter (team vs personal)<br>- [ ] Confidence threshold (>= 0.8)<br>- [ ] Deduplication (UUID + content-hash)<br>- [ ] Reinforcement merging (same learning from 2+ devs = confidence boost) |
| REQ-CTX-014 | Curator: behavioral learning export | Must | - [ ] Exports qualifying `behavioral_learnings` to `.omega/shared/behavioral-learnings.jsonl`<br>- [ ] Skips entries where `is_private = 1`<br>- [ ] Includes: uuid, contributor, rule, context, confidence, occurrences, source_project, created_at |
| REQ-CTX-015 | Curator: incident export | Must | - [ ] Exports resolved incidents to `.omega/shared/incidents/INC-NNN.json`<br>- [ ] One file per incident<br>- [ ] Includes full timeline from `incident_entries`<br>- [ ] Includes: title, domain, symptoms, root_cause, resolution, entries, contributor, tags |
| REQ-CTX-016 | Curator: hotspot export | Must | - [ ] Exports hotspot data to `.omega/shared/hotspots.jsonl`<br>- [ ] Aggregates by file_path, contributor, risk_level, times_touched<br>- [ ] Weighted by contributor count and recency |
| REQ-CTX-017 | Curator: lesson export | Should | - [ ] Exports qualifying `lessons` to `.omega/shared/lessons.jsonl`<br>- [ ] Confidence >= 0.8, status = 'active', is_private = 0 |
| REQ-CTX-018 | Curator: pattern export | Should | - [ ] Exports `patterns` to `.omega/shared/patterns.jsonl` |
| REQ-CTX-019 | Curator: decision export | Should | - [ ] Exports active `decisions` to `.omega/shared/decisions.jsonl`<br>- [ ] Confidence >= 0.8, status = 'active' |
| REQ-CTX-020 | Curator: redundancy check (deduplication) | Must | - [ ] Checks if entry UUID or content_hash already exists in shared store<br>- [ ] If exists: reinforce (bump occurrences, update confidence) rather than duplicate<br>- [ ] If new: append to JSONL file |
| REQ-CTX-021 | Curator: conflict detection | Should | - [ ] Detects contradictory learnings (same domain, opposing rules)<br>- [ ] Writes conflicts to `.omega/shared/conflicts.jsonl`<br>- [ ] Does NOT auto-resolve -- flags for human review |
| REQ-CTX-022 | Curator: cross-contributor reinforcement | Must | - [ ] Same learning from 2+ contributors independently = confidence boost of +0.2 (double normal reinforcement)<br>- [ ] Contributor list tracked in JSONL entry |
| REQ-CTX-023 | `/omega:share` command | Must | - [ ] Manually triggers curator evaluation and export<br>- [ ] Shows what was shared, what was skipped and why<br>- [ ] Supports `--force` flag for sharing below-threshold entries<br>- [ ] Creates `workflow_runs` entry with type='share' |
| REQ-CTX-024 | Session-close.sh curator trigger | Should | - [ ] `session-close.sh` enhanced to invoke curator evaluation<br>- [ ] Lightweight: only checks if new shareable entries exist since last share<br>- [ ] Silent if nothing qualifies<br>- [ ] Does not block session close on failure |

### Phase 3: Consumption

| ID | Requirement | Priority | Acceptance Criteria |
|----|------------|----------|-------------------|
| REQ-CTX-025 | Briefing: shared behavioral learnings import | Must | - [ ] `briefing.sh` reads `.omega/shared/behavioral-learnings.jsonl`<br>- [ ] Imports entries not in `shared_imports` table<br>- [ ] Injects top 10 shared learnings (by confidence) alongside local ones<br>- [ ] Labels shared entries with contributor attribution<br>- [ ] Skips if `.omega/shared/` does not exist |
| REQ-CTX-026 | Briefing: shared incidents import | Must | - [ ] `briefing.sh` reads `.omega/shared/incidents/*.json`<br>- [ ] Imports incident metadata into local `incidents` table (marked `is_shared=1`)<br>- [ ] Shows top 3 relevant shared resolved incidents in briefing<br>- [ ] Skips if no shared incidents exist |
| REQ-CTX-027 | Briefing: shared hotspots import | Must | - [ ] `briefing.sh` reads `.omega/shared/hotspots.jsonl`<br>- [ ] Merges shared hotspot data with local hotspot data<br>- [ ] Shows top 5 shared hotspots in briefing<br>- [ ] Cross-contributor correlation surfaced (e.g., "3 devs hit issues in payments/") |
| REQ-CTX-028 | `shared_imports` tracking (prevent re-import) | Must | - [ ] Every imported shared UUID recorded in `shared_imports` table<br>- [ ] On subsequent briefings, only new entries (not in `shared_imports`) are processed<br>- [ ] Incremental import: O(new entries), not O(all entries) |
| REQ-CTX-029 | Briefing token budget enforcement | Must | - [ ] Shared knowledge injection capped: 10 behavioral learnings + 3 incidents + 5 hotspots<br>- [ ] Total shared section under 400 tokens<br>- [ ] Labels clearly distinguish shared vs local entries |
| REQ-CTX-030 | Diagnostician: shared incident query | Must | - [ ] During Phase 2 (Evidence Assembly), diagnostician queries `.omega/shared/incidents/`<br>- [ ] Pattern matching: symptom/domain/tag similarity to current investigation<br>- [ ] Surfaces relevant shared incidents: "This resembles INC-042 -- see resolution"<br>- [ ] Adds shared incident evidence to constraint table |
| REQ-CTX-031 | `/omega:team-status` command | Should | - [ ] Dashboard showing: shared knowledge stats (counts by category), recent contributions (who, what, when), active shared incidents, team hotspot map, unresolved conflicts<br>- [ ] Creates `workflow_runs` entry with type='team-status'<br>- [ ] Read-only: does not modify any data |
| REQ-CTX-032 | Contributor attribution in shared entries | Must | - [ ] Every shared entry tracks contributor (git user.name + email)<br>- [ ] Attribution surfaced in briefing: "Learned from Developer A (INC-042)"<br>- [ ] Attribution visible in `/omega:team-status` |
| REQ-CTX-033 | Cortex protocol pointer in CLAUDE.md | Should | - [ ] One-line pointer in "Institutional Memory" section<br>- [ ] References `.claude/protocols/cortex-protocol.md`<br>- [ ] Under 50 characters added to CLAUDE.md |
| REQ-CTX-034 | Documentation updates | Should | - [ ] `docs/architecture.md` -- Cortex architecture section<br>- [ ] `docs/agent-inventory.md` -- curator agent entry<br>- [ ] `README.md` -- feature description, new commands<br>- [ ] `core/protocols/memory-protocol.md` -- shared knowledge section |
| REQ-CTX-035 | setup.sh command listing update | Could | - [ ] `/omega:share` and `/omega:team-status` in summary output |
| REQ-CTX-036 | Shared knowledge decay in shared store | Won't | - [ ] Deferred to v2 -- shared entries do not decay in v1<br>- [ ] Local imports respect local decay mechanics |
| REQ-CTX-037 | Cross-project knowledge sharing | Won't | - [ ] Explicitly out of scope -- Cortex shares within a single repository only |
| REQ-CTX-038 | `/omega:resolve-conflicts` command | Won't | - [ ] Conflicts flagged in `conflicts.jsonl` are resolved manually for v1<br>- [ ] Dedicated command deferred to v2 |

### Phase 4: Sync Adapters (Real-Time Backends)

| ID | Requirement | Priority | Acceptance Criteria |
|----|------------|----------|-------------------|
| REQ-CTX-039 | Sync Adapter abstraction layer | Must | - [ ] New file: `core/protocols/sync-adapters.md` defining the adapter interface<br>- [ ] Adapter interface: `export(entries)`, `import() -> entries`, `status() -> stats`, `health() -> bool`<br>- [ ] Backend selection via `.omega/cortex-config.json` (or `memory.db` setting)<br>- [ ] Default backend: `git-jsonl` (Phases 1-3 behavior, zero config needed) |
| REQ-CTX-040 | Git JSONL adapter (refactored default) | Must | - [ ] Existing Phase 1-3 git JSONL logic refactored into adapter pattern<br>- [ ] Export: writes to `.omega/shared/` JSONL/JSON files (unchanged behavior)<br>- [ ] Import: reads from `.omega/shared/` files (unchanged behavior)<br>- [ ] Sync: developer commits + pushes (manual, git-native)<br>- [ ] Zero configuration required -- this is the default |
| REQ-CTX-041 | Cloud DB adapter: Cloudflare D1 | Should | - [ ] Adapter connects to Cloudflare D1 via REST API<br>- [ ] Configuration: `cortex-config.json` with `api_token`, `account_id`, `database_id`<br>- [ ] Export: curator pushes entries via D1 HTTP API<br>- [ ] Import: briefing hook pulls new entries via D1 HTTP API<br>- [ ] Real-time: no git commit/push needed -- changes propagate immediately<br>- [ ] Schema: D1 tables mirror the JSONL structure (behavioral_learnings, incidents, hotspots, etc.)<br>- [ ] Authentication: API token stored in env var `OMEGA_CORTEX_API_TOKEN` (never in files) |
| REQ-CTX-042 | Cloud DB adapter: Turso (libSQL) | Could | - [ ] Adapter connects to Turso via HTTP API<br>- [ ] Configuration: `cortex-config.json` with `url`, `auth_token`<br>- [ ] Same export/import interface as D1 adapter<br>- [ ] Turso-native features: embedded replicas for offline-first with automatic sync |
| REQ-CTX-043 | Self-hosted adapter: VPS SQLite/PostgreSQL | Should | - [ ] Adapter connects to a user-managed database via HTTP bridge<br>- [ ] Configuration: `cortex-config.json` with `endpoint_url`, `auth_token`<br>- [ ] HTTP bridge: lightweight script (Python/Node) user deploys on their VPS<br>- [ ] Bridge script provided in `extensions/cortex-bridge/` with setup instructions<br>- [ ] Supports SQLite (via HTTP) and PostgreSQL backends<br>- [ ] Self-sovereignty: user owns their data, no third-party dependencies |
| REQ-CTX-044 | `/omega:cortex-config` command | Must | - [ ] Interactive configuration for sync backend selection<br>- [ ] Options: `git` (default), `cloudflare-d1`, `turso`, `self-hosted`<br>- [ ] Validates connectivity on selection (health check)<br>- [ ] Stores config in `.omega/cortex-config.json`<br>- [ ] `.omega/cortex-config.json` is gitignored (contains credentials reference) |
| REQ-CTX-045 | Sync middleware pipeline | Must | - [ ] Curator output flows through: Curator -> Middleware -> Adapter -> Backend<br>- [ ] Middleware handles: format transformation, batching, retry on failure, conflict pre-check<br>- [ ] Middleware is adapter-agnostic (same pipeline for all backends)<br>- [ ] Error handling: if backend is unavailable, cache locally and retry next session |
| REQ-CTX-046 | Real-time import for cloud/self-hosted backends | Should | - [ ] Briefing hook detects backend type from `cortex-config.json`<br>- [ ] For cloud/self-hosted: pull latest entries via HTTP instead of reading `.omega/shared/` files<br>- [ ] Incremental pull: use `last_sync_timestamp` to fetch only new entries<br>- [ ] Fallback: if HTTP fails, fall back to `.omega/shared/` files if they exist |
| REQ-CTX-047 | Offline-first resilience | Must | - [ ] All backends degrade gracefully when offline<br>- [ ] Cloud/self-hosted: queue exports locally, sync when connectivity returns<br>- [ ] Git JSONL: already offline-first by design<br>- [ ] Local memory.db always functional regardless of backend availability |
| REQ-CTX-048 | Backend migration command | Could | - [ ] `/omega:cortex-migrate --from=git --to=cloudflare-d1`<br>- [ ] Exports all shared knowledge from source backend, imports into target<br>- [ ] Non-destructive: source data preserved<br>- [ ] Validates completeness after migration |
| REQ-CTX-049 | D1 schema provisioning | Should | - [ ] `/omega:cortex-config` for D1 backend auto-provisions the D1 database schema<br>- [ ] SQL migration script for D1 tables matching JSONL entry structure<br>- [ ] Idempotent: safe to re-run |
| REQ-CTX-050 | Cortex bridge server (self-hosted) | Should | - [ ] Lightweight HTTP server in `extensions/cortex-bridge/`<br>- [ ] Receives export requests from OMEGA curator, stores in local DB<br>- [ ] Serves import requests from OMEGA briefing hook<br>- [ ] Languages: Python (Flask/FastAPI) or Node.js -- minimal dependencies<br>- [ ] Docker support: `Dockerfile` + `docker-compose.yml` for easy VPS deployment<br>- [ ] Authentication: shared secret token<br>- [ ] API: `POST /export`, `GET /import?since=TIMESTAMP`, `GET /health`, `GET /status` |

## Acceptance Criteria (detailed)

### REQ-CTX-001: Schema version bump
- [ ] `core/db/schema.sql` line 2 comment updated from `Version: 1.2.0` to `Version: 1.3.0 -- Added Cortex collective intelligence layer`
- [ ] No functional change -- comment only

### REQ-CTX-002: `shared_imports` table
- [ ] Table created with `CREATE TABLE IF NOT EXISTS shared_imports` in `core/db/schema.sql`
- [ ] Columns: `id INTEGER PRIMARY KEY AUTOINCREMENT`, `shared_uuid TEXT NOT NULL`, `category TEXT NOT NULL` (behavioral_learning, incident, hotspot, lesson, pattern, decision), `source_file TEXT` (which JSONL/JSON file it came from), `imported_at TEXT DEFAULT (datetime('now'))`
- [ ] `UNIQUE(shared_uuid)` constraint prevents duplicate imports
- [ ] Running `db-init.sh` on an existing `memory.db` creates the table without affecting existing tables
- [ ] Index on `shared_uuid` for fast lookup during import

### REQ-CTX-003: `contributor` column on shareable tables
- [ ] Migration script adds `contributor TEXT` to: `behavioral_learnings`, `incidents`, `lessons`, `patterns`, `decisions`, `hotspots`
- [ ] Uses `ALTER TABLE ADD COLUMN` with existence check pattern: query `PRAGMA table_info(table_name)` first, only ALTER if column missing
- [ ] Existing rows get NULL for `contributor` (no backfill -- these are pre-Cortex entries)
- [ ] New entries populate `contributor` via `git config user.name` + `git config user.email` formatted as `"Name <email>"`
- [ ] NULL contributor is valid -- agents must handle gracefully

### REQ-CTX-004: `shared_uuid` column on shareable tables
- [ ] Migration script adds `shared_uuid TEXT` to: `behavioral_learnings`, `incidents`, `lessons`, `patterns`, `decisions`
- [ ] NOT added to `hotspots` (hotspots use `file_path` as natural key for dedup)
- [ ] NULL for locally-created entries; populated when imported from shared store
- [ ] Used by `shared_imports` tracking to prevent re-import

### REQ-CTX-005: `is_private` column on shareable tables
- [ ] Migration script adds `is_private INTEGER DEFAULT 0` to: `behavioral_learnings`, `incidents`, `lessons`, `patterns`, `decisions`
- [ ] DEFAULT 0 = not private = eligible for sharing
- [ ] Set to 1 by developer to exclude from curation
- [ ] Curator MUST check `is_private = 0` before exporting any entry

### REQ-CTX-006: Migration script for existing DBs
- [ ] New file: `core/db/migrate-1.3.0.sql` (or inline in `db-init.sh`)
- [ ] Uses pattern: `SELECT COUNT(*) FROM pragma_table_info('table') WHERE name='column'` to check existence before ALTER
- [ ] Idempotent: running twice produces no errors and no data loss
- [ ] `db-init.sh` calls migration after running `schema.sql`
- [ ] Tested on: fresh DB (no-op, columns created by CREATE TABLE), existing 1.2.0 DB (columns added), already-migrated 1.3.0 DB (no-op)

### REQ-CTX-007: `.omega/shared/` directory initialization
- [ ] `setup.sh` creates `.omega/shared/` in the target project root
- [ ] Creates `.omega/shared/incidents/` subdirectory
- [ ] Places `.gitkeep` in both directories (ensures git tracks empty dirs)
- [ ] Idempotent: does not error if directories already exist
- [ ] Only creates if not already present (does not overwrite existing shared data)
- [ ] Output message: `+ .omega/shared/ initialized` (new) or `= .omega/shared/ already exists` (existing)

### REQ-CTX-008: Gitignore configuration
- [ ] `setup.sh` ensures `.omega/shared/` is NOT in `.gitignore` of the target project
- [ ] If target `.gitignore` contains `.omega/` or `.omega/shared/`, setup.sh warns: "WARNING: .omega/shared/ appears to be gitignored -- Cortex requires it to be tracked"
- [ ] `memory.db` gitignore entries remain unchanged
- [ ] `.omega/shared/` IS tracked by git (this is the distribution mechanism)

### REQ-CTX-009: JSONL entry format specification
- [ ] Each JSONL file has one JSON object per line (no multi-line JSON)
- [ ] Common fields across ALL entries: `uuid` (UUID v4), `contributor` (git identity string), `source_project` (project name), `created_at` (ISO 8601), `confidence` (0.0-1.0), `occurrences` (integer), `content_hash` (SHA-256 of content field for dedup)
- [ ] `behavioral-learnings.jsonl` additional fields: `rule`, `context`, `status`
- [ ] `hotspots.jsonl` additional fields: `file_path`, `risk_level`, `times_touched`, `description`, `contributors` (JSON array of contributor strings)
- [ ] `lessons.jsonl` additional fields: `domain`, `content`, `source_agent`
- [ ] `patterns.jsonl` additional fields: `domain`, `name`, `description`, `example_files`
- [ ] `decisions.jsonl` additional fields: `domain`, `decision`, `rationale`, `alternatives`
- [ ] Incident files (`.omega/shared/incidents/INC-NNN.json`): full JSON object (not JSONL) with: `incident_id`, `title`, `domain`, `status`, `description`, `symptoms`, `root_cause`, `resolution`, `affected_files`, `tags`, `contributor`, `created_at`, `resolved_at`, `entries` (array of incident_entries)
- [ ] Format documented in `core/protocols/cortex-protocol.md`

### REQ-CTX-010: `v_shared_briefing` view
- [ ] View created with `CREATE VIEW IF NOT EXISTS v_shared_briefing` in `core/db/schema.sql`
- [ ] Selects from `behavioral_learnings` where `confidence >= 0.8 AND status = 'active' AND is_private = 0`
- [ ] Orders by `confidence DESC, occurrences DESC`
- [ ] Graceful fallback: if `is_private` column does not exist (pre-migration), view creation uses a subquery that checks column existence or the view is created by the migration script
- [ ] Returns empty result set if no qualifying entries exist

### REQ-CTX-011: Backward compatibility
- [ ] Given a target project without `.omega/shared/`: `briefing.sh` produces identical output to pre-Cortex version
- [ ] Given a `memory.db` without Cortex columns (`contributor`, `shared_uuid`, `is_private`): all 15 existing agents function without errors
- [ ] Given a project where setup.sh has NOT been re-run since Cortex: no errors, no new behavior
- [ ] The `shared_imports` table being absent does not cause errors (existence-checked before use)
- [ ] No existing hook behavior is altered for non-Cortex projects

### REQ-CTX-012: Cortex protocol reference file
- [ ] New file: `core/protocols/cortex-protocol.md`
- [ ] @INDEX block in first 15 lines mapping sections to line ranges
- [ ] Sections: SHARED-STORE-FORMAT, CURATION-RULES, IMPORT-RULES, PRIVACY, CONTRIBUTOR-IDENTITY, CONFLICT-RESOLUTION
- [ ] Agents reference this file via lazy-load (read @INDEX, then offset/limit for needed section)
- [ ] Total file under 300 lines

### REQ-CTX-013: Curator agent definition
- [ ] New file: `core/agents/curator.md` with YAML frontmatter (name, description, tools, model)
- [ ] Model: `claude-sonnet-4-20250514` (curation is routine evaluation, not deep reasoning -- Sonnet is appropriate)
- [ ] Tools: Read, Write, Bash, Grep, Glob (no Edit -- curator writes new files, doesn't edit code)
- [ ] Relevance filter documented: personal preferences (communication style, address-as) = NOT shared; technical corrections, debugging patterns, code conventions = shared
- [ ] Confidence threshold: `>= 0.8` hardcoded in v1, documented as tunable
- [ ] Institutional Memory Protocol section (standard: briefing, incremental logging, close-out)
- [ ] Process: (1) query memory.db for qualifying entries, (2) check `.omega/shared/` for existing entries, (3) deduplicate, (4) export new/reinforced entries, (5) detect conflicts, (6) report
- [ ] Error handling: if `.omega/shared/` does not exist, create it; if JSONL file does not exist, create it; if sqlite3 fails, log and continue

### REQ-CTX-014: Behavioral learning export
- [ ] Curator queries: `SELECT * FROM behavioral_learnings WHERE confidence >= 0.8 AND status = 'active' AND is_private = 0`
- [ ] For each qualifying entry: generate UUID v4 (via `python3 -c "import uuid; print(uuid.uuid4())"` or `uuidgen`), compute content_hash (SHA-256 of `rule` field)
- [ ] Check `.omega/shared/behavioral-learnings.jsonl` for existing entry with matching `content_hash`
- [ ] If match: update existing line (bump occurrences, update confidence, add contributor to contributors list)
- [ ] If no match: append new JSONL line
- [ ] Record `shared_uuid` back to local `behavioral_learnings` row for tracking
- [ ] Populate `contributor` from `git config user.name` + `git config user.email`

### REQ-CTX-015: Incident export
- [ ] Curator queries: `SELECT * FROM incidents WHERE status = 'resolved' AND is_private = 0`
- [ ] For each qualifying incident: query all `incident_entries` for that incident_id
- [ ] Export as `.omega/shared/incidents/INC-NNN.json` (one file per incident)
- [ ] If file already exists: update it (merge entries, update resolution)
- [ ] Include full timeline: all entries with entry_type, content, result, agent, created_at
- [ ] Include extracted behavioral learnings linked to this incident (cross-reference via `context` field)
- [ ] Populate `contributor` field

### REQ-CTX-016: Hotspot export
- [ ] Curator queries: `SELECT * FROM hotspots WHERE risk_level IN ('medium', 'high', 'critical')`
- [ ] For each qualifying hotspot: create JSONL entry with file_path, risk_level, times_touched, description, contributor
- [ ] Check `.omega/shared/hotspots.jsonl` for existing entry with matching `file_path`
- [ ] If match: merge -- take highest risk_level, sum times_touched, append contributor to contributors list
- [ ] If no match: append new JSONL line
- [ ] Cross-contributor correlation: when 2+ contributors flag the same file_path, add `"cross_contributor_alert": true` and `"contributor_count": N`

### REQ-CTX-017: Lesson export
- [ ] Same pattern as behavioral learnings: confidence >= 0.8, active, not private
- [ ] Content_hash computed from `domain` + `content` concatenation
- [ ] Deduplicated against `.omega/shared/lessons.jsonl`

### REQ-CTX-018: Pattern export
- [ ] Export all patterns (no confidence threshold -- patterns are already curated)
- [ ] Content_hash computed from `domain` + `name` + `description`
- [ ] Deduplicated against `.omega/shared/patterns.jsonl`

### REQ-CTX-019: Decision export
- [ ] Confidence >= 0.8, status = 'active', not private
- [ ] Content_hash computed from `domain` + `decision`
- [ ] Deduplicated against `.omega/shared/decisions.jsonl`

### REQ-CTX-020: Redundancy check (deduplication)
- [ ] Before appending to any JSONL file: read the file line-by-line, parse each JSON object, compare `content_hash`
- [ ] If `content_hash` match found: reinforce (update that line: bump occurrences, update confidence, merge contributor list)
- [ ] If UUID match found but content_hash differs: this is an UPDATE -- replace the line
- [ ] If no match: append new line
- [ ] JSONL files are rewritten in-place when lines are updated (read all, modify, write all)
- [ ] Incident files (JSON, not JSONL): overwrite entirely when updating

### REQ-CTX-021: Conflict detection
- [ ] After deduplication, compare new entry against all existing entries in same category
- [ ] For behavioral learnings: flag if new `rule` contains negation of existing rule (heuristic: "never X" vs "always X" for same X)
- [ ] For decisions: flag if new `decision` for same `domain` contradicts existing decision
- [ ] Conflicts written to `.omega/shared/conflicts.jsonl` with: `uuid`, `type` (contradiction), `entry_a_uuid`, `entry_b_uuid`, `description`, `contributor`, `created_at`, `status` (unresolved)
- [ ] Curator outputs warning: "CONFLICT DETECTED: [description] -- see .omega/shared/conflicts.jsonl"

### REQ-CTX-022: Cross-contributor reinforcement
- [ ] When an entry is reinforced by a DIFFERENT contributor than the original: confidence boost = +0.2 (vs normal +0.1)
- [ ] `contributors` field in JSONL entries is a JSON array of contributor strings
- [ ] When 3+ unique contributors reinforce the same entry: confidence set to 1.0 (maximum -- strong team consensus)
- [ ] Reinforcement is tracked: each contributor's reinforcement timestamp logged in the entry

### REQ-CTX-023: `/omega:share` command
- [ ] New file: `core/commands/omega-share.md`
- [ ] Invokes curator agent with explicit share directive
- [ ] Creates `workflow_runs` entry with `type='share'`
- [ ] Output: summary table showing what was shared, what was skipped (with reason), what was reinforced, any conflicts detected
- [ ] `--force` flag: share entries below confidence threshold (overrides >= 0.8 rule)
- [ ] `--dry-run` flag: show what WOULD be shared without actually sharing
- [ ] Memory protocol: briefing, incremental logging, close-out

### REQ-CTX-024: Session-close.sh curator trigger
- [ ] `session-close.sh` enhanced: after hotspot promotion, check if new shareable entries exist
- [ ] Check: `SELECT COUNT(*) FROM behavioral_learnings WHERE confidence >= 0.8 AND status = 'active' AND is_private = 0 AND shared_uuid IS NULL`
- [ ] Check: `SELECT COUNT(*) FROM incidents WHERE status = 'resolved' AND is_private = 0 AND shared_uuid IS NULL`
- [ ] If count > 0: invoke curator evaluation (lightweight -- the bash hook spawns a background process or logs a reminder)
- [ ] Note: the actual curation may need to be done by a Claude agent, which cannot be spawned from a bash hook. Alternative implementation: write a `.claude/hooks/.curation_pending` flag file that the next session's briefing detects and recommends running `/omega:share`
- [ ] Must not block session close. Must not error if `.omega/shared/` does not exist. Must be silent if nothing qualifies.

### REQ-CTX-025: Shared behavioral learnings import in briefing
- [ ] `briefing.sh` new section: after "BEHAVIORAL LEARNINGS" section (line 118), before "OPEN INCIDENTS" section (line 128)
- [ ] Checks if `.omega/shared/behavioral-learnings.jsonl` exists
- [ ] If exists: reads entries, filters to those NOT in `shared_imports` table
- [ ] For each new entry: inserts into `shared_imports` (shared_uuid, category='behavioral_learning', source_file)
- [ ] Inserts qualifying entries into local `behavioral_learnings` table with `is_shared=1` flag (... wait, schema does not have `is_shared`. The `shared_uuid` being non-NULL is the indicator that it came from shared store)
- [ ] Injects top 10 shared behavioral learnings in briefing output, labeled with `[TEAM]` prefix and contributor attribution
- [ ] Format: `  [TEAM 0.9] Never mock the database in integration tests (from Developer A)`
- [ ] Uses python3 to parse JSONL (bash cannot parse JSON reliably)
- [ ] Error handling: if python3 fails, if JSONL is malformed, if sqlite3 fails -- all suppressed, briefing continues

### REQ-CTX-026: Shared incidents import in briefing
- [ ] `briefing.sh` checks if `.omega/shared/incidents/` directory exists and has files
- [ ] For each `INC-NNN.json` file: check if `INC-NNN` UUID is in `shared_imports`
- [ ] If not imported: import incident metadata into local `incidents` table (with `shared_uuid` populated)
- [ ] Import incident entries into local `incident_entries` table
- [ ] Record in `shared_imports`
- [ ] Briefing output: show top 3 recent shared resolved incidents with title, domain, and contributor
- [ ] Format: `  [TEAM] INC-042: Race condition in auth module (resolved by Developer A)`
- [ ] Scope-filtered if `--scope` is available from the session context

### REQ-CTX-027: Shared hotspots import in briefing
- [ ] `briefing.sh` checks if `.omega/shared/hotspots.jsonl` exists
- [ ] Reads entries, merges with local hotspot data
- [ ] Merge logic: for each shared hotspot, if local hotspot exists for same `file_path`: take MAX(risk_level), note contributor_count; if not: create local entry with shared data
- [ ] Does NOT record in `shared_imports` (hotspots are stateful, not append-only -- re-read every time)
- [ ] Briefing output: show top 5 shared hotspots with cross-contributor info
- [ ] Format: `  [TEAM] payments/processor.rs -- high risk (3 devs, 12 touches)`

### REQ-CTX-028: `shared_imports` tracking
- [ ] Every import operation records: `INSERT INTO shared_imports (shared_uuid, category, source_file) VALUES (?, ?, ?)`
- [ ] Before importing: `SELECT 1 FROM shared_imports WHERE shared_uuid = ?` -- skip if exists
- [ ] On subsequent briefings: only process entries with UUIDs not in `shared_imports`
- [ ] Import is O(new entries) not O(all entries) -- critical for performance as shared store grows

### REQ-CTX-029: Briefing token budget enforcement
- [ ] Shared behavioral learnings: LIMIT 10 (by confidence DESC)
- [ ] Shared incidents: LIMIT 3 (by resolved_at DESC, or scope relevance if available)
- [ ] Shared hotspots: LIMIT 5 (by risk_level DESC, contributor_count DESC)
- [ ] Entire shared section clearly delimited: starts with `★ TEAM KNOWLEDGE (shared across developers):` header
- [ ] Total injection estimated at 200-400 tokens -- validated against 60% context budget
- [ ] If all caps are hit (10 + 3 + 5 = 18 entries), total section is under 500 tokens

### REQ-CTX-030: Diagnostician shared incident query
- [ ] `core/agents/diagnostician.md` Phase 2 (Evidence Assembly) enhanced
- [ ] New step after loading prior system model: "Query shared incidents for pattern matching"
- [ ] Implementation: read `.omega/shared/incidents/*.json`, compare symptoms/domain/tags to current investigation
- [ ] If match found: add to constraint table as "Shared evidence from INC-NNN (resolved by Developer X)"
- [ ] Match criteria: same domain, overlapping tags, similar symptoms (fuzzy match via keyword overlap)
- [ ] If strong match: surface in hypothesis generation -- "This resembles INC-042 -- race condition pattern in auth module. See resolution."
- [ ] Does NOT auto-apply the resolution -- the diagnostician evaluates whether the shared resolution is relevant to the current bug

### REQ-CTX-031: `/omega:team-status` command
- [ ] New file: `core/commands/omega-team-status.md`
- [ ] Dashboard sections: (1) Shared Knowledge Stats (counts by category: N behavioral learnings, N incidents, N hotspots, N lessons, N patterns, N decisions), (2) Recent Contributions (last 10 shared entries with contributor, category, date), (3) Active Shared Incidents (resolved incidents available to team), (4) Team Hotspot Map (top 10 shared hotspots with contributor counts), (5) Unresolved Conflicts (from conflicts.jsonl)
- [ ] Read-only: does NOT modify any data (no INSERT/UPDATE/DELETE)
- [ ] Creates `workflow_runs` entry with `type='team-status'`
- [ ] Works without memory.db (reads `.omega/shared/` files directly)
- [ ] If `.omega/shared/` does not exist: outputs "Cortex not initialized. Run setup.sh to enable."

### REQ-CTX-032: Contributor attribution
- [ ] Contributor identity derived from: `git config user.name` + ` <` + `git config user.email` + `>`
- [ ] Example: `"Ivan Lozada <ilozada@me.com>"`
- [ ] Stored in every shared JSONL/JSON entry's `contributor` field
- [ ] Stored in local memory.db `contributor` column when entries are created
- [ ] Surfaced in briefing: `(from Ivan Lozada)` appended to shared entries
- [ ] Surfaced in `/omega:team-status`: contributor activity listing
- [ ] NOT used for access control -- all contributors are equal

### REQ-CTX-033: CLAUDE.md Cortex pointer
- [ ] One line added to CLAUDE.md under "Institutional Memory" section
- [ ] Text: `**Cortex (team knowledge):** Read @INDEX of `.claude/protocols/cortex-protocol.md` for shared knowledge rules.`
- [ ] Under 80 characters on the line
- [ ] Does not increase CLAUDE.md beyond the 10,000 character limit

### REQ-CTX-034: Documentation updates
- [ ] `docs/architecture.md`: new "Cortex: Collective Intelligence Layer" section explaining the hybrid architecture, shared store format, curator role, and import mechanism
- [ ] `docs/agent-inventory.md`: curator agent entry with description, tools, trigger mechanism
- [ ] `README.md`: Cortex feature paragraph, `/omega:share` and `/omega:team-status` in command listing
- [ ] `core/protocols/memory-protocol.md`: new "Shared Knowledge" section after "Incident Tracking" section, documenting export/import rules, privacy marking, contributor identity

### REQ-CTX-039: Sync Adapter abstraction layer
- [ ] New file: `core/protocols/sync-adapters.md` defining the adapter interface contract
- [ ] Interface methods: `export(entries: Entry[]) -> ExportResult`, `import(since: Timestamp) -> Entry[]`, `status() -> BackendStats`, `health() -> bool`
- [ ] Backend selection via `.omega/cortex-config.json` with `backend` field: `"git-jsonl"` (default), `"cloudflare-d1"`, `"turso"`, `"self-hosted"`
- [ ] If no `cortex-config.json` exists: default to `git-jsonl` (zero config, backward compatible)
- [ ] Curator agent reads backend config and routes through the appropriate adapter
- [ ] Briefing hook reads backend config and imports through the appropriate adapter
- [ ] All adapters implement the same interface -- curator and briefing are adapter-agnostic

### REQ-CTX-040: Git JSONL adapter (refactored default)
- [ ] Existing Phase 1-3 JSONL read/write logic refactored to implement adapter interface
- [ ] `export()`: writes to `.omega/shared/` JSONL/JSON files (unchanged behavior from Phases 1-3)
- [ ] `import()`: reads from `.omega/shared/` files, filters by `shared_imports` table (unchanged behavior)
- [ ] `status()`: counts entries per JSONL file, lists incident files
- [ ] `health()`: checks `.omega/shared/` directory exists and is writable
- [ ] Zero configuration -- this adapter is used when no `cortex-config.json` exists
- [ ] Sync mechanism: git commit + push (manual, developer-driven)

### REQ-CTX-041: Cloudflare D1 adapter
- [ ] Configuration in `cortex-config.json`: `{"backend": "cloudflare-d1", "account_id": "...", "database_id": "...", "api_token_env": "OMEGA_CORTEX_CF_TOKEN"}`
- [ ] API token read from environment variable (NEVER stored in config file)
- [ ] `export()`: `POST` entries to D1 via Cloudflare REST API (`/client/v4/accounts/{id}/d1/database/{id}/query`)
- [ ] `import()`: `SELECT` entries from D1 where `created_at > last_sync_timestamp`
- [ ] `status()`: `SELECT COUNT(*)` by category from D1
- [ ] `health()`: test API connectivity and authentication
- [ ] D1 tables: `shared_behavioral_learnings`, `shared_incidents`, `shared_incident_entries`, `shared_hotspots`, `shared_lessons`, `shared_patterns`, `shared_decisions`
- [ ] HTTP calls via `curl` (available everywhere) -- no additional runtime dependencies
- [ ] Rate limiting: respect Cloudflare API limits (batch inserts, avoid per-row API calls)

### REQ-CTX-042: Turso adapter
- [ ] Configuration in `cortex-config.json`: `{"backend": "turso", "url": "libsql://...", "auth_token_env": "OMEGA_CORTEX_TURSO_TOKEN"}`
- [ ] Same table schema as D1 adapter (standard SQL)
- [ ] `export()`: HTTP POST to Turso API
- [ ] `import()`: HTTP GET with `since` parameter
- [ ] Turso-specific: embedded replica support for offline-first usage (future enhancement)

### REQ-CTX-043: Self-hosted adapter
- [ ] Configuration in `cortex-config.json`: `{"backend": "self-hosted", "endpoint_url": "https://my-vps:8443/cortex", "auth_token_env": "OMEGA_CORTEX_BRIDGE_TOKEN"}`
- [ ] Bridge server (provided in `extensions/cortex-bridge/`) exposes REST API
- [ ] `export()`: `POST /api/export` with JSON body of entries
- [ ] `import()`: `GET /api/import?since=TIMESTAMP` returns new entries
- [ ] `status()`: `GET /api/status` returns category counts
- [ ] `health()`: `GET /api/health` returns 200 OK
- [ ] Bridge stores data in SQLite (default) or PostgreSQL (configurable)

### REQ-CTX-044: `/omega:cortex-config` command
- [ ] New file: `core/commands/omega-cortex-config.md`
- [ ] Interactive flow: (1) Select backend type, (2) Enter backend-specific config, (3) Run health check, (4) Save config
- [ ] Backend options presented with descriptions: `git (default, zero infra)`, `cloudflare-d1 (real-time, managed)`, `turso (real-time, edge)`, `self-hosted (real-time, self-sovereign)`
- [ ] Health check validates connectivity before saving config
- [ ] Saves to `.omega/cortex-config.json` in target project
- [ ] `.omega/cortex-config.json` added to `.gitignore` by setup.sh (may contain credential references)
- [ ] `--show` flag: display current configuration (masks token env var names)

### REQ-CTX-045: Sync middleware pipeline
- [ ] Middleware sits between curator output and adapter input
- [ ] Responsibilities: (1) format transformation (memory.db row -> adapter entry format), (2) batching (group entries for efficient API calls), (3) retry on failure (max 3 retries with exponential backoff), (4) conflict pre-check (verify no content_hash collision before export)
- [ ] Middleware is the same for all backends -- adapter handles transport
- [ ] If backend unavailable: cache entries in `.omega/.pending-exports.jsonl`, retry on next session/share
- [ ] Pending exports file is gitignored (local-only, transient)

### REQ-CTX-046: Real-time import for cloud/self-hosted
- [ ] `briefing.sh` reads `cortex-config.json` to determine backend
- [ ] If `git-jsonl`: existing file-based import (unchanged)
- [ ] If `cloudflare-d1` / `turso` / `self-hosted`: HTTP pull via `curl`
- [ ] Stores `last_sync_timestamp` in local `memory.db` table `cortex_sync_state`
- [ ] Incremental: `GET /import?since=2026-03-20T15:00:00Z` returns only entries after timestamp
- [ ] Fallback chain: HTTP pull -> `.omega/shared/` files -> skip import (never fail)
- [ ] Timeout: 5 seconds max for HTTP calls (briefing must not block)

### REQ-CTX-047: Offline-first resilience
- [ ] Core invariant: local memory.db always functional regardless of backend status
- [ ] Git JSONL: inherently offline-first (files are local)
- [ ] Cloud/self-hosted offline: exports queued in `.omega/.pending-exports.jsonl`
- [ ] On next session with connectivity: pending exports flushed to backend
- [ ] Import offline: use last-known local data, skip shared import, log info "Cortex backend unavailable -- using local knowledge only"
- [ ] Never error, never block, never degrade local OMEGA functionality

### REQ-CTX-048: Backend migration command
- [ ] `/omega:cortex-migrate --from=git --to=cloudflare-d1` (or any backend combination)
- [ ] Reads all entries from source backend via `import(since=epoch)`
- [ ] Writes all entries to target backend via `export(entries)`
- [ ] Validates: count comparison between source and target
- [ ] Non-destructive: source data preserved after migration
- [ ] Handles deduplication if target already has some entries

### REQ-CTX-049: D1 schema provisioning
- [ ] `/omega:cortex-config` for D1 backend includes "Provision database schema?" step
- [ ] Runs SQL migration via D1 API to create Cortex tables
- [ ] Schema matches JSONL entry structure: common fields (uuid, contributor, source_project, created_at, confidence, occurrences, content_hash) + category-specific fields
- [ ] Idempotent: `CREATE TABLE IF NOT EXISTS` for all tables

### REQ-CTX-050: Cortex bridge server
- [ ] Located in `extensions/cortex-bridge/`
- [ ] Python implementation (FastAPI) -- minimal dependencies: `fastapi`, `uvicorn`, `aiosqlite`
- [ ] Endpoints: `POST /api/export`, `GET /api/import`, `GET /api/health`, `GET /api/status`
- [ ] Authentication: Bearer token from `CORTEX_BRIDGE_TOKEN` env var
- [ ] Storage: SQLite by default (file path configurable), PostgreSQL optional (connection string)
- [ ] `Dockerfile` + `docker-compose.yml` for one-command VPS deployment
- [ ] `README.md` with deployment instructions (bare metal, Docker, systemd)
- [ ] Rate limiting: 100 req/min per token
- [ ] CORS: disabled by default (server-to-server only)
- [ ] TLS: expects reverse proxy (nginx/caddy) for HTTPS in production

## Architecture Context

### Module Boundaries
| Module | Responsibility | Depends On | Depended By |
|--------|---------------|------------|-------------|
| `core/db/schema.sql` | Schema definition, table creation, view creation | None | All 15 agents (via sqlite3 queries), `db-init.sh`, `briefing.sh` |
| `scripts/db-init.sh` | Database initialization and migration | `schema.sql` | `setup.sh` |
| `scripts/setup.sh` | Full deployment to target projects | `db-init.sh`, all `core/` files | End users (manual invocation) |
| `core/hooks/briefing.sh` | Session-start context injection | `memory.db`, (new) `.omega/shared/` | All agents (receives injected context) |
| `core/hooks/session-close.sh` | Session-end cleanup | `memory.db` | None (terminal hook) |
| `core/agents/diagnostician.md` | Deep diagnostic reasoning for hard bugs | `memory.db` incident_entries, (new) shared incidents | Invoked by `/omega:diagnose` |
| `core/protocols/memory-protocol.md` | Institutional memory rules reference | None (documentation) | All agents (lazy-load reference) |
| `.omega/shared/` | (NEW) Git-tracked shared knowledge store | Created by `setup.sh`, written by curator, read by `briefing.sh` | `briefing.sh`, diagnostician, `/omega:team-status` |
| `core/agents/curator.md` | (NEW) Knowledge curation and export | `memory.db`, `.omega/shared/`, sync adapter | `/omega:share`, `session-close.sh` |
| `core/protocols/sync-adapters.md` | (NEW, Phase 4) Sync adapter interface spec | None (documentation) | Curator, briefing.sh, all adapters |
| `.omega/cortex-config.json` | (NEW, Phase 4) Backend configuration | Created by `/omega:cortex-config` | Curator, briefing.sh (determines adapter) |
| `extensions/cortex-bridge/` | (NEW, Phase 4) Self-hosted bridge server | Python/FastAPI | Self-hosted adapter |
| `core/commands/omega-cortex-config.md` | (NEW, Phase 4) Backend config command | sync-adapters protocol | End users |

### Data Flows Through Affected Area

**Current flow (unchanged):**
```
Agent work → INSERT into memory.db → briefing.sh reads memory.db → injects into next session
```

**New Cortex flow (Phases 1-3, git JSONL backend):**
```
Agent work -> INSERT into memory.db (with contributor field)
  -> Session close / manual /omega:share
    -> Curator reads memory.db (qualifying entries)
    -> Curator reads .omega/shared/ (existing entries)
    -> Curator deduplicates, reinforces, or appends
    -> Curator writes to .omega/shared/ JSONL/JSON files
    -> Developer commits and pushes (git handles distribution)

Other developer pulls
  -> briefing.sh reads .omega/shared/ files
  -> Imports new entries into local memory.db (via shared_imports tracking)
  -> Injects shared knowledge into session context
  -> Diagnostician can query shared incidents during diagnosis
```

**Cortex flow with Sync Adapters (Phase 4, cloud/self-hosted backend):**
```
Agent work -> INSERT into memory.db (with contributor field)
  -> Session close / manual /omega:share
    -> Curator reads memory.db (qualifying entries)
    -> Middleware: format, batch, conflict pre-check
    -> Sync Adapter: route to configured backend
      -> Git JSONL: write .omega/shared/ files (as above)
      -> Cloud DB (D1/Turso): HTTP POST to API
      -> Self-hosted: HTTP POST to bridge server
    -> If offline: cache in .omega/.pending-exports.jsonl

Other developer starts session
  -> briefing.sh reads cortex-config.json -> determines backend
    -> Git: read .omega/shared/ files (as above)
    -> Cloud/Self-hosted: curl GET /import?since=LAST_SYNC
    -> Fallback: .omega/shared/ files -> skip -> local only
  -> Imports new entries into local memory.db
  -> Injects shared knowledge into session context
```

### Architectural Constraints & Invariants

| Constraint | Why It Exists | What Breaks If Violated |
|-----------|---------------|------------------------|
| memory.db is local-only, never committed to git | SQLite on shared/network filesystems is unsafe (locking, corruption) | Data corruption, lost writes, WAL file conflicts |
| briefing.sh fires once per session (session_id flag) | Prevents duplicate injection, saves tokens | Context window bloat, duplicate entries |
| briefing.sh uses `2>/dev/null \|\| true` on all queries | Error tolerance -- briefing must not block work | Session start failures, unusable OMEGA |
| schema.sql uses `CREATE TABLE IF NOT EXISTS` | Safe re-run for migration | Existing table destruction on redeploy |
| All agents use 60% context budget | Prevents context window exhaustion | Agent runs out of context, loses work |
| CLAUDE.md must stay under 10,000 characters | Every character costs tokens in every session | Token waste across all sessions and subagents |
| Hooks must not block on failure | Work continuity -- hooks are infrastructure, not gatekeepers (except debrief-gate) | Session failures on transient errors |
| `behavioral_learnings` has `UNIQUE(rule)` constraint | Content-based deduplication | Duplicate rules consuming briefing tokens |
| `hotspots` has `UNIQUE(file_path)` constraint | One entry per file | Multiple entries per file breaking risk calculations |
| `lessons` has `UNIQUE(domain, content)` constraint | Content-based deduplication per domain | Duplicate lessons per domain |

### Blast Radius
**Direct impact:**
- `briefing.sh` -- the highest-risk change. Every session starts with this hook. Any error here degrades every OMEGA session. Risk: HIGH.
- `schema.sql` -- additive changes only (new table, new columns). Safe if `IF NOT EXISTS` / existence-check patterns are followed. Risk: LOW.
- `setup.sh` -- directory creation is idempotent. Risk: LOW.
- `session-close.sh` -- adding a check+flag is lightweight. Risk: LOW.

**Indirect impact:**
- All 15 existing agents -- they consume briefing.sh output. If shared knowledge injection is malformed or excessive, agents receive bad context. Mitigation: clear labeling, hard token caps, error suppression.
- `diagnostician.md` -- explicitly modified to query shared incidents. Must not break existing diagnosis flow. Mitigation: shared incident query is additive (new step after existing steps), not a replacement.
- `db-init.sh` -- must run migration script. If migration fails, new columns are absent but existing columns work. Mitigation: idempotent migration with existence checks.
- Target projects' `.gitignore` -- setup.sh must not accidentally gitignore `.omega/shared/`. Mitigation: explicit check and warning.

## Impact Analysis

### Existing Code Affected

| File | Lines | Risk | What Changes |
|------|-------|------|-------------|
| `core/db/schema.sql` | 461 | Low | One new table (`shared_imports`), one new view (`v_shared_briefing`). No existing definitions modified. Version comment updated. |
| `scripts/db-init.sh` | 44 | Medium | Must call migration script for ALTER TABLE operations. New code path for column additions. |
| `core/hooks/briefing.sh` | 144 | **High** | New section (~40-60 lines) for shared knowledge import. JSONL parsing via python3. New sqlite3 queries. This is the riskiest change -- every session depends on this hook. |
| `core/hooks/session-close.sh` | 25 | Low | ~10 lines added for curation check and flag file. |
| `scripts/setup.sh` | 726 | Low | Directory creation for `.omega/shared/`. Command listing update. ~15 new lines. |
| `core/agents/diagnostician.md` | 402 | Medium | New step in Phase 2 (Evidence Assembly). ~20 lines. Must not disrupt existing diagnosis flow. |
| `core/protocols/memory-protocol.md` | ~342 | Low | New section appended. No existing content modified. |
| `CLAUDE.md` | ~734 | Low | One line added. Well under 10,000 character limit. |
| `docs/architecture.md` | 344 | Low | New section appended. No existing content modified. |
| `README.md` | varies | Low | Feature description and command listing. |

### What Breaks If This Changes

| Module/Function | What Happens | Mitigation |
|----------------|-------------|------------|
| `briefing.sh` JSONL parsing fails | Shared knowledge not injected, session proceeds without it | `2>/dev/null \|\| true` on all new code paths; `if` existence checks before reads |
| `schema.sql` migration fails | New columns absent; curator cannot export; import cannot track | Existence checks in migration; agents check column presence before using |
| `.omega/shared/` directory missing | Curator cannot export; briefing cannot import | Check existence before every operation; create if missing |
| JSONL file malformed (bad merge) | Python3 JSONL parser throws exception | Try/except in python3 parsing; skip malformed lines, log warning |
| `shared_imports` table missing | Import cannot track; re-imports on every session | `CREATE TABLE IF NOT EXISTS`; existence check before INSERT |
| Contributor identity not available | `git config` returns empty | Default to "Unknown" contributor; do not block sharing |

### Regression Risk Areas
- **briefing.sh session flag logic** (lines 14-25): New code must not interfere with session detection
- **briefing.sh behavioral learnings query** (lines 112-118): Shared learnings must not duplicate local ones in output
- **briefing.sh error handling**: Every new query/operation must use the existing `2>/dev/null || true` pattern
- **schema.sql view dependencies**: `v_shared_briefing` depends on `is_private` column existing -- must be created AFTER migration
- **setup.sh CLAUDE.md extraction**: sed command captures everything from `# OMEGA Ω` to EOF -- new pointer line is within this range, no issue
- **diagnostician evidence assembly**: New shared incident query must not replace existing `incident_entries` / `failed_approaches` queries
- **db-init.sh idempotency**: Migration script must be safe to run on fresh DBs, pre-Cortex DBs, and already-migrated DBs

## Traceability Matrix

| Requirement ID | Phase | Priority | Test IDs | Architecture Section | Implementation Module | Milestone |
|---------------|-------|----------|----------|---------------------|---------------------|-----------|
| REQ-CTX-001 | 1 | Must | (filled by test-writer) | Module 1: Schema + Migration | `core/db/schema.sql` | M1 |
| REQ-CTX-002 | 1 | Must | (filled by test-writer) | Module 1: Schema + Migration | `core/db/schema.sql` | M1 |
| REQ-CTX-003 | 1 | Must | (filled by test-writer) | Module 1: Schema + Migration | `core/db/migrate-1.3.0.sh` | M1 |
| REQ-CTX-004 | 1 | Must | (filled by test-writer) | Module 1: Schema + Migration | `core/db/migrate-1.3.0.sh` | M1 |
| REQ-CTX-005 | 1 | Must | (filled by test-writer) | Module 1: Schema + Migration | `core/db/migrate-1.3.0.sh` | M1 |
| REQ-CTX-006 | 1 | Must | (filled by test-writer) | Module 1: Schema + Migration | `scripts/db-init.sh`, `core/db/migrate-1.3.0.sh` | M1 |
| REQ-CTX-007 | 1 | Must | TEST-CTX-M2-001 to M2-009, M2-033 to M2-038, M2-091, M2-092 | Module 2: Setup + Shared Store | `scripts/setup.sh` | M2 |
| REQ-CTX-008 | 1 | Must | TEST-CTX-M2-010 to M2-013, M2-030 to M2-032, M2-093, M2-094, M2-096, M2-097 | Module 2: Setup + Shared Store | `scripts/setup.sh` | M2 |
| REQ-CTX-009 | 1 | Must | TEST-CTX-M2-055 to M2-078 | Module 3: Cortex Protocol | `core/protocols/cortex-protocol.md` | M2 |
| REQ-CTX-010 | 1 | Should | (filled by test-writer) | Module 1: Schema + Migration | `core/db/schema.sql` | M1 |
| REQ-CTX-011 | 1 | Must | TEST-CTX-M2-014 to M2-029, M2-088 to M2-090, M2-095 | All Modules | All modified files | M2 |
| REQ-CTX-012 | 1 | Should | TEST-CTX-M2-039 to M2-054, M2-079 to M2-087, M2-098, M2-099 | Module 3: Cortex Protocol | `core/protocols/cortex-protocol.md` | M2 |
| REQ-CTX-013 | 2 | Must | (filled by test-writer) | Module 4: Curator Agent | `core/agents/curator.md` | M3 |
| REQ-CTX-014 | 2 | Must | (filled by test-writer) | Module 4: Curator Agent | `core/agents/curator.md` | M3 |
| REQ-CTX-015 | 2 | Must | (filled by test-writer) | Module 4: Curator Agent | `core/agents/curator.md` | M3 |
| REQ-CTX-016 | 2 | Must | (filled by test-writer) | Module 4: Curator Agent | `core/agents/curator.md` | M3 |
| REQ-CTX-017 | 2 | Should | (filled by test-writer) | Module 4: Curator Agent | `core/agents/curator.md` | M3 |
| REQ-CTX-018 | 2 | Should | (filled by test-writer) | Module 4: Curator Agent | `core/agents/curator.md` | M3 |
| REQ-CTX-019 | 2 | Should | (filled by test-writer) | Module 4: Curator Agent | `core/agents/curator.md` | M3 |
| REQ-CTX-020 | 2 | Must | (filled by test-writer) | Module 4: Curator Agent | `core/agents/curator.md` | M3 |
| REQ-CTX-021 | 2 | Should | (filled by test-writer) | Module 4: Curator Agent | `core/agents/curator.md` | M3 |
| REQ-CTX-022 | 2 | Must | (filled by test-writer) | Module 4: Curator Agent | `core/agents/curator.md` | M3 |
| REQ-CTX-023 | 2 | Must | (filled by test-writer) | Module 5: Share Command | `core/commands/omega-share.md` | M3 |
| REQ-CTX-024 | 2 | Should | (filled by test-writer) | Module 6: Session Close Trigger | `core/hooks/session-close.sh` | M4 |
| REQ-CTX-025 | 3 | Must | (filled by test-writer) | Module 7: Briefing Import | `core/hooks/briefing.sh` | M5 |
| REQ-CTX-026 | 3 | Must | (filled by test-writer) | Module 7: Briefing Import | `core/hooks/briefing.sh` | M5 |
| REQ-CTX-027 | 3 | Must | (filled by test-writer) | Module 7: Briefing Import | `core/hooks/briefing.sh` | M5 |
| REQ-CTX-028 | 3 | Must | (filled by test-writer) | Module 7: Briefing Import | `core/hooks/briefing.sh` | M5 |
| REQ-CTX-029 | 3 | Must | (filled by test-writer) | Module 7: Briefing Import | `core/hooks/briefing.sh` | M5 |
| REQ-CTX-030 | 3 | Must | (filled by test-writer) | Module 8: Diagnostician Enhancement | `core/agents/diagnostician.md` | M6 |
| REQ-CTX-031 | 3 | Should | (filled by test-writer) | Module 9: Team Status Command | `core/commands/omega-team-status.md` | M6 |
| REQ-CTX-032 | 3 | Must | (filled by test-writer) | Module 7: Briefing Import | All shared entry producers/consumers | M5 |
| REQ-CTX-033 | 3 | Should | (filled by test-writer) | Module 10: Documentation | `CLAUDE.md` | M7 |
| REQ-CTX-034 | 3 | Should | Not tested (documentation) | Module 10: Documentation | `docs/*.md`, `README.md`, `core/protocols/memory-protocol.md` | M7 |
| REQ-CTX-035 | 3 | Could | Not tested (documentation) | Module 10: Documentation | `scripts/setup.sh` | M7 |
| REQ-CTX-036 | -- | Won't | N/A | N/A | Deferred to v2 | -- |
| REQ-CTX-037 | -- | Won't | N/A | N/A | Deferred | -- |
| REQ-CTX-038 | -- | Won't | N/A | N/A | Deferred to v2 | -- |
| REQ-CTX-039 | 4 | Must | (filled by test-writer) | Module 11: Sync Adapter Abstraction | `core/protocols/sync-adapters.md` | M8 |
| REQ-CTX-040 | 4 | Must | (filled by test-writer) | Module 11: Sync Adapter Abstraction | Git JSONL adapter (refactored) | M8 |
| REQ-CTX-041 | 4 | Should | (filled by test-writer) | Module 14: Cloudflare D1 Adapter | D1 adapter logic in curator/briefing | M9 |
| REQ-CTX-042 | 4 | Could | (filled by test-writer) | Module 14: Cloudflare D1 Adapter | Turso adapter logic | M9 |
| REQ-CTX-043 | 4 | Should | (filled by test-writer) | Module 15: Self-Hosted Bridge | Self-hosted adapter + bridge server | M11 |
| REQ-CTX-044 | 4 | Must | (filled by test-writer) | Module 12: Cortex Config Command | `core/commands/omega-cortex-config.md` | M9 |
| REQ-CTX-045 | 4 | Must | (filled by test-writer) | Module 13: Sync Middleware | Middleware pipeline in curator | M10 |
| REQ-CTX-046 | 4 | Should | (filled by test-writer) | Module 13: Sync Middleware | `core/hooks/briefing.sh` (cloud pull) | M10 |
| REQ-CTX-047 | 4 | Must | (filled by test-writer) | Module 13: Sync Middleware | All adapters | M10 |
| REQ-CTX-048 | 4 | Could | (filled by test-writer) | Module 12: Cortex Config Command | Backend migration logic | M10 |
| REQ-CTX-049 | 4 | Should | (filled by test-writer) | Module 14: Cloudflare D1 Adapter | D1 schema provisioning | M9 |
| REQ-CTX-050 | 4 | Should | (filled by test-writer) | Module 15: Self-Hosted Bridge | `extensions/cortex-bridge/` | M11 |

## Specs Drift Detected
- `docs/architecture.md` line 17 -- states "17 tables + 10 views". After Phase 1: 18 tables + 11 views. Must be updated.
- `core/db/schema.sql` line 2 -- version "1.2.0". Must update to "1.3.0".
- `CLAUDE.md` -- references "15 core agents" (implied). After Phase 2: 16 core agents (curator added). Agent count references must be updated in CLAUDE.md, README.md, and docs/architecture.md.
- `scripts/setup.sh` line 697 -- command listing shows 16 commands. After Cortex: 18 commands (/omega:share, /omega:team-status added).
- `docs/architecture.md` line 16 -- states "Core (15) always". After Cortex: Core (16).

## Assumptions

| # | Assumption (technical) | Explanation (plain language) | Confirmed |
|---|----------------------|---------------------------|-----------|
| 1 | `python3` is available on all target systems | briefing.sh needs python3 for JSONL parsing. python3 is already used by briefing.sh (line 18) for session_id extraction. | Yes (existing dependency) |
| 2 | `uuidgen` or python3 `uuid` module available for UUID generation | Curator needs to generate UUIDs for shared entries. `uuidgen` is standard on macOS and most Linux. Python3 `uuid.uuid4()` is a universal fallback. | Yes |
| 3 | Git merge conflicts on JSONL files are rare and easily resolvable | JSONL is one entry per line, append-only by default. Git merges at line level. Conflicts only occur if two developers modify the same line (same entry reinforced simultaneously). | Yes (design choice) |
| 4 | `.omega/shared/` will be committed and pushed by developers | Cortex depends on git for distribution. If developers do not commit/push the shared files, the knowledge does not propagate. | Unconfirmed (depends on team workflow) |
| 5 | `ALTER TABLE ADD COLUMN` with existence checks is safe for SQLite migration | SQLite does not support `IF NOT EXISTS` for ALTER TABLE. We use `PRAGMA table_info()` to check column existence first. This is the same pattern used elsewhere in OMEGA. | Yes |
| 6 | Confidence threshold of 0.8 is appropriate for v1 | Conservative threshold per user agreement. May need tuning based on real usage. | Yes (user accepted) |
| 7 | 10 + 3 + 5 = 18 shared entries in briefing stays under 400 tokens | Each entry is approximately 15-25 tokens. 18 entries * 22 tokens avg = ~396 tokens. | Yes (estimated) |
| 8 | The curator agent (claude-sonnet-4-20250514) has sufficient capability for curation tasks | Curation is evaluative (relevance, confidence, dedup) not creative. Sonnet is appropriate for structured evaluation. | Yes |
| 9 | `briefing.sh` can parse JSONL files within the 30-second hook timeout | JSONL files are small (hundreds of lines, not thousands) in typical team usage. Python3 parsing is fast. | Yes (for typical usage) |
| 10 | `session-close.sh` can check for pending curation within its 10-second timeout | A single COUNT(*) query against memory.db is sub-millisecond. Writing a flag file is instantaneous. | Yes |

## Identified Risks

| # | Risk | Severity | Probability | Mitigation |
|---|------|----------|------------|------------|
| 1 | briefing.sh error in shared import crashes session start | High | Low | Every new code path uses `2>/dev/null \|\| true`. Existence checks before every file read. Python3 parsing wrapped in try/except. |
| 2 | Curator over-shares (noise in shared store) | Medium | Medium | Conservative confidence threshold (0.8). Privacy marking (is_private). Manual review via `/omega:share --dry-run`. |
| 3 | Curator under-shares (value never reaches team) | Medium | Medium | Start with 0.8 threshold, lower to 0.7 based on real usage feedback. Manual `/omega:share --force` for important entries. |
| 4 | JSONL files grow unbounded over time | Medium | Low | v1 does not include shared knowledge decay (REQ-CTX-036 deferred). For v1, JSONL files are small enough for typical teams. Future: decay mechanism or archival. |
| 5 | Git merge conflicts on JSONL files | Low | Low | Line-level granularity minimizes conflicts. When they occur, they are simple to resolve (each line is self-contained JSON). |
| 6 | Schema migration breaks existing memory.db | High | Low | Idempotent migration with existence checks. No ALTER on existing columns. No DROP operations. |
| 7 | briefing.sh timeout (30s) exceeded by JSONL parsing | Medium | Low | Hard caps on entries processed. Python3 parsing is fast for hundreds of lines. If timeout approaches: skip shared import gracefully. |
| 8 | Bad behavioral learning propagates to entire team | High | Low | Confidence threshold (0.8) filters unproven learnings. Contributor attribution enables accountability. `/omega:team-status` shows what was shared. Manual override to archive bad entries. |
| 9 | Diagnostician false-matches shared incidents | Medium | Medium | Match is suggestive, not prescriptive. Diagnostician evaluates relevance -- does NOT auto-apply shared resolutions. Attribution shows source for human judgment. |
| 10 | Curator trigger from session-close.sh cannot invoke Claude agent | Medium | High | Bash hooks cannot spawn Claude agent subprocesses. Mitigation: write `.curation_pending` flag file; next session's briefing detects it and recommends `/omega:share`. |

## Out of Scope (Won't)

| Item | Why Deferred |
|------|-------------|
| **Shared knowledge decay** (REQ-CTX-036) | v1 focuses on accumulation. Decay requires usage metrics (which entries are consumed) that v1 does not track. Deferred to v2 when consumption data is available. |
| **Cross-project knowledge sharing** (REQ-CTX-037) | Cortex shares within a single git repository. Cross-repo sharing requires a registry or central index -- fundamentally different architecture. Future capability. |
| **`/omega:resolve-conflicts` command** (REQ-CTX-038) | v1 flags conflicts in `conflicts.jsonl`. Manual resolution is sufficient for early adoption. Dedicated command deferred to v2 when conflict patterns are understood from real usage. |
| **Access control/permissions** | If you have git access, you participate. No fine-grained sharing permissions. |
| **UI/dashboard** | No web interface. `/omega:team-status` is CLI output. |
| **Shared user profiles** | Persona system remains per-developer. Communication preferences are personal. |
| **Automatic conflict resolution** | Curator flags; humans resolve. |

**Previously out of scope, now addressed by Phase 4:**
| Item | Phase 4 Coverage |
|------|-----------------|
| ~~Real-time sync~~ | REQ-CTX-041/042/043: Cloud DB and self-hosted adapters provide real-time sync via HTTP API |
| ~~Central server/service~~ | REQ-CTX-050: Self-hosted bridge server for teams wanting full control. REQ-CTX-041: Cloudflare D1 for managed service. Both optional -- git JSONL remains the zero-infrastructure default. |