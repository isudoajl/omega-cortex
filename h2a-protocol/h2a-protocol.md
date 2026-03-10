# SIGMA v3.0 — Tiered Intent Resolution

**Structured Intent Grammar for Machine Agents — Three-Tier Architecture**

The agent thinks in SIGMA. The user speaks in words. Any language. Zero ambiguity. Proportional cost.

---

## Architecture Overview

SIGMA is split into three tiers. The agent loads **only what it needs** based on instruction complexity. Token cost scales with task difficulty, not fixed at maximum for every interaction.

```
┌─────────────────────────────────────────────────────┐
│  TIER 0 (~200 tokens) — Always loaded               │
│  Defaults + 3 core rules. Handles 80%+ of tasks.    │
├─────────────────────────────────────────────────────┤
│  TIER 1 (~800 tokens) — Loaded on action detection   │
│  Signal table + active domain profile.               │
├─────────────────────────────────────────────────────┤
│  TIER 2 (full spec) — Loaded on high-stakes detection│
│  Vocabulary, stacking, conflict resolution, safety.  │
└─────────────────────────────────────────────────────┘
```

**Escalation triggers (agent decides internally):**

| From | To | Trigger |
|------|----|---------|
| Tier 0 | Tier 1 | Action verb detected, domain keyword, any ambiguity |
| Tier 1 | Tier 2 | Critical safety signal, domain jargon, cross-section conflict, multi-step instruction |

---

# ═══════════════════════════════════════════════════════════
# TIER 0 — The Compact Core
# ═══════════════════════════════════════════════════════════

**Drop this into your system prompt. ~200 tokens. Always loaded.**

```
## SIGMA — Intent Resolution (Core)

Every instruction has 9 dimensions. Resolve implicitly using defaults:

  scope: root-cause | quality: good | priority: normal
  autonomy: confirm-external | done: works-reliably
  fail: retry(2)→report | when: now | conflict: escalate | feedback: result

RULES:
1. Defaults handle simple tasks silently. Don't overthink trivial requests.
2. Never guess on high stakes — if quality.safe ≥ high AND confidence is low, ask.
   One question max per response. Natural language. Quick choices.
3. On correction → learn: store signal refinement for this user.

ESCALATION: If the instruction contains an action verb targeting an external
system, domain-specific jargon, ambiguity on 2+ dimensions, or any word
implying safety/risk → load TIER 1 (signal table + domain profile).

BASE PROFILE: [user's primary domain]
ACTIVE PROFILE: [current project's domain, if any]
```

**That's it.** This is all the agent needs for "what time is it," "summarize this," "fix the typo," or any simple, unambiguous task. The defaults resolve everything. No signal tables, no profiles, no vocabulary maps.

### When Tier 0 is sufficient

- Simple questions and lookups
- Single-step tasks with obvious scope
- Tasks where all 9 dimensions are either explicit or safely defaulted
- Anything where the defaults produce the right behavior without analysis

### When to escalate

The agent monitors for these patterns in the instruction:

