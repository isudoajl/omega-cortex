# Architecture Overview

> v2 — Core/Extensions with Institutional Memory (March 2026)

## What This Toolkit Is

A multi-agent orchestration system for Claude Code. It forces every piece of code through structured validation layers — questioning, architecture, TDD, implementation, QA, review — each handled by a specialized agent. Every agent reads from and writes to a shared SQLite knowledge base, creating persistent institutional memory across sessions.

It is **not** an application. It is a set of agent definitions, command orchestrators, a memory schema, and a deployment script designed to be copied into any project.

## What Changed (v1 → v2)

| v1 | v2 |
|----|-----|
| Flat `.claude/agents/` and `.claude/commands/` | `core/` + `extensions/` source organization |
| All 20 agents copied to every project | Core (13) always; extensions opt-in via `--ext=` |
| No cross-session memory | SQLite `.claude/memory.db` with 14 tables + 7 views |
| Agents act independently | Mandatory briefing/debrief + self-learning — agents score their own work and distill patterns |
| `workflow-feature.md` + `workflow-new-feature.md` (duplicate) | Consolidated: only `workflow-new-feature.md` |
| `workflow-improve.md` + `workflow-improve-functionality.md` (duplicate) | Consolidated: only `workflow-improve.md` |
| `setup.sh` copies everything blindly | `setup.sh --ext=blockchain,omega` — selective deployment |

## Repository Structure

```
claude-workflow/
├── core/                              # Universal foundation
│   ├── agents/                        # 13 agents every project needs
│   ├── commands/                      # 13 workflow orchestrators
│   ├── db/                            # Institutional memory layer
│   │   ├── schema.sql                 # SQLite schema (tables, views, indexes)
│   │   └── queries/                   # Named query templates
│   │       ├── briefing.sql           # What agents run BEFORE work
│   │       ├── debrief.sql            # What agents run AFTER work
│   │       └── maintenance.sql        # Periodic cleanup & health
│   └── hooks/                         # Claude Code automation hooks
│       ├── briefing.sh                # SessionStart: auto-injects memory context
│       └── session-close.sh           # SessionEnd: closes open runs
│
├── extensions/                        # Domain-specific packs (opt-in)
│   ├── blockchain/                    # 3 agents, 3 commands
│   ├── omega/                         # 2 agents, 1 command
│   └── c2c-protocol/                  # 2 agents, 3 commands
│
├── scripts/
│   ├── setup.sh                       # Deploy to target projects
│   └── db-init.sh                     # Initialize/migrate SQLite
│
├── poc/                               # Experimental standalone agents
├── c2c-protocol/                      # C2C protocol spec research
├── h2a-protocol/                      # H2A protocol spec research
├── CLAUDE.md                          # Toolkit rules + workflow rules
└── README.md
```

## Deployment Model

The toolkit repo is the **source**. Target projects are **consumers**. The setup script flattens `core/` + selected `extensions/` into the target's `.claude/` directory:

```
claude-workflow (source)                target-project (consumer)
─────────────────────────              ─────────────────────────
core/agents/analyst.md          →      .claude/agents/analyst.md
core/agents/developer.md        →      .claude/agents/developer.md
core/commands/workflow-new.md   →      .claude/commands/workflow-new.md
extensions/blockchain/agents/   →      .claude/agents/ (if --ext=blockchain)
core/db/schema.sql              →      .claude/memory.db (initialized)
core/db/queries/*.sql           →      .claude/db-queries/*.sql
```

Claude Code reads agents from `.claude/agents/` and commands from `.claude/commands/` — it requires them flat. The source repo organizes by category; the setup script flattens on deploy.

## Data Flow

### Single Pipeline Execution

