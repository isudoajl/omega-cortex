# Context Window Management

## Critical Rules
- **NEVER read the entire codebase at once** — always scope to the relevant area
- **Read indexes first** — start with `specs/SPECS.md` or `docs/DOCS.md` to identify which files matter
- **Query memory.db first** — check what's already known before reading files
- **Scope narrowing** — all commands accept an optional scope parameter to limit the area of work
- **Chunking** — for large operations (audit, sync, docs), work one milestone/domain at a time

## Agent Scoping Strategy
1. Query memory.db for context on the target area (hotspots, decisions, failures)
2. Read the master index (`specs/SPECS.md`) to understand the project layout
3. Identify which domains/milestones are relevant to the task
4. Read ONLY the relevant spec files and code files
5. If you feel context getting heavy, stop and summarize what you've learned so far before continuing

## Scope Parameter
All workflow commands accept an optional scope to limit context usage:
```
/workflow:new-feature "add retry logic" --scope="providers"
/workflow:audit --scope="milestone 3: core"
/workflow:sync --scope="memory"
/workflow:bugfix "scheduler crash" --scope="backend/src/gateway/scheduler.rs"
```

When no scope is provided, the analyst determines the minimal scope needed based on the task description.

## 60% Context Budget
Every agent operates under a **60% context window budget**. This is a proactive limit, not a reactive fallback — agents plan their work to fit within 60%, leaving 40% headroom for reasoning, edge cases, and unexpected complexity.

**Why 60%:** Agents that consume their full context window produce degraded output — they lose track of earlier decisions, repeat themselves, and miss connections. The 60% budget ensures each agent finishes strong with full recall of its work.

**How it works:**
- The **Architect** sizes milestones so each downstream agent can complete one milestone within 60% of its context (max 3 modules per milestone)
- Each **pipeline agent** monitors its own usage proactively and stops at the 60% mark
- When an agent hits the budget, it saves state to `docs/.workflow/` and the pipeline continues via `/workflow:resume`

**Heuristics for agents:**
- If you've read more than ~20 files without saving progress, you are likely near the budget
- If you've processed more than 3 modules without checkpointing, save progress now
- If you're on your second major domain/area, consider whether you have enough budget remaining for the rest

## When Reaching the 60% Budget
When an agent reaches 60% of its context window:
1. **Summarize** what has been learned so far into a temporary file at `docs/.workflow/[agent]-[task]-summary.md`
2. **Delegate** remaining work by spawning a continuation subagent that reads the summary
3. **Never silently degrade** — if you can't do a thorough job, say so and suggest splitting the task
