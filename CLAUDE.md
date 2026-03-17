# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About This Repository

This is **OMEGA Ω** — a multi-agent orchestration toolkit for Claude Code. It consists of core agents, commands, an institutional memory layer (SQLite), and optional extension packs. All designed to be **deployed into target projects** via `setup.sh`.

### Development

There is no build system or runtime. To test changes:
1. Edit agent/command files under `core/` or `extensions/`
2. Deploy to a target project: `bash scripts/setup.sh [--ext=name]` (run from the target project directory)
3. Run the workflow commands in the target project via Claude Code

### Key Structure
- `core/agents/` — 14 core agent definitions
- `core/commands/` — 15 core workflow commands
- `core/protocols/` — Detailed protocol reference files (deployed to `.claude/protocols/`)
- `core/db/` — SQLite schema and query templates
- `core/hooks/` — Automation hooks (deployed to `.claude/hooks/`)
- `extensions/` — Domain-specific packs (blockchain, c2c-protocol)
- `scripts/setup.sh` — Deploys core + extensions to target projects

For full inventory, see `docs/agent-inventory.md`, `docs/architecture.md`, and `docs/setup-guide.md`.

### Rules for This Repository
- **CLAUDE.md MUST stay under 10,000 characters.** Never inline templates, SQL examples, or detailed procedures. Put them in `core/protocols/` and reference with a pointer. This rule applies to agent and command files too — prefer pointers over inline content.
- **Always update `docs/` and `README.md`** after ANY modification to the toolkit
- **Always commit and push** after completing any modification
- Use conventional commit messages (`feat:`, `fix:`, `docs:`, `refactor:`)
- Source files are in `core/` and `extensions/`, NOT in `.claude/`
- **NEVER copy CLAUDE.md** to target projects — setup.sh extracts the workflow rules section below

---

# Workflow Rules (copied to target projects)

Everything below this line defines the workflow behavior when this CLAUDE.md is installed in a target project.

---

# OMEGA Ω

## Philosophy
This project uses OMEGA, a multi-agent workflow designed to produce the highest quality code possible.
Each agent has a specific role and the code passes through multiple validation layers before being considered complete.
Every agent reads from and writes to a shared institutional memory (SQLite) — no agent acts alone, without backpressure.

## Source of Truth Hierarchy
1. **Codebase** — the ultimate source of truth. Always trust code over documentation.
2. **`.claude/memory.db`** — institutional memory. Accumulated decisions, failed approaches, hotspots, findings across all sessions.
3. **specs/** — technical specifications per domain. `specs/SPECS.md` is the master index.
4. **docs/** — user-facing and developer documentation. `docs/DOCS.md` is the master index.

When specs or docs conflict with the codebase, the codebase wins. Agents must flag the discrepancy and update specs/docs accordingly.

## Institutional Memory

Every workflow reads from and writes to `.claude/memory.db`. **This protocol is not optional.**

**Full protocol reference:** Read `.claude/protocols/memory-protocol.md` for complete briefing queries, incremental logging templates, close-out procedures, self-learning, and pipeline tracking.

**Core rules (always in effect):**
- **DB Detection**: `test -f .claude/memory.db` at session/workflow start. If missing, skip memory ops gracefully.
- **Briefing before action**: Every agent queries memory.db (hotspots, failed approaches, findings, decisions, patterns, bugs) before starting work.
- **Log incrementally**: Write to memory.db immediately after each significant action. Never batch for the end — context compaction loses batched entries.
- **Self-score every action**: Rate significant actions (-1/0/+1) immediately after completing them.
- **Close-out when done**: Verify completeness, distill lessons from patterns (3+ similar outcomes → lesson).
- **Pipeline tracking**: Every `/workflow:*` command registers a `workflow_runs` entry at start, updates status at end.
- **Non-pipeline work**: Even informal work gets a `workflow_runs` entry with type `'manual'`.
- **Error tolerance**: If sqlite3 fails, log the error and continue working. Never block work for a DB failure.

## Identity

The briefing hook may inject an identity block. **Full reference:** `.claude/protocols/identity.md`

**Core rule:** Protocol always overrides identity. Identity influences communication style, not functional behavior. Experience levels: beginner/intermediate/advanced. Communication styles: verbose/balanced/terse.

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
11. **60% context budget** — every agent must complete its work within 60% of the context window
12. **Briefing before action** — every agent queries memory.db before starting work
13. **Log incrementally during work** — every agent writes to memory.db immediately after each significant action
14. **Self-score every action** — every agent rates its own significant actions (-1/0/+1) immediately
15. **Distill lessons from patterns** — when 3+ outcomes share a theme, distill into a permanent lesson

## Fail-Safe Controls

**Full reference:** `.claude/protocols/fail-safes.md`

**Core rules:** Prerequisite gates (every agent verifies upstream output exists). Iteration limits (QA↔Dev: 3, Reviewer↔Dev: 2, Audit fix: 5). Error recovery saves state to `docs/.workflow/chain-state.md`. Developer max 5 retries per module.

## Context Efficiency (ENFORCED)

**Full reference:** `.claude/protocols/context-budget.md`

**This file (CLAUDE.md) MUST stay under 10,000 characters.** It is loaded into every conversation and every subagent. Every character here costs tokens in every session. The same principle applies to agent files, command files, and any file that is auto-loaded.

**Rules:**
- **NEVER inline detailed templates, SQL examples, scoring tables, or step-by-step procedures into CLAUDE.md.** Put them in `core/protocols/` (deployed to `.claude/protocols/`) and reference them with a one-line pointer.
- **NEVER inline detailed protocols into agent files.** Agent files should contain the agent's role, rules, and a pointer to `.claude/protocols/memory-protocol.md` for the memory protocol. Not the full SQL templates.
- **NEVER duplicate content across files.** If two agents need the same protocol, both reference the same protocol file. Do not copy-paste protocol sections.
- **Before adding content to any auto-loaded file** (CLAUDE.md, agent .md, command .md), ask: "Will every session need this, or can it be loaded on demand?" If on-demand, put it in a protocol file or a doc file and reference it.
- **Prefer pointers over inline content.** A one-line reference like `Read .claude/protocols/X.md` costs ~20 tokens. An inlined protocol costs 2,000+.
- **60% context budget per agent.** Read indexes first. Query memory.db before reading files. Scope narrowing via `--scope`. Chunk large operations by milestone/domain.
- **Never read the entire codebase at once** — always scope to the relevant area.

## Traceability Chain
```
Discovery → Analyst (REQ-XXX-001) → Architect (module map) → Test Writer (TEST-XXX-001) → Developer → QA (acceptance criteria) → Reviewer (completeness)
```

## Project Layout
```
root-project/
├── backend/              ← Backend source code
├── frontend/             ← Frontend (if applicable)
├── specs/                ← Technical specifications
├── docs/                 ← Documentation
├── CLAUDE.md             ← Workflow rules
└── .claude/
    ├── agents/           ← Agent definitions
    ├── commands/         ← Command definitions
    ├── protocols/        ← Protocol reference files (loaded on-demand)
    ├── memory.db         ← Institutional memory (SQLite)
    └── db-queries/       ← Query reference files
```

## Conventions
- Preferred language: Rust (or whatever the user defines)
- Tests: alongside code or in `backend/tests/` (or `frontend/tests/`)
- Commits: conventional (feat:, fix:, docs:, refactor:, test:)
- Branches: feature/, bugfix/, hotfix/
