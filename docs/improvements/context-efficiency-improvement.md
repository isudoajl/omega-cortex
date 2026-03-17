# Context Efficiency Improvement

## Current Behavior (to preserve)
- CLAUDE.md provides all workflow rules to Claude Code sessions
- Agent files contain complete institutional memory protocol
- setup.sh deploys CLAUDE.md workflow rules section to target projects
- All information is available to agents when they need it

## What Will Be Improved

### REQ-CTX-001: Slim CLAUDE.md (Must)
**Current**: 42,766 chars (772 lines), exceeds 40k recommended limit
**Target**: ~12,000 chars (~200 lines)
**Acceptance**: CLAUDE.md under 15,000 chars with all rules preserved as pointers

### REQ-CTX-002: Extract protocols to on-demand files (Must)
**Current**: 22,767 chars of detailed protocol (SQL templates, scoring guides, iteration tables) inline in CLAUDE.md
**Target**: Extracted to `core/protocols/*.md`, deployed to `.claude/protocols/` in target projects
**Acceptance**: 4 protocol files created, all content from CLAUDE.md preserved in them

### REQ-CTX-003: Slim agent memory protocol sections (Must)
**Current**: 30,291 chars of duplicated memory protocol across 8 agent files
**Target**: Replace with ~200 char reference to `.claude/protocols/memory-protocol.md`
**Acceptance**: Each agent's memory section reduced to a pointer; no protocol content lost

### REQ-CTX-004: Update setup.sh to deploy protocols (Must)
**Current**: setup.sh copies agents, commands, hooks, DB
**Target**: Also copies `core/protocols/*.md` to `.claude/protocols/` in target projects
**Acceptance**: `setup.sh` deploys protocol files; idempotent

### REQ-CTX-005: Slim toolkit header section (Should)
**Current**: 12,649 chars of repo structure trees, agent tables, command tables
**Target**: ~3,000 chars with pointers to directories and docs
**Acceptance**: All derivable information removed, key rules preserved

## What Will NOT Change
- The actual rules and protocols (just where they live)
- Agent behavior (they read protocols on-demand instead of having them inline)
- setup.sh deployment targets and options
- Memory DB schema or queries
- Hook behavior
- Command files (they orchestrate, not execute protocol)

## Impact Analysis
- **setup.sh**: Must add protocol directory copying (low risk, follows existing pattern)
- **All 14 agent files**: 8 agents need memory section replaced with reference
- **Target projects**: Will get new `.claude/protocols/` directory
- **Existing target projects**: Re-running setup.sh will deploy protocols and update CLAUDE.md
