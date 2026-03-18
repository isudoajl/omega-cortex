---
name: omega:diagnose
description: "Deep diagnostic investigation for hard bugs where the root cause is unknown. Use when: 'I can\\'t figure out why...', mysterious behavior, intermittent failure, flaky test, root cause unknown, 'bugfix didn\\'t work', 'we tried fixing it but...', heisenbug, race condition, deep investigation needed. Escalation path when omega:bugfix has failed. Use --incident=INC-NNN to resume an existing incident."
---

# Workflow: Diagnose

For bugs that have resisted multiple fix attempts. This is NOT a faster bugfix — it's a fundamentally different approach: **understand first, fix once**.

Optional: `--scope="file, module, or subsystem"` to focus the investigation.
Optional: `--fix` to also implement the fix after diagnosis (otherwise stops at the diagnosis report).
Optional: `--incident=INC-NNN` to resume an existing incident ticket.

## When to Use This Instead of omega:bugfix

- You've tried `omega:bugfix` and the bug persists
- The bug has been "fixed" multiple times but keeps coming back
- Nobody understands WHY the system misbehaves
- The bug is intermittent, timing-dependent, or only appears under specific conditions
- The bug involves multiple components interacting (distributed systems, async flows, state synchronization)

## Pipeline Tracking (Institutional Memory)
If `.claude/memory.db` exists, register this workflow run:

```bash
sqlite3 .claude/memory.db "INSERT INTO workflow_runs (type, description, scope) VALUES ('diagnose', 'USER_DESCRIPTION_HERE', 'SCOPE_OR_NULL');"
RUN_ID=$(sqlite3 .claude/memory.db "SELECT last_insert_rowid();")
```

Close at end: `UPDATE workflow_runs SET status='completed|failed|partial', completed_at=datetime('now') WHERE id=$RUN_ID;`
Pass `$RUN_ID` to the diagnostician agent.

## Incident Tracking

Every diagnosis is tracked as an incident. Read `.claude/protocols/incident-protocol.md` for full reference.

### If `--incident=INC-NNN` is provided (resuming):
1. Query the full incident timeline — this is PRIMARY EVIDENCE for the diagnostician:
```bash
sqlite3 -header -column .claude/memory.db "SELECT entry_type, content, result, agent, created_at FROM incident_entries WHERE incident_id='INC-NNN' ORDER BY id;"
sqlite3 -header -column .claude/memory.db "SELECT title, description, symptoms, root_cause FROM incidents WHERE incident_id='INC-NNN';"
```
2. Update status: `UPDATE incidents SET status='investigating' WHERE incident_id='INC-NNN';`
3. Pass the timeline to the Diagnostician — failed attempts become the constraint table.

### If no `--incident` (new investigation):
1. Auto-create an incident:
```bash
INC_ID=$(sqlite3 .claude/memory.db "SELECT 'INC-' || printf('%03d', COALESCE(MAX(CAST(SUBSTR(incident_id, 5) AS INTEGER)), 0) + 1) FROM incidents;")
sqlite3 .claude/memory.db "INSERT INTO incidents (incident_id, title, domain, description, symptoms, run_id) VALUES ('$INC_ID', 'SHORT_TITLE', 'SCOPE_OR_DOMAIN', 'USER_DESCRIPTION', 'SYMPTOMS_IF_ANY', $RUN_ID);"
```
2. Tell the user: "Tracking as **$INC_ID**. Resume in future sessions with `/omega:diagnose --incident=$INC_ID`"

### During diagnosis:
The Diagnostician MUST log entries as it works:
- **hypothesis**: each hypothesis generated → `INSERT INTO incident_entries (incident_id, entry_type, content, agent) VALUES ('$INC_ID', 'hypothesis', 'HYPOTHESIS_TEXT', 'diagnostician');`
- **discovery**: each piece of evidence found → entry_type `'discovery'`
- **attempt**: each diagnostic test run → entry_type `'attempt'`, result `'worked'`/`'failed'`

### On resolution (Step 7):
1. Close the incident with root cause:
```bash
sqlite3 .claude/memory.db "UPDATE incidents SET status='resolved', root_cause='ROOT_CAUSE', resolution='HOW_FIXED', resolved_at=datetime('now') WHERE incident_id='$INC_ID';"
```
2. **Extract behavioral learning** if the bug revealed a flaw in Claude's reasoning process.

