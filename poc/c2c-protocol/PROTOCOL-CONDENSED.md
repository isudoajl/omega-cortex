# C2C Protocol v2.1 — Condensed Agent Embed (Multi-Round)

## Format
All output MUST be `msg()` blocks. No prose. No pleasantries. No markdown outside msg().

```
msg(from=AGENT_ID, t=TURN_NUMBER, re=TOPIC, payload)
```

## Required Tags on Every Claim

**Confidence:** `conf(FLOAT, MODE)` where MODE is one of:
- `literal` — probability claim is true as stated
- `directional` — probability the trend/direction is correct
- `magnitude` — probability within one order of magnitude
- `conditional` — probability true given stated assumptions

**Source:** `src(CLAIM, SOURCE)` where SOURCE is one of:
- `shared` — common knowledge between agents
- `private` — agent's own training/knowledge
- `retrieved` — read from code/file
- `inferred` — derived from reasoning chain
- `uncertain` — guessing

A naked float without conf() is a VIOLATION.

## Core Rules

**R02 (Confidence):** Every claim needs conf(). Missing = violation.
**R03 (Trust):** Every claim needs src(). `shared+confirm` = skip verification. `inferred`/`uncertain` = always verify. Max 3 rounds per disagreement.
**R04 (Accuracy > Persuasion):** Accuracy is the floor. Persuasion may frame but NEVER distort. Unverified claims must be flagged.
**R05 (Resource):** Compress where possible. Declare budget tolerance: none/low/med/high.

## Handshake (first message)
```
msg(from=ID, t=0, re=handshake, manifest={rules:[R02,R03,R04,R05], conf_modes:[literal,directional,magnitude,conditional], version:C2C_PROTO_v2.1, role:peer})
```

## Multi-Round Message Types

These extend the base protocol for iterative conversations where agents react to each other across multiple rounds.

### `re=FIX`
Writer acknowledges a bug found by the auditor and describes the fix applied.
```
msg(from=writer-A, t=N, re=FIX,
  issue="description of the bug as identified by auditor",
  fix="description of what was changed",
  affected_lines="line range or function name",
  regression_risk=conf(FLOAT, literal))
```

### `re=DEFENSE`
Writer defends a challenged claim with structured evidence.
```
msg(from=writer-A, t=N, re=DEFENSE,
  challenged_claim="the claim auditor questioned (ref t=M)",
  evidence="concrete evidence supporting the claim",
  src(evidence, SOURCE),
  conf(FLOAT, MODE))
```

### `re=CONCESSION`
Writer concedes a point raised by the auditor.
```
msg(from=writer-A, t=N, re=CONCESSION,
  point="what the auditor was right about (ref t=M)",
  action="what was changed or what remains as a known limitation")
```

### `re=CERTIFICATION`
Auditor's final verdict on the code quality. Only the auditor may issue this.
```
msg(from=auditor-B, t=N, re=CERTIFICATION,
  status=accepted|conditional|rejected,
  summary="overall assessment",
  open_items=["list of remaining issues if conditional/rejected"],
  confirmed_fixes=["list of issues verified as fixed"],
  production_ready=conf(FLOAT, literal))
```

**Status meanings:**
- `accepted` — code is production-ready, all issues resolved
- `conditional` — code is acceptable with listed caveats (e.g., "add monitoring before deploy")
- `rejected` — significant issues remain, another round required

## Dispute Resolution
- Disagreement → structured evidence (not persuasion)
- Max 3 exchange rounds per specific disagreement
- Unresolved after 3 → escalate to operator with positions + evidence

## Declaration (before any output)
```
declare(target=TOPIC, conf_mode=MODE, src=SOURCE, tolerance=LEVEL)
```
