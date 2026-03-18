# FUNCTIONALITIES.md — Codebase Functionality Inventory

> Master index of all functionalities in OMEGA Ω.
> Generated: 2026-02-28

## Summary

| Metric | Value |
|--------|-------|
| Total domains analyzed | 7 |
| Total functionalities | 68 |
| Source files (traditional) | 0 (1 Python POC, 1 Bash script) |
| Markdown files | 42 |
| Dead code / stale items | 0 (all resolved in this session) |

## Domains

| Domain | File | Functionalities | Description |
|--------|------|-----------------|-------------|
| Agent Definitions | [agents-functionalities.md](agents-functionalities.md) | 14 | Agent role definitions with YAML frontmatter |
| Command Definitions | [commands-functionalities.md](commands-functionalities.md) | 14 | Slash command orchestrators chaining agents |
| Setup Script | [setup-functionalities.md](setup-functionalities.md) | 8 | Deployment tool for copying toolkit to target projects |
| C2C Protocol | [c2c-protocol-functionalities.md](c2c-protocol-functionalities.md) | 4 | Formal protocol specifications for agent-to-agent communication |
| POC C2C Protocol | [poc-c2c-functionalities.md](poc-c2c-functionalities.md) | 11 | Proof-of-concept multi-round agent conversation |
| Documentation | [docs-functionalities.md](docs-functionalities.md) | 6 | Reference docs and workflow audit reports |
| Root Configuration | [root-config-functionalities.md](root-config-functionalities.md) | 3 | CLAUDE.md, README.md, .gitignore |

## Cross-Domain Dependencies

### Pipeline Chains (Command → Agent sequences)

```
omega:new               → discovery → analyst → architect → test-writer → developer → QA → reviewer
omega:new-feature       → (discovery) → feature-evaluator → analyst → architect → test-writer → developer → QA → reviewer
omega:improve-functionality → analyst → test-writer → developer → QA → reviewer
omega:bugfix            → analyst → test-writer → developer → QA → reviewer
omega:audit             → reviewer
omega:docs              → architect
omega:sync              → architect
omega:functionalities   → functionality-analyst
omega:understand        → codebase-expert
omega:c2c               → c2c-writer ↔ c2c-auditor (multi-round loop, max 20 rounds)
omega:proto-audit       → proto-auditor
omega:proto-improve     → proto-architect
omega:create-role       → role-creator → role-auditor → auto-remediation (max 2 cycles)
omega:audit-role        → role-auditor
```

### Data Flow (File artifacts)

```
Discovery → docs/.workflow/idea-brief.md → Feature Evaluator, Analyst
Feature Evaluator → docs/.workflow/feature-evaluation.md → omega-new-feature (gate decision)
Analyst → specs/[domain]-requirements.md → Architect, Test Writer, Developer, QA
Architect → specs/[domain]-architecture.md → Test Writer, Developer
Test Writer → test files → Developer
Developer → source code → QA, Reviewer
QA → docs/qa/[domain]-qa-report.md → Reviewer
Reviewer → docs/reviews/ or docs/audits/ reports
Role Creator → .claude/agents/[name].md → Role Auditor
Proto-Auditor → c2c-protocol/audits/ → Proto-Architect
Proto-Architect → c2c-protocol/patches/ → (operator review)
```
