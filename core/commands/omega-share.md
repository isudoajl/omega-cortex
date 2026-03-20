---
name: omega:share
description: "Export curated knowledge from local memory.db to the shared team store (.omega/shared/). Invokes the curator agent to evaluate, deduplicate, and share qualifying entries. Accepts --force to override confidence threshold, --dry-run to preview without writing, --scope to limit to a domain."
---

# Workflow: Share

Export curated knowledge from the local project's memory.db to the shared team store at `.omega/shared/`. This command invokes the **curator** agent to evaluate entries, apply the confidence quality gate, check privacy, deduplicate against existing shared knowledge, and write qualifying entries to JSONL/JSON files.

## Pipeline Tracking

Register a `workflow_runs` entry at the start:

```sql
INSERT INTO workflow_runs (type, description, scope, status)
VALUES ('share', 'Export curated knowledge to shared store', $SCOPE, 'running');
```

At completion, UPDATE the workflow_runs entry to mark it finished:

```sql
UPDATE workflow_runs
SET status = 'completed', completed_at = datetime('now')
WHERE id = $RUN_ID;
```

If an error occurs, update status to `'failed'` with the error_message.

## Flags

- `--force` — Override the confidence threshold (0.8) to share entries below threshold. Use when you have knowledge that is valuable but hasn't yet accumulated enough reinforcement to reach 0.8 confidence.
- `--dry-run` — Show what would be shared without actually writing to `.omega/shared/`. Useful for previewing the curation results before committing them.
- `--scope="domain"` — Limit the curation to a specific domain or category (e.g., `--scope="incidents"` or `--scope="payments"`).

## Invocation

This command invokes the **curator** agent to perform the actual curation work. The curator:

1. Queries memory.db for each export category (behavioral_learnings, incidents, hotspots, lessons, patterns, decisions)
2. Applies the confidence >= 0.8 quality gate (unless `--force` is set)
3. Checks is_private to ensure private entries are never exported
4. Deduplicates against existing `.omega/shared/` entries via content_hash
5. Handles cross-contributor reinforcement (different contributor = +0.2 boost)
6. Detects and flags conflicts to `.omega/shared/conflicts.jsonl`
7. Writes qualifying entries to the appropriate JSONL/JSON files

## Output Summary

After curation completes, display a summary table:

| Category              | Shared | Skipped | Reinforced | Conflicts |
|-----------------------|--------|---------|------------|-----------|
| Behavioral Learnings  | N      | N       | N          | N         |
| Incidents (resolved)  | N      | N       | N          | -         |
| Hotspots              | N      | N       | N          | N         |
| Lessons               | N      | N       | N          | N         |
| Patterns              | N      | N       | N          | N         |
| Decisions             | N      | N       | N          | N         |

For skipped entries, include the reason (below threshold, is_private, already shared, etc.).
For reinforced entries, note whether same-contributor (+0.1) or cross-contributor (+0.2).
For conflicts, reference the conflict UUID in conflicts.jsonl.

## Dry Run Mode

When `--dry-run` is specified, the curator performs all evaluation and deduplication logic but does NOT write any files. Instead, it outputs what would be shared:

- Entries that would be shared (with their category, content preview, and confidence)
- Entries that would be skipped (with reason)
- Entries that would be reinforced (with current vs new confidence)
- Conflicts that would be detected

This allows reviewing the curation before committing it.

## Institutional Memory Protocol

- **Briefing**: Query memory.db for recent share runs, known conflicts, and current shared store stats before starting.
- **Incremental logging**: Log each category's export results to memory.db as they complete.
- **Close-out**: Record final summary, any new conflicts detected, and update the workflow_runs entry.

## Error Handling

If the curator encounters errors (missing .omega/shared/, sqlite3 failures, malformed JSONL), it logs warnings and continues. The share command should still produce a summary even if some categories failed.
