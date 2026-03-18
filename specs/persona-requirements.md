# Requirements: OMEGA Persona (Reduced Scope)

## Scope
**Domains/modules/files affected:**
- `core/db/schema.sql` — new `user_profile` table, `onboarding_state` table, `v_workflow_usage` view
- `core/hooks/briefing.sh` — OMEGA Identity Block injection, experience auto-upgrade logic, `last_seen` update
- `CLAUDE.md` — new "OMEGA Identity" section in workflow rules
- `core/commands/omega-onboard.md` — new onboarding command (Should priority)
- `scripts/setup.sh` — command listing update
- `docs/institutional-memory.md` — new table/view documentation
- `README.md` — feature and command documentation

## Summary (plain language)
OMEGA currently starts every session cold — it does not know who the user is, how experienced they are, or how they prefer to communicate. This feature adds a lightweight identity layer: OMEGA stores the user's name, experience level, and communication preference in `memory.db`, displays this at the top of every session briefing, and automatically upgrades experience level as the user gains workflow completions. Personality archetypes are explicitly dropped in favor of Claude Code's native `/output-style` command.

## User Stories
- As a first-time OMEGA user, I want to be guided through setting my name and preferences so that OMEGA knows who I am from the start.
- As a returning user, I want OMEGA to greet me by name and show my experience level so that every session feels personal and continuous.
- As a power user with 30+ workflow completions, I want OMEGA to recognize my advanced experience so that agents skip unnecessary explanations and focus on edge cases.
- As an existing OMEGA user upgrading to this version, I want everything to work exactly as before until I choose to set up a profile.
- As a user, I want to update my name, experience level, or communication style at any time so that my profile stays current.

## Requirements

| ID | Requirement | Priority | Acceptance Criteria |
|----|------------|----------|-------------------|
| REQ-PERSONA-001 | `user_profile` table in schema.sql | Must | CREATE TABLE IF NOT EXISTS with columns: id, user_name, experience_level, communication_style, created_at, last_seen; CHECK constraints; safe migration |
| REQ-PERSONA-002 | `onboarding_state` table in schema.sql | Must | CREATE TABLE IF NOT EXISTS with columns: id, step, status, data, started_at, completed_at; CHECK constraint on status; safe migration |
| REQ-PERSONA-003 | `v_workflow_usage` view in schema.sql | Must | Aggregates workflow_runs by type; shows total_runs, completed_runs, last_run per type; returns empty on fresh DB |
| REQ-PERSONA-004 | OMEGA Identity Block in briefing.sh | Must | At TOP of briefing output (before hotspots); shows name, experience, style, usage summary; under 200 tokens |
| REQ-PERSONA-005 | No-profile backward compatibility | Must | No errors when user_profile table is missing or empty; existing agents unaffected |
| REQ-PERSONA-006 | Experience auto-upgrade logic | Must | beginner→intermediate at 10 completed workflows; intermediate→advanced at 30; checked during briefing |
| REQ-PERSONA-007 | OMEGA Identity protocol in CLAUDE.md | Must | New section with agent instructions; explicit override: protocol > identity; under 40 lines |
| REQ-PERSONA-008 | `/omega:onboard` command | Should | Conversational 3-question flow; writes to user_profile and onboarding_state; supports --update flag; no new agent |
| REQ-PERSONA-009 | `last_seen` auto-update | Should | Updated in briefing.sh once per session; fire-and-forget |
| REQ-PERSONA-010 | Onboarding prompt in briefing.sh | Should | Shown when user_profile is empty; informational only; includes manual SQL alternative |
| REQ-PERSONA-011 | Profile update capability | Should | Via /omega:onboard --update; via manual sqlite3; both documented |
| REQ-PERSONA-012 | Documentation updates | Should | institutional-memory.md, README.md, DOCS.md updated |
| REQ-PERSONA-013 | setup.sh command listing | Could | /omega:onboard in summary output |
| REQ-PERSONA-014 | Onboarding state resumability | Could | Partial answers stored in JSON; resumes on next invocation |
| REQ-PERSONA-015 | Personality archetypes | Won't | Use /output-style instead |
| REQ-PERSONA-016 | Full onboarding agent | Won't | Stays at 14 agents |
| REQ-PERSONA-017 | Gamification / RPG systems | Won't | Deferred |
| REQ-PERSONA-018 | Global cross-project profiles | Won't | Deferred |
| REQ-PERSONA-019 | Per-agent personality customization | Won't | Deferred |

