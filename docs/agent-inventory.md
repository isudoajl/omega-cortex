# Agent Inventory

> All 20 agents: 13 core + 7 extensions. Each with tools, inputs, outputs, and memory protocol.

## Core Agents (13)

All core agents include **mandatory briefing/incremental logging/close-out** for institutional memory. Agents log to memory.db incrementally during work (not batched at the end), ensuring data survives context compaction. They skip the memory protocol gracefully if `.claude/memory.db` does not exist.

### Pipeline Agents (7)

These execute in sequence within workflow commands.

---

#### Discovery

**File:** `core/agents/discovery.md`
**Model:** claude-opus-4-6
**Tools:** Read, Grep, Glob, WebFetch, WebSearch

| | |
|-|-|
| **Role** | Pre-pipeline conversation: explores, challenges, clarifies raw ideas with the user |
| **Input** | Raw user idea or feature description |
| **Output** | `docs/.workflow/idea-brief.md` |
| **Memory** | No structured briefing/debrief — conversational agent |
| **Invoked by** | `workflow:new`, `workflow:new-feature` (conditional) |

The only agent that engages in extended back-and-forth with the user. Produces a validated concept that downstream agents can act on without ambiguity.

---

#### Analyst

**File:** `core/agents/analyst.md`
**Model:** claude-opus-4-6
**Tools:** Read, Grep, Glob, WebFetch, WebSearch

| | |
|-|-|
| **Role** | Business analysis: requirements, acceptance criteria, MoSCoW priorities, traceability matrix, impact analysis |
| **Input** | Idea brief (from discovery) or user description; existing codebase + specs |
| **Output** | `specs/[domain]-requirements.md`, updates to `specs/SPECS.md` |
| **Briefing reads** | Past bugs, open findings, hotspots, existing requirements, recent workflow history |
| **Debrief writes** | New requirements (INSERT into `requirements`), scope/priority decisions |
| **Invoked by** | All workflow commands except audit, docs, sync, functionalities, understand |

---

#### Architect

**File:** `core/agents/architect.md`
**Model:** claude-opus-4-6
**Tools:** Read, Write, Edit, Grep, Glob

| | |
|-|-|
| **Role** | System design: failure modes, security, performance budgets, milestones. Maintains specs/ and docs/ |
| **Input** | Analyst requirements in `specs/`; existing codebase |
| **Output** | `specs/[domain]-architecture.md`, updates to `specs/SPECS.md` and `docs/DOCS.md` |
| **Briefing reads** | Failed approaches, component dependencies, hotspots, active decisions, known patterns |
| **Debrief writes** | Architectural decisions with rationale + alternatives, new dependencies, superseded old decisions |
| **Invoked by** | `workflow:new`, `workflow:new-feature`, `workflow:docs`, `workflow:sync` |

---

#### Test Writer

**File:** `core/agents/test-writer.md`
**Model:** claude-opus-4-6
**Tools:** Read, Write, Edit, Bash, Glob, Grep

| | |
|-|-|
| **Role** | TDD red phase: writes failing tests before code exists, priority-driven (Must → Should → Could) |
| **Input** | Architect design + analyst requirements in `specs/` |
| **Output** | Test files; traceability matrix updates |
| **Briefing reads** | Past bugs (regression tests), open findings (need coverage), existing requirements (avoid duplicates), hotspots (prioritize coverage) |
| **Debrief writes** | UPDATE requirement status to 'tested', test strategy decisions |
| **Invoked by** | `workflow:new`, `workflow:new-feature`, `workflow:improve`, `workflow:bugfix`, `workflow:audit --fix` |

---

#### Developer

**File:** `core/agents/developer.md`
**Model:** claude-opus-4-6
**Tools:** Read, Write, Edit, Bash, Glob, Grep

| | |
|-|-|
| **Role** | Implementation: minimum code to pass tests, module by module, commits per module |
| **Input** | Test files, architect design, analyst requirements |
| **Output** | Source code; specs/docs updates if behavior changed |
| **Briefing reads** | Hotspots, failed approaches, open findings, active decisions, established patterns |
| **Debrief writes** | File changes + why, decisions made, failed approaches (even partial), hotspot counter updates, patterns discovered |
| **Invoked by** | `workflow:new`, `workflow:new-feature`, `workflow:improve`, `workflow:bugfix`, `workflow:audit --fix` |
| **Max retry** | 5 attempts per test-fix cycle, then escalation |

---

#### QA

**File:** `core/agents/qa.md`
**Model:** claude-opus-4-6
**Tools:** Read, Write, Edit, Bash, Glob, Grep

