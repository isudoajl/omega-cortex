# Architecture: OMEGA Persona (Identity Layer)

## Scope
Lightweight identity layer for OMEGA: per-project user profile in `memory.db`, automatic briefing injection, experience-based adaptation, and optional onboarding command. Covers modules in `core/db/schema.sql`, `core/hooks/briefing.sh`, `CLAUDE.md`, `core/commands/omega-onboard.md`, and documentation files.

## Overview

```
User starts session
  |
  v
briefing.sh (UserPromptSubmit hook)
  |
  +-- [1] Check if user_profile table exists (table-existence check)
  |     |
  |     +-- Table missing? --> Skip identity block entirely (backward compat)
  |     +-- Table exists, no rows? --> Show onboarding prompt (informational)
  |     +-- Table exists, has row? --> Continue to [2]
  |
  +-- [2] Query user_profile (name, experience_level, communication_style)
  |
  +-- [3] Query v_workflow_usage (compact usage summary)
  |
  +-- [4] Experience auto-upgrade check
  |     |
  |     +-- completed_count >= 30 AND level='intermediate'? --> UPDATE to 'advanced'
  |     +-- completed_count >= 10 AND level='beginner'? --> UPDATE to 'intermediate'
  |     +-- Otherwise no-op
  |
  +-- [5] Update last_seen (fire-and-forget)
  |
  +-- [6] Output OMEGA Identity Block (under 200 tokens)
  |
  +-- [existing briefing continues: hotspots, failed approaches, etc.]
```

## Modules

### Module 1: Schema (`core/db/schema.sql`)
- **Responsibility**: Define `user_profile` table, `onboarding_state` table, and `v_workflow_usage` view
- **Public interface**: SQL DDL statements (consumed by `db-init.sh` via `sqlite3 < schema.sql`)
- **Dependencies**: `workflow_runs` table (already defined, for `v_workflow_usage` view)
- **Implementation order**: 1 (foundation -- all other modules depend on this)

#### Exact SQL Additions

Append after the existing `decay_log` table (after line 217) and before the `-- VIEWS` section (line 219):

```sql
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
```

Append after the last existing view (`v_recent_activity`, after line 318):

```sql
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
```

#### Design Decisions
- **No single-row constraint**: The `user_profile` table does not enforce a UNIQUE or single-row constraint. Single-row is by convention, enforced by the onboarding command doing `INSERT OR REPLACE`. This avoids migration complexity.
- **No multi-user support**: Deliberately one profile per project. Future multi-user would require schema changes.
- **`CREATE TABLE IF NOT EXISTS`**: Follows the existing migration pattern. Running `db-init.sh` on old databases adds the new tables without affecting existing ones.
- **View depends only on `workflow_runs`**: The `v_workflow_usage` view has no dependency on `user_profile`, so it works regardless of whether a profile exists.

#### Failure Modes
| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| Table already exists on re-run | Normal migration | `IF NOT EXISTS` handles it | Automatic | None |
| CHECK constraint violation | Bad INSERT | SQLite rejects the row | Caller retries with valid value | Insert fails, no data loss |
| View query on empty `workflow_runs` | Fresh DB | Returns empty result set | None needed | Identity block shows "0 completed" |

