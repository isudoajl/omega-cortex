# OMEGA Extension

> 2 agents, 1 command for the OMEGA framework.

## Install

```bash
bash /path/to/claude-workflow/scripts/setup.sh --ext=omega
```

## Agents

### omega-topology-architect
Maps user business domains to OMEGA primitives:
- **Projects** — isolated work contexts
- **Skills** — domain-specific capabilities (tools, CLIs, APIs)
- **Topologies** — agent collaboration structures
- **Schedules** — recurring task definitions
- **Heartbeats** — health monitoring

Discovers existing OMEGA infrastructure at `~/.omega/`, designs a minimum viable configuration, presents a proposal for human approval, then executes the setup.

**Outputs**: `~/.omega/projects/<name>/ROLE.md` and related config files.

### skill-creator
Creates production-ready OMEGA skill definitions. Researches domain tools, CLIs, and APIs, then produces:
- `~/.omega/skills/<name>/SKILL.md` with proper frontmatter
- Optional supporting resources (scripts, references, assets)

Validates frontmatter, checks trigger collisions with existing skills, enforces progressive disclosure (basic → advanced).

## Commands

| Command | Description |
|---------|-------------|
| `/workflow:omega-setup "desc"` | Map a business domain to OMEGA primitives and configure the setup |
