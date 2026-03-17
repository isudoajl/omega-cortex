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
| Automation hooks | `.claude/hooks/` | 4 hooks: auto-briefing, commit gate, debrief nudge, cleanup |
| Hook config | `.claude/settings.json` | Registers hooks with Claude Code |
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
│   ├── hooks/                 ← Automation hooks
│   │   ├── briefing.sh        ← UserPromptSubmit: injects memory context on first prompt
│   │   ├── debrief-gate.sh   ← PreToolUse (Bash): blocks git commit without outcomes
│   │   ├── incremental-gate.sh ← PreToolUse (Write/Edit): blocks after 10 edits without outcomes
│   │   ├── debrief-nudge.sh  ← PostToolUse: periodic incremental logging reminder
│   │   └── session-close.sh   ← Notification: promotes hotspot risk levels
│   ├── settings.json          ← Hook configuration (registers hooks with Claude Code)
│   ├── memory.db              ← Institutional memory + self-learning (SQLite)
│   ├── db-queries/            ← Query reference files
│   │   ├── briefing.sql       ← Includes self-learning queries
│   │   ├── debrief.sql        ← Incremental logging + close-out templates
│   │   └── maintenance.sql    ← Includes lesson cap + confidence decay
│   └── settings.local.json    ← (unchanged if exists)
├── specs/
│   └── SPECS.md               ← Master spec index (created if missing)
└── docs/
    └── DOCS.md                ← Master doc index (created if missing)
```

## How Hooks Work (Automated Briefing/Incremental Logging Enforcement)

The toolkit deploys five Claude Code hooks that automate and enforce the institutional memory protocol:

### `briefing.sh` (UserPromptSubmit)
Runs on the first user prompt of each session (uses session_id to fire only once). It:
- Queries `memory.db` for hotspots, failed approaches, open findings, decisions, patterns
- Queries self-learning context (recent outcomes, active lessons)
- Outputs everything to stdout, which Claude Code injects into the conversation context
- Includes an **incremental logging reminder** so Claude knows to log to memory.db during work

**This is what makes the system work without relying on AI memory.** Claude sees the institutional context automatically — no "remember to run briefing" needed.

### `session-close.sh` (Notification)
Runs on notifications. It:
- Promotes hotspot risk levels based on touch counts

### `debrief-gate.sh` (PreToolUse — Bash)
Runs before every Bash tool call. For non-commit commands, exits instantly (no overhead). When it detects `git commit`:
- Reads the briefing timestamp from `.briefing_done` (set by briefing.sh at session start)
- Checks if any outcomes (self-scores) were logged **after** that timestamp (this session only)
- If **no** → **blocks the commit** (exit 2) with instructions to log outcomes first
- If **yes** → allows the commit through

This is the hard enforcement for commits. Each session must log outcomes independently — outcomes from previous sessions don't count.

### `incremental-gate.sh` (PreToolUse — Write, Edit)
Runs before every Write and Edit tool call. Counts file modifications per session:
- If outcomes have been logged since session start → resets counter, allows edit
- If no outcomes logged → increments counter
- After **10 file modifications** without any outcomes → **blocks the edit** (exit 2) with instructions to log to memory.db first
- Resets counter when outcomes are detected

This enforces incremental logging even when the agent never reaches a git commit — catching manual work sessions that accumulate changes without recording them.

### `debrief-nudge.sh` (PostToolUse)
Runs after every tool execution. Throttled to avoid noise:
- Checks if any outcomes were logged since this session's briefing timestamp
- If yes → silent
- If no → reminds every 5th tool call (not every one)
- Resets when outcomes are logged

### Enforcement summary

| Hook | Event | Enforcement level |
|------|-------|------------------|
| `briefing.sh` | UserPromptSubmit | **Automatic** — context injected on first prompt per session |
| `debrief-gate.sh` | PreToolUse (Bash) | **Blocking** — git commits fail without this session's outcomes |
| `incremental-gate.sh` | PreToolUse (Write/Edit) | **Blocking** — file edits blocked after 10 modifications without outcomes |
| `debrief-nudge.sh` | PostToolUse | **Reminder** — periodic nudge every 5th tool call |
| `session-close.sh` | Notification | **Automatic** — promotes hotspot risk levels |

### Verifying hooks are active
In Claude Code, run:
```
/hooks
```
You should see `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, and `Notification` listed with hook counts.

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
| Hook scripts | Overwritten with latest versions |
| Hook config (settings.json) | Hooks key always updated; other settings preserved |
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