| | |
|-|-|
| **Role** | End-to-end validation, acceptance criteria verification, traceability matrix completion, exploratory testing |
| **Input** | Source code, test files, analyst requirements |
| **Output** | `docs/qa/[domain]-qa-report.md` |
| **Briefing reads** | Past bugs with same symptoms, known fragile areas, open findings, component dependencies |
| **Debrief writes** | New bugs found, hotspot risk level updates, requirement status updates to 'verified' |
| **Invoked by** | `workflow:new`, `workflow:new-feature`, `workflow:improve`, `workflow:bugfix` |

---

#### Reviewer

**File:** `core/agents/reviewer.md`
**Model:** claude-opus-4-6
**Tools:** Read, Grep, Glob (READ-ONLY)

| | |
|-|-|
| **Role** | Audit: bugs, security, performance, tech debt, specs/docs drift. Structured P0-P3 output for `--fix` mode |
| **Input** | Source code; optionally specs/, docs/, QA reports |
| **Output** | `docs/reviews/` or `docs/audits/` |
| **Briefing reads** | Full hotspot map, open findings history, component dependencies, past bugs, known patterns |
| **Debrief writes** | New findings (with AUDIT-PX-NNN IDs), hotspot risk reassessment, discovered dependencies |
| **Invoked by** | `workflow:new`, `workflow:new-feature`, `workflow:improve`, `workflow:bugfix`, `workflow:audit` |

---

### Utility Agents (4)

These execute standalone or as gates in the pipeline.

---

#### Feature Evaluator

**File:** `core/agents/feature-evaluator.md`
**Model:** claude-opus-4-6
**Tools:** Read, Write, Grep, Glob, WebSearch, WebFetch

| | |
|-|-|
| **Role** | GO/NO-GO gate: scores features across 7 dimensions (necessity, impact, complexity, alternatives, alignment, risk, timing) |
| **Input** | Idea brief or feature description |
| **Output** | `docs/.workflow/feature-evaluation.md` with GO/CONDITIONAL/NO-GO verdict |
| **Memory** | No structured briefing/debrief (evaluation is self-contained) |
| **Invoked by** | `workflow:new-feature` (always, before analyst) |

Advisory — user always has final say. NO-GO can be overridden.

---

#### Functionality Analyst

**File:** `core/agents/functionality-analyst.md`
**Model:** claude-opus-4-6
**Tools:** Read, Grep, Glob (READ-ONLY)

| | |
|-|-|
| **Role** | Codebase inventory: maps endpoints, services, models, handlers, integrations |
| **Input** | Source code |
| **Output** | `docs/functionalities/FUNCTIONALITIES.md` + per-domain files |
| **Memory** | No structured briefing/debrief (read-only inventory) |
| **Invoked by** | `workflow:functionalities` |

---

#### Codebase Expert

**File:** `core/agents/codebase-expert.md`
**Model:** claude-opus-4-6
**Tools:** Read, Grep, Glob (READ-ONLY)

| | |
|-|-|
| **Role** | Deep comprehension: 6-layer progressive exploration (shape → architecture → domain → data flow → patterns → complexity) |
| **Input** | Source code |
| **Output** | `docs/understanding/PROJECT-UNDERSTANDING.md` |
| **Memory** | No structured briefing/debrief (read-only comprehension) |
| **Invoked by** | `workflow:understand` |

---

#### Wizard UX

**File:** `core/agents/wizard-ux.md`
**Model:** claude-opus-4-6
**Tools:** Read, Write, Grep, Glob, WebSearch, WebFetch

| | |
|-|-|
| **Role** | Wizard/setup flow design for TUI, GUI, Web, CLI contexts |
| **Input** | Feature description + optional `--scope` for target medium |
| **Output** | `specs/[domain]-wizard-flow.md` |
| **Memory** | No structured briefing/debrief (design spec is self-contained) |
| **Invoked by** | `workflow:wizard-ux` |

Produces specifications consumed by architect → test-writer → developer. Does NOT write implementation code.

---

### Meta Agents (2)

These create and audit other agents.

---

#### Role Creator

**File:** `core/agents/role-creator.md`
**Model:** claude-opus-4-6
**Tools:** Read, Write, Grep, Glob, WebSearch, WebFetch

| | |
|-|-|
| **Role** | Designs new agent role definitions: sharp boundaries, detailed processes, output formats, failure handling |
| **Input** | Description of desired role |
| **Output** | `.claude/agents/[name].md` |
| **Invoked by** | `workflow:create-role` |

Uses an 8-phase process with structural completeness verification.

---

#### Role Auditor

**File:** `core/agents/role-auditor.md`
**Model:** claude-opus-4-6
**Tools:** Read, Grep, Glob (READ-ONLY)