## Acceptance Criteria (detailed)

### REQ-PERSONA-001: `user_profile` table in schema.sql
- [ ] Table created with `CREATE TABLE IF NOT EXISTS user_profile` in `core/db/schema.sql`
- [ ] Columns: `id INTEGER PRIMARY KEY AUTOINCREMENT`, `user_name TEXT`, `experience_level TEXT DEFAULT 'beginner'` with `CHECK(experience_level IN ('beginner','intermediate','advanced'))`, `communication_style TEXT DEFAULT 'balanced'` with `CHECK(communication_style IN ('verbose','balanced','terse'))`, `created_at TEXT DEFAULT (datetime('now'))`, `last_seen TEXT DEFAULT (datetime('now'))`
- [ ] Table designed for exactly one row per project (no multi-user support); single-row constraint is by convention, not enforced via UNIQUE
- [ ] Running `db-init.sh` on an existing `memory.db` without this table creates it without affecting existing tables
- [ ] Follows the existing `CREATE TABLE IF NOT EXISTS` migration pattern

### REQ-PERSONA-002: `onboarding_state` table in schema.sql
- [ ] Table created with `CREATE TABLE IF NOT EXISTS onboarding_state` in `core/db/schema.sql`
- [ ] Columns: `id INTEGER PRIMARY KEY AUTOINCREMENT`, `step TEXT DEFAULT 'not_started'`, `status TEXT DEFAULT 'not_started'` with `CHECK(status IN ('not_started','in_progress','completed'))`, `data TEXT` (JSON blob for partial state), `started_at TEXT`, `completed_at TEXT`
- [ ] Designed for exactly one row per project
- [ ] Running `db-init.sh` on an existing `memory.db` without this table creates it without affecting existing tables

### REQ-PERSONA-003: `v_workflow_usage` view in schema.sql
- [ ] View created with `CREATE VIEW IF NOT EXISTS v_workflow_usage` in `core/db/schema.sql`
- [ ] Query: `SELECT type, COUNT(*) as total_runs, SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as completed_runs, MAX(started_at) as last_run FROM workflow_runs GROUP BY type ORDER BY completed_runs DESC`
- [ ] Output columns: `type`, `total_runs`, `completed_runs`, `last_run`
- [ ] Returns empty result set on a fresh DB (no workflow_runs) — does NOT error
- [ ] The total completed count used by experience auto-upgrade is obtained separately: `SELECT COUNT(*) FROM workflow_runs WHERE status='completed'`

### REQ-PERSONA-004: OMEGA Identity Block in briefing.sh
- [ ] New section added at the TOP of the briefing output, after the header box (lines 53-56) and before "CRITICAL HOTSPOTS" (line 59)
- [ ] When `user_profile` has a row: outputs the user's name, experience level, communication style, and a compact workflow usage summary
- [ ] Total injected token count for the identity block MUST be under 200 tokens
- [ ] Format example: `Ω IDENTITY: Ivan | Experience: intermediate | Style: balanced | Workflows: 27 completed (12 new-feature, 8 bugfix, 4 improve, 3 new)`
- [ ] The identity block uses the same formatting conventions as existing briefing sections
- [ ] When `user_profile` does NOT exist or is empty: behavior defers to REQ-PERSONA-010 (onboarding prompt) or produces no output

### REQ-PERSONA-005: No-profile backward compatibility
- [ ] Given a `memory.db` that predates this feature (no `user_profile` table), `briefing.sh` produces identical output to the current version — no errors, no new output
- [ ] Given a `memory.db` with empty `user_profile` table, `briefing.sh` produces identical output plus the optional onboarding prompt (REQ-PERSONA-010)
- [ ] All existing agents function without modification when no profile exists
- [ ] The `v_workflow_usage` view works regardless of whether `user_profile` exists (depends only on `workflow_runs`)
- [ ] `briefing.sh` wraps profile queries in table-existence checks or uses error suppression

### REQ-PERSONA-006: Experience auto-upgrade logic
- [ ] Thresholds: beginner → intermediate at 10 completed workflows; intermediate → advanced at 30 completed workflows
- [ ] The check runs during `briefing.sh` execution, once per session
- [ ] When a threshold is crossed, `briefing.sh` executes UPDATE on user_profile
- [ ] The upgrade is silent — no additional output; the identity block reflects the new level
- [ ] Downgrade is NOT automatic; users must use onboard command or manual SQL
- [ ] If `user_profile` is empty or missing, the upgrade logic is a no-op

