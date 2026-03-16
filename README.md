# Claude Code Quality Workflow

A multi-agent orchestration system for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that produces high-quality code through structured validation layers with **persistent institutional memory**. Instead of asking an AI to "build X" and hoping for the best, this workflow forces every piece of code through questioning, architecture design, test-driven development, implementation, QA validation, and review — each handled by a specialized agent that reads from and writes to a shared knowledge base.

## The Problem

When you ask an AI to write code directly, it:
- **Assumes things** instead of asking — leading to silent bugs
- **Writes tests after code** — biasing tests toward what was built, not what should be built
- **Skips architecture** — jumping straight to implementation without thinking through design
- **Ignores context** — not reading existing code conventions, patterns, or documentation
- **Lets documentation rot** — specs and docs drift out of sync with the actual codebase
- **Has no traceability** — requirements, tests, and code aren't linked, so gaps go unnoticed
- **Forgets everything** — each session starts fresh with zero knowledge of past decisions, failures, or patterns

This workflow solves all of that.

## How It Works

Thirteen core agents execute in chain or standalone, each with a single responsibility. Every agent has **mandatory briefing/debrief** phases — querying institutional memory before starting and writing findings back after completing.

```
Your Idea
  ↓
[Pipeline registers in memory.db]
  ↓
Discovery     → Explores and challenges your idea through conversation
  ↓
Evaluator     → GO/NO-GO gate: scores necessity, impact, complexity, alternatives
  ↓
Analyst       → Questions your idea, defines requirements with acceptance criteria
  ↓
Architect     → Designs architecture with failure modes, security, performance budgets
  ↓
┌─── Per Milestone (auto-loop) ───────────────────────────────────────────────┐
│ Test Writer   → Writes tests BEFORE code exists (TDD, priority-driven)      │
│ Developer     → Implements minimum code to pass (module by module)           │
│ Compiler      → Build + lint + test validation gate                          │
│ QA            → End-to-end validation, acceptance criteria, exploratory tests │
│ Reviewer      → Audits for bugs, security, performance, specs/docs drift     │
└─────────────────────────────────────────────────────────────────────────────┘
  ↓
[Pipeline completes, memory.db updated with all decisions, findings, patterns]
```

## Architecture

### Core + Extensions

The toolkit separates **universal foundation** (core) from **domain-specific packs** (extensions):

```
claude-workflow/
├── core/                              # Every project gets this
│   ├── agents/                        # 13 universal agents
│   ├── commands/                      # 13 universal commands
│   └── db/                            # Institutional memory layer
│       ├── schema.sql                 # SQLite schema
│       └── queries/                   # Named query templates
│           ├── briefing.sql           # Pre-work queries
│           ├── debrief.sql            # Post-work inserts/updates
│           └── maintenance.sql        # Periodic cleanup
│
├── extensions/                        # Opt-in per project
│   ├── blockchain/                    # Ethereum, Solana, Cosmos, Substrate
│   │   ├── agents/                    # blockchain-network, blockchain-debug, stress-tester
│   │   └── commands/                  # 3 commands
│   ├── omega/                         # OMEGA framework
│   │   ├── agents/                    # omega-topology-architect, skill-creator
│   │   └── commands/                  # 1 command
│   └── c2c-protocol/                  # C2C protocol research
│       ├── agents/                    # proto-auditor, proto-architect
│       └── commands/                  # 3 commands
│
└── scripts/
    ├── setup.sh                       # Deploy to target projects
    └── db-init.sh                     # Initialize SQLite
```

### Institutional Memory (SQLite)

Every target project gets `.claude/memory.db` — a persistent knowledge base that survives context compression and session boundaries:

| Table | Purpose | Written By | Read By |
|-------|---------|-----------|---------|
| `workflow_runs` | Pipeline execution traces | Orchestrator commands | All agents |
| `changes` | What files were changed and why | developer, architect | analyst, reviewer |
| `decisions` | Design decisions with rationale + rejected alternatives | architect, analyst, developer | All agents |
| `failed_approaches` | What was tried and why it failed | developer, architect | developer, architect |
| `bugs` | Symptoms, root cause, fix, affected files | qa, developer | analyst, test-writer |
| `hotspots` | Files that keep breaking (risk levels, touch counts) | All agents | All agents |
| `findings` | Reviewer/QA findings with status tracking | reviewer, qa | developer, test-writer |
| `dependencies` | Component relationships | architect, reviewer | architect, reviewer |
| `requirements` | Requirement lifecycle (defined → tested → verified) | analyst, test-writer, qa | All agents |
| `patterns` | Successful patterns to reuse | developer, architect | developer, architect |
| `outcomes` | Self-learning Tier 1: raw self-scored results per action | All pipeline agents | All agents (briefing) |
| `lessons` | Self-learning Tier 2: distilled patterns from outcomes | All pipeline agents | All agents (briefing) |
| `decay_log` | Memory evolution audit trail | maintenance | maintenance |

**Agent protocol**: Before work → query DB (briefing + learning context). After work → write back (debrief + self-score). **Briefing is automated via Claude Code hooks** — agents see institutional memory context at the start of every session without relying on AI compliance.

### Self-Learning Loop

Agents don't just record what happened — they evaluate *how well it worked* and distill patterns into permanent rules:

```
Agent starts → briefing injects recent outcomes + active lessons
  → Agent works (confirms or contradicts existing lessons)
  → Agent debriefs: scores outcomes (-1/0/+1), distills new lessons
  → Next agent/session gets updated learning context
```

