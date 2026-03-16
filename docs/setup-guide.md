# Setup Guide

> The single source of truth for deploying the workflow toolkit to any project.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- `sqlite3` available (standard on macOS and most Linux distributions)
- A git repository as the target project

## Quick Start

Navigate to your **target project** (not the toolkit repo) and run:

```bash
bash /path/to/claude-workflow/scripts/setup.sh
```

That's it. One command deploys everything:

| What | Where | Notes |
|------|-------|-------|
| 13 agents | `.claude/agents/` | Core pipeline agents |
| 13 commands | `.claude/commands/` | Workflow orchestrators |
| Workflow rules | `CLAUDE.md` | **Appended** to existing CLAUDE.md (never overwrites) |
| Memory DB | `.claude/memory.db` | SQLite with 14 tables, 7 views (incl. self-learning) |
| Query references | `.claude/db-queries/` | Briefing, debrief, maintenance SQL templates |
| Scaffolding | `specs/SPECS.md`, `docs/DOCS.md` | Only created if they don't exist |

## How CLAUDE.md Is Handled

This is the most important detail to understand:

- **If your project already has a CLAUDE.md** → the workflow rules are **appended** after a `---` separator. Your project-specific rules at the top are preserved untouched.
- **If your project has no CLAUDE.md** → one is created with a placeholder for your project rules at the top, and the workflow rules appended below.
- **On re-run** → the workflow rules section is **replaced** with the latest version. Your project-specific rules above the `---` separator are preserved.

The resulting CLAUDE.md structure in your target project:

```
┌─────────────────────────────────────────┐
│ Your project-specific rules             │  ← NEVER touched by setup.sh
│ (coding conventions, team preferences,  │
│  deployment instructions, etc.)         │
├─────────────────────────────────────────┤
│ ---                                     │  ← Separator
├─────────────────────────────────────────┤
│ # Claude Code Quality Workflow          │  ← Appended/updated by setup.sh
│                                         │
│ Philosophy, source of truth hierarchy,  │
│ institutional memory protocol,          │
│ self-learning protocol,                 │
│ briefing/debrief rules,                 │
│ global rules, fail-safe controls,       │
│ context management, etc.                │
│ (~500 lines of workflow rules)          │
└─────────────────────────────────────────┘
```

**Why this matters**: The workflow rules define the institutional memory protocol (briefing/debrief), the self-learning mechanism (outcomes/lessons), the 60% context budget, TDD enforcement, and all global constraints. Without them, the agents still work but lose coordinated behavior — each agent would act independently without the shared protocol.

## With Extensions

```bash
# Single extension
bash /path/to/claude-workflow/scripts/setup.sh --ext=blockchain

# Multiple extensions
bash /path/to/claude-workflow/scripts/setup.sh --ext=blockchain,omega

# All extensions
bash /path/to/claude-workflow/scripts/setup.sh --ext=all
```

### Available Extensions

```bash
bash /path/to/claude-workflow/scripts/setup.sh --list-ext
```

| Extension | Agents | Commands | When to use |
|-----------|--------|----------|-------------|
| `blockchain` | 3 | 3 | Ethereum/Solana/Cosmos node operations, P2P networking, RPC infrastructure |
| `omega` | 2 | 1 | OMEGA framework projects |
| `c2c-protocol` | 2 | 3 | Agent-to-agent protocol research |

## All Options

| Flag | Effect |
|------|--------|
| `--ext=name1,name2` | Install named extensions alongside core |
| `--ext=all` | Install all available extensions |
| `--no-db` | Skip SQLite initialization (agents will skip briefing/debrief and self-learning) |
| `--list-ext` | Show available extensions and exit |
| `--help` | Show usage help |

## What Gets Deployed

```
your-project/
├── CLAUDE.md                  ← Workflow rules appended (project rules preserved)
├── .claude/
│   ├── agents/                ← Agent definitions (core + selected extensions)
│   │   ├── analyst.md
│   │   ├── architect.md
│   │   ├── developer.md
│   │   ├── ... (13 core agents)
│   │   └── blockchain-network.md  (if --ext=blockchain)
│   ├── commands/              ← Workflow orchestrators
│   │   ├── workflow-new.md
│   │   ├── workflow-bugfix.md
│   │   ├── ... (13 core commands)
│   │   └── workflow-blockchain-network.md  (if --ext=blockchain)
│   ├── memory.db              ← Institutional memory + self-learning (SQLite)
│   ├── db-queries/            ← Query reference files
│   │   ├── briefing.sql       ← Includes self-learning queries
│   │   ├── debrief.sql        ← Includes self-scoring + lesson distillation
│   │   └── maintenance.sql    ← Includes lesson cap + confidence decay
│   └── settings.local.json   ← (unchanged if exists)
├── specs/
│   └── SPECS.md               ← Master spec index (created if missing)
└── docs/
    └── DOCS.md                ← Master doc index (created if missing)
```

## What Is NOT Deployed

- **README.md** — toolkit documentation only, not deployed
- **docs/** and **specs/** content — only the master index files are scaffolded
- **poc/** — experimental agents are not deployed
- **Toolkit-specific CLAUDE.md sections** — only the workflow rules section (below the separator) is appended

## Re-running Setup (Updates)

The setup script is **safe to re-run** at any time:

| Component | Behavior on re-run |
|-----------|-------------------|
| Agents & commands | Overwritten with latest versions |
| CLAUDE.md workflow rules | Replaced with latest (project rules preserved) |
| `specs/SPECS.md`, `docs/DOCS.md` | NOT overwritten if they exist |
| `memory.db` | Schema migrated (new tables added, existing data preserved) |
| Query reference files | Overwritten with latest |

To update an existing project to the latest toolkit:

```bash
cd /path/to/claude-workflow
git pull

cd /path/to/your-project
bash /path/to/claude-workflow/scripts/setup.sh
```

## Verifying the Installation

After setup, start Claude Code in your project:

```bash
claude
```

Verify agents are available:
```
/workflow:new "test"        # Should invoke the discovery agent
/workflow:audit             # Should invoke the reviewer agent
```

Check the memory DB:
```bash
sqlite3 .claude/memory.db ".tables"
# Should show: bugs, changes, decay_log, decisions, dependencies,
#              failed_approaches, findings, hotspots, lessons, outcomes,
#              patterns, requirements, workflow_runs
```

Check self-learning tables exist:
```bash
sqlite3 .claude/memory.db "SELECT COUNT(*) FROM outcomes; SELECT COUNT(*) FROM lessons;"
# Should return 0 for both (empty on fresh install — they accumulate over time)
```

Verify CLAUDE.md has workflow rules:
```bash
grep "Claude Code Quality Workflow" CLAUDE.md
# Should match — confirms workflow rules are present
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `sqlite3: command not found` | Install: `brew install sqlite3` (macOS) or `sudo apt install sqlite3` (Ubuntu) |
| Agents not showing in Claude Code | Verify `.claude/agents/*.md` files exist. Restart Claude Code |
| Memory DB errors | Re-initialize: `bash /path/to/claude-workflow/scripts/db-init.sh .` |
| CLAUDE.md workflow rules missing | Re-run setup: `bash /path/to/claude-workflow/scripts/setup.sh` |
| Self-learning tables missing | Re-run setup — schema migration adds new tables to existing DB |
| Project CLAUDE.md overwritten | It shouldn't be — setup.sh appends, never overwrites. If it happened, check git history to restore |
