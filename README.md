# OMEGA Ω

A multi-agent orchestration toolkit for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that produces high-quality code through structured validation layers with **persistent institutional memory**. Instead of asking an AI to "build X" and hoping for the best, OMEGA forces every piece of code through questioning, architecture design, test-driven development, implementation, QA validation, and review — each handled by a specialized agent that reads from and writes to a shared knowledge base.

## The Problem

When you ask an AI to write code directly, it:
- **Assumes things** instead of asking — leading to silent bugs
- **Writes tests after code** — biasing tests toward what was built, not what should be built
- **Skips architecture** — jumping straight to implementation without thinking through design
- **Ignores context** — not reading existing code conventions, patterns, or documentation
- **Lets documentation rot** — specs and docs drift out of sync with the actual codebase
- **Has no traceability** — requirements, tests, and code aren't linked, so gaps go unnoticed
- **Forgets everything** — each session starts fresh with zero knowledge of past decisions, failures, or patterns

OMEGA solves all of that.

## How It Works

Fifteen core agents execute in chain or standalone, each with a single responsibility. Every agent has **mandatory briefing/incremental logging/close-out** phases — querying institutional memory before starting, writing to memory.db continuously during work, and verifying completeness after finishing.

```
Your Idea
  |
[Pipeline registers in memory.db]
  |
Discovery     -> Explores and challenges your idea through conversation
  |
Evaluator     -> GO/NO-GO gate: scores necessity, impact, complexity, alternatives
  |
Analyst       -> Questions your idea, defines requirements with acceptance criteria
  |
Architect     -> Designs architecture with failure modes, security, performance budgets
  |
+--- Per Milestone (auto-loop) ------------------------------------------+
| Test Writer   -> Writes tests BEFORE code exists (TDD, priority-driven) |
| Developer     -> Implements minimum code to pass (module by module)     |
| Compiler      -> Build + lint + test validation gate                    |
| QA            -> End-to-end validation, acceptance criteria, exploratory |
| Reviewer      -> Audits for bugs, security, performance, specs drift    |
+-------------------------------------------------------------------------+
  |
[Pipeline completes, memory.db populated incrementally throughout]
```

## Prerequisites

- **Claude Code** — `npm install -g @anthropic-ai/claude-code`
- **Git** — the target project must be inside a git repository (setup.sh will `git init` if needed)
- **SQLite3** — for institutional memory (`sqlite3` CLI must be in PATH; not needed if using the `omg` binary for init)

## Deployment

OMEGA is **not an application** — it's deployed into target projects. There are two ways to deploy:

### Option A: `omg` CLI (Recommended)

A single Rust binary that embeds all assets and has zero runtime dependencies for installation:

```bash
# Install the CLI
curl -fsSL https://raw.githubusercontent.com/isudoajl/claude-workflow/main/cli/install.sh | bash

# Navigate to your target project
cd /path/to/your-project

# Deploy core toolkit
omg init

# Start Claude Code and use the workflow
claude
```

See `omg --help` for all commands: `init`, `update`, `doctor`, `self-update`, `list-ext`, `version`.

### Option B: Shell Script (Legacy)

```bash
# Navigate to your target project
cd /path/to/your-project

# Deploy core toolkit
bash /path/to/omega/scripts/setup.sh

# Start Claude Code and use the workflow
claude
```

> **Note**: The shell script requires Python 3 (for JSON merging) and sqlite3 CLI. The `omg` binary eliminates both dependencies.

Then inside Claude Code:
```
/workflow:new "build a REST API for user management"
```

### Setup Options

#### Using `omg` CLI
```bash
omg init                              # Core only (15 agents, 16 commands, 5 hooks, SQLite memory)
omg init --ext=blockchain             # Core + specific extension
omg init --ext=blockchain,c2c-protocol # Core + multiple extensions
omg init --ext=all                    # Core + all extensions
omg init --no-db                      # Skip SQLite initialization
omg init --dry-run                    # Show what would be deployed without writing
omg init --verbose                    # Show unchanged files individually
omg update                            # Update to latest (idempotent)
omg doctor                            # Health check
omg list-ext                          # List available extensions
```

#### Using shell script (legacy)
```bash
bash /path/to/omega/scripts/setup.sh
bash /path/to/omega/scripts/setup.sh --ext=blockchain
bash /path/to/omega/scripts/setup.sh --ext=all
bash /path/to/omega/scripts/setup.sh --no-db
bash /path/to/omega/scripts/setup.sh --verbose
bash /path/to/omega/scripts/setup.sh --list-ext
bash /path/to/omega/scripts/setup.sh --help
```

### What Gets Deployed

When you run setup.sh, the following is created/updated in your target project:

```
your-project/
├── .claude/
│   ├── agents/           <- 15 core agent definitions (+ extension agents)
│   ├── commands/         <- 16 core commands (+ extension commands)
│   ├── protocols/        <- 4 on-demand protocol reference files
│   ├── hooks/            <- 5 automation hooks
│   ├── settings.json     <- Hook configuration (merged, not overwritten)
│   ├── memory.db         <- SQLite institutional memory database
│   └── db-queries/       <- Query reference files for agents
├── specs/
│   └── SPECS.md          <- Master spec index (created if missing)
├── docs/
│   └── DOCS.md           <- Master doc index (created if missing)
└── CLAUDE.md             <- Workflow rules appended (project rules preserved)
```

