# Setup Guide

> How to deploy the workflow toolkit to any project.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- `sqlite3` available (standard on macOS and most Linux distributions)
- A git repository as the target project

## Basic Setup (Core Only)

Navigate to your target project and run:

```bash
bash /path/to/claude-workflow/scripts/setup.sh
```

This installs:
- 13 agents → `.claude/agents/`
- 13 commands → `.claude/commands/`
- SQLite memory DB → `.claude/memory.db`
- Query references → `.claude/db-queries/`
- Scaffolding → `specs/SPECS.md`, `docs/DOCS.md` (only if they don't exist)

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

## Options

| Flag | Effect |
|------|--------|
| `--ext=name1,name2` | Install named extensions alongside core |
| `--ext=all` | Install all available extensions |
| `--no-db` | Skip SQLite initialization (agents will skip briefing/debrief) |
| `--list-ext` | Show available extensions and exit |
| `--help` | Show usage help |

## What Gets Deployed

```
your-project/
├── .claude/
│   ├── agents/              ← Agent definitions (core + selected extensions)
│   │   ├── analyst.md
│   │   ├── architect.md
│   │   ├── developer.md
│   │   ├── ... (13 core agents)
│   │   └── blockchain-network.md  (if --ext=blockchain)
│   ├── commands/            ← Workflow orchestrators
│   │   ├── workflow-new.md
│   │   ├── workflow-bugfix.md
│   │   ├── ... (13 core commands)
│   │   └── workflow-blockchain-network.md  (if --ext=blockchain)
│   ├── memory.db            ← Institutional memory (SQLite)
│   ├── db-queries/          ← Query reference files
│   │   ├── briefing.sql
│   │   ├── debrief.sql
│   │   └── maintenance.sql
│   └── settings.local.json  ← (unchanged if exists)
├── specs/
│   └── SPECS.md             ← Master spec index (created if missing)
└── docs/
    └── DOCS.md              ← Master doc index (created if missing)
```

## Re-running Setup

The setup script is **safe to re-run**:
- Agents and commands are always overwritten (picks up updates from the toolkit)
- `specs/SPECS.md` and `docs/DOCS.md` are NOT overwritten if they exist
- `memory.db` schema uses `CREATE TABLE IF NOT EXISTS` — new tables/views are added, existing data is preserved
- Query reference files are always overwritten

To update an existing project to the latest toolkit:

```bash
bash /path/to/claude-workflow/scripts/setup.sh --ext=blockchain
```

## What Is NOT Deployed

- **CLAUDE.md** — never copied. Each project maintains its own workflow rules.
- **README.md** — toolkit documentation only, not deployed.
- **docs/** and **specs/** content — only the master index files are scaffolded.
- **poc/** — experimental agents are not deployed.

## Post-Setup: Adding CLAUDE.md

The toolkit's CLAUDE.md contains workflow rules below the `---` separator. To use them in your project, either:

1. **Copy the workflow rules section** (everything below `# Claude Code Quality Workflow`) into your project's CLAUDE.md
2. **Or write your own** — the agents are self-contained and work without CLAUDE.md rules (the rules add global constraints like TDD enforcement and 60% context budget)

## Verifying the Installation

After setup, start Claude Code in your project:

```bash
claude
```

Then verify agents are available:
```
/workflow:new "test"        # Should invoke the discovery agent
/workflow:audit             # Should invoke the reviewer agent
```

To check the memory DB:
```bash
sqlite3 .claude/memory.db ".tables"
# Should show: bugs, changes, decay_log, decisions, dependencies,
#              failed_approaches, findings, hotspots, lessons, outcomes,
#              patterns, requirements, workflow_runs
```

## Updating the Toolkit

When the toolkit repo is updated:

```bash
cd /path/to/claude-workflow
git pull

# Then re-run setup in each target project:
cd /path/to/your-project
bash /path/to/claude-workflow/scripts/setup.sh --ext=blockchain
```

This overwrites agents/commands with the latest versions while preserving your project's memory DB, specs, and docs.
