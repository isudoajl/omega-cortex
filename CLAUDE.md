# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About This Repository

This is a **multi-agent workflow toolkit** for Claude Code — not an application. It consists of agent definitions (`.claude/agents/*.md`), slash commands (`.claude/commands/*.md`), a setup script, and the CLAUDE.md rules file. All of these are designed to be **copied into target projects** to enable structured TDD workflows.

### Development

There is no build system, test suite, or runtime. To test changes:
1. Edit agent/command files in this repo
2. Copy them to a target project: `bash scripts/setup.sh` (run from the target project directory)
3. Run the workflow commands in the target project via Claude Code

The setup script (`scripts/setup.sh`) copies agents and commands into the current directory. It creates `specs/` and `docs/` scaffolding if missing and never overwrites existing files (except agents and commands which are always overwritten). It does **not** copy CLAUDE.md — each target project maintains its own.

### Architecture

**Agents** (`.claude/agents/`) — subagent definitions with YAML frontmatter (`name`, `description`, `tools`, `model`):
- `discovery.md` (claude-opus-4-6) — pre-pipeline conversational agent: takes raw ideas, discusses with the user, challenges the concept, produces an Idea Brief. The only agent with extended user back-and-forth. Outputs `docs/.workflow/idea-brief.md`
- `analyst.md` (claude-opus-4-6) — full BA: requirements with acceptance criteria, MoSCoW priorities, traceability matrix, impact analysis. Flags and fixes stale specs before writing new requirements. Outputs `specs/[domain]-requirements.md`
- `architect.md` (claude-opus-4-6) — designs architecture with failure modes, security, performance budgets. Maintains specs/ and docs/. Outputs `specs/[domain]-architecture.md`
- `test-writer.md` (claude-opus-4-6) — writes failing tests before code (TDD red phase), priority-driven (Must first), references requirement IDs for traceability. Flags specs inconsistencies when tests reveal undocumented behavior
- `developer.md` (claude-opus-4-6) — implements minimum code to pass tests, commits per module. Updates relevant specs/docs when implementation changes documented behavior
- `qa.md` (claude-opus-4-6) — end-to-end validation, acceptance criteria verification, traceability matrix completion, exploratory testing. Verifies specs/docs accuracy against actual behavior and flags drift
- `reviewer.md` (claude-opus-4-6, read-only) — audits for bugs/security/performance/drift, outputs review reports
- `functionality-analyst.md` (claude-opus-4-6, read-only) — maps what the codebase does, outputs structured functionality inventory
- `codebase-expert.md` (claude-opus-4-6, read-only) — deep codebase comprehension: progressively explores projects of any size, builds holistic understanding (architecture, domain, data flows, patterns, risk). Outputs `docs/understanding/PROJECT-UNDERSTANDING.md`
- `proto-auditor.md` (claude-opus-4-6, read-only) — audits protocol specifications across 12 dimensions at 3 levels (protocol, enforcement, self). Adversarial stance. Outputs structured audit findings to `c2c-protocol/audits/`
- `proto-architect.md` (claude-opus-4-6) — protocol improvement specialist. Consumes audit reports from proto-auditor, generates structured patches through a 6-step pipeline. Outputs patch reports to `c2c-protocol/patches/`
- `role-creator.md` (claude-opus-4-6) — meta-agent specialized in designing other agents. Researches the role's domain, studies existing agents for consistency, and produces comprehensive role definitions with sharp boundaries, detailed processes, and complete failure handling. Outputs `.claude/agents/[name].md`
- `role-auditor.md` (claude-opus-4-6, read-only) — adversarial auditor for role definitions. Audits across 12 dimensions at 2 levels (role definition, self-audit). Assumes every role is broken until proven safe. Outputs structured findings with severity classification and deployment verdicts to `docs/.workflow/role-audit-[name].md`
- `feature-evaluator.md` (claude-opus-4-6) — feature gate agent: scores proposed features across 7 dimensions (necessity, impact, complexity cost, alternatives, alignment, risk, timing) and produces a GO/NO-GO/CONDITIONAL verdict. Advisory — user always has final say. Automatically invoked in workflow-new-feature before the Analyst. Outputs `docs/.workflow/feature-evaluation.md`