## Step 1: Diagnostician

Invoke the `diagnostician` agent with the full bug description, scope, and `$RUN_ID`.

The Diagnostician will:
1. **Characterize the symptom** — precise description of what happens vs. what should happen
2. **Assemble evidence** — build constraint table from all failed approaches in memory.db
3. **Generate and eliminate hypotheses** — Explorer/Skeptic/Analogist reasoning loop
4. **Design diagnostic tests** — experiments that distinguish between surviving hypotheses
5. **Confirm root cause** — with evidence from diagnostic tests
6. **Explain why previous fixes failed** — tied to the confirmed root cause

### Expected Outputs
- `docs/.workflow/diagnosis-symptoms.md` — symptom profile
- `docs/.workflow/diagnosis-report.md` — full diagnosis report with root cause
- `docs/.workflow/diagnosis-reasoning.md` — reasoning trace (hypotheses, eliminations, evidence)

### Verify Output
After the Diagnostician completes, verify:
1. `docs/.workflow/diagnosis-report.md` exists and contains a "Root Cause" section
2. The root cause explains all observed symptoms
3. The "Why Previous Fixes Failed" section addresses known failed approaches

**If the Diagnostician cannot confirm a root cause:**
- The report will contain a "Narrowed To" section with remaining hypotheses
- It will recommend specific next steps (additional logging, test scenarios, etc.)
- STOP the pipeline and present the partial diagnosis to the user
- The user decides whether to pursue the recommended next steps

## Step 2: Fix Decision Gate

If `--fix` was NOT passed:
- Present the diagnosis report to the user
- STOP here. The user can:
  - Run `omega:bugfix` with the diagnosis as context
  - Run `omega:diagnose --fix` to continue with the fix
  - Address the root cause manually

If `--fix` WAS passed:
- Continue to Step 3

## Step 3: Test Writer (if --fix)

Write a test that reproduces the **confirmed root cause** directly — not just the symptom.

1. Reference the diagnosis report for the root cause and causal chain
2. The test should fail because of the root cause mechanism, not just because the symptom appears
3. Add edge case tests for related failure modes identified in the diagnosis

## Step 4: Developer (if --fix)

Fix the bug by addressing the confirmed root cause.

1. The developer MUST read `docs/.workflow/diagnosis-report.md` before writing any code
2. The fix must address the root cause described in the diagnosis, not the symptoms
3. The reproduction test must pass
4. All existing tests must pass (regression check)
5. Remove any diagnostic instrumentation added during the diagnosis

### Developer Max Retry: 3 attempts
If the fix doesn't work after 3 attempts, STOP and return to the Diagnostician — the diagnosis may need refinement.

## Step 5: QA (if --fix)

1. Verify the root cause is actually addressed (not just the symptom)
2. Test the specific causal chain described in the diagnosis report
3. Test under the conditions that triggered the original bug (load, timing, multi-node, etc.)
4. Verify no regression in related functionality

### QA ↔ Developer iterations: Maximum 2
If QA still finds issues after 2 rounds, STOP and report.

## Step 6: Reviewer (if --fix)

1. Verify the fix addresses the confirmed root cause from the diagnosis
2. Verify the fix doesn't introduce new assumptions of the same class that caused the original bug
3. Verify diagnostic instrumentation was removed
4. Verify specs/docs updated if the diagnosis revealed incorrect documentation

### Reviewer ↔ Developer iterations: Maximum 2

## Step 7: Versioning (if --fix)

Once approved, create the final commit with `fix:` prefix.
Reference the diagnosis in the commit message: "Root cause: [one-line description]".
Clean up `docs/.workflow/` temporary files (keep `diagnosis-report.md` — it's valuable for memory).

## Error Recovery

If the Diagnostician hits context limits mid-diagnosis:
1. Save progress to `docs/.workflow/diagnosis-progress.md`
2. Update memory.db with partial findings
3. The user can resume with `omega:diagnose` — the new session reads the progress file and memory.db to continue where the last session stopped

## Inter-Step Output Validation

- Before Test Writer: verify `docs/.workflow/diagnosis-report.md` exists with confirmed root cause
- Before Developer: verify reproduction test exists
- Before QA: verify code changes exist
- Before Reviewer: verify QA report exists

**If any expected output is missing, STOP the chain.**
