# Agent Definitions — Functionality Inventory

> Domain: `.claude/agents/` (14 agent definitions)
> Generated: 2026-02-28

## Overview

All agent definitions are Markdown files with YAML frontmatter (`name`, `description`, `tools`, `model`) and a body defining the agent's identity, process, output format, rules, and failure handling.

## Agents

| # | Agent | File | Lines | Model | Tools | Read-Only | Primary Output |
|---|-------|------|-------|-------|-------|-----------|----------------|
| 1 | Discovery | `.claude/agents/discovery.md` | 1-275 | Opus | Read, Grep, Glob, WebFetch, WebSearch | No | `docs/.workflow/idea-brief.md` |
| 2 | Analyst | `.claude/agents/analyst.md` | 1-191 | Opus | Read, Grep, Glob, WebFetch, WebSearch | No | `specs/[domain]-requirements.md` |
| 3 | Architect | `.claude/agents/architect.md` | 1-207 | Opus | Read, Write, Edit, Grep, Glob | No | `specs/[domain]-architecture.md` |
| 4 | Test Writer | `.claude/agents/test-writer.md` | 1-220 | Opus | Read, Write, Edit, Bash, Glob, Grep | No | Test files + traceability update |
| 5 | Developer | `.claude/agents/developer.md` | 1-121 | Opus | Read, Write, Edit, Bash, Glob, Grep | No | Source code + specs/docs updates + commits |
| 6 | QA | `.claude/agents/qa.md` | 1-307 | Opus | Read, Write, Edit, Bash, Glob, Grep | No | `docs/qa/[domain]-qa-report.md` |
| 7 | Reviewer | `.claude/agents/reviewer.md` | 1-164 | Opus | Read, Grep, Glob | Yes | Review/audit report |
| 8 | Functionality Analyst | `.claude/agents/functionality-analyst.md` | 1-151 | Opus | Read, Grep, Glob | Yes | `docs/functionalities/FUNCTIONALITIES.md` |
| 9 | Codebase Expert | `.claude/agents/codebase-expert.md` | 1-281 | Opus | Read, Grep, Glob | Yes | `docs/understanding/PROJECT-UNDERSTANDING.md` |
| 10 | Proto-Auditor | `.claude/agents/proto-auditor.md` | 1-416 | Opus | Read, Grep, Glob | Yes | `c2c-protocol/audits/audit-[protocol]-[date].md` |
| 11 | Proto-Architect | `.claude/agents/proto-architect.md` | 1-219 | Opus | Read, Write, Edit, Grep, Glob | No | `c2c-protocol/patches/patches-[protocol]-[date].md` |
| 12 | Role Creator | `.claude/agents/role-creator.md` | 1-335 | Opus | Read, Write, Grep, Glob, WebSearch, WebFetch | No | `.claude/agents/[name].md` |
| 13 | Role Auditor | `.claude/agents/role-auditor.md` | 1-495 | Opus | Read, Grep, Glob | Yes | `docs/.workflow/role-audit-[name].md` |
| 14 | Feature Evaluator | `.claude/agents/feature-evaluator.md` | 1-310 | Opus | Read, Write, Grep, Glob, WebSearch, WebFetch | No | `docs/.workflow/feature-evaluation.md` |

## Agent Architecture Patterns

Every agent follows a consistent structure:
- **YAML frontmatter**: name, description, tools, model
- **Identity statement**: core responsibility
- **Prerequisite Gate**: required upstream inputs
- **Directory Safety**: directories created before writing
- **Source of Truth**: ordered list of what to read
- **Context Management**: strategy for protecting context window
- **Process**: step-by-step methodology with named phases
- **Output**: template and save location
- **Rules**: hard constraints
- **Anti-Patterns**: explicit "don't do this" list
- **Failure Handling**: scenario-response table

## Internal Dependencies

```
Discovery ──→ docs/.workflow/idea-brief.md ──→ Feature Evaluator, Analyst
Feature Evaluator ──→ docs/.workflow/feature-evaluation.md ──→ omega-new-feature (gate)
Analyst ──→ specs/[domain]-requirements.md ──→ Architect, Test Writer, Developer, QA
Architect ──→ specs/[domain]-architecture.md ──→ Test Writer, Developer
Test Writer ──→ test files ──→ Developer
Developer ──→ source code ──→ QA, Reviewer
QA ──→ docs/qa/ reports ──→ Reviewer
Role Creator ──→ .claude/agents/[name].md ──→ Role Auditor
Proto-Auditor ──→ c2c-protocol/audits/ ──→ Proto-Architect
```
