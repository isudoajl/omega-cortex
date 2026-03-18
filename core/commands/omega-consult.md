---
name: omega:consult
description: "Intelligent specialist routing — finds or creates the right domain expert for any request. Use when: 'I need help with marketing', 'consult a specialist', 'find an expert in...', domain-specific task outside normal development workflows, 'I need advice on [field]', cross-domain problem, 'who can help with...', specialist needed, 'this requires expertise in...', complex domain request, 'I need a [domain] expert'."
---

# Workflow: Consult

Routes user requests to the right specialist agent. If no specialist exists for the domain, creates one on the fly via role-creator. For critical problems, assembles multi-agent reasoning pipelines with adversarial tension.

This is OMEGA's **catch-all for domain-specific expertise** — it handles everything that doesn't fit neatly into the structured development workflows (bugfix, new-feature, improve, audit, etc.).

Optional: `--critical` to force Tier 3 pipeline assembly regardless of complexity assessment.

## Pipeline Tracking (Institutional Memory)
If `.claude/memory.db` exists, register this workflow run:

```bash
sqlite3 .claude/memory.db "INSERT INTO workflow_runs (type, description, scope) VALUES ('consult', 'USER_REQUEST_HERE', NULL);"
RUN_ID=$(sqlite3 .claude/memory.db "SELECT last_insert_rowid();")
```

Close at end: `UPDATE workflow_runs SET status='completed|failed|partial', completed_at=datetime('now') WHERE id=$RUN_ID;`

## Step 1: Route

Invoke the `omega-router` agent with the user's full request and `$RUN_ID`.

The router will:
1. **Classify** the request by domain, complexity, and task type
2. **Search** `.claude/agents/` for matching specialist agents
3. **Produce** a routing decision at `docs/.workflow/routing-decision.md`

If `--critical` was passed, tell the router to classify as Tier 3 regardless.

### Verify Output
After the router completes, verify `docs/.workflow/routing-decision.md` exists and contains a **Decision** section with an **Action** field.

Read the routing decision. Branch based on the **Action** field:

---

## Branch A: Handle Directly (Tier 1)

The router determined this is simple enough to handle without a specialist.

1. Respond to the user's request directly using general knowledge
2. Log the outcome:
```bash
sqlite3 .claude/memory.db "INSERT INTO outcomes (run_id, agent, score, domain, action, lesson) VALUES ($RUN_ID, 'orchestrator', 1, 'routing', 'Tier 1: handled directly for [domain]', 'Simple request, no specialist needed');"
```
3. Close the workflow run as completed

---

## Branch B: Delegate to Existing Specialist (Tier 2 — delegate-existing)

A matching specialist agent was found in `.claude/agents/`.

1. Read the **Specialist** and **Agent File** fields from the routing decision
2. Invoke that specialist agent as a subagent with:
   - The user's original request
   - The `$RUN_ID` for memory logging
   - Any relevant context from the routing decision
3. Present the specialist's output to the user
4. Log the routing outcome:
```bash
sqlite3 .claude/memory.db "INSERT INTO outcomes (run_id, agent, score, domain, action, lesson) VALUES ($RUN_ID, 'omega-router', 1, 'routing', 'Delegated to existing specialist: [name]', '[domain] specialist handled the request');"
```
5. Close the workflow run as completed

---

## Branch C: Create Then Delegate (Tier 2 — create-then-delegate)

No matching specialist exists. Create one, then delegate.

1. Read the **If Creating Specialist** section from the routing decision
2. Invoke the `role-creator` agent with:
   - The suggested name, domain, and brief description from the routing decision
   - Instruction to **skip Phase 7 user confirmation** — the routing context serves as implicit approval
   - Instruction to create a focused, practical specialist (not over-engineered)
3. The role-creator will:
   - Design the specialist following the standard agent format
   - Include "Use when:" trigger keywords in the description
   - Validate structural completeness (Phase 6)
   - Save to `.claude/agents/[name].md`
4. **Skip the adversarial audit** — the specialist is for immediate use. Suggest auditing later via `/omega:audit-role` if the specialist will be reused
5. Verify the new specialist file exists at `.claude/agents/[name].md`
6. Invoke the newly created specialist agent with the user's original request and `$RUN_ID`
7. Present the specialist's output to the user
8. Log the creation and routing:
```bash
sqlite3 .claude/memory.db "INSERT INTO decisions (run_id, domain, decision, rationale, confidence) VALUES ($RUN_ID, 'routing', 'Created specialist: [name] for [domain]', 'No existing agent matched the domain. Created on demand via role-creator.', 0.8);"
sqlite3 .claude/memory.db "INSERT INTO outcomes (run_id, agent, score, domain, action, lesson) VALUES ($RUN_ID, 'omega-router', 1, 'routing', 'Created and delegated to new specialist: [name]', 'First [domain] request — specialist now available for future routing');"
```
9. Close the workflow run as completed

