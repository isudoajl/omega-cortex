# C2C Protocol Extension

> 2 agents, 3 commands for Claude-to-Claude protocol research.

## Background

The C2C (Claude-to-Claude) protocol is a research experiment in structured agent-to-agent communication. It defines how two Claude agents can work together with formal trust, verification, and certification mechanisms — one agent writes code/docs, the other audits them, iterating until the work meets production standards.

The protocol specs live in `c2c-protocol/` at the repository root. The POC agents (standalone, unrelated to the extension agents) live in `poc/c2c-protocol/`.

## Install

```bash
bash /path/to/claude-workflow/scripts/setup.sh --ext=c2c-protocol
```

## Agents

### proto-auditor
Audits protocol specifications across 12 dimensions at 3 levels:

**Levels:**
- Protocol — is the spec internally consistent?
- Enforcement — can the spec be enforced in practice?
- Self — does the auditor's own process have blind spots?

**Dimensions:** completeness, consistency, safety, liveness, fairness, privacy, efficiency, extensibility, composability, implementability, testability, formalizability.

**Adversarial stance** — assumes broken until proven safe.

**Outputs**: `c2c-protocol/audits/audit-[protocol]-[date].md`

### proto-architect
Consumes audit reports from proto-auditor and generates structured patches through a 6-step pipeline:
1. Parse audit findings
2. Classify by root cause
3. Design patches
4. Verify patches don't introduce new issues
5. Generate patch report
6. Update the protocol spec

**Outputs**: `c2c-protocol/patches/patches-[protocol]-[date].md`

## Commands

| Command | Description |
|---------|-------------|
| `/workflow:c2c` | Multi-round POC: writer + auditor iterate until certification (max 5 rounds) |
| `/workflow:proto-audit "path" [--scope]` | Audit a protocol spec (12 dimensions, 3 levels). Scope: specific dimensions |
| `/workflow:proto-improve "path" [--scope]` | Improve a protocol spec from audit findings (6-step pipeline) |

## Typical Workflow

```
1. Write/update a protocol spec in c2c-protocol/
2. /workflow:proto-audit "c2c-protocol/spec.md"     → produces audit findings
3. /workflow:proto-improve "c2c-protocol/spec.md"    → generates patches from findings
4. Repeat until the audit produces no critical findings
```