### REQ-PERSONA-007: OMEGA Identity protocol section in CLAUDE.md
- [ ] New section titled `## OMEGA Identity` added to workflow rules
- [ ] Positioned after `## Institutional Memory` subsections, before `## Main Workflow`
- [ ] Contains: purpose, override hierarchy (protocol > identity), experience-level behavior definitions, communication style behavior definitions, name usage guidance, carve-outs list
- [ ] Explicit carve-outs: severity classification, TDD enforcement, read-only constraints, iteration limits, prerequisite gates, acceptance criteria completeness
- [ ] Total section length under 40 lines of markdown

### REQ-PERSONA-008: `/omega:onboard` command
- [ ] New command file at `core/commands/omega-onboard.md`
- [ ] Conversational flow: (1) user's name, (2) experience level with descriptions, (3) communication style with descriptions
- [ ] Maximum 3 questions
- [ ] Writes to `user_profile` and `onboarding_state`
- [ ] Creates `workflow_runs` entry with `type='onboard'`
- [ ] No new agent definition
- [ ] Supports `--update` flag for existing profiles
- [ ] Logs to memory.db per standard protocol

### REQ-PERSONA-009: `last_seen` auto-update
- [ ] `user_profile.last_seen` updated to `datetime('now')` on every session start
- [ ] Happens in `briefing.sh` after querying the profile
- [ ] Fire-and-forget: failure does not block briefing

### REQ-PERSONA-010: Onboarding prompt in briefing.sh
- [ ] Shown when `user_profile` table exists but has no rows
- [ ] Uses upgrade-friendly language for existing users
- [ ] Includes manual SQL alternative
- [ ] Informational only — does NOT block usage

### REQ-PERSONA-011: Profile update capability
- [ ] Via `/omega:onboard --update`
- [ ] Via manual `sqlite3` command
- [ ] Both methods documented

### REQ-PERSONA-012: Documentation updates
- [ ] `docs/institutional-memory.md` — add user_profile, onboarding_state, v_workflow_usage sections
- [ ] `README.md` — add /omega:onboard, update counts, mention persona feature
- [ ] `CLAUDE.md` — update command count and table if new command added

## Impact Analysis

### Existing Code Affected
| File | Lines | Risk | What Changes |
|------|-------|------|-------------|
| `core/db/schema.sql` | 319 | Low | Two new tables, one new view appended. No existing definitions modified. |
| `core/hooks/briefing.sh` | 127 | Medium | Identity block section, experience auto-upgrade, last_seen writes. ~40-50 new lines. |
| `CLAUDE.md` | ~734 | Medium | New "OMEGA Identity" section (~30-40 lines). Deployed to all target projects. |
| `scripts/setup.sh` | 658 | Low | One echo line in summary output. |
| `docs/institutional-memory.md` | 448 | Low | Three new documentation sections. |
| `README.md` | varies | Low | Feature description and command listing. |

### Regression Risk Areas
- **briefing.sh session flag logic** (lines 14-25): Must not be broken by new code
- **briefing.sh error handling**: New queries must use `2>/dev/null || true` pattern
- **schema.sql CREATE VIEW ordering**: v_workflow_usage depends on workflow_runs (defined first, no issue)
- **setup.sh CLAUDE.md extraction**: sed command captures everything from `# OMEGA Ω` to EOF (no issue)

## Traceability Matrix

