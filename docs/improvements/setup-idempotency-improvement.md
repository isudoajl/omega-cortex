# Requirements: Setup Script Idempotency Improvement

## Scope
- `scripts/setup.sh` (476 lines) — primary target
- `scripts/db-init.sh` (43 lines) — secondary target (query file copying)
- `docs/setup-guide.md` — must be updated to reflect new output behavior

## Summary
The setup script is already safe to re-run (same filesystem state). But it does unnecessary work (copying identical files) and produces misleading output (always says `+ file` even when unchanged). This improvement adds change detection so the script: (1) skips copying identical files, (2) accurately reports status (`+` new, `~` updated, `=` unchanged), and (3) provides a summary showing counts.

## Section-by-Section Idempotency Classification

| Section | Lines | Current Behavior | Status |
|---------|-------|-----------------|--------|
| Arg parsing / --list-ext | 1-64 | Read-only | N/A |
| Core agents copy | 87-93 | Always `cp`, always prints `+` | NOT idempotent |
| Core commands copy | 98-105 | Always `cp`, always prints `+` | NOT idempotent |
| Extensions copy | 110-161 | Always `cp`, always prints `+` | NOT idempotent |
| Project structure | 163-212 | Checks existence, prints `+`/`=` | ALREADY IDEMPOTENT |
| Hooks copy | 217-226 | Always `cp`, always prints `+` | NOT idempotent |
| settings.json merge | 228-333 | Merges hooks, always writes | Partially idempotent |
| CLAUDE.md injection | 335-400 | Marker-based replace, always rewrites | Behaviorally idempotent |
| DB init (delegated) | 404-409 | Schema migration idempotent, query files always copied | Mostly idempotent |
| Summary | 413-476 | Static message, no change counts | NOT idempotent |

## Requirements

| ID | Requirement | Priority |
|----|------------|----------|
| REQ-SETUP-001 | Add `copy_if_changed` helper using `cmp -s` for file comparison | Must |
| REQ-SETUP-002 | Track per-run counters (NEW, UPDATED, UNCHANGED) | Must |
| REQ-SETUP-003 | Core agents section uses `copy_if_changed` with accurate symbols | Must |
| REQ-SETUP-004 | Core commands section uses `copy_if_changed` with accurate symbols | Must |
| REQ-SETUP-005 | Extensions section uses `copy_if_changed` with accurate symbols | Must |
| REQ-SETUP-006 | Hooks section uses `copy_if_changed` with accurate symbols | Must |
| REQ-SETUP-007 | settings.json detects whether hooks actually changed before writing | Should |
| REQ-SETUP-008 | CLAUDE.md detects whether workflow rules changed before rewriting | Should |
| REQ-SETUP-009 | Summary shows counts of new/updated/unchanged | Must |
| REQ-SETUP-010 | db-init.sh query file copying uses change detection | Could |
| REQ-SETUP-011 | `--verbose` flag to show unchanged files (hidden by default) | Could |
| REQ-SETUP-012 | `--dry-run` flag | Won't |

## Acceptance Criteria

### REQ-SETUP-001: copy_if_changed helper
- Given destination does not exist → copies file, returns "new"
- Given destination exists but differs → copies file, returns "updated"
- Given destination exists and is identical → does NOT copy, returns "unchanged"
- Uses `cmp -s` (POSIX standard, works on macOS and Linux)

### REQ-SETUP-002: Per-run counters
- Fresh project: NEW = total files, UPDATED/UNCHANGED = 0
- Up-to-date project: UNCHANGED = total files, NEW/UPDATED = 0
- Partial update: correct split across all three counters

### REQ-SETUP-003-006: File copy sections
- `+` symbol for new files
- `~` symbol for updated files
- Unchanged files suppressed by default, shown with `(N unchanged)` per section
- No `cp` executed for unchanged files
- Hooks: `chmod +x` always applied regardless of copy status

### REQ-SETUP-007: settings.json change detection
- Compare generated hooks JSON with existing hooks in settings.json
- Print `= hooks already configured` when unchanged
- Print `~ hooks updated` when changed, `+ settings.json created` when new
- Preserve non-hook settings in all cases

### REQ-SETUP-008: CLAUDE.md change detection
- Extract current workflow rules section, compare with source
- Print `= Workflow rules already current` when identical
- Print `~ Workflow rules updated` when different
- Skip sed replacement entirely when identical (preserves mtime)

### REQ-SETUP-009: Summary with counts
- Fresh: `Deployed: 14 agents (14 new), 14 commands (14 new), 5 hooks (5 new)`
- Nothing changed: `Nothing changed — already up to date`
- Partial: shows breakdown of new/updated/unchanged

### REQ-SETUP-011: --verbose flag
- Default: suppress `=` lines, show `(N unchanged)` per section
- With `--verbose`: show all `=` lines

## Design Guidance

### copy_if_changed implementation
```bash
TOTAL_NEW=0
TOTAL_UPDATED=0
TOTAL_UNCHANGED=0

copy_if_changed() {
    local src="$1"
    local dest="$2"
    if [ ! -f "$dest" ]; then
        cp "$src" "$dest"
        COPY_STATUS="new"
        TOTAL_NEW=$((TOTAL_NEW + 1))
    elif ! cmp -s "$src" "$dest"; then
        cp "$src" "$dest"
        COPY_STATUS="updated"
        TOTAL_UPDATED=$((TOTAL_UPDATED + 1))
    else
        COPY_STATUS="unchanged"
        TOTAL_UNCHANGED=$((TOTAL_UNCHANGED + 1))
    fi
}
```

### Output format (default, no --verbose)
```
# Fresh install:
  Copying core agents...
   + analyst.md
   + architect.md
   ...

# Re-run with 1 change:
  Copying core agents...
   ~ analyst.md
   (13 unchanged)

# Re-run, nothing changed:
  Copying core agents...
   (14 unchanged)
```

## Impact Analysis
- All file copy loops are straightforward rewrites (low risk)
- settings.json comparison adds python3 complexity (medium risk, python3 already required)
- CLAUDE.md comparison adds bash string comparison (medium risk, existing logic preserved as-is)
- No downstream consumers parse setup.sh stdout (no breaking change)

## Assumptions
1. `cmp -s` available on all targets (POSIX standard) — confirmed
2. `python3` available (already required by settings.json merge) — confirmed
3. No external tooling parses setup.sh stdout — confirmed
4. `copy_if_changed` as shell function within setup.sh — no separate script needed

## Out of Scope
- `--dry-run` flag (adds complexity, deferred)
- Colored ANSI output (cosmetic, deferred)
- Checksum caching in memory.db (unnecessary, `cmp -s` is fast enough)