**Commands** (`.claude/commands/`) — slash command orchestrators that chain agents in sequence:
- `workflow-new.md` — full chain (discovery + all 6 agents) for greenfield projects
- `workflow-new-feature.md` — full chain for existing projects (discovery conditional on vague descriptions, feature-evaluator gate before analyst)
- `workflow-improve-functionality.md` — no architect; analyst → test-writer → developer → QA → reviewer
- `workflow-bugfix.md` — reduced chain with bug reproduction test + QA validation
- `workflow-audit.md` — reviewer only (read-only analysis)
- `workflow-docs.md` — architect only (documentation generation)
- `workflow-sync.md` — architect only (drift detection and fix)
- `workflow-functionalities.md` — functionality-analyst only (codebase functionality inventory)
- `workflow-understand.md` — codebase-expert only (deep project comprehension)
- `workflow-c2c.md` — multi-round C2C protocol POC: writer ↔ auditor iterate until certification (max 5 rounds)
- `workflow-proto-audit.md` — proto-auditor only (protocol specification audit, 12 dimensions, 3 levels)
- `workflow-proto-improve.md` — proto-architect only (protocol improvement from audit findings, 6-step pipeline)
- `workflow-create-role.md` — role-creator → role-auditor → auto-remediation (designs agent roles, audits them adversarially, fixes findings automatically; max 2 remediation cycles)
- `workflow-audit-role.md` — role-auditor only (adversarial audit of role definitions, 12 dimensions, 2 levels). Accepts `--scope` to limit to specific dimensions

**POC Agents** (`poc/c2c-protocol/`) — standalone agent prompts for the C2C protocol experiment:
- `c2c-writer.md` — Agent A: code writer + doc author, operates under C2C protocol with confidence/source tags
- `c2c-auditor.md` — Agent B: code auditor + fact-checker, issues certification when code is production-ready

All commands accept `--scope="area"` to limit context window usage. Agent model assignments are set in the YAML frontmatter.

### Maintaining README.md
**Always update `README.md`** when any of the following change:
- An agent is added, removed, or modified (`.claude/agents/*.md`)
- A command is added, removed, or modified (`.claude/commands/*.md`)
- The setup script behavior changes (`scripts/setup.sh`)

The README must stay in sync with the actual agents, commands, and project structure at all times.

### Git After Every Change
**Always commit and push** after completing any modification to the toolkit (agents, commands, setup script, CLAUDE.md, README.md). Use conventional commit messages (`feat:`, `fix:`, `docs:`, `refactor:`) and push to the remote immediately.

---

# Workflow Rules (copied to target projects)

Everything below this line defines the workflow behavior when this CLAUDE.md is installed in a target project.

---

# Claude Code Quality Workflow

## Philosophy
This project uses a multi-agent workflow designed to produce the highest quality code possible.
Each agent has a specific role and the code passes through multiple validation layers before being considered complete.