| Requirement ID | Priority | Test IDs | Architecture Section | Implementation Module |
|---------------|----------|----------|---------------------|---------------------|
| REQ-PERSONA-001 | Must | TEST-PERSONA-001a..001l (12 tests: table exists, columns, defaults, CHECK constraints valid/invalid, created_at/last_seen defaults, idempotent, NULL name) | Module 1: Schema | core/db/schema.sql |
| REQ-PERSONA-002 | Must | TEST-PERSONA-002a..002h (8 tests: table exists, columns, defaults, CHECK valid/invalid, JSON data, idempotent) | Module 1: Schema | core/db/schema.sql |
| REQ-PERSONA-003 | Must | TEST-PERSONA-003a..003g (7 tests: view exists, empty DB, aggregation, columns, ordering, last_run, works without user_profile) | Module 1: Schema | core/db/schema.sql |
| REQ-PERSONA-004 | Must | TEST-PERSONA-004a..004g (7 tests: identity block shown, format, usage summary, breakdown, zero completed, position before hotspots, position after header) + edge cases (special chars, NULL name, multiple rows, large count) | Module 2: Briefing Hook | core/hooks/briefing.sh |
| REQ-PERSONA-005 | Must | TEST-PERSONA-005a..005c (3 tests: no error without table, no error with empty table, existing sections unchanged) + edge cases (no DB file, read-only DB) | Module 2: Briefing Hook (table-existence check) | core/hooks/briefing.sh |
| REQ-PERSONA-006 | Must | TEST-PERSONA-006a..006i (9 tests: beginner->intermediate at 10, no upgrade at 9, intermediate->advanced at 30, no upgrade at 29, no double-upgrade, advanced stays, noop without profile, only counts completed, upgrade reflected in output) | Module 2: Briefing Hook (auto-upgrade logic) | core/hooks/briefing.sh |
| REQ-PERSONA-007 | Must | TEST-PERSONA-007a..007i (9 tests: section exists, override hierarchy, experience levels, communication styles, carve-outs, under 40 lines, position, name guidance, no-identity guidance) | Module 3: CLAUDE.md Identity Protocol | CLAUDE.md |
| REQ-PERSONA-008 | Should | TEST-PERSONA-008a..008f (6 tests + 5 skips: file exists, purpose, 3 questions, --update flag, workflow_run, no agent, manual SQL) | Module 4: Onboarding Command | core/commands/omega-onboard.md |
| REQ-PERSONA-009 | Should | TEST-PERSONA-009a..009b (2 tests: last_seen updated, not updated without profile) | Module 2: Briefing Hook (last_seen update) | core/hooks/briefing.sh |
| REQ-PERSONA-010 | Should | TEST-PERSONA-010a..010e (5 tests: prompt when empty, includes manual SQL, not shown when table missing, not shown when profile exists, nonblocking) | Module 2: Briefing Hook (onboarding prompt) | core/hooks/briefing.sh |
| REQ-PERSONA-011 | Should | TEST-PERSONA-011a (1 test: manual SQL documented in onboard command) | Module 4: Onboarding Command (--update flag) | core/commands/omega-onboard.md |
| REQ-PERSONA-012 | Should | Not tested (documentation) | Module 5: Documentation | docs/*.md, README.md |
| REQ-PERSONA-013 | Could | Not tested (documentation) | Module 5: Documentation | scripts/setup.sh |
| REQ-PERSONA-014 | Could | Not tested (Could priority, deferred) | Module 4: Onboarding Command (resumability) | core/commands/omega-onboard.md |

## Specs Drift Detected
- `docs/institutional-memory.md` — states "12 tables" and "7 views". After this feature: 14 tables, 8 views.
- `CLAUDE.md` — references "14 core commands". If REQ-PERSONA-008 implemented: 15.
- `README.md` — same count issue.

## Assumptions

| # | Assumption | Explanation | Confirmed |
|---|-----------|-------------|-----------|
| 1 | `user_profile` has at most one row per project | Single-user per project, by convention | Yes |
| 2 | `briefing.sh` can safely execute UPDATE statements | Failures suppressed via `2>/dev/null \|\| true` | Yes |
| 3 | `CREATE TABLE IF NOT EXISTS` handles migration | Existing DBs gain new tables when db-init.sh re-runs | Yes |
| 4 | `/output-style` covers personality needs | Users use Claude Code native for tone customization | Yes |
| 5 | Identity block fits under 200 tokens | ~70 tokens estimated, well under budget | Yes |
| 6 | CLAUDE.md workflow rules deploy correctly with new section | setup.sh extracts everything from `# OMEGA Ω` to EOF | Yes |
| 7 | Experience thresholds of 10/30 are reasonable | Can be tuned later | Unconfirmed |

## Out of Scope (Won't)
- Personality archetypes — use Claude Code's `/output-style`
- Full onboarding agent — no 15th agent
- Gamification / RPG systems
- Global cross-project profiles
- Per-agent personality customization
- Avatar or visual identity
- Multi-user support
- Natural language profile modification mid-session
