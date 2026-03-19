# Architecture Overview

> v2 — Core/Extensions with Institutional Memory (March 2026)

## What OMEGA Is

OMEGA Ω is a multi-agent orchestration system for Claude Code. It forces every piece of code through structured validation layers — questioning, architecture, TDD, implementation, QA, review — each handled by a specialized agent. Every agent reads from and writes to a shared SQLite knowledge base, creating persistent institutional memory across sessions.

OMEGA is **not** an application. It is a set of agent definitions, command orchestrators, a memory schema, and a deployment script designed to be copied into any project.

## What Changed (v1 → v2)

| v1 | v2 |
|----|-----|
| Flat `.claude/agents/` and `.claude/commands/` | `core/` + `extensions/` source organization |
| All 20 agents copied to every project | Core (15) always; extensions opt-in via `--ext=` |
| No cross-session memory | SQLite `.claude/memory.db` with 17 tables + 10 views |
| Agents act independently | Mandatory briefing/incremental logging/close-out + self-learning — agents log as they work and distill patterns |
| `omega-feature.md` + `omega-new-feature.md` (duplicate) | Consolidated: only `omega-new-feature.md` |
| `omega-improve.md` + `omega-improve-functionality.md` (duplicate) | Consolidated: only `omega-improve.md` |
| `setup.sh` copies everything blindly | `setup.sh --ext=blockchain` — selective deployment |

## Repository Structure

```
omega/
├── core/                              # Universal foundation
│   ├── agents/                        # 15 agents every project needs
│   ├── commands/                      # 16 workflow orchestrators
│   ├── db/                            # Institutional memory layer
│   │   ├── schema.sql                 # SQLite schema (tables, views, indexes)
│   │   └── queries/                   # Named query templates
│   │       ├── briefing.sql           # What agents run BEFORE work
│   │       ├── debrief.sql            # What agents run AFTER work
│   │       └── maintenance.sql        # Periodic cleanup & health
│   ├── protocols/                     # On-demand protocol reference files
│   │   ├── memory-protocol.md        # Full institutional memory protocol
│   │   ├── incident-protocol.md      # Bug tracking with INC-NNN tickets
│   │   ├── fail-safes.md             # Iteration limits, prerequisite gates
│   │   ├── context-budget.md         # 60% budget, scoping strategy
│   │   └── identity.md               # Experience levels, communication styles
│   └── hooks/                         # Claude Code automation hooks
│       ├── briefing.sh                # UserPromptSubmit: auto-injects memory context (once per session)
│       ├── learning-detector.sh       # UserPromptSubmit: detects corrections → behavioral learnings (every message)
│       ├── debrief-gate.sh            # PreToolUse: blocks git commit without outcomes
│       ├── incremental-gate.sh        # PreToolUse: blocks edits after 10 modifications without outcomes
│       ├── debrief-nudge.sh           # PostToolUse: periodic incremental logging reminder
│       └── session-close.sh           # Notification: promotes hotspot risk levels
│
├── extensions/                        # Domain-specific packs (opt-in)
│   ├── blockchain/                    # 3 agents, 3 commands
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
omega (source)                         target-project (consumer)
─────────────────────────              ─────────────────────────
core/agents/analyst.md          →      .claude/agents/analyst.md
core/agents/developer.md        →      .claude/agents/developer.md
core/commands/omega-new.md   →      .claude/commands/omega-new.md
extensions/blockchain/agents/   →      .claude/agents/ (if --ext=blockchain)
core/db/schema.sql              →      .claude/memory.db (initialized)
core/db/queries/*.sql           →      .claude/db-queries/*.sql
```

Claude Code reads agents from `.claude/agents/` (OMEGA flattens them there) and commands from `.claude/commands/` — it requires them flat. The source repo organizes by category; the setup script flattens on deploy.

## Data Flow

### Single Pipeline Execution