- **Tier 1 (Outcomes)**: After every significant action, the agent self-scores: +1 (helpful), 0 (neutral), -1 (unhelpful). The 15 most recent outcomes for the scope are injected into every future briefing.
- **Tier 2 (Lessons)**: When patterns emerge from 3+ repeated outcomes, agents distill them into permanent rules with content-based deduplication, confidence tracking, and a cap of 10 active lessons per domain.
- **Cross-agent learning**: The developer's -1 score on a retry-heavy module informs the architect to design smaller milestones next time. The test-writer's +1 on edge-case-first testing reinforces that approach across sessions.

**Why this matters**: Without institutional memory, every session is a fresh hire. The developer wastes cycles on approaches that already failed. The reviewer misses that a file was flagged fragile three sessions ago. The analyst re-specifies requirements that already exist. The DB eliminates this.

## Core Agents (13)

| Agent | Role |
|-------|------|
| **discovery** | Pre-pipeline conversation: explores, challenges, clarifies raw ideas |
| **analyst** | Business analysis: requirements, acceptance criteria, MoSCoW, traceability, impact |
| **architect** | System design: failure modes, security, performance budgets, milestones |
| **test-writer** | TDD red phase: writes failing tests before code, priority-driven |
| **developer** | Implementation: module by module, minimum code to pass tests |
| **qa** | End-to-end validation, acceptance criteria verification, exploratory testing |
| **reviewer** | Audit: bugs, security, performance, tech debt, specs/docs drift (read-only) |
| **feature-evaluator** | GO/NO-GO gate: 7-dimension scoring before committing pipeline resources |
| **functionality-analyst** | Codebase inventory: maps endpoints, services, models, handlers (read-only) |
| **codebase-expert** | Deep comprehension: 6-layer progressive exploration (read-only) |
| **wizard-ux** | Wizard/setup flow design for TUI/GUI/Web/CLI |
| **role-creator** | Meta-agent: designs new agent role definitions |
| **role-auditor** | Meta-agent: adversarial audit of role definitions (read-only) |

## Extension Packs

### Blockchain (3 agents, 3 commands)
- **blockchain-network** — P2P networking, node operations, RPC infrastructure, monitoring, security
- **blockchain-debug** — Firefighter: diagnoses active connectivity problems using 7-phase methodology
- **stress-tester** — Black-box adversarial testing of blockchain CLI/RPC endpoints

### OMEGA (2 agents, 1 command)
- **omega-topology-architect** — Maps business domains to OMEGA primitives
- **skill-creator** — Creates OMEGA skill definitions

### C2C Protocol (2 agents, 3 commands)
- **proto-auditor** — Audits protocol specs across 12 dimensions at 3 levels
- **proto-architect** — Generates patches from audit findings via 6-step pipeline

## Core Commands (13)

| Command | Description |
|---------|-------------|
| `/workflow:new "idea"` | Full pipeline for greenfield projects |
| `/workflow:new-feature "feat" [--scope]` | Full pipeline for existing projects (with feature gate) |
| `/workflow:improve "desc" [--scope]` | Refactor/optimize (no architect step) |
| `/workflow:bugfix "bug" [--scope]` | Bug fix with reproduction test |
| `/workflow:audit [--fix] [--scope]` | Code audit; `--fix` for auto-fix pipeline |
| `/workflow:docs [--scope]` | Generate/update specs & docs |
| `/workflow:sync [--scope]` | Detect and fix specs/docs drift |
| `/workflow:functionalities [--scope]` | Map codebase functionalities |
| `/workflow:understand [--scope]` | Deep codebase comprehension |
| `/workflow:resume [--from]` | Resume stopped milestone-based workflow |
| `/workflow:wizard-ux "desc" [--scope]` | Design wizard/setup UX flows |
| `/workflow:create-role "desc"` | Design a new agent role |
| `/workflow:audit-role "path" [--scope]` | Adversarial audit of role definitions |

## Setup

Navigate to your **target project** and run:

```bash
bash /path/to/claude-workflow/scripts/setup.sh
```

One command deploys everything: 13 agents, 13 commands, automation hooks (auto-briefing/debrief), SQLite memory DB (with self-learning), query templates, scaffolding, and **appends** the workflow rules to your project's CLAUDE.md (preserving your project-specific rules).

```bash
# With extensions
bash /path/to/claude-workflow/scripts/setup.sh --ext=blockchain,omega

# All extensions
bash /path/to/claude-workflow/scripts/setup.sh --ext=all
```

**Safe to re-run** — agents/commands update, CLAUDE.md workflow rules refresh, DB schema migrates, your data is preserved.

For the complete deployment reference (prerequisites, what gets deployed, CLAUDE.md handling, verification, troubleshooting), see **[docs/setup-guide.md](docs/setup-guide.md)**.

## Guardrails

- **Prerequisite gates**: Every agent verifies upstream output exists before proceeding
- **Iteration limits**: QA↔Developer max 3, Reviewer↔Developer max 2, Audit fix max 5 per finding
- **60% context budget**: Agents stop at 60% context usage, save state, continue via `/workflow:resume`
- **Inter-step validation**: Commands verify each agent produced output before invoking the next
- **Error recovery**: Failed chains save state to `docs/.workflow/chain-state.md` + memory.db
- **Developer max retry**: 5 attempts per test-fix cycle, then escalation
- **Language-agnostic**: Adapts to Rust, TypeScript, Python, Go, Elixir, or any detected language

## Source of Truth

```
Codebase > .claude/memory.db > specs/ > docs/
```

When anything conflicts, the codebase wins. Agents flag discrepancies and update accordingly.

## License

This toolkit is designed for use with Claude Code by Anthropic.