### Specialist Quality
The role-creator produces structurally complete agents (all mandatory sections, memory protocol, boundaries, process, output format). For immediate use, structural validation is sufficient. If the specialist will be reused across sessions, recommend:
```
The [name] specialist was created for immediate use. For production-quality assurance, run:
/omega:audit-role ".claude/agents/[name].md"
```

---

## Branch D: Assemble Pipeline (Tier 3 — assemble-pipeline)

Critical problem requiring multiple agent perspectives with adversarial tension.

1. Read the **Pipeline** field from the routing decision (ordered list of agents)
2. For any specialist in the pipeline that doesn't exist yet:
   - Follow Branch C's creation flow to create it first
   - Maximum **1 specialist creation** per pipeline run
3. Invoke each agent in the pipeline **sequentially**:
   - Each agent receives:
     - The user's original request
     - Output from previous agents in the pipeline
     - The `$RUN_ID` for memory logging
   - Each agent reads/writes memory.db per its protocol
   - Collect each agent's output for the next agent in the chain
4. After all pipeline agents complete, **synthesize**:
   - Present the combined insights to the user
   - Highlight areas of agreement and disagreement between agents
   - If the pipeline included adversarial agents (reviewer), surface their challenges prominently
5. Log the pipeline execution:
```bash
sqlite3 .claude/memory.db "INSERT INTO decisions (run_id, domain, decision, rationale, confidence) VALUES ($RUN_ID, 'routing', 'Tier 3 pipeline: [agent1] → [agent2] → [agent3] for [domain]', 'Critical [domain] problem requiring multi-perspective analysis', 0.85);"
sqlite3 .claude/memory.db "INSERT INTO outcomes (run_id, agent, score, domain, action, lesson) VALUES ($RUN_ID, 'omega-router', 1, 'routing', 'Assembled Tier 3 pipeline for [domain]', 'Pipeline pattern: [agents] worked for critical [domain] problems');"
```
6. Close the workflow run as completed

### Pipeline Constraints
- Maximum **4 agents** in a single Tier 3 pipeline
- Maximum **1 specialist creation** per pipeline (don't create 3 specialists in one run)
- If the pipeline exceeds context budget, save state to `docs/.workflow/consult-state.md` and suggest `/omega:resume`
- Each agent in the pipeline must produce output before the next one starts (sequential, not parallel)

---

## Close-Out

```bash
# On success
sqlite3 .claude/memory.db "UPDATE workflow_runs SET status='completed', completed_at=datetime('now') WHERE id=$RUN_ID;"

# On failure
sqlite3 .claude/memory.db "UPDATE workflow_runs SET status='failed', completed_at=datetime('now'), error_message='[reason]' WHERE id=$RUN_ID;"

# On partial (context budget hit)
sqlite3 .claude/memory.db "UPDATE workflow_runs SET status='partial', completed_at=datetime('now'), error_message='Context budget reached at [step]' WHERE id=$RUN_ID;"
```

Clean up: `docs/.workflow/routing-decision.md` is a temporary working file — delete after the workflow completes successfully.

## Error Recovery

If the workflow fails mid-execution:
1. Save state to `docs/.workflow/consult-state.md`:
   - Which branch was selected
   - Which step failed and why
   - What output has been produced so far
2. Update memory.db with the failure
3. The user can resume with `/omega:resume`

## Inter-Step Output Validation

- Before Branch B/C/D: verify `docs/.workflow/routing-decision.md` exists with a valid Decision section
- Before invoking specialist (Branch B/C): verify the agent file exists at the path specified
- Before pipeline execution (Branch D): verify all pipeline agents exist (create missing ones first)

**If any expected output is missing, STOP the chain.**

## What This Workflow Produces

- **Tier 1**: A direct response to the user's request
- **Tier 2**: Specialist agent output (and possibly a new `.claude/agents/[name].md` file)
- **Tier 3**: Multi-perspective analysis from a pipeline of agents (and possibly a new specialist)
- **Always**: A routing decision logged to memory.db for future sessions to learn from
