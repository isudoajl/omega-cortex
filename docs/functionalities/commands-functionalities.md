# Command Definitions — Functionality Inventory

> Domain: `.claude/commands/` (14 slash command orchestrators)
> Generated: 2026-02-28

## Overview

All command definitions are Markdown files with YAML frontmatter (`name`, `description`) and a body defining the orchestration chain, fail-safe controls, iteration limits, and inter-step output validation.

## Commands

| # | Command | File | Type | Agents Used | Scope Support |
|---|---------|------|------|-------------|---------------|
| 1 | `omega:new` | `.claude/commands/omega-new.md` | Full Chain | discovery → analyst → architect → test-writer → developer → QA → reviewer | Yes |
| 2 | `omega:new-feature` | `.claude/commands/omega-new-feature.md` | Full Chain | (discovery) → feature-evaluator → analyst → architect → test-writer → developer → QA → reviewer | Yes |
| 3 | `omega:improve-functionality` | `.claude/commands/omega-improve-functionality.md` | Reduced Chain | analyst → test-writer → developer → QA → reviewer | Yes |
| 4 | `omega:bugfix` | `.claude/commands/omega-bugfix.md` | Reduced Chain | analyst → test-writer → developer → QA → reviewer | Yes |
| 5 | `omega:audit` | `.claude/commands/omega-audit.md` | Single Agent | reviewer | Yes |
| 6 | `omega:docs` | `.claude/commands/omega-docs.md` | Single Agent | architect | Yes |
| 7 | `omega:sync` | `.claude/commands/omega-sync.md` | Single Agent | architect | Yes |
| 8 | `omega:functionalities` | `.claude/commands/omega-functionalities.md` | Single Agent | functionality-analyst | Yes |
| 9 | `omega:understand` | `.claude/commands/omega-understand.md` | Single Agent | codebase-expert | Yes |
| 10 | `omega:c2c` | `.claude/commands/omega-c2c.md` | Multi-Round Loop | c2c-writer ↔ c2c-auditor (max 20 rounds) | No |
| 11 | `omega:proto-audit` | `.claude/commands/omega-proto-audit.md` | Single Agent | proto-auditor | Yes (dimensions) |
| 12 | `omega:proto-improve` | `.claude/commands/omega-proto-improve.md` | Single Agent | proto-architect | Yes (findings) |
| 13 | `omega:create-role` | `.claude/commands/omega-create-role.md` | Three-Phase Chain | role-creator → role-auditor → auto-remediation (max 2 cycles) | No |
| 14 | `omega:audit-role` | `.claude/commands/omega-audit-role.md` | Single Agent | role-auditor | Yes (dimensions) |

## Shared Fail-Safe Controls

All multi-step commands share these controls:
- **Iteration Limits**: QA ↔ Developer max 3 iterations; Reviewer ↔ Developer max 2 iterations
- **Inter-Step Output Validation**: Each step verifies the previous step produced expected output files
- **Error Recovery**: Failed chains save state to `docs/.workflow/chain-state.md`
- **Scope Parameter**: All commands accept `--scope` to limit context window usage