### CLAUDE.md Handling

The setup script **appends** the workflow rules section to your project's CLAUDE.md, separated by `---`. Your project-specific rules above the separator are preserved. On re-runs, the workflow rules section is replaced in-place — your project rules are never touched.

If no CLAUDE.md exists, one is created with a placeholder for project-specific rules plus the workflow rules.

### Safe to Re-run

The setup script is fully idempotent with change detection:
- Files are compared before copying — unchanged files are skipped
- The DB schema migrates without data loss
- CLAUDE.md workflow rules are replaced, not duplicated
- Hook configuration is merged into existing settings.json
- Output shows `+` (new), `~` (updated), `=` (unchanged) for every file

## Architecture

### Core + Extensions

```
omega/
├── core/                              # Every project gets this
│   ├── agents/                        # 15 universal agents
│   ├── commands/                      # 16 universal commands
│   ├── protocols/                     # 4 on-demand reference files
│   ├── db/                            # Institutional memory layer
│   │   ├── schema.sql                 # SQLite schema
│   │   └── queries/                   # Named query templates
│   └── hooks/                         # 5 automation hooks
│
├── extensions/                        # Opt-in per project
│   ├── blockchain/                    # Ethereum, Solana, Cosmos, Substrate
│   └── c2c-protocol/                  # C2C protocol research
│
├── cli/                               # Rust binary (omg) — recommended installer
│   ├── src/                           # 11 modules (~2900 lines)
│   ├── Cargo.toml
│   └── install.sh                     # curl-pipe-bash installer
│
└── scripts/
    ├── setup.sh                       # Legacy shell installer
    └── db-init.sh                     # Initialize/migrate SQLite
```

### Institutional Memory (SQLite)

Every target project gets `.claude/memory.db` — a persistent knowledge base that survives context compression and session boundaries:

| Table | Purpose |
|-------|---------|
| `workflow_runs` | Pipeline execution traces |
| `changes` | What files were changed and why |
| `decisions` | Design decisions with rationale + rejected alternatives |
| `failed_approaches` | What was tried and why it failed |
| `bugs` | Symptoms, root cause, fix, affected files |
| `hotspots` | Files that keep breaking (risk levels, touch counts) |
| `findings` | Reviewer/QA findings with status tracking |
| `dependencies` | Component relationships |
| `requirements` | Requirement lifecycle (defined -> tested -> verified) |
| `patterns` | Successful patterns to reuse |
| `outcomes` | Self-learning Tier 1: raw self-scored results per action |
| `lessons` | Self-learning Tier 2: distilled patterns from outcomes |
| `decay_log` | Memory evolution audit trail |
| `user_profile` | Per-project identity (name, experience level, communication style) |
| `onboarding_state` | Tracks onboarding flow progress and resumability |

**Agent protocol**: Before work -> query DB (briefing). During work -> log incrementally. After work -> close-out (verify completeness, distill lessons). The briefing hook also injects an **OMEGA Identity** block when a user profile exists — adapting agent communication style to the user's experience level.

### Self-Learning Loop

Agents don't just record what happened — they evaluate *how well it worked* and distill patterns:

- **Tier 1 (Outcomes)**: After every significant action, the agent self-scores: +1 (helpful), 0 (neutral), -1 (unhelpful). The 15 most recent outcomes for the scope are injected into every future briefing.
- **Tier 2 (Lessons)**: When 3+ outcomes share a theme, agents distill them into permanent rules with confidence tracking and a cap of 10 active lessons per domain.
- **Cross-agent learning**: The developer's -1 on a retry-heavy module informs the architect to design smaller milestones. The test-writer's +1 on edge-case-first testing reinforces that approach.

### Automation Hooks

Five hooks enforce the memory protocol automatically:

| Hook | Event | Purpose |
|------|-------|---------|
| `briefing.sh` | UserPromptSubmit | Auto-injects institutional memory context (once per session) |
| `debrief-gate.sh` | PreToolUse (Bash) | Blocks `git commit` if no outcomes are logged |
| `incremental-gate.sh` | PreToolUse (Write/Edit) | Blocks after 10 file edits without logging outcomes |
| `debrief-nudge.sh` | PostToolUse | Periodic reminder to log incrementally |
| `session-close.sh` | Notification | Promotes hotspot risk levels at session end |

## Core Agents (15)

