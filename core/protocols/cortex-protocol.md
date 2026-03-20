<!-- @INDEX
SHARED-STORE-FORMAT                      15-60
CURATION-RULES                           62-96
IMPORT-RULES                             98-133
PRIVACY                                  135-153
CONTRIBUTOR-IDENTITY                     155-178
CONFLICT-RESOLUTION                      180-207
@/INDEX -->

# Cortex Protocol

The Cortex collective intelligence layer enables team knowledge sharing through a git-tracked shared store.

---
## SHARED-STORE-FORMAT

The shared knowledge store lives at `.omega/shared/` in the project root. It is tracked by git (NOT gitignored) so that knowledge propagates via normal git pull/push workflows.

### Directory Structure
```
.omega/shared/
  behavioral-learnings.jsonl   # One JSON object per line
  hotspots.jsonl               # One JSON object per line
  lessons.jsonl                # One JSON object per line
  patterns.jsonl               # One JSON object per line
  decisions.jsonl              # One JSON object per line
  incidents/
    INC-001.json               # Full JSON object (not JSONL)
    INC-002.json
```

### JSONL Format
All `.jsonl` files use the JSONL format: one JSON object per line. No multi-line JSON. Each line is a complete, self-contained JSON object.

### Common Fields (all JSONL entries)
| Field | Type | Description |
|-------|------|-------------|
| `uuid` | string (UUID v4) | Unique identifier for deduplication |
| `contributor` | string | Git identity: "Name <email>" |
| `source_project` | string | Project name where the entry originated |
| `created_at` | string (ISO 8601) | Timestamp of creation |
| `confidence` | float (0.0-1.0) | Confidence score for curation filtering |
| `occurrences` | integer | How many times this entry has been observed |
| `content_hash` | string (SHA-256) | Hash of content field for deduplication |

### Category-Specific Fields
**behavioral-learnings.jsonl**: `rule` (string), `context` (string), `status` (string: active/deprecated/superseded)

**hotspots.jsonl**: `file_path` (string), `risk_level` (string: low/medium/high/critical), `times_touched` (integer), `description` (string), `contributors` (array of strings)

**lessons.jsonl**: `domain` (string), `content` (string), `source_agent` (string)

**patterns.jsonl**: `domain` (string), `name` (string), `description` (string), `example_files` (array of strings)

**decisions.jsonl**: `domain` (string), `decision` (string), `rationale` (string), `alternatives` (array of strings)

### Incident Files
Incidents are stored as individual JSON files (not JSONL) at `.omega/shared/incidents/INC-NNN.json`. Each is a full JSON object with fields:
`incident_id`, `title`, `domain`, `status`, `symptoms` (array), `root_cause`, `resolution`, `affected_files` (array), `tags` (array), `contributor`, `entries` (array of timeline objects)

---
## CURATION-RULES

The Curator evaluates local memory.db entries for team relevance. Only high-confidence, team-relevant knowledge is shared.

### Confidence Threshold
Only entries with `confidence >= 0.8` are eligible for sharing. Below this threshold, entries remain local.

### Relevance Filter
**Shared (team-relevant):** Behavioral learnings about codebase patterns, incident root causes and resolutions, file hotspots, architectural decisions, reusable code patterns.

**NOT shared (personal):** Personal preferences, session-specific notes, draft analyses, entries marked `is_private = 1`.

### Deduplication
Before writing to the shared store, the Curator checks:
1. **UUID match**: If `uuid` exists in the JSONL file, reinforce (bump `occurrences`, update `confidence`) rather than duplicate.
2. **Content hash match**: If `content_hash` exists, treat as duplicate and reinforce.

### Cross-Contributor Reinforcement
When the same learning is independently contributed by multiple developers:
- 2 contributors: confidence boost of +0.2 (double normal reinforcement of +0.1)
- 3+ contributors: confidence set to 1.0 (maximum -- team consensus)

### What IS Shared vs What is NOT
| Category | Shared? | Condition |
|----------|---------|-----------|
| Behavioral learnings | Yes | confidence >= 0.8, is_private = 0, status = 'active' |
| Resolved incidents | Yes | status = 'resolved' or 'closed' |
| Hotspots | Yes | confidence >= 0.8 |
| Lessons | Yes | confidence >= 0.8, is_private = 0, status = 'active' |
| Patterns | Yes | confidence >= 0.8, is_private = 0 |
| Decisions | Yes | confidence >= 0.8, is_private = 0, status = 'active' |
| Open incidents | No | Shared only when resolved |
| Private entries | No | is_private = 1 |
| Personal preferences | No | Never shared |