```
User invokes /workflow:new-feature "add retry logic" --scope="scheduler"
    │
    ├─ Orchestrator creates workflow_run in memory.db → gets $RUN_ID
    │
    ├─ Discovery (if vague)
    │   ├─ Briefing: query memory.db for recent work in "scheduler"
    │   ├─ Work: conversation with user → idea-brief.md
    │   └─ Debrief: (discovery has no structured debrief — it's conversational)
    │
    ├─ Feature Evaluator
    │   ├─ Reads idea-brief.md
    │   └─ Produces GO/CONDITIONAL/NO-GO verdict
    │
    ├─ Analyst
    │   ├─ Briefing: past bugs, open findings, hotspots, existing requirements
    │   ├─ Work: requirements, MoSCoW, traceability → specs/scheduler-requirements.md
    │   └─ Debrief: INSERT requirements, decisions into memory.db
    │
    ├─ Architect
    │   ├─ Briefing: failed approaches, dependencies, hotspots, active decisions
    │   ├─ Work: design, milestones → specs/scheduler-architecture.md
    │   └─ Debrief: INSERT decisions, dependencies into memory.db
    │
    ├─ [Per Milestone Loop]
    │   ├─ Test Writer
    │   │   ├─ Briefing: past bugs, open findings, requirement status
    │   │   ├─ Work: TDD tests → test files
    │   │   └─ Debrief: UPDATE requirements status to 'tested'
    │   │
    │   ├─ Developer
    │   │   ├─ Briefing: hotspots, failed approaches, open findings, decisions, patterns
    │   │   ├─ Work: implement → source code
    │   │   └─ Debrief: INSERT changes, decisions, failed_approaches, hotspot updates
    │   │
    │   ├─ QA
    │   │   ├─ Briefing: past bugs, hotspots, open findings, dependencies
    │   │   ├─ Work: end-to-end validation → qa-report.md
    │   │   └─ Debrief: INSERT bugs, UPDATE hotspot risk levels, UPDATE requirement status
    │   │
    │   └─ Reviewer
    │       ├─ Briefing: hotspot map, open findings, dependencies, past bugs, patterns
    │       ├─ Work: code review → review.md
    │       └─ Debrief: INSERT findings, UPDATE hotspot risk, INSERT dependencies
    │
    └─ Orchestrator closes workflow_run (status=completed, git_commits=[...])
```

### Self-Learning Layer

Every briefing and debrief now includes a self-learning phase:

- **Briefing addition**: Inject the 15 most recent outcomes + all active lessons for the scope
- **Debrief addition**: Score every significant action (-1/0/+1), check for lesson distillation opportunity, reinforce/supersede existing lessons

This creates a feedback loop on top of the existing memory protocol. The `failed_approaches` table captures *what didn't work*. The `outcomes` + `lessons` tables capture *what worked, how well, and why* — turning passive record-keeping into active learning.

### Cross-Session Memory Accumulation

```
Session 1: /workflow:new-feature "add scheduler"
  → memory.db accumulates: decisions about scheduler design, patterns used,
    files touched, dependencies discovered

Session 2: /workflow:bugfix "scheduler crash on empty queue"
  → Developer briefing reveals: "scheduler.rs is a hotspot (touched 3x),
    approach X failed before because of race condition,
    AUDIT-P1-003 is still open in this file"
  → Developer avoids the failed approach, addresses the open finding,
    commits fix → debrief updates memory.db

Session 3: /workflow:audit --scope="scheduler"
  → Reviewer briefing shows: full history of scheduler changes, bug clusters,
    which findings were fixed vs deferred
  → Review is informed by accumulated context, not starting fresh
```

## Core vs Extension Boundary

### What Makes an Agent "Core"

An agent is core if it is useful in **any** software project regardless of domain:

- **Pipeline agents**: discovery, analyst, architect, test-writer, developer, qa, reviewer
- **Utility agents**: feature-evaluator, functionality-analyst, codebase-expert, wizard-ux
- **Meta agents**: role-creator, role-auditor

### What Makes an Agent an "Extension"

An agent is an extension if it requires **domain-specific knowledge** that only applies to certain projects:

- **blockchain**: Ethereum/Solana node operations, P2P networking, consensus — irrelevant to a web app
- **omega**: OMEGA framework primitives (projects, skills, topologies) — irrelevant outside OMEGA
- **c2c-protocol**: Agent-to-agent communication protocol research — experimental