| Agent | Role |
|-------|------|
| **discovery** | Pre-pipeline conversation: explores, challenges, clarifies raw ideas |
| **analyst** | Business analysis: requirements, acceptance criteria, MoSCoW, traceability |
| **architect** | System design: failure modes, security, performance budgets, milestones |
| **test-writer** | TDD red phase: writes failing tests before code, priority-driven |
| **developer** | Implementation: module by module, minimum code to pass tests |
| **qa** | End-to-end validation, acceptance criteria verification, exploratory testing |
| **reviewer** | Audit: bugs, security, performance, tech debt, specs/docs drift (read-only) |
| **feature-evaluator** | GO/NO-GO gate: 7-dimension scoring before committing resources |
| **functionality-analyst** | Codebase inventory: maps endpoints, services, models, handlers (read-only) |
| **codebase-expert** | Deep comprehension: 6-layer progressive exploration (read-only) |
| **wizard-ux** | Wizard/setup flow design for TUI/GUI/Web/CLI |
| **diagnostician** | Deep diagnostic reasoning: hypothesis-driven root cause analysis |
| **omega-router** | Intelligent dispatch: classifies requests, finds/creates specialists, assembles pipelines |
| **role-creator** | Meta-agent: designs new agent role definitions |
| **role-auditor** | Meta-agent: adversarial audit of role definitions (read-only) |

## Core Commands (16)

| Command | Description |
|---------|-------------|
| `/workflow:new "idea"` | Full pipeline for greenfield projects |
| `/workflow:new-feature "feat" [--scope]` | Full pipeline for existing projects (with feature gate) |
| `/workflow:improve "desc" [--scope]` | Refactor/optimize (no architect step) |
| `/workflow:bugfix "bug" [--scope]` | Bug fix with reproduction test |
| `/workflow:audit [--fix] [--scope]` | Code audit; `--fix` for auto-fix pipeline |
| `/workflow:docs [--scope]` | Generate/update specs and docs |
| `/workflow:sync [--scope]` | Detect and fix specs/docs drift |
| `/workflow:functionalities [--scope]` | Map codebase functionalities |
| `/workflow:understand [--scope]` | Deep codebase comprehension |
| `/workflow:resume [--from]` | Resume stopped workflow |
| `/workflow:wizard-ux "desc" [--scope]` | Design wizard/setup UX flows |
| `/workflow:consult "request" [--critical]` | Intelligent specialist routing: find/create domain experts |
| `/workflow:create-role "desc"` | Design a new agent role |
| `/workflow:audit-role "path" [--scope]` | Adversarial audit of role definitions |
| `/workflow:diagnose "bug" [--scope] [--fix]` | Deep root cause diagnosis for hard bugs |
| `/workflow:onboard [--update]` | Set up your OMEGA identity profile |

## Intelligent Specialist Routing

OMEGA ships with 15 agents that cover software development. But real projects need expertise in hundreds of domains — marketing, compliance, database optimization, DevOps, security hardening, content writing, etc.

`/workflow:consult` is the catch-all for domain expertise that doesn't fit the structured development commands:

```bash
/workflow:consult "help me design a HIPAA-compliant data flow"
/workflow:consult "optimize my PostgreSQL queries for 10M rows"
/workflow:consult "write SEO-optimized copy for my landing page"
/workflow:consult --critical "should we migrate to microservices?"
```

### How It Works

The **omega-router** agent classifies every request into one of three tiers:

| Tier | When | What happens |
|------|------|--------------|
| **1 — Simple** | General knowledge, quick answer | Handled directly, no specialist |
| **2 — Specialist** | Domain expertise needed | Finds existing specialist OR creates one via role-creator, then delegates |
| **3 — Critical** | High-stakes, needs adversarial review | Assembles a multi-agent pipeline (e.g., discovery → specialist → reviewer) |

### Self-Growing Expertise

The first time you ask about a domain, the router creates a specialist agent (saved to `.claude/agents/`). The second time, that specialist already exists — routing is instant.

```
Session 1: "help with HIPAA compliance" → creates hipaa-specialist.md → analyzes your code
Session 5: "check this new endpoint for HIPAA" → hipaa-specialist exists → routes directly
```

Over time, your project accumulates the exact specialists it needs. A fintech project might grow `hipaa-specialist.md`, `dba-optimizer.md`, `tokenomics-designer.md`. A SaaS project might grow `seo-specialist.md`, `pricing-strategist.md`.

### When to Use What

| Your task | Use this, not /workflow:consult |
|---|---|
| Fix a bug | `/workflow:bugfix` |
| Add a feature | `/workflow:new-feature` |
| Refactor code | `/workflow:improve` |
| Code review | `/workflow:audit` |
| Hard bug, unknown cause | `/workflow:diagnose` |
| **Domain expertise outside development** | **`/workflow:consult`** |

## Extension Packs

### Blockchain (3 agents, 3 commands)
- **blockchain-network** — P2P networking, node operations, RPC infrastructure, monitoring
- **blockchain-debug** — Diagnoses active connectivity problems using 7-phase methodology
- **stress-tester** — Black-box adversarial testing of blockchain CLI/RPC endpoints

### C2C Protocol (2 agents, 3 commands)
- **proto-auditor** — Audits protocol specs across 12 dimensions at 3 levels
- **proto-architect** — Generates patches from audit findings via 6-step pipeline

## Guardrails

- **Prerequisite gates**: Every agent verifies upstream output exists before proceeding
- **Iteration limits**: QA<->Developer max 3, Reviewer<->Developer max 2, Audit fix max 5 per finding
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

OMEGA is designed for use with Claude Code by Anthropic.