---
## IMPORT-RULES

The briefing hook imports shared knowledge at session start. Import is incremental and budget-capped.

### Import Trigger
The `briefing.sh` hook checks for `.omega/shared/` at session start. If the directory does not exist, import is skipped entirely (backward compatibility with pre-Cortex projects).

### Shared Imports Table
The `shared_imports` table in `memory.db` prevents re-importing entries:
- Every imported shared UUID is recorded in `shared_imports`
- On subsequent briefings, only new entries (UUIDs not in `shared_imports`) are processed
- This makes import O(new entries), not O(all entries)

### Token Budget Caps
| Category | Max Entries | Selection Criteria |
|----------|------------|-------------------|
| Behavioral learnings | 10 | Highest confidence first |
| Incidents | 3 | Most relevant to current domain |
| Hotspots | 5 | Highest risk_level first |

Total shared section target: under 400 tokens.

### Labeling
Shared entries are labeled with the `[TEAM]` prefix in briefing output to distinguish them from local entries:
```
[TEAM] Never skip the compile gate (from Developer A)
[TEAM] INC-042: Payment timeout -- fixed by retry logic (from Developer B)
```

### Incremental Import Process
1. Read JSONL file line by line
2. Parse each JSON object, extract `uuid`
3. Check `uuid` against `shared_imports` table
4. If not found: import into local memory.db, record in `shared_imports`
5. If found: skip (already imported)

---
## PRIVACY

The Cortex privacy model is opt-out: entries are shared by default, developers explicitly mark entries as private to exclude them.

### The `is_private` Flag
- `is_private = 0` (default): Entry is eligible for sharing
- `is_private = 1`: Entry is excluded from curation and never written to `.omega/shared/`

The Curator MUST check `is_private = 0` before exporting any entry.

### What Is Never Shared
Regardless of `is_private`: personal preferences are never shared, `cortex-config.json` is gitignored (may reference credentials), `memory.db` is gitignored (contains all local data including private entries).

### Default Behavior
The default `is_private = 0` means sharing is opt-out, not opt-in. This maximizes knowledge flow while giving developers an escape hatch for sensitive or personal entries.

### Configuration Security
`.omega/cortex-config.json` is gitignored because it may contain references to API tokens or credential environment variables for cloud sync backends.

---
## CONTRIBUTOR-IDENTITY

Every shared entry includes contributor attribution for accountability and trust.

### Identity Format
The contributor identity is derived from git configuration:
```
git config user.name  ->  "Ivan Lozada"
git config user.email ->  "ilozada@me.com"
Format: "Ivan Lozada <ilozada@me.com>"
```

### Purpose
1. **Attribution**: Who contributed this knowledge, for accountability
2. **Trust**: Entries from known contributors carry implicit team trust
3. **Reinforcement tracking**: Detecting independent discovery by different people
4. **Accountability**: Tracing problematic shared entries to their source

### Not Access Control
Contributor identity is for attribution, NOT access control. Any team member can read, contribute, and reinforce entries. No permission model in v1 -- trust is established by git repository access.

### NULL Contributors
Entries with `NULL` contributor are valid (pre-Cortex entries). Agents must handle `NULL` contributor gracefully.

---
## CONFLICT-RESOLUTION

When multiple contributors share contradictory knowledge, the Curator detects and flags conflicts.

### Detection
The Curator checks for contradictions when writing to the shared store:
- Same domain + opposing rules (e.g., "always use async" vs "never use async")
- Same file_path + different risk assessments
- Same decision domain + different choices

### Conflict File
Detected conflicts are written to `.omega/shared/conflicts.jsonl`:
`uuid`, `entry_a_uuid`, `entry_b_uuid`, `domain`, `description`, `detected_at`, `status` ("unresolved" in v1)

### Resolution (v1)
In v1, conflict resolution is manual:
- Conflicts are flagged in `conflicts.jsonl` for human review
- No automatic resolution attempted
- `/omega:team-status` surfaces unresolved conflicts

### Confidence-Based Tiebreaking
When the Curator must decide and conflict resolution is unavailable:
- Higher confidence entry wins
- Equal confidence: more recent entry wins
- Conflicts are still logged even when tiebreaker applies

### Future (v2)
Dedicated `/omega:resolve-conflicts` command (deferred -- REQ-CTX-038).