| | |
|-|-|
| **Role** | Adversarial audit of role definitions across 12 dimensions (identity, boundaries, prerequisites, process, output, failures, context, rules, anti-patterns, tools, integration, self-audit) |
| **Input** | Agent definition file(s) |
| **Output** | `docs/.workflow/role-audit-[name].md` |
| **Verdicts** | broken → degraded → hardened → deployable |
| **Invoked by** | `workflow:audit-role`, `workflow:create-role` (post-creation audit) |

---

## Extension Agents (7)

### Blockchain Extension (3 agents)

#### Blockchain Network

**File:** `extensions/blockchain/agents/blockchain-network.md`
**Model:** claude-opus-4-6
**Tools:** Read, Write, Bash, Glob, Grep, WebSearch, WebFetch

| | |
|-|-|
| **Role** | Infrastructure architect: P2P networking, node operations, RPC/API, monitoring, security, chain sync |
| **Covers** | Ethereum (Geth, Reth, Nethermind, Erigon + CL clients), Solana, Cosmos/CometBFT, Substrate/Polkadot |
| **Output** | Infrastructure reports, configs, docker-compose, monitoring setups, node guides |
| **Invoked by** | `workflow:blockchain-network` |

---

#### Blockchain Debug

**File:** `extensions/blockchain/agents/blockchain-debug.md`
**Model:** claude-opus-4-6
**Tools:** Read, Write, Bash, Glob, Grep, WebSearch, WebFetch

| | |
|-|-|
| **Role** | Firefighter: diagnoses active connectivity problems using 7-phase methodology (gather → confirm → isolate → diagnose → fix → verify → document) |
| **Handles** | Peer failures, sync stuck, RPC unreachable, Engine API breakdowns, validator missing attestations, network partitions |
| **Output** | `docs/.workflow/blockchain-debug-rca.md` (Root Cause Analysis) |
| **Invoked by** | `workflow:blockchain-debug` |

Read-only diagnostics by default. Destructive actions require explicit user approval.

---

#### Stress Tester

**File:** `extensions/blockchain/agents/stress-tester.md`
**Model:** claude-opus-4-6
**Tools:** Read, Write, Bash, Glob, Grep

| | |
|-|-|
| **Role** | Black-box adversarial testing of blockchain CLI/RPC endpoints |
| **Method** | Uses only CLI commands, curl RPC calls, and log analysis — never modifies code or touches node processes |
| **Output** | Stress test reports with crashes, corrupt states, protocol violations |
| **Invoked by** | `workflow:stress-test` |

---

### OMEGA Extension (2 agents)

#### OMEGA Topology Architect

**File:** `extensions/omega/agents/omega-topology-architect.md`
**Model:** claude-opus-4-6
**Tools:** Read, Write, Grep, Glob

| | |
|-|-|
| **Role** | Maps business domains to OMEGA primitives (projects, skills, topologies, schedules, heartbeats) |
| **Output** | `~/.omega/projects/<name>/ROLE.md` and related config files |
| **Invoked by** | `workflow:omega-setup` |

Proposes minimum viable configurations and executes only after human approval.

---

#### Skill Creator

**File:** `extensions/omega/agents/skill-creator.md`
**Model:** claude-opus-4-6
**Tools:** Read, Write, Glob, Grep, Bash, WebSearch, WebFetch

| | |
|-|-|
| **Role** | Creates OMEGA skill definitions: researches domain tools, CLIs, APIs, produces `SKILL.md` with frontmatter, instructions, supporting resources |
| **Output** | `~/.omega/skills/<name>/SKILL.md` |
| **Invoked by** | `workflow:omega-setup` (indirect) or standalone |

---

### C2C Protocol Extension (2 agents)

#### Proto Auditor

**File:** `extensions/c2c-protocol/agents/proto-auditor.md`
**Model:** claude-opus-4-6
**Tools:** Read, Grep, Glob (READ-ONLY)

| | |
|-|-|
| **Role** | Audits protocol specifications across 12 dimensions at 3 levels (protocol, enforcement, self). Adversarial stance. |
| **Output** | `c2c-protocol/audits/audit-[protocol]-[date].md` |
| **Invoked by** | `workflow:proto-audit` |

---

#### Proto Architect

**File:** `extensions/c2c-protocol/agents/proto-architect.md`
**Model:** claude-opus-4-6
**Tools:** Read, Write, Edit, Grep, Glob

| | |
|-|-|
| **Role** | Protocol improvement: consumes audit reports, generates structured patches via 6-step pipeline |
| **Output** | `c2c-protocol/patches/patches-[protocol]-[date].md` |
| **Invoked by** | `workflow:proto-improve` |