```
User invokes /omega:new-feature "add retry logic" --scope="scheduler"
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
    │   ├─ Work + Incremental Logging: requirements, MoSCoW, traceability → specs/scheduler-requirements.md
    │   │   (logs requirements, decisions to memory.db as they are defined)
    │   └─ Close-Out: verify completeness, distill lessons
    │
    ├─ Architect
    │   ├─ Briefing: failed approaches, dependencies, hotspots, active decisions
    │   ├─ Work + Incremental Logging: design, milestones → specs/scheduler-architecture.md
    │   │   (logs decisions, dependencies to memory.db as they are made)
    │   └─ Close-Out: verify completeness, distill lessons
    │
    ├─ [Per Milestone Loop]
    │   ├─ Test Writer
    │   │   ├─ Briefing: past bugs, open findings, requirement status
    │   │   ├─ Work + Incremental Logging: TDD tests → test files
    │   │   │   (logs requirement status updates, decisions after each module)
    │   │   └─ Close-Out: verify completeness, distill lessons
    │   │
    │   ├─ Developer
    │   │   ├─ Briefing: hotspots, failed approaches, open findings, decisions, patterns
    │   │   ├─ Work + Incremental Logging: implement → source code
    │   │   │   (logs changes, decisions, failed_approaches, outcomes after each module)
    │   │   └─ Close-Out: verify completeness, distill lessons
    │   │
    │   ├─ QA
    │   │   ├─ Briefing: past bugs, hotspots, open findings, dependencies
    │   │   ├─ Work + Incremental Logging: end-to-end validation → qa-report.md
    │   │   │   (logs bugs, hotspot updates, requirement verifications as found)
    │   │   └─ Close-Out: verify completeness, distill lessons
    │   │
    │   └─ Reviewer
    │       ├─ Briefing: hotspot map, open findings, dependencies, past bugs, patterns
    │       ├─ Work + Incremental Logging: code review → review.md
    │       │   (logs findings, hotspot updates, dependencies as identified)
    │       └─ Close-Out: verify completeness, distill lessons
    │
    └─ Orchestrator closes workflow_run (status=completed, git_commits=[...])
```

### Learning Layer (Three Tiers)

Learning operates at three tiers, each with different scope and injection timing:

| Tier | What | When Injected |
|------|------|---------------|
| **Behavioral Learnings** | Cross-domain meta-cognitive rules ("verify before claiming") | Session start — every session |
| **Lessons** | Domain-specific patterns ("use Option<T> for concurrent access") | Agent briefing — scope-specific |
| **Outcomes** | Raw self-scored actions (+1/-1) | Never — feeds lesson distillation |

- **Session briefing**: Behavioral learnings + open incidents (lean, focused)
- **Agent briefing**: Scope-specific queries (hotspots, failed approaches, findings, patterns, lessons)
- **During work (incremental)**: Score actions, log incidents (INC-NNN), track attempts
- **Close-out**: Distill lessons, extract behavioral learnings, resolve incidents

Behavioral learnings make Claude **progressively smarter across sessions**. They are extracted from user corrections, incident resolutions, and self-reflection. Unlike outcomes and lessons, they are about HOW Claude should think, not domain-specific patterns.

### Incident Tracking

Bugs are tracked as **incidents** (INC-NNN). Each incident has a structured timeline of attempts, discoveries, clues, hypotheses, and resolution. On resolution, agents extract behavioral learnings if the incident revealed a flaw in Claude's reasoning. Full protocol: `.claude/protocols/incident-protocol.md`.

### Specialist Routing Flow

```
User invokes /omega:consult "help me with HIPAA compliance"
    │
    ├─ Orchestrator creates workflow_run (type='consult') in memory.db
    │
    ├─ omega-router agent
    │   ├─ Classify: domain=compliance/HIPAA, complexity=medium, type=audit
    │   ├─ Search: grep .claude/agents/*.md descriptions for HIPAA/compliance
    │   ├─ Check memory.db: any past routing decisions for this domain?
    │   └─ Decision → docs/.workflow/routing-decision.md
    │       ├─ MATCH? → Tier 2: delegate-existing (route to specialist)
    │       └─ NO MATCH? → Tier 2: create-then-delegate
    │
    ├─ [If creating specialist]
    │   ├─ role-creator builds .claude/agents/hipaa-specialist.md
    │   ├─ Structural validation (Phase 6) — no adversarial audit for speed
    │   └─ Agent file saved, ready for immediate use
    │
    ├─ Specialist agent invoked with original request
    │   ├─ Briefing: reads memory.db for context
    │   ├─ Work: domain-specific analysis/output
    │   └─ Close-out: logs outcomes, decisions
    │
    └─ Orchestrator presents output, closes workflow_run
```

For **Tier 3 (critical)**, the router assembles a pipeline of existing core agents + specialist:

```
/omega:consult --critical "should we migrate to microservices?"
    │
    ├─ Router classifies: Tier 3 (high-stakes architectural decision)
    │
    ├─ Pipeline: discovery → architect → reviewer
    │   ├─ discovery: explores options boldly (Explorer role)
    │   ├─ architect: evaluates migration architecture
    │   └─ reviewer: attacks the proposal (Skeptic role)
    │
    └─ Output: multi-perspective analysis with agreements and disagreements
```

Specialists accumulate per project — the first request creates them, subsequent requests reuse them. Routing decisions are logged to memory.db so the router improves over time.

### Cross-Session Memory Accumulation

```
Session 1: /omega:new-feature "add scheduler"
  → memory.db accumulates: decisions about scheduler design, patterns used,
    files touched, dependencies discovered

Session 2: /omega:bugfix "scheduler crash on empty queue"
  → Session briefing: behavioral learnings + any related open incidents
  → Agent briefing: "scheduler.rs is a hotspot (touched 3x),
    approach X failed before because of race condition"
  → Bug tracked as INC-001, all attempts logged as entries
  → On resolution, behavioral learning extracted:
    "Always enumerate shared state access points before modifying concurrent code"

Session 3: New session starts
  → Briefing injects: "[0.8] Always enumerate shared state access points..."
  → Claude is now smarter — applies the rule before touching any concurrent code
```

## Core vs Extension Boundary

### What Makes an Agent "Core"

An agent is core if it is useful in **any** software project regardless of domain:

- **Pipeline agents**: discovery, analyst, architect, test-writer, developer, qa, reviewer
- **Utility agents**: feature-evaluator, functionality-analyst, codebase-expert, wizard-ux, diagnostician
- **Dispatch agent**: omega-router (intelligent specialist routing)
- **Meta agents**: role-creator, role-auditor

### What Makes an Agent an "Extension"

An agent is an extension if it requires **domain-specific knowledge** that only applies to certain projects:

- **blockchain**: Ethereum/Solana node operations, P2P networking, consensus — irrelevant to a web app
- **c2c-protocol**: Agent-to-agent communication protocol research — experimental

### Creating New Extensions

New extensions follow the same structure:

```
extensions/my-domain/
├── agents/
│   └── my-agent.md          # YAML frontmatter + agent definition
└── commands/
    └── omega-my-domain.md # Slash command orchestrator
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

### Why Mandatory Briefing/Incremental Logging/Close-Out

Without it, agents are memoryless. The institutional memory DB exists but is useless if agents don't read from or write to it. The protocol evolved from a two-phase (briefing/debrief) to three-phase (briefing/incremental logging/close-out) model because the original batched debrief failed under context compaction — agents lost the details of what they did, producing vague or empty debriefs. Incremental logging ensures data reaches the DB as it is produced, making the protocol resilient to context window limits.

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
| Agent must remember to run briefing | Briefing runs automatically on first prompt (UserPromptSubmit) |
| Agent must remember to debrief | Debrief reminder injected into every session |
| "MANDATORY" is aspirational text | Hook execution is infrastructure-level |
| AI skips it under cognitive load | Hook runs regardless of what the AI is doing |

Four hooks cover the full lifecycle:

| Hook | Enforcement |
|-|-|
| `briefing.sh` (UserPromptSubmit) | Automatic — behavioral learnings + open incidents injected on first prompt per session |
| `debrief-gate.sh` (PreToolUse/Bash) | **Blocking** — git commits fail without this session's self-scoring |
| `incremental-gate.sh` (PreToolUse/Write,Edit) | **Blocking** — file modifications blocked after 10 edits without outcomes |
| `debrief-nudge.sh` (PostToolUse) | Reminder — periodic nudge to log incrementally every 5th tool call |
| `session-close.sh` (Notification) | Automatic — promotes hotspot risk levels |

Self-scoring and lesson distillation still require AI judgment, but the AI literally cannot commit code without doing it first. This is the closest analog to Omega's gateway — the infrastructure forces the protocol.

### Why Decay Mechanics

Memory without forgetting becomes noise. The `decay_log` table and `maintenance.sql` queries implement controlled forgetting:
- Decisions older than 30 days without reinforcement get flagged as stale
- Resolved findings older than 90 days get archived
- Hotspot risk levels auto-promote based on incident frequency
- Orphaned hotspots (files that no longer exist) get flagged for cleanup

This prevents the briefing from being polluted by ancient, irrelevant data.