## Source of Truth Hierarchy
1. **Codebase** — the ultimate source of truth. Always trust code over documentation.
2. **specs/** — technical specifications per domain. `specs/SPECS.md` is the master index linking to per-domain spec files (e.g. `specs/auth.md`, `specs/memory-store.md`).
3. **docs/** — user-facing and developer documentation. `docs/DOCS.md` is the master index linking to topic guides.

When specs or docs conflict with the codebase, the codebase wins. Agents must flag the discrepancy and update specs/docs accordingly.

## Main Workflow

```
Raw Idea ("build a CRM tool")
  → Discovery (explores, challenges, clarifies the IDEA with the user)
  → Idea Brief (clear, validated concept)
  → Feature Evaluator (GO/NO-GO gate: scores necessity, impact, complexity, alternatives, alignment, risk, timing)
  → Analyst (BA: requirements, acceptance criteria, MoSCoW priorities, traceability)
  → Architect (design with failure modes, security, performance budgets)
  → Test Writer (TDD by priority: Must first, then Should, then Could)
  → Developer (implements module by module)
  → Compiler (automatic validation)
  → QA (end-to-end validation, acceptance criteria verification, exploratory testing)
  → Reviewer (audits code, verifies specs/docs accuracy)
  → Git (automatic versioning)
```

## Traceability Chain
Every requirement flows through the entire pipeline via unique IDs:
```
Discovery validates the idea → Analyst assigns REQ-XXX-001 → Architect maps to module → Test Writer writes TEST-XXX-001 → Developer implements → QA verifies acceptance criteria → Reviewer audits completeness
```

## Global Rules

1. **NEVER write code without tests first** (strict TDD)
2. **NEVER assume** — if something is unclear, the analyst must ask
3. **Module by module** — do not implement everything at once
4. **Document before coding** — architecture is defined first
5. **Every assumption must be explicit** — technical + human-readable summary
6. **Codebase is king** — when in doubt, read the actual code
7. **Keep specs/ and docs/ in sync** — every code change must update relevant specs and docs
8. **Every requirement has acceptance criteria** — "it should work" is not acceptable
9. **Every requirement has a priority** — Must/Should/Could/Won't (MoSCoW)
10. **Every requirement is traceable** — from ID through tests to implementation

## Fail-Safe Controls

The workflow enforces guardrails at every level to prevent silent failures, infinite loops, and cascading garbage.

### Prerequisite Gates
Every agent that receives upstream output verifies its input exists before proceeding. If required input is missing, the agent **STOPS** with a clear error message identifying what's missing and which upstream agent failed.

| Agent | Required Input |
|-------|---------------|
| Analyst (after discovery) | `docs/.workflow/idea-brief.md` |
| Architect | Analyst requirements file in `specs/` |
| Test Writer | Architect design + Analyst requirements in `specs/` |
| Developer | Test files must exist |
| QA | Source code + test files must exist |
| Reviewer | Source code must exist |

### Iteration Limits
Multi-step commands enforce maximum iteration counts to prevent infinite loops:
- **QA ↔ Developer loops:** Maximum **3 iterations**
- **Reviewer ↔ Developer loops:** Maximum **2 iterations**

If the limit is reached, the workflow STOPS and reports remaining issues to the user for a human decision.

### Inter-Step Output Validation
Multi-step commands verify that each agent produced its expected output file before invoking the next agent. If output is missing, the chain halts with a clear report of which step failed.

### Error Recovery
If any agent fails mid-chain, the workflow saves chain state to `docs/.workflow/chain-state.md` documenting which steps completed, which failed, and what remains. The user can resume from the failed step.

### Directory Safety
Every agent that writes output files verifies target directories exist before writing. If a directory is missing, the agent creates it. This prevents silent file-write failures.

### Developer Max Retry
The developer has a maximum of **5 attempts** per test-fix cycle for a single module. If tests still fail after 5 attempts, the developer stops and escalates for human review or architecture reassessment.

### Language-Agnostic Patterns
Test-writer and reviewer adapt their patterns to the project's language (detected from config files, architect design, or existing source). No agent assumes a specific language.

## Context Window Management

### Critical Rules
- **NEVER read the entire codebase at once** — always scope to the relevant area
- **Read indexes first** — start with `specs/SPECS.md` or `docs/DOCS.md` to identify which files matter
- **Scope narrowing** — all commands accept an optional scope parameter to limit the area of work
- **Chunking** — for large operations (audit, sync, docs), work one milestone/domain at a time

### Agent Scoping Strategy
1. Read the master index (`specs/SPECS.md`) to understand the project layout
2. Identify which domains/milestones are relevant to the task
3. Read ONLY the relevant spec files and code files
4. If you feel context getting heavy, stop and summarize what you've learned so far before continuing

### Scope Parameter
All workflow commands accept an optional scope to limit context usage:
```
/workflow:new-feature "add retry logic" --scope="omega-providers"
/workflow:audit --scope="milestone 3: omega-core"
/workflow:sync --scope="omega-memory"
/workflow:bugfix "scheduler crash" --scope="backend/src/gateway/scheduler.rs"
```

When no scope is provided, the analyst determines the minimal scope needed based on the task description.

### When Approaching Context Limits
If an agent notices it's consuming too much context:
1. **Summarize** what has been learned so far into a temporary file at `docs/.workflow/[agent]-[task]-summary.md`
2. **Delegate** remaining work by spawning a continuation subagent that reads the summary
3. **Never silently degrade** — if you can't do a thorough job, say so and suggest splitting the task

## Project Layout

```
root-project/
├── backend/              ← Backend source code (Rust or preferred language)
├── frontend/             ← Frontend source code (if applicable)
├── specs/                ← Technical specifications (at project root)
├── docs/                 ← Documentation (at project root)
├── CLAUDE.md             ← Workflow rules
└── .claude/              ← Agents and commands
```

Code lives in `backend/` (and optionally `frontend/`). Specs and docs remain at the project root.
Agents must be aware of this structure when scoping reads and writes.

## Documentation Structure

### specs/ (technical specifications)
```
specs/
├── SPECS.md              ← Master index (links to all domain specs)
├── core-config.md        ← Per-domain spec files
├── core-context.md
├── memory-store.md
├── channels-telegram.md
└── ...
```
- One spec file per domain/module/file
- SPECS.md must be updated when new specs are added
- Specs describe WHAT the code does technically

### docs/ (documentation)
```
docs/
├── DOCS.md               ← Master index (links to all doc files)
├── quickstart.md
├── architecture.md
├── configuration.md
└── ...
```
- Topic-oriented guides and references
- DOCS.md must be updated when new docs are added
- Docs describe HOW to use/understand the system

## Usage Modes

### New project from scratch
```
/workflow:new "description of the idea"
```
Full chain: discovery → analyst → architect → test-writer → developer → QA → reviewer. Discovery explores the idea with the user first.

### Add feature to existing project
```
/workflow:new-feature "description of the feature" [--scope="area"]
```
Full chain: (discovery if vague) → **feature-evaluator** (GO/NO-GO gate) → analyst → architect → test-writer → developer → QA → reviewer. Discovery is invoked when the feature description is vague; skipped for specific, well-scoped features. The feature-evaluator always runs to assess whether the feature is worth building before committing pipeline resources.

### Improve existing code
```
/workflow:improve-functionality "description of the improvement" [--scope="area"]
```
Reduced chain (no architect): analyst → test-writer (regression) → developer (refactor) → QA → reviewer

### Fix a bug
```
/workflow:bugfix "description of the bug" [--scope="file or module"]
```
Reduced chain: analyst → test-writer (reproduces the bug) → developer → QA → reviewer

### Audit existing code
```
/workflow:audit [--scope="milestone or module"]
```
Reviewer only: looks for vulnerabilities, technical debt, performance issues, and specs/docs drift.

### Document existing project
```
/workflow:docs [--scope="milestone or module"]
```
Architect only: reads the codebase, generates/updates specs/ and docs/.

### Sync specs and docs with codebase
```
/workflow:sync [--scope="milestone or module"]
```
Architect only: reads the codebase, compares against specs/ and docs/, flags drift, updates outdated files.

### Map codebase functionalities
```
/workflow:functionalities [--scope="module or area"]
```
Functionality-analyst only: reads the codebase and produces a structured inventory of all functionalities (endpoints, services, models, handlers, etc.).

### Understand a codebase
```
/workflow:understand [--scope="module or area"]
```
Codebase-expert only: deep comprehension of a project of any size. Progressively explores through 6 layers (shape → architecture → domain → data flow → patterns → complexity). Produces a holistic understanding document at `docs/understanding/`.

### Create a new agent role
```
/workflow:create-role "description of the desired role"
```
Role-creator only: designs comprehensive agent role definitions with sharp boundaries, detailed processes, output formats, and complete failure handling. Researches the role's domain and validates against existing agents.

### Audit an agent role definition
```
/workflow:audit-role ".claude/agents/[name].md" [--scope="dimensions"]
/workflow:audit-role "all"
```
Role-auditor only: adversarial audit of role definitions across 12 dimensions (identity, boundaries, prerequisites, process, output, failures, context, rules, anti-patterns, tools, integration, self-audit). Assumes broken until proven safe. Scope accepts dimension ranges (`D1-D3`), names (`boundaries,tools`), or both. Verdicts: broken → degraded → hardened → deployable.

## Conventions
- Preferred language: Rust (or whatever the user defines)
- Tests: alongside code or in `backend/tests/` (or `frontend/tests/`) folder
- Commits: conventional (feat:, fix:, docs:, refactor:, test:)
- Branches: feature/, bugfix/, hotfix/