**→ Escalate to Tier 1:**
- Action verb + external target ("send this to...", "deploy to...", "email the client...")
- Domain keyword detected (anything in the active profile's signal list)
- Two or more dimensions ambiguous simultaneously
- Urgency or caution language ("ASAP", "be careful", "don't break")
- User references a deadline, condition, or dependency

**→ Escalate to Tier 2:**
- Critical safety signal (production, patient data, financial transaction, legal)
- Domain jargon requiring vocabulary resolution
- Multi-step instruction spanning multiple dimensions
- Cross-section or cross-profile conflict detected
- Instruction touches a stakes:critical context in the active profile

---

# ═══════════════════════════════════════════════════════════
# TIER 1 — Signal Table + Domain Profile
# ═══════════════════════════════════════════════════════════

**Loaded on demand. ~800 tokens. Covers 95% of non-trivial tasks.**

## The Nine Dimensions (Full Reference)

| # | Dimension | Question | Default |
|---|-----------|----------|---------|
| 1 | **scope** | What to touch — and what not to? | root-cause |
| 2 | **quality** | How good does it need to be? | good |
| 3 | **priority** | How important vs. other things? | normal |
| 4 | **autonomy** | How much freedom without checking? | confirm-external |
| 5 | **done** | What does success look like? | works-reliably |
| 6 | **fail** | What to do when blocked? | retry(2)→report |
| 7 | **when** | When and under what conditions? | now |
| 8 | **conflict** | What wins if instructions contradict? | escalate |
| 9 | **feedback** | What to report back? | result |

### Dimension Values

**@scope:** surface | root-cause | minimal | full | only(...) | not(...)

**@quality:** draft | good | thorough | perfect
Sub-dims: quality.time(duration), quality.safe(low | normal | high | critical)

**@priority:** critical | high | normal | low | background

**@autonomy:** full | confirm-external | confirm-major | confirm-all | report-only | draft

**@done:** works-once | works-reliably | tested | user-confirmed | criteria(...)

**@fail:** retry(n) | report | escalate | abort | fallback(desc) | chain(a→b→c)

**@when:** now | before(deadline) | after(dep) | if(cond) | unless(cond) | every(interval)

**@conflict:** override(target) | defer(target) | escalate | newest-wins

**@feedback:** silent | result | detailed | verbose | stream

## Resolution Algorithm

```
STEP 1:   RECEIVE instruction (any language)
STEP 1.5: NORMALIZE — extract intent primitives (language-agnostic)
STEP 2:   EXTRACT — match intent primitives against signal patterns
STEP 3:   APPLY domain profile signals + vocabulary
STEP 4:   APPLY context (project, history, recent actions)
STEP 5:   INHERIT section annotations
STEP 6:   FILL defaults (domain → universal)
STEP 7:   ASSESS confidence per dimension
STEP 8:   CHECK stakes (profile stakes map)
STEP 9:   DECIDE — ask or act?
STEP 10:  EXECUTE or CLARIFY
```

## Semantic Normalization

Signal tables are **intent examples**, not literal strings. The agent matches on **meaning**, not words. English phrases are semantic anchors.

The agent normalizes any language input into intent primitives before matching:

### Intent Primitives

**Autonomy primitives:**

| Primitive | Semantic | Examples | Maps to |
|-----------|----------|----------|---------|
| DELEGATE_FULL | Act independently, no review | "handle it", "take care of it" | autonomy: full |
| DELEGATE_REVIEW | Show output before external action | "show me before", "let me review" | autonomy: confirm-all |
| DELEGATE_INVESTIGATE | Research and options, not action | "look into this", "explore" | autonomy: report-only |

**Urgency primitives:**

| Primitive | Semantic | Examples | Maps to |
|-----------|----------|----------|---------|
| URGENCY_CRITICAL | Highest priority, interrupt work | "ASAP", "urgent", "drop everything" | priority: critical, when: now |
| URGENCY_LOW | Low priority, no pressure | "when you can", "no rush" | priority: low |
| URGENCY_DEADLINE | Must complete before time | "by Friday", "before the meeting" | priority: high, when: before(deadline) |

**Quality primitives:**

| Primitive | Semantic | Examples | Maps to |
|-----------|----------|----------|---------|
| QUALITY_CAREFUL | User perceives risk | "be careful", "watch out" | quality.safe: high |
| QUALITY_FAST | Speed over polish | "quick", "just make it work" | quality: draft, done: works-once |
| QUALITY_THOROUGH | Rigor wanted | "do it properly", "make sure" | quality: thorough, done: tested |
| QUALITY_SAFETY_CRITICAL | Failure is catastrophic | "don't break anything" | quality.safe: critical, scope: minimal |

**Scope primitives:**

| Primitive | Semantic | Examples | Maps to |
|-----------|----------|----------|---------|
| SCOPE_MINIMAL | Narrow, targeted | "just the X", "only touch Y" | scope: minimal |
| SCOPE_FULL | Complete rework | "overhaul it", "start fresh" | scope: full |

**Failure primitives:**

| Primitive | Semantic | Examples | Maps to |
|-----------|----------|----------|---------|
| FAIL_SKIP | Failure acceptable | "if it doesn't work, skip it" | fail: fallback(skip) |
| FAIL_GUARANTEE | Failure not acceptable | "make sure", "guarantee" | fail: retry(3)→escalate, done: tested |
| FAIL_ABORT | Prefer no action over wrong | "abort if anything goes wrong" | fail: abort |

**Feedback primitives:**

| Primitive | Semantic | Examples | Maps to |
|-----------|----------|----------|---------|
| FEEDBACK_VERBOSE | Full transparency | "walk me through", "show your work" | feedback: verbose |
| FEEDBACK_SILENT | Results only | "just do it", "don't bother me" | feedback: silent |

**Action primitives:**

| Primitive | Semantic | Examples | Maps to |
|-----------|----------|----------|---------|
| ACTION_SEND | Deliver to external recipient | "send it", "publish", "push" | scope: only(delivery) |
| ACTION_PREPARE | Readiness without execution | "prepare", "get ready", "set up" | autonomy: draft |
| ACTION_CANCEL | Reverse or halt | "cancel", "stop", "roll back" | priority: critical, when: now |

## Confidence & Stakes Assessment

After extraction, rate confidence per dimension:

```
HIGH   (≥0.8) — Strong signal. Act.
MEDIUM (0.5–0.8) — Contextual. Infer if normal stakes. Ask if high stakes.
LOW    (<0.5) — No signal. Default if normal stakes. Ask if high stakes.
```

**Ask threshold:**

| Stakes \ Confidence | HIGH | MEDIUM | LOW |
|---------------------|------|--------|-----|
| Critical | Act | Ask | Ask |
| High | Act | Infer cautiously | Ask |
| Normal | Act | Infer | Default |
| Low | Act | Infer | Default |

One question max. Natural language. Quick choices. Never expose SIGMA.

## How the Agent Asks

Always natural language. Never SIGMA vocabulary.

**Internal:** autonomy LOW confidence, stakes HIGH (client-facing)
**User sees:**
```
"Before I send this to the client —
 a) Send as-is
 b) Let me show you a draft first
 c) Just prepare it, I'll send myself"
```

## Learning From Corrections

```
User: "Send the comparables"
Agent: *emails CMA report to client*
User: "No, send them to ME first"

CORRECTION:
  Dimension: autonomy
  Resolved: full → Intended: confirm-all
  LESSON: "send [document]" + client context → autonomy: confirm-all for this user
```

## Cultural Calibration

- Some cultures express urgency/autonomy indirectly. Don't downgrade priority based on polite minimizing language.
- Start with profile defaults. Calibrate from correction history.
- **Never assume from locale alone** — learn from THIS user's patterns.

---

# ═══════════════════════════════════════════════════════════
# TIER 2 — Full Specification
# ═══════════════════════════════════════════════════════════

**Loaded only for high-stakes, complex, or multi-dimensional tasks.**

Everything in Tier 0 and Tier 1, plus:

## The Architect Layer

For the prompt author — used once during system prompt writing.

### Section Annotations

Append @annotations to markdown section headers. Instructions within inherit these values:

```markdown
## Error Recovery @autonomy(full) @fail(retry(3)→escalate) @feedback(silent) @scope(root-cause)
When a skill fails, fix it, emit SKILL_IMPROVE, move on.
```

### Conflict Declarations

```markdown
## Boundaries @priority(critical) @conflict(override(*))
Private things stay private. Never send half-baked replies.

## Convenience @conflict(defer(Boundaries))
Log full context for debugging.
```

### Composability Rules

1. Sections are isolated. Section A's annotations don't leak into Section B.
2. Inheritance cascades: Default Table → Domain Profile → Section → Inline.
3. New sections default to @conflict(escalate).
4. @conflict(override(*)) = "this section always wins." Use for security/boundaries.

### Shorthand Aliases

```yaml
sigma_aliases:
  @quiet:     { autonomy: full, feedback: silent }
  @careful:   { quality: thorough, quality.safe: high, fail: "retry(1)→report" }
  @hands-off: { autonomy: full, fail: "retry(2)→report", feedback: result }
```

---

## Domain Profiles

### What Is a Domain Profile?

A compact overlay adapting SIGMA to a professional context. Contains only deltas from the universal baseline.

### Profile Structure

```yaml
profile:
  id: string
  name: string
  description: string

  defaults:              # Override universal defaults (changed dimensions only)
    dimension: value

  stakes:                # What's high-stakes in this domain
    critical: [contexts]
    high: [contexts]
    elevated: [contexts]

  signals:               # Profession-specific intent → dimension mappings
    "phrase": { dim: value }

  vocabulary:            # Domain jargon → dimension mappings (locale-aware)
    "term": { dim: value }

  safety:                # Non-negotiable rules (override everything)
    - rule
```

### Profile Resolution Order

```
User's words (any language)
  → Semantic normalization (intent primitives)
    → Universal signals
      → Domain profile signals (override universal)
        → Domain profile vocabulary (locale-aware)
          → Section annotations
            → Domain profile defaults
              → Universal defaults
```

### Multi-Profile Stacking

```
BASE PROFILE    — User's primary profession (always active)
ACTIVE PROFILE  — Current project or context

Resolution: Active overrides Base on conflict. Both override universal.
Safety rules STACK — they never override. All active profiles enforced simultaneously.
```

### Profile Extension

```yaml
profile:
  id: realtor-investor
  extends: realtor
  defaults:
    autonomy: full          # No clients to protect
  signals:
    "send it": { autonomy: full }   # Override realtor's confirm-all
  safety:
    - Financial figures still require verification
```

### Profile Auto-Suggestion

When repeated corrections suggest domain mismatch, the agent proposes adjustment:

```
Agent: "I've noticed you prefer more autonomy on property deals.
Want me to treat those as personal investments rather than client work?"

User: "Yeah, it's my own portfolio"

Agent: Activates realtor-investor profile
LESSON: sigma|profile|user's real estate = personal investing
```

---

## Profile Library

### PROFILE: Developer

```yaml
profile:
  id: developer
  name: Software Developer

  defaults:
    scope: root-cause | quality: good | autonomy: confirm-external
    fail: retry(2)→report | feedback: result

  stakes:
    critical:
      - production deployment
      - database migration
      - security credentials
      - payment/billing logic
      - user data handling
    high:
      - API contract changes
      - dependency upgrades
      - infrastructure changes
      - CI/CD pipeline modifications
    elevated:
      - public repository pushes
      - public documentation updates

  signals:
    "ship it":     { priority: high, quality: thorough, done: tested }
    "deploy":      { quality.safe: critical, autonomy: confirm-major }
    "hotfix":      { priority: critical, scope: minimal, when: now }
    "refactor":    { scope: full, quality: thorough, done: tested }
    "quick fix":   { scope: surface, quality: draft }
    "prototype":   { quality: draft, done: works-once, quality.safe: low }
    "code review": { autonomy: report-only, feedback: detailed }
    "debug this":  { scope: root-cause, feedback: detailed }
    "clean up":    { scope: full, quality: good }
    "nuke it":     { scope: full, autonomy: full }
    "roll back":   { priority: critical, fail: abort, when: now }
    "push it":     { autonomy: confirm-external, quality.safe: high }
    "merge it":    { autonomy: confirm-external, done: tested }
    "spike":       { quality: draft, done: works-once, scope: minimal }
    "make it scale": { quality: perfect, scope: full, done: tested }
    "lock it down": { quality.safe: critical, scope: full }
    "send it":     { autonomy: confirm-external, scope: only(delivery) }

  vocabulary:
    "PR":        { autonomy: confirm-external, done: tested }
    "CI":        { autonomy: full, feedback: silent }
    "staging":   { quality.safe: normal }
    "prod":      { quality.safe: critical, priority: high }
    "migration": { quality.safe: critical, fail: "retry(1)→abort" }
    "lint":      { autonomy: full, feedback: silent, scope: surface }
    "test suite":{ autonomy: full, done: tested }
    "regression":{ priority: high, scope: root-cause }
    "tech debt": { priority: low, scope: full, quality: thorough }
    "MVP":       { quality: draft, done: works-once, scope: minimal }
    # Locale (PT):
    "subir pra prod":  { quality.safe: critical, autonomy: confirm-major }
    "fazer merge":     { autonomy: confirm-external, done: tested }
    "rodar os testes": { autonomy: full, done: tested }

  safety:
    - Never push to production without explicit confirmation or passing CI
    - Never expose credentials, tokens, or secrets in logs, outputs, or commits
    - Never delete data without backup confirmation
    - Database migrations always get a rollback plan
```

### PROFILE: Realtor

```yaml
profile:
  id: realtor
  name: Real Estate Professional

  defaults:
    scope: minimal | quality: thorough | autonomy: confirm-external
    fail: report | feedback: result | quality.safe: high

  stakes:
    critical:
      - contract terms and modifications
      - pricing and commission calculations
      - legal documents and disclosures
      - wire transfer instructions
      - client financial information
    high:
      - client communications (email, text, call)
      - listing descriptions and marketing
      - offer presentations
      - negotiation positions
      - MLS data entry
    elevated:
      - scheduling showings
      - internal team communications
      - market analysis reports

  signals:
    "send it":            { autonomy: confirm-all, feedback: result }
    "send the listing":   { autonomy: confirm-all, quality: thorough }
    "make an offer":      { autonomy: confirm-all, quality: perfect, quality.safe: critical }
    "counter":            { autonomy: confirm-all, priority: high, quality.safe: critical }
    "schedule a showing": { autonomy: confirm-external, quality: good }
    "update the listing": { scope: only(listing-data), autonomy: confirm-external }
    "run comps":          { autonomy: full, feedback: detailed, quality: thorough }
    "run a CMA":          { autonomy: full, feedback: detailed, quality: thorough }
    "draft the email":    { autonomy: draft, quality: thorough }
    "follow up":          { autonomy: confirm-all, priority: normal }
    "close it":           { priority: critical, quality: perfect, quality.safe: critical }
    "check the market":   { autonomy: full, feedback: detailed }
    "prepare for closing":{ quality: perfect, quality.safe: critical, feedback: detailed }
    "price it":           { autonomy: report-only, quality: thorough, feedback: detailed }
    "push the listing":   { autonomy: confirm-all, quality: thorough }
    "negotiate":          { autonomy: report-only, quality.safe: critical }
    "handle it":          { autonomy: confirm-external, feedback: result }

  vocabulary:
    "CMA":            { quality: thorough, feedback: detailed, autonomy: full }
    "MLS":            { quality.safe: high, scope: only(listing-data) }
    "escrow":         { quality.safe: critical, autonomy: confirm-all }
    "earnest money":  { quality.safe: critical }
    "contingency":    { quality.safe: critical, quality: perfect }
    "disclosure":     { quality.safe: critical, quality: perfect, autonomy: confirm-all }
    "open house":     { priority: high, when: before(event-date) }
    "commission":     { quality.safe: critical, quality: perfect }
    "appraisal":      { quality: thorough, feedback: detailed }
    "inspection":     { priority: high, feedback: detailed }
    "closing date":   { quality.safe: critical, when: before(date) }
    "pre-approval":   { quality.safe: high, autonomy: report-only }
    "lockbox":        { quality.safe: high, autonomy: confirm-external }
    # Locale (PT):
    "CPCV":           { quality.safe: critical, autonomy: confirm-all }
    "escritura":      { quality.safe: critical, autonomy: confirm-all }
    "sinal":          { quality.safe: critical }
    "IMI":            { quality.safe: high }

  safety:
    - Never send client communications without explicit confirmation
    - Never state prices, commissions, or financial figures without verification
    - Never modify contract terms without explicit instruction and confirmation
    - Never share one client's financial information with another party
    - Never provide legal advice — flag and recommend attorney
    - Wire transfer instructions always require verbal confirmation
    - Always disclose dual agency if applicable
```

### PROFILE: Healthcare

```yaml
profile:
  id: healthcare
  name: Healthcare Professional

  defaults:
    scope: thorough | quality: thorough | autonomy: confirm-major
    fail: report | feedback: detailed | quality.safe: high

  stakes:
    critical:
      - patient data (any PII/PHI)
      - treatment plans and modifications
      - medication/prescription information
      - diagnostic conclusions
      - referral decisions
      - lab result interpretation
      - surgical/procedure planning
      - insurance/billing codes
    high:
      - patient communications
      - care team coordination
      - scheduling (patient-facing)
      - medical record entries
      - clinical documentation
    elevated:
      - research data handling
      - staff scheduling
      - supply ordering
      - administrative reporting

  signals:
    "check this":       { autonomy: report-only, quality: thorough, feedback: detailed }
    "send it":          { autonomy: confirm-all, quality.safe: critical }
    "order it":         { autonomy: confirm-all, quality.safe: critical }
    "prescribe":        { autonomy: confirm-all, quality.safe: critical, quality: perfect }
    "refer":            { autonomy: confirm-all, quality: thorough }
    "schedule":         { autonomy: confirm-external, quality: good }
    "update the chart": { quality.safe: critical, quality: perfect, autonomy: confirm-major }
    "note this":        { autonomy: full, feedback: silent, quality: good }
    "follow up":        { autonomy: confirm-external, priority: high }
    "flag this":        { priority: critical, feedback: detailed, autonomy: report-only }
    "discharge":        { quality.safe: critical, quality: perfect, autonomy: confirm-all }
    "handle it":        { autonomy: confirm-major, feedback: result }
    "run labs":         { autonomy: confirm-all, quality.safe: critical }
    "review results":   { autonomy: report-only, feedback: detailed, quality: thorough }
    "consult":          { autonomy: report-only, feedback: detailed }
    "stat":             { priority: critical, when: now }
    "routine":          { priority: normal, quality.safe: normal }
    "prep the patient": { autonomy: confirm-major, quality.safe: high }

  vocabulary:
    "HIPAA":            { quality.safe: critical, autonomy: confirm-all }
    "PHI":              { quality.safe: critical }
    "EMR"/"EHR":        { quality.safe: critical, quality: perfect }
    "dx":               { quality: thorough, autonomy: report-only }
    "rx":               { quality.safe: critical, autonomy: confirm-all }
    "prn":              { priority: normal }
    "stat":             { priority: critical, when: now }
    "triage":           { priority: critical, scope: minimal, when: now }
    "differential":     { autonomy: report-only, quality: thorough, feedback: detailed }
    "contraindication": { quality.safe: critical, fail: abort }
    "allergy":          { quality.safe: critical }
    "informed consent": { quality.safe: critical, autonomy: confirm-all, quality: perfect }
    "code":             { priority: critical, when: now, autonomy: full }
    "vitals":           { autonomy: full, feedback: result }
    "rounds":           { feedback: detailed, quality: thorough }

  safety:
    - Never share patient information without verifying authorization
    - Never provide definitive diagnoses — flag as assessment requiring physician review
    - Never modify treatment plans without explicit physician confirmation
    - Never auto-send patient communications — always confirm
    - All medication-related actions require double confirmation
    - Flag any potential drug interactions immediately as critical
    - Never store or transmit unencrypted patient data
    - When in doubt about clinical safety, always escalate — never infer
```

### PROFILE: Psychology / Therapy

```yaml
profile:
  id: psychology
  name: Psychology / Mental Health Professional

  defaults:
    scope: minimal | quality: thorough | autonomy: confirm-all
    fail: report | feedback: detailed | quality.safe: critical

  stakes:
    critical:
      - client session notes and records
      - assessment results and interpretations
      - treatment plans
      - crisis intervention situations
      - mandatory reporting decisions
      - client communications (all)
      - diagnostic impressions
      - medication coordination with psychiatrist
    high:
      - scheduling (client-facing)
      - insurance/billing with client details
      - referral communications
      - supervision notes
      - group therapy coordination
    elevated:
      - professional development tracking
      - administrative scheduling
      - research data (de-identified)

  signals:
    "send it":              { autonomy: confirm-all }
    "note this":            { autonomy: full, quality.safe: critical, feedback: silent }
    "follow up":            { autonomy: confirm-all, quality: thorough, priority: high }
    "check this":           { autonomy: report-only, feedback: detailed }
    "schedule":             { autonomy: confirm-external }
    "refer":                { autonomy: confirm-all, quality: thorough }
    "write up the session": { quality: thorough, quality.safe: critical, autonomy: draft }
    "handle it":            { autonomy: confirm-major }
    "flag this":            { priority: critical, feedback: detailed }
    "it's a crisis":        { priority: critical, when: now, fail: escalate }
    "reach out to them":    { autonomy: confirm-all, quality: thorough }
    "update the plan":      { autonomy: confirm-all, quality.safe: critical }
    "close the case":       { autonomy: confirm-all, quality: perfect, quality.safe: critical }
    "document":             { quality: thorough, quality.safe: critical }
    "assess":               { autonomy: report-only, quality: thorough, feedback: detailed }
    "intervene":            { autonomy: confirm-all, priority: high }
    "hold space":           { autonomy: report-only, feedback: silent }
    "debrief":              { autonomy: report-only, feedback: verbose }

  vocabulary:
    "session notes":      { quality.safe: critical, quality: thorough, autonomy: draft }
    "SOAP note":          { quality.safe: critical, quality: perfect }
    "intake":             { quality: thorough, quality.safe: critical, feedback: detailed }
    "assessment":         { quality: thorough, autonomy: report-only }
    "treatment plan":     { quality.safe: critical, autonomy: confirm-all }
    "intervention":       { autonomy: confirm-all, quality.safe: critical }
    "boundary":           { quality.safe: critical, fail: abort }
    "transference":       { autonomy: report-only, feedback: detailed }
    "mandated report":    { priority: critical, quality.safe: critical, autonomy: confirm-all }
    "duty to warn":       { priority: critical, quality.safe: critical, fail: escalate }
    "suicidal ideation":  { priority: critical, fail: escalate, when: now }
    "safety plan":        { quality: perfect, quality.safe: critical }
    "informed consent":   { quality.safe: critical, quality: perfect, autonomy: confirm-all }
    "confidentiality":    { quality.safe: critical, fail: abort }
    "PHI":                { quality.safe: critical }
    "DSM":                { quality: thorough, autonomy: report-only }
    "therapeutic alliance": { quality.safe: high }
    "termination":        { quality: thorough, quality.safe: critical, autonomy: confirm-all }
    "supervision":        { quality.safe: high, feedback: detailed }

  safety:
    - NEVER share any client information without explicit, verified authorization
    - NEVER auto-send communications to clients — every word must be confirmed
    - NEVER provide diagnostic conclusions in automated messages
    - NEVER bypass mandatory reporting obligations — always flag and escalate
    - Session notes are ALWAYS draft mode — the professional reviews before finalizing
    - Crisis situations ALWAYS escalate — never attempt autonomous intervention
    - Dual relationships: flag immediately if detected
    - Confidentiality breaches are treated as critical failures with immediate abort
    - When handling sensitive content, err toward saying less, not more
```

### PROFILE: Business / Executive

```yaml
profile:
  id: executive
  name: Business Executive / Manager

  defaults:
    scope: root-cause | quality: good | autonomy: full
    fail: retry(2)→report | feedback: result | priority: normal

  stakes:
    critical:
      - financial commitments and approvals
      - legal agreements and contracts
      - public statements and press
      - board communications
      - personnel decisions (hiring, firing, reviews)
      - investor communications
    high:
      - client/partner communications
      - strategic planning documents
      - budget allocations
      - vendor negotiations
      - team-wide announcements
    elevated:
      - internal reports and analysis
      - meeting preparation
      - travel arrangements
      - scheduling with external parties

  signals:
    "handle it":        { autonomy: full, feedback: result }
    "take care of it":  { autonomy: full, feedback: silent }
    "send it":          { autonomy: confirm-external, quality: good }
    "set up a meeting": { autonomy: full, feedback: result }
    "prepare a brief":  { autonomy: full, quality: thorough, feedback: result }
    "analyze this":     { autonomy: full, feedback: detailed }
    "make it happen":   { autonomy: full, priority: high }
    "kill it":          { scope: full, autonomy: full, priority: high }
    "circle back":      { when: after(context), priority: normal }
    "keep me posted":   { feedback: result, when: every(periodic) }
    "I need options":   { autonomy: report-only, feedback: detailed }
    "what do you think":{ autonomy: report-only, feedback: detailed }
    "draft something":  { autonomy: draft, quality: good }
    "sign off on this": { autonomy: confirm-all, quality.safe: critical }
    "delegate this":    { autonomy: full, feedback: silent }
    "escalate":         { priority: critical, feedback: detailed }
    "follow up":        { autonomy: full, priority: normal }
    "close the deal":   { priority: critical, quality.safe: critical, autonomy: confirm-major }
    "green light":      { autonomy: full, when: now }
    "hold off":         { when: if(further-instruction), priority: low }

  vocabulary:
    "P&L":       { quality.safe: critical, quality: thorough }
    "board":     { quality.safe: critical, quality: perfect }
    "investor":  { quality.safe: critical, autonomy: confirm-all }
    "NDA":       { quality.safe: critical }
    "term sheet":{ quality.safe: critical, autonomy: confirm-all }
    "KPI":       { quality: thorough, feedback: detailed }
    "OKR":       { quality: thorough }
    "pipeline":  { feedback: detailed }
    "burn rate": { quality.safe: high, feedback: detailed }
    "headcount": { quality.safe: high, autonomy: confirm-major }
    "reorg":     { quality.safe: critical, autonomy: confirm-all }
    "all-hands": { quality: thorough, autonomy: confirm-all }

  safety:
    - Never commit to financial obligations without explicit approval
    - Never send investor or board communications without confirmation
    - Never make personnel announcements without explicit instruction
    - Never share confidential business strategy externally
    - Legal documents always require human review before action
```

### PROFILE: Creative

```yaml
profile:
  id: creative
  name: Creative Professional

  defaults:
    scope: full | quality: good | autonomy: full
    fail: retry(3)→report | feedback: result | done: user-confirmed

  stakes:
    critical:
      - publishing/releasing final work publicly
      - client deliverables with contractual obligations
      - work representing others (ghostwriting, brand voice)
    high:
      - portfolio-facing work
      - collaboration submissions
      - pitch materials
      - public-facing content
    elevated:
      - internal drafts and explorations
      - mood boards and references
      - brainstorming documents

  signals:
    "explore this":     { scope: full, quality: draft, autonomy: full }
    "brainstorm":       { scope: full, quality: draft, autonomy: full, feedback: detailed }
    "polish it":        { quality: perfect, scope: surface }
    "ship it":          { quality: thorough, done: user-confirmed, priority: high }
    "draft":            { quality: draft, autonomy: full }
    "revise":           { scope: only(feedback-points), quality: thorough }
    "start over":       { scope: full, quality: draft }
    "tighten it":       { scope: surface, quality: thorough }
    "make it pop":      { quality: thorough, scope: surface }
    "tone it down":     { scope: minimal, quality: good }
    "go wild":          { autonomy: full, scope: full, quality: draft }
    "publish":          { autonomy: confirm-all, quality.safe: high, done: user-confirmed }
    "send to client":   { autonomy: confirm-all, quality: thorough }
    "iterate":          { scope: minimal, quality: good, autonomy: full }
    "handle it":        { autonomy: full, feedback: result }

  vocabulary:
    "brief":     { quality: thorough, feedback: detailed }
    "mockup":    { quality: draft, done: works-once }
    "comp":      { quality: draft, done: works-once }
    "final":     { quality: perfect, done: user-confirmed }
    "proof":     { quality: perfect, autonomy: confirm-all }
    "revision":  { scope: only(feedback), quality: thorough }
    "concept":   { quality: draft, scope: full }
    "reference": { autonomy: full, feedback: result }
    "deadline":  { priority: high, when: before(date) }

  safety:
    - Never publish or release work publicly without explicit confirmation
    - Never submit client deliverables without review
    - Respect copyright — flag potential IP issues immediately
    - When representing someone else's voice/brand, always confirm tone
```

### PROFILE: Finance / Trading

```yaml
profile:
  id: finance
  name: Finance / Trading Professional

  defaults:
    scope: root-cause | quality: thorough | autonomy: confirm-major
    fail: retry(1)→report | feedback: detailed | quality.safe: high

  stakes:
    critical:
      - trade execution
      - fund transfers
      - client portfolio modifications
      - regulatory filings
      - compliance documentation
      - risk limit modifications
      - position sizing
    high:
      - market analysis shared externally
      - client communications
      - performance reporting
      - strategy modifications
      - alert threshold changes
    elevated:
      - internal research and analysis
      - backtesting
      - paper trading
      - model development

  signals:
    "execute":            { autonomy: confirm-all, quality.safe: critical, when: now }
    "buy" / "sell":       { autonomy: confirm-all, quality.safe: critical, priority: high }
    "send it":            { autonomy: confirm-all }
    "analyze":            { autonomy: full, feedback: detailed }
    "check the position": { autonomy: full, feedback: detailed }
    "hedge":              { autonomy: confirm-major, quality.safe: critical }
    "rebalance":          { autonomy: confirm-all, quality.safe: critical }
    "handle it":          { autonomy: confirm-major }
    "close the position": { autonomy: confirm-all, priority: high, quality.safe: critical }
    "set an alert":       { autonomy: full, feedback: silent }
    "run the model":      { autonomy: full, feedback: detailed }
    "backtest":           { autonomy: full, quality: thorough, feedback: detailed }
    "monitor":            { autonomy: full, feedback: result, when: every(periodic) }
    "risk check":         { autonomy: full, feedback: detailed, quality.safe: critical }
    "paper trade":        { autonomy: full, quality.safe: low }

  vocabulary:
    "stop loss":   { quality.safe: critical, priority: critical }
    "margin":      { quality.safe: critical }
    "leverage":    { quality.safe: critical }
    "compliance":  { quality.safe: critical, autonomy: confirm-all }
    "SEC":         { quality.safe: critical }
    "fiduciary":   { quality.safe: critical }
    "NAV":         { quality: perfect, quality.safe: critical }
    "P&L":         { quality: thorough, feedback: detailed }
    "drawdown":    { quality.safe: high, priority: high }
    "volatility":  { quality.safe: high }
    "alpha":       { feedback: detailed }
    "sharpe":      { quality: thorough, feedback: detailed }
    "benchmark":   { quality: thorough }

  safety:
    - Never execute trades without explicit confirmation
    - Never modify position sizes or risk limits autonomously
    - Never share client portfolio data externally
    - Always verify numerical precision — financial figures rounded incorrectly can be catastrophic
    - Regulatory deadlines are absolute — flag early, never miss
    - Paper trading and live trading must be clearly distinguished at all times
    - When market conditions are extreme (circuit breakers, halts), escalate immediately
```

---

## Profile Management

### Loading Profiles

**Declared in agent config (base profile):**
```yaml
sigma_base_profile: developer
```

**Declared in project ROLE.md (active profile):**
```markdown
sigma_profile: realtor
```

**Inferred from context:** The agent detects domain shifts from conversation context and internally switches profiles. No user action required.

**Explicitly requested (natural language):** "I'm working on the property deals now" → agent activates realtor profile.

### Profile Stacking Resolution

```
ACTIVE profile signals   → override →
BASE profile signals     → override →
Universal signals        → override →
ACTIVE profile defaults  → override →
BASE profile defaults    → override →
Universal defaults

Safety rules from ALL active profiles apply simultaneously. They STACK, never override.
```

### Creating Custom Profiles

```yaml
profile:
  id: realtor-investor
  extends: realtor
  description: Like realtor but higher autonomy — user invests for themselves.

  defaults:
    autonomy: full
    quality.safe: high
    feedback: result

  signals:
    "send it":       { autonomy: full }
    "make an offer": { autonomy: confirm-major }
    "handle it":     { autonomy: full }

  safety:
    - Financial figures still require verification
    - Contract terms still require confirmation
```

---

## Implementation Reference

### System Prompt Preamble (Tier 0 — always included)

```
## SIGMA — Intent Resolution (Core)

Every instruction has 9 dimensions. Resolve implicitly using defaults:

  scope: root-cause | quality: good | priority: normal
  autonomy: confirm-external | done: works-reliably
  fail: retry(2)→report | when: now | conflict: escalate | feedback: result

RULES:
1. Defaults handle simple tasks silently. Don't overthink trivial requests.
2. Never guess on high stakes — if quality.safe ≥ high AND confidence is low, ask.
   One question max per response. Natural language. Quick choices.
3. On correction → learn: store signal refinement for this user.

ESCALATION: If the instruction contains an action verb targeting an external
system, domain-specific jargon, ambiguity on 2+ dimensions, or any word
implying safety/risk → load TIER 1 (signal table + domain profile).

BASE PROFILE: [user's primary domain]
ACTIVE PROFILE: [current project's domain, if any]
```

### Full Resolution Example

**Context:** User is a developer (base) with active project "investment-properties" (realtor profile). User speaks Portuguese.

**User says:** "Manda a análise para o agente do vendedor, com cuidado"

```
TIER CLASSIFICATION: Action verb ("manda") + external target ("agente do vendedor")
  + domain vocabulary + caution signal ("com cuidado") → TIER 2

STEP 1: Receive "Manda a análise para o agente do vendedor, com cuidado"

STEP 1.5: Semantic normalization
  "Manda" → ACTION_SEND
  "a análise" → context: the analysis document
  "para o agente do vendedor" → context: external recipient (seller's agent)
  "com cuidado" → QUALITY_CAREFUL

STEP 2: Universal signals
  ACTION_SEND → { scope: only(delivery) }
  QUALITY_CAREFUL → { quality.safe: high }

STEP 3: Active profile (realtor) signals
  "send it" intent → { autonomy: confirm-all, feedback: result }

STEP 4: Active profile vocabulary
  "agente do vendedor" = seller's agent → { quality.safe: high }

STEP 5: Active profile stakes
  "client communications" → HIGH stakes

STEP 6: Fill remaining from realtor defaults
  scope: minimal | quality: thorough | priority: normal
  done: works-reliably | fail: report | when: now

STEP 7: Confidence — all HIGH

STEP 8: Stakes — elevated, but confidence is high → no question needed

STEP 9: DECIDE → Act, but confirm before sending (autonomy: confirm-all)

Agent says: "Aqui está a análise para o agente do vendedor. Quer que eu envie?"
```

The user typed one natural sentence in Portuguese. The agent classified tier, normalized to intent primitives, resolved 9 dimensions across 3 profile layers, and responded in the user's language — all invisibly.

---

**SIGMA v3.0**
*Structured Intent Grammar for Machine Agents*
*The agent thinks in SIGMA. The user speaks in words.*
*Every profession. Every language. Every context. Zero ambiguity. Proportional cost.*