### Creating New Extensions

New extensions follow the same structure:

```
extensions/my-domain/
├── agents/
│   └── my-agent.md          # YAML frontmatter + agent definition
└── commands/
    └── workflow-my-domain.md # Slash command orchestrator
```

Then `setup.sh --ext=my-domain` deploys it. The `--list-ext` flag auto-discovers extensions from the directory structure.

## Design Decisions

### Why SQLite (not markdown, not Postgres)

| Option | Verdict | Reason |
|--------|---------|--------|
| Markdown files | Rejected | No selective retrieval — must load entire file into context. No relational queries. |
| JSON files | Rejected | Same context window problem. No atomic writes. |
| SQLite | Chosen | Selective retrieval via SQL. `sqlite3` CLI available everywhere. Single file, no server. Git-portable (with caveats). |
| Postgres/external DB | Rejected | Requires infrastructure. Agents run in ephemeral contexts — external DB adds latency and config complexity. |

### Why Flat Deployment (not subdirectories)

Claude Code loads agents from `.claude/agents/` — it does not recurse into subdirectories. The source repo organizes by category (`core/`, `extensions/`) for human comprehension, but the setup script must flatten everything into the target's `.claude/agents/` and `.claude/commands/`.

### Why Mandatory Briefing/Debrief

Without it, agents are memoryless. The institutional memory DB exists but is useless if agents don't read from or write to it. Making briefing/debrief mandatory in every agent definition ensures the protocol is followed — it's not optional behavior that can be skipped under time pressure.

### Why Separate Briefing Queries per Agent

Each agent needs different context:
- **Developer** needs failed approaches and patterns (what to avoid, what to follow)
- **Reviewer** needs the hotspot map and dependency graph (where to focus review)
- **Analyst** needs existing requirements and past bugs (avoid duplicates, flag regression risk)
- **Test Writer** needs bug history and open findings (write regression tests for known failures)

A single "dump everything" query would consume too much context. Targeted queries respect the 60% budget.

### Why Self-Learning (not just record-keeping)

The original institutional memory is a **ledger** — it records what happened faithfully. But it never asks "how well did it work?" The self-learning mechanism adds evaluation and distillation:

| Without self-learning | With self-learning |
|-|-|
| Records failures (failed_approaches) | Records failures AND successes (outcomes) |
| No quality signal | Score: -1/0/+1 per action |
| Manual pattern discovery (patterns table) | Automatic pattern distillation (lessons table) |
| No cross-agent feedback | Developer -1 informs architect next time |
| Static knowledge | Confidence-tracked, decay-aware knowledge |

The design choice to keep this as SQL tables (not a separate system) ensures it rides the existing briefing/debrief protocol with no new infrastructure.

### Why Hooks (not voluntary compliance)

The original design relied on agents voluntarily running briefing queries and debrief inserts. This failed immediately — the AI doesn't reliably execute the protocol, even when the documentation says "MANDATORY."

| Voluntary compliance | Hooks |
|-|-|
| Agent must remember to run briefing | Briefing runs automatically on SessionStart |
| Agent must remember to debrief | Debrief reminder injected into every session |
| "MANDATORY" is aspirational text | Hook execution is infrastructure-level |
| AI skips it under cognitive load | Hook runs regardless of what the AI is doing |

Hooks don't solve everything — self-scoring and lesson distillation still require AI judgment. But the briefing (80% of the value) is now fully automated. The AI sees the institutional context whether it wants to or not.

### Why Decay Mechanics

Memory without forgetting becomes noise. The `decay_log` table and `maintenance.sql` queries implement controlled forgetting:
- Decisions older than 30 days without reinforcement get flagged as stale
- Resolved findings older than 90 days get archived
- Hotspot risk levels auto-promote based on incident frequency
- Orphaned hotspots (files that no longer exist) get flagged for cleanup

This prevents the briefing from being polluted by ancient, irrelevant data.