### Module 2: Briefing Hook (`core/hooks/briefing.sh`)
- **Responsibility**: Inject OMEGA Identity Block at top of briefing, auto-upgrade experience, update `last_seen`
- **Public interface**: stdout (injected into Claude's context by the UserPromptSubmit hook)
- **Dependencies**: `user_profile` table (Module 1), `v_workflow_usage` view (Module 1), `workflow_runs` table (existing)
- **Implementation order**: 2 (depends on schema)

#### Exact Placement and Logic Flow

The identity block is inserted **after the header box** (lines 53-56) and **before "CRITICAL HOTSPOTS"** (line 59). The new code goes between line 57 (`echo ""`) and line 59 (`# --- CRITICAL HOTSPOTS ---`).

**New code block (approximately 45 lines of bash):**

```bash
# --- OMEGA IDENTITY ---
# Check if user_profile table exists (backward compatibility)
PROFILE_TABLE_EXISTS=$(sqlite3 "$DB_PATH" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='user_profile' LIMIT 1;" 2>/dev/null || true)

if [ -n "$PROFILE_TABLE_EXISTS" ]; then
    # Query profile
    PROFILE_ROW=$(sqlite3 -separator '|' "$DB_PATH" "SELECT user_name, experience_level, communication_style FROM user_profile LIMIT 1;" 2>/dev/null || true)

    if [ -n "$PROFILE_ROW" ]; then
        # Parse profile fields
        USER_NAME=$(echo "$PROFILE_ROW" | cut -d'|' -f1)
        EXP_LEVEL=$(echo "$PROFILE_ROW" | cut -d'|' -f2)
        COMM_STYLE=$(echo "$PROFILE_ROW" | cut -d'|' -f3)

        # Experience auto-upgrade (fire-and-forget)
        COMPLETED_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM workflow_runs WHERE status='completed';" 2>/dev/null || echo "0")
        if [ "$EXP_LEVEL" = "intermediate" ] && [ "$COMPLETED_COUNT" -ge 30 ] 2>/dev/null; then
            sqlite3 "$DB_PATH" "UPDATE user_profile SET experience_level='advanced';" 2>/dev/null || true
            EXP_LEVEL="advanced"
        elif [ "$EXP_LEVEL" = "beginner" ] && [ "$COMPLETED_COUNT" -ge 10 ] 2>/dev/null; then
            sqlite3 "$DB_PATH" "UPDATE user_profile SET experience_level='intermediate';" 2>/dev/null || true
            EXP_LEVEL="intermediate"
        fi

        # Update last_seen (fire-and-forget)
        sqlite3 "$DB_PATH" "UPDATE user_profile SET last_seen=datetime('now');" 2>/dev/null || true

        # Build compact usage summary
        USAGE_SUMMARY=$(sqlite3 "$DB_PATH" "SELECT SUM(completed_runs) FROM v_workflow_usage;" 2>/dev/null || echo "0")
        USAGE_BREAKDOWN=$(sqlite3 -separator '' "$DB_PATH" "SELECT completed_runs || ' ' || type FROM v_workflow_usage WHERE completed_runs > 0 ORDER BY completed_runs DESC LIMIT 4;" 2>/dev/null || true)
        USAGE_LINE=""
        if [ -n "$USAGE_BREAKDOWN" ]; then
            USAGE_LINE=$(echo "$USAGE_BREAKDOWN" | tr '\n' ', ' | sed 's/, $//')
            USAGE_LINE=" ($USAGE_LINE)"
        fi

        # Output identity block
        echo "OMEGA IDENTITY: ${USER_NAME:-User} | Experience: $EXP_LEVEL | Style: $COMM_STYLE | Workflows: ${USAGE_SUMMARY:-0} completed${USAGE_LINE}"
        echo ""
    else
        # Table exists but no profile row -- show onboarding prompt
        echo "Welcome to OMEGA. Personalize your experience: /omega:onboard"
        echo "  Or set manually: sqlite3 .claude/memory.db \"INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('Your Name', 'beginner', 'balanced');\""
        echo ""
    fi
fi
```

#### Key Design Principles
1. **Table-existence check first**: Uses `sqlite_master` query, not error suppression on the main query. This cleanly separates "table missing" (old DB) from "table empty" (new DB, no onboarding yet).
2. **All queries use `2>/dev/null || true`**: Every sqlite3 call is fire-and-forget. No query can block the briefing.
3. **Upgrade check uses intermediate variable**: The `COMPLETED_COUNT` is fetched once and reused for both threshold checks, avoiding redundant queries.
4. **Upgrade order matters**: Check `intermediate->advanced` BEFORE `beginner->intermediate` to avoid double-upgrading in a single session.
5. **`last_seen` update is unconditional**: If a profile row exists, `last_seen` is always updated. This is idempotent and safe.
6. **Usage summary is compact**: A single line like `Workflows: 27 completed (12 new-feature, 8 bugfix, 4 improve, 3 new)` stays well under 200 tokens.

#### Failure Modes
| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| `sqlite_master` query fails | DB corruption or missing | `2>/dev/null \|\| true` returns empty | Identity block skipped entirely | Briefing works as before |
| `user_profile` query fails | Table exists but broken | `2>/dev/null \|\| true` returns empty | Treated as no profile | No identity block |
| Experience upgrade fails | Write permission issue | `2>/dev/null \|\| true` | Silently skipped | Level shown may be stale by one session |
| `last_seen` update fails | Write permission | `2>/dev/null \|\| true` | Silently skipped | `last_seen` stale by one session |
| `v_workflow_usage` view missing | Old schema without view | Query returns empty | Shows "0 completed" | Degraded but functional |
| COMPLETED_COUNT is non-numeric | Unexpected query result | Bash `[ -ge ]` comparison fails silently | Upgrade skipped | No harm |

#### Security Considerations
- **No SQL injection risk**: All queries are static strings with no user-interpolated input in the bash script. Profile data is read from the DB, not constructed from user input at query time.
- **Fire-and-forget writes**: The `UPDATE` statements in briefing.sh cannot be weaponized because they only modify fixed columns to fixed values (`datetime('now')`, or fixed experience level strings).

### Module 3: CLAUDE.md Identity Protocol
- **Responsibility**: Instruct all agents how to interpret and use identity context from the briefing
- **Public interface**: Markdown section deployed to all target projects via `setup.sh`
- **Dependencies**: Module 2 (briefing outputs the identity block that agents read)
- **Implementation order**: 3 (depends on briefing design to know what agents will see)

#### Exact Placement

New section inserted between `### Error Handling` (end of Institutional Memory, line 468) and `## Main Workflow` (line 470).

#### Exact Content (39 lines including blanks)

```markdown
## OMEGA Identity

The briefing hook injects an identity block at the top of every session. This gives agents awareness of who they are working with and how to adapt.

### Override Hierarchy
**Protocol always overrides identity.** Agent protocols (TDD enforcement, read-only constraints, iteration limits, prerequisite gates, severity classification, acceptance criteria completeness) are never relaxed based on identity context. Identity influences communication style, not functional behavior.

### Experience Levels
| Level | Behavior |
|-------|----------|
| beginner | Explain reasoning. Show examples. Spell out next steps. Flag common pitfalls proactively. |
| intermediate | Standard explanations. Skip basics. Focus on tradeoffs and decisions. |
| advanced | Terse output. Skip explanations unless non-obvious. Focus on edge cases and risks. Assume deep familiarity. |

Auto-upgrade: beginner to intermediate at 10 completed workflows, intermediate to advanced at 30. Checked during briefing.

### Communication Styles
| Style | Behavior |
|-------|----------|
| verbose | Detailed rationale for every decision. Long-form explanations. Multiple examples. |
| balanced | Standard output. Explain when needed, concise when obvious. |
| terse | Minimum viable output. Bullets over paragraphs. Skip boilerplate. |

### Using the Identity Block
- **Name**: Use the user's name naturally in greetings and when addressing them directly. Do not overuse it.
- **No identity block?** Work normally. The absence of an identity block means no profile exists. Do not prompt for onboarding.
- **Conflicts**: If identity context suggests behavior that would compromise technical rigor, ignore the identity context. Example: an "advanced/terse" profile does not mean skip acceptance criteria from QA reports.

### Carve-outs (never modified by identity)
Severity classification, TDD enforcement, read-only constraints, iteration limits, prerequisite gates, acceptance criteria completeness, memory protocol compliance.
```

#### Design Decisions
- **39 lines total**: Stays under the 40-line constraint while being complete.
- **Override hierarchy is the first subsection**: The most important rule appears first.
- **Tables for experience/style**: Compact, scannable, unambiguous.
- **Carve-outs are explicit**: Lists every protocol that identity cannot override, preventing ambiguity.
- **"No identity block" guidance**: Prevents agents from prompting for onboarding -- only the briefing hook does that.

### Module 4: Onboarding Command (`core/commands/omega-onboard.md`)
- **Responsibility**: Conversational 3-question flow to create or update user profile
- **Public interface**: `/omega:onboard` and `/omega:onboard --update` commands
- **Dependencies**: `user_profile` table, `onboarding_state` table, `workflow_runs` table (Module 1)
- **Implementation order**: 4 (depends on schema and understanding of identity block format)

#### Command Structure

```markdown
# /omega:onboard

## Purpose
Set up your OMEGA identity. Three questions: name, experience level, communication style.

## Flags
- `--update` — modify an existing profile instead of creating one

## Flow

### Step 1: Check existing state
- Query `onboarding_state` and `user_profile`
- If `--update` and no profile exists: inform user, proceed as new onboarding
- If no `--update` and profile exists: inform user profile exists, suggest `--update`
- If `onboarding_state.status = 'in_progress'` and `data` contains partial answers: resume from last incomplete step

### Step 2: Register workflow run
- `INSERT INTO workflow_runs (type, description) VALUES ('onboard', 'User profile setup');`
- Capture RUN_ID

### Step 3: Conversational questions (3 total)
1. **Name**: "What should I call you?"
   - Stores answer in `onboarding_state.data` JSON immediately
   - Updates `onboarding_state.step = 'name'`, `status = 'in_progress'`

2. **Experience level**: "How much experience do you have with AI-assisted development workflows?"
   - Options: beginner (new to structured AI workflows), intermediate (familiar with TDD and multi-step pipelines), advanced (extensive experience, want minimal hand-holding)
   - Stores answer in `onboarding_state.data` JSON immediately

3. **Communication style**: "How do you prefer OMEGA to communicate?"
   - Options: verbose (detailed explanations), balanced (explain when needed), terse (minimum viable output)
   - Stores answer in `onboarding_state.data` JSON immediately

### Step 4: Write profile
- For new: `INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES (?, ?, ?);`
- For update: `UPDATE user_profile SET user_name=?, experience_level=?, communication_style=?;`

### Step 5: Mark complete
- `UPDATE onboarding_state SET status='completed', completed_at=datetime('now');`
- `UPDATE workflow_runs SET status='completed', completed_at=datetime('now') WHERE id=$RUN_ID;`
- Log outcome to `outcomes` table

### Step 6: Confirmation
- Show the identity block that will appear in future sessions
- Remind user they can update anytime with `/omega:onboard --update`
- Remind user about `/output-style` for tone customization beyond what OMEGA identity provides

## No Agent Required
This command operates directly without a dedicated agent. Claude executes the conversational flow using standard prompting. The command markdown provides the script; no `.claude/agents/onboard.md` is created.

## Resumability (Could priority)
If the user quits mid-onboard:
- `onboarding_state.data` contains partial answers as JSON: `{"name": "Ivan", "experience_level": "intermediate"}`
- Next invocation of `/omega:onboard` reads `onboarding_state.data` and resumes from the last incomplete question
- If `onboarding_state.status = 'in_progress'`: ask "You started onboarding earlier. Want to continue from where you left off?"

## Memory Protocol
- Creates a `workflow_runs` entry with `type='onboard'`
- Logs one `outcomes` entry on completion
- Does NOT run the full briefing/incremental-logging/close-out protocol (too lightweight)
```

#### Failure Modes
| Failure | Cause | Detection | Recovery | Impact |
|---------|-------|-----------|----------|--------|
| DB write fails | Permission or corruption | sqlite3 returns error | Show error, suggest manual SQL | User can still set profile manually |
| User quits mid-flow | Interrupted session | `onboarding_state.status='in_progress'` | Resume on next invocation | Partial data preserved |
| Profile already exists without `--update` | User re-runs | Query detects existing row | Inform user, suggest `--update` | No data loss |
| Invalid enum value entered | User types free text | CHECK constraint rejects | Re-prompt with valid options | No data corruption |

### Module 5: Documentation & Deployment Updates
- **Responsibility**: Update README.md, institutional-memory.md, DOCS.md, setup.sh to reflect the new feature
- **Public interface**: Documentation files
- **Dependencies**: All other modules (documents what they provide)
- **Implementation order**: 5 (last -- documents everything else)

#### Changes per File

**`scripts/setup.sh`** (line ~629, after the diagnose command):
```bash
echo "    /omega:onboard                     Personalize your profile"
```

**`docs/institutional-memory.md`**:
- Add `user_profile` table documentation section (columns, purpose, single-row convention)
- Add `onboarding_state` table documentation section (columns, purpose, resumability)
- Add `v_workflow_usage` view documentation section (query, columns, purpose)
- Update table/view counts: "12 tables" to "14 tables", "7 views" to "8 views"

**`README.md`**:
- Add `/omega:onboard` to the commands table
- Update command count from 14 to 15
- Add brief mention of the persona/identity feature in the features section

**`CLAUDE.md`** (repository structure section):
- Update `# 14 core commands` to `# 15 core commands` in the tree comment
- Add `omega-onboard.md` to the commands list in the tree
- Update the Core Commands table with the onboard entry
- Update the Usage Modes section with the new command

**`docs/DOCS.md`**:
- No structural changes needed unless a new doc file is created for persona specifically

**`specs/SPECS.md`**:
- Add persona-architecture.md entry

## Failure Modes (system-level)

| Scenario | Affected Modules | Detection | Recovery Strategy | Degraded Behavior |
|----------|-----------------|-----------|-------------------|-------------------|
| Old memory.db without new tables | Module 2 (briefing) | `sqlite_master` check returns empty | Identity block silently skipped | Identical to pre-persona behavior |
| DB is read-only | Module 2, Module 4 | Write operations fail | `2>/dev/null \|\| true` suppresses errors | Profile not updated, experience not upgraded, but briefing still works |
| DB is missing entirely | Module 2 | `[ ! -f "$DB_PATH" ]` on line 33 | Briefing exits early (existing behavior) | No briefing at all (existing behavior) |
| Identity block causes agent protocol drift | All agents | QA/reviewer catches deviations | Override hierarchy rule in CLAUDE.md | Agents ignore identity when it conflicts with protocol |
| Onboarding command unavailable | Module 4 | User gets command-not-found | Manual SQL documented as fallback | Profile can be created via sqlite3 CLI |

## Security Model

### Trust Boundaries
- **Briefing hook output -> Claude context**: The identity block is constructed from DB-stored values. No user input is interpolated into SQL at query time. Values are read from the DB and placed into echo statements.
- **Onboarding command -> DB**: User input flows through Claude's natural language processing into SQL INSERT/UPDATE. The CHECK constraints on `experience_level` and `communication_style` prevent invalid enum values. The `user_name` field is free text but only stored/read, never executed.

### Data Classification
| Data | Classification | Storage | Access Control |
|------|---------------|---------|---------------|
| `user_name` | Internal | `memory.db` (local file) | File system permissions |
| `experience_level` | Internal | `memory.db` | File system permissions |
| `communication_style` | Internal | `memory.db` | File system permissions |
| `last_seen` | Internal | `memory.db` | File system permissions |
| `onboarding_state.data` | Internal | `memory.db` (JSON) | File system permissions |

### Attack Surface
- **SQL injection via `user_name`**: Low risk. The onboarding command writes via parameterized-style sqlite3 CLI commands. The briefing hook only reads, never interpolates user data back into queries. Risk: Minimal.
- **Identity block prompt injection**: Low risk. A malicious `user_name` could theoretically contain prompt-injection text. Mitigation: The identity block is a single compact line, and the override hierarchy rule means agents prioritize protocol over identity context regardless.

## Graceful Degradation

| Dependency | Normal Behavior | Degraded Behavior | User Impact |
|-----------|----------------|-------------------|-------------|
| `user_profile` table | Identity block shown in briefing | Block silently omitted | Session works as pre-persona |
| `v_workflow_usage` view | Usage summary in identity block | Shows "0 completed" | Minor cosmetic |
| `onboarding_state` table | Resumable onboarding | Fresh start each attempt | Minor inconvenience |
| `memory.db` entirely | Full briefing with identity | No briefing at all | Existing degradation behavior |

## Performance Budgets

| Operation | Latency Target | Memory | Notes |
|-----------|---------------|--------|-------|
| Identity block generation (briefing.sh) | < 50ms total | Negligible | 3-4 sqlite3 queries on tiny tables |
| Experience auto-upgrade | < 10ms | Negligible | Single COUNT(*) + conditional UPDATE |
| `last_seen` update | < 5ms | Negligible | Single UPDATE on 1-row table |
| Onboarding flow (total) | Interactive (user-paced) | Negligible | 3 questions + final writes |
| Token budget for identity block | < 200 tokens | N/A | Single-line output format |

## Data Flow

```
/omega:onboard          briefing.sh (every session)
       |                          |
       v                          v
  user_profile  <---- READ ---- user_profile
  onboarding_state               |
  workflow_runs                   v
                          v_workflow_usage (view on workflow_runs)
                                  |
                                  v
                          OMEGA Identity Block (stdout)
                                  |
                                  v
                          Claude context (all agents read this)
                                  |
                                  v
                          CLAUDE.md "OMEGA Identity" section
                          (tells agents HOW to use the block)
```

## Design Decisions

| Decision | Alternatives Considered | Justification |
|----------|------------------------|---------------|
| Table-existence check via `sqlite_master` | Error suppression on direct query | Cleaner separation of "table missing" vs "table empty" -- enables different behavior for each case |
| Single identity line format | Multi-line block with headers | Stays well under 200-token budget; agents parse it as context, not structured data |
| Experience upgrade check order (advanced first) | Beginner check first | Prevents double-upgrade from beginner to advanced in one session |
| No personality archetypes | Formal Mentor, Casual Pair-Programmer, etc. | Dropped per requirements -- use `/output-style` instead. Simpler, fewer conflicts |
| `onboarding_state` as separate table | JSON field on `user_profile` | Cleaner separation of concerns; enables resume without parsing nested JSON |
| Manual SQL as documented fallback | Force onboarding before use | Respects power users who prefer CLI; prevents blocking |
| Onboarding prompt only when table exists but empty | Always show if no profile | Backward compat: old DBs without the table should produce zero new output |

## External Dependencies
- `sqlite3` CLI — already required by OMEGA
- `python3` — already used by briefing.sh for JSON parsing (session_id)
- No new external dependencies

## Milestones

| ID | Name | Scope (Modules) | Scope (Requirements) | Est. Size | Dependencies |
|----|------|-----------------|---------------------|-----------|-------------|
| M1 | OMEGA Persona | schema.sql, briefing.sh, CLAUDE.md, omega-onboard.md, docs | REQ-PERSONA-001 to REQ-PERSONA-014 | M | None |

This is a single-milestone feature. All five modules are tightly coupled and small enough to implement in one pass. The schema is the foundation, briefing.sh is the core logic, CLAUDE.md is the protocol, the onboarding command is the user interface, and documentation is the wrapper. No module exceeds 50 new lines of meaningful code.

**Rationale for single milestone**: The total scope is 2 new tables (5 lines each), 1 view (6 lines), ~45 lines of bash in briefing.sh, ~39 lines of markdown in CLAUDE.md, one command file, and documentation updates. This fits comfortably within a single agent's 60% context budget across all pipeline phases.

## Requirement Traceability

| Requirement ID | Priority | Architecture Section | Module(s) |
|---------------|----------|---------------------|-----------|
| REQ-PERSONA-001 | Must | Module 1: Schema | `core/db/schema.sql` |
| REQ-PERSONA-002 | Must | Module 1: Schema | `core/db/schema.sql` |
| REQ-PERSONA-003 | Must | Module 1: Schema | `core/db/schema.sql` |
| REQ-PERSONA-004 | Must | Module 2: Briefing Hook | `core/hooks/briefing.sh` |
| REQ-PERSONA-005 | Must | Module 2: Briefing Hook (table-existence check) | `core/hooks/briefing.sh` |
| REQ-PERSONA-006 | Must | Module 2: Briefing Hook (auto-upgrade logic) | `core/hooks/briefing.sh` |
| REQ-PERSONA-007 | Must | Module 3: CLAUDE.md Identity Protocol | `CLAUDE.md` |
| REQ-PERSONA-008 | Should | Module 4: Onboarding Command | `core/commands/omega-onboard.md` |
| REQ-PERSONA-009 | Should | Module 2: Briefing Hook (last_seen update) | `core/hooks/briefing.sh` |
| REQ-PERSONA-010 | Should | Module 2: Briefing Hook (onboarding prompt) | `core/hooks/briefing.sh` |
| REQ-PERSONA-011 | Should | Module 4: Onboarding Command (--update flag) | `core/commands/omega-onboard.md` |
| REQ-PERSONA-012 | Should | Module 5: Documentation | `docs/institutional-memory.md`, `README.md`, `CLAUDE.md` |
| REQ-PERSONA-013 | Could | Module 5: Documentation | `scripts/setup.sh` |
| REQ-PERSONA-014 | Could | Module 4: Onboarding Command (resumability) | `core/commands/omega-onboard.md` |
