# Idea Brief: OMEGA Persona -- Identity, Onboarding, and Adaptive Personality System

## One-Line Summary
Give OMEGA a persistent identity layer that knows who the user is, presents a configurable personality, guides first-time users through onboarding, and adapts its behavior based on accumulated experience -- all per-project, stored in `memory.db`.

## Problem Statement
Today, OMEGA is a powerful multi-agent toolkit but it feels like a faceless pipeline. Every session starts cold. The system has no idea who is using it, how experienced they are, or how they prefer to communicate. A user who has run 50 workflows gets the same unexplained output as someone launching their first `/omega:new`. There is no relationship continuity between sessions -- no "welcome back," no adaptation, no sense that OMEGA knows its user. This makes the experience transactional when it could be deeply personal.

## Current State
- **No user identity**: OMEGA does not know the user's name, role, or preferences.
- **No personality**: All agents communicate in a uniform, clinical tone. There is no OMEGA "voice."
- **No onboarding**: Users are dropped into the system with a command list. Understanding what OMEGA can do requires reading documentation.
- **No experience adaptation**: A first-time user and a power user receive identical verbosity and explanation levels.
- **Session-start briefing exists**: `briefing.sh` already injects institutional memory context once per session via the `UserPromptSubmit` hook. This is the natural injection point for identity/personality context.
- **`workflow_runs` already tracks usage**: The table records every pipeline execution with type, description, and status -- experience data is partially here already.

## Proposed Solution
Build a three-part system layered into OMEGA's existing architecture:

### Part 1: User Profile (DB tables + onboarding flow)
New `user_profile` and `onboarding_state` tables in `memory.db`. A dedicated `/omega:onboard` command (or auto-triggered on first session) guides the user through identity collection: name, experience level, communication preferences, and desired OMEGA personality archetype. Onboarding state is tracked so it never repeats.

### Part 2: OMEGA Personality Engine (briefing injection)
The `briefing.sh` hook gains a new section at the **top** of its output: the OMEGA Identity Block. This injects the user's name, their selected personality archetype, their experience level, and any communication preferences into Claude's context. Every agent in the session sees this context. The personality is a **relationship/branding layer** -- it wraps around agent-specific functional tones without overriding them.

### Part 3: Experience-Aware Adaptation
Track which workflows the user has run and how many times (leveraging existing `workflow_runs`). Add a `workflow_usage` view that summarizes usage counts per workflow type. OMEGA adapts verbosity: first time using a workflow gets more explanation; experienced usage gets streamlined output. The `experience_level` field (beginner/intermediate/advanced) is set during onboarding and auto-upgrades as usage accumulates past configurable thresholds.

## Target Users
- **Primary**: Solo developers using OMEGA on their projects -- they want a personal, adaptive AI coding companion that gets better at working with them over time.
- **Secondary**: Team leads who deploy OMEGA to team projects -- they may configure OMEGA's personality to match team culture.

## Success Criteria
- A new user running OMEGA for the first time is greeted and guided through a brief onboarding.
- After onboarding, OMEGA addresses the user by name and communicates in the selected personality style.
- Onboarding never repeats for a completed profile.
- A user who has run `/omega:new` ten times sees noticeably less hand-holding than someone running it the first time.
- The personality layer does NOT break existing agent protocols -- the Reviewer is still strict, the Developer still follows TDD, but they all "sound like OMEGA" and know the user.

## MVP Scope
What MUST be in v1:

1. **DB schema additions** (`core/db/schema.sql`):
   - `user_profile` table: `user_name`, `experience_level` (beginner/intermediate/advanced), `personality_archetype`, `communication_style` (e.g., verbose/balanced/terse), `custom_personality_notes`, `created_at`, `last_seen`
   - `onboarding_state` table: `step` (current onboarding step), `status` (not_started/in_progress/completed), `data` (JSON blob for partial onboarding state), `started_at`, `completed_at`
   - `workflow_usage` view: aggregates `workflow_runs` by type with counts, feeding experience adaptation

2. **Onboarding command** (`core/commands/omega-onboard.md`):
   - New command: `/omega:onboard`
   - Conversational flow (not a form) that collects: name, experience level, personality preference
   - Personality archetypes offered: Formal Mentor, Casual Pair-Programmer, Socratic Teacher, Terse Operator, or Custom
   - Saves to `user_profile` and marks `onboarding_state` as completed
   - Can be re-run to update preferences: `/omega:onboard --update`

3. **Briefing hook enhancement** (`core/hooks/briefing.sh`):
   - New section at the TOP of briefing output (before hotspots): OMEGA Identity Block
   - Queries `user_profile` for name, personality, experience level
   - Queries `workflow_usage` view for usage patterns
   - Outputs personality instructions that all agents receive
   - If `onboarding_state` is not completed, outputs a prompt to run `/omega:onboard`

4. **Auto-trigger on first session**:
   - When `briefing.sh` detects no `user_profile` exists, it outputs a message: "Welcome to OMEGA. Run `/omega:onboard` to personalize your experience."
   - NOT forced -- the user can skip and use OMEGA without onboarding

5. **Experience-level auto-upgrade logic**:
   - Thresholds in `briefing.sh` or a maintenance query: beginner -> intermediate after N workflow completions, intermediate -> advanced after M
   - Simple, not gamified -- just practical adaptation

6. **CLAUDE.md personality protocol** (appended to workflow rules section):
   - New "OMEGA Identity" section in the workflow rules that instructs all agents to read personality context from the briefing and adapt their communication style accordingly while preserving functional tone
   - Clear guidance: personality is additive, not overriding

## Explicitly Out of Scope
- **Global cross-project profiles**: User identity is per-project `memory.db`. No shared global profile across projects (could be a future enhancement).
- **Gamification/RPG systems**: No XP points, levels with names, badges, or achievement systems. Experience tracking is purely practical.
- **Per-agent personality customization**: Users do not configure different personalities per agent. One personality wraps all agents.
- **Avatar or visual identity**: No images, icons, or visual branding -- this is a CLI tool.
- **Multi-user support**: One user per project. No user switching, authentication, or team profiles.
- **Natural language personality modification mid-session**: Users change personality via `/omega:onboard --update`, not by saying "be more casual" in conversation.

## Key Decisions Made
- **Per-project, not global**: Personality and identity live in each project's `memory.db`. Rationale: OMEGA's entire memory system is per-project. Adding a global layer would require a new storage mechanism and cross-project synchronization -- complexity that is not justified for v1.
- **Relationship layer, not tone override**: Personality wraps around agents but does not replace their functional tone. The Reviewer stays strict even if OMEGA's personality is "casual." Rationale: Agent tone is functional -- a casual reviewer would miss severity. The personality manifests in greetings, explanations, encouragement, and framing, not in technical rigor.
- **Conversational onboarding, not a form**: The onboarding command runs as a conversation, not a settings dump. Rationale: OMEGA's first interaction with the user should exemplify the personal relationship being built.
- **Auto-prompt, not auto-force**: First session suggests onboarding but does not block usage. Rationale: Some users want to dive in immediately. Forced onboarding feels like a corporate HR tool.
- **Briefing hook is the injection point**: No new hooks needed. The existing `briefing.sh` UserPromptSubmit hook already fires once per session and injects context. Adding personality to it is the architecturally clean path.
- **OMEGA presents as OMEGA, not Claude Code**: The identity layer establishes OMEGA as its own entity. Agents say "I" as OMEGA, not as Claude.

## Directions Explored and Rejected
- **Global profile stored in `~/.omega/profile.db`**: Would enable cross-project identity persistence. Rejected because it introduces a new storage location outside the project, complicates the setup script, and raises questions about sync and migration. The benefit (not re-onboarding per project) does not justify the complexity in v1.
- **RPG-style experience system with levels and titles**: ("Novice -> Apprentice -> Journeyman -> Master"). Rejected because it adds cognitive overhead, feels gimmicky for a professional tool, and the practical benefit (verbosity adaptation) does not require gamification.
- **Deep psychological profiling during onboarding**: (learning style, frustration handling, motivation patterns). Rejected because it makes onboarding feel invasive, the data is hard to act on meaningfully, and simple preferences (verbose/terse, formal/casual) capture 80% of the value.
- **Per-agent personality configuration**: (different personality for Reviewer vs. Developer). Rejected because it creates combinatorial complexity, confuses the user identity ("which OMEGA is talking to me?"), and the agent's functional tone already differentiates their communication style.

## Open Questions
- **Personality archetype definitions**: What exactly does each archetype mean in terms of prompt instructions? The Analyst should define the specific behavioral rules for each archetype (Formal Mentor: uses structured language, explains rationale, addresses user formally; Casual Pair-Programmer: uses contractions, shorter sentences, more direct, etc.).
- **Experience threshold values**: At what workflow completion counts should experience auto-upgrade? Suggested: beginner -> intermediate at 10 completed workflows, intermediate -> advanced at 30. Needs validation.
- **`last_seen` update mechanism**: Should `briefing.sh` update `user_profile.last_seen` on every session start? This adds a write to the read-only briefing hook. Alternative: update it in the first `workflow_runs` INSERT of each session.
- **Onboarding resumability**: If the user quits mid-onboarding, should it resume from where they left off? The `onboarding_state.data` JSON blob supports this, but the onboarding command needs to implement it.
- **Personality in non-pipeline sessions**: When the user works outside a `/omega:*` command (manual sessions), does OMEGA still use the personality? Answer should be yes since `briefing.sh` fires on all sessions, but this should be confirmed.
- **Schema migration for existing projects**: Projects already deployed with OMEGA have an existing `memory.db` without the new tables. The `db-init.sh` script uses `CREATE TABLE IF NOT EXISTS` so it handles this, but should the onboarding prompt appear for existing heavy users on first session after upgrade?

## Constraints
- **Technology**: Pure SQLite + bash (briefing hook) + markdown (agent definitions and CLAUDE.md rules). No external services, no new runtimes.
- **Scale**: Single user per project. The profile tables will have exactly one row each. Performance is not a concern.
- **Integration**: Must integrate with existing `briefing.sh` hook, `db-init.sh` migration path, `setup.sh` deployment, and the CLAUDE.md workflow rules injection. Must not break any existing agent protocol.
- **Backward compatibility**: Existing OMEGA deployments must continue working after this change. The personality system must be graceful when no profile exists -- identical to current behavior.

## Risks & Unknowns
- **Prompt budget consumption**: The personality block injected by `briefing.sh` adds tokens to every session. If the personality instructions are too verbose, they eat into the 60% context budget that agents operate under. Mitigation: keep the personality injection compact (under 200 tokens).
- **Personality drift across long sessions**: Claude's context window may "forget" or deprioritize the personality instructions injected at session start as the conversation grows. The personality may feel strong at the beginning and fade. Mitigation: personality instructions should be concise and high-priority-positioned; the `debrief-nudge.sh` hook could optionally reinforce identity.
- **Agent functional tone conflict**: Despite the "relationship layer" framing, some personality archetypes could conflict with agent function. A "Casual Pair-Programmer" personality on the QA agent could undermine the seriousness of P0 findings. Mitigation: the CLAUDE.md personality protocol must clearly state that severity, technical accuracy, and protocol compliance always override personality tone.
- **Onboarding quality dependence on the model**: The conversational onboarding experience depends on Claude executing a natural, flowing conversation. If the model is switched or degrades, onboarding could feel robotic. Mitigation: the onboarding command should have fallback structured prompts if the conversation stalls.
- **#1 Kill Risk**: **Personality injection interferes with agent reliability.** If the personality prompt causes agents to deviate from their strict protocols (TDD, read-only, iteration limits), the entire OMEGA quality guarantee breaks. This is mitigable with clear prompt hierarchy (protocol > personality) but must be validated with real usage across all 14 agents.

## Analogies & References
- **Brand voice over departmental function** (corporate communications): A company has a brand personality (friendly, authoritative, irreverent) but Legal still writes like Legal and Engineering still writes like Engineering. The brand voice shows up in the wrapper -- how you are greeted, how bad news is framed, how achievements are celebrated -- not in the technical substance. This is exactly the model for OMEGA personality: it is the brand voice, agents are the departments.
- **Video game companion AI** (e.g., Cortana in Halo, Ghost in Destiny): These companions have a persistent personality and remember the player's progress, but they adapt their guidance based on experience. Early in the game they explain mechanics; later they just call out tactical information. The adaptation is practical, not gamified -- the companion gets less verbose because the player already knows. This maps to OMEGA's experience-aware verbosity adaptation.
- **IDE themes and settings** (VS Code, JetBrains): Developers customize their tools not because the defaults are broken but because personalization creates ownership and comfort. OMEGA personality customization serves the same function -- it makes the tool feel like *your* tool, not a generic system.

## Files That Will Need Changes

### New Files
| File | Purpose |
|------|---------|
| `core/commands/omega-onboard.md` | Onboarding command definition |
| `core/agents/onboard.md` | Onboarding agent (conversational profile collection) |

### Modified Files
| File | What Changes |
|------|-------------|
| `core/db/schema.sql` | Add `user_profile` table, `onboarding_state` table, `workflow_usage` view |
| `core/hooks/briefing.sh` | Add OMEGA Identity Block at top of briefing output; query user profile and experience |
| `scripts/setup.sh` | Register new command in deployment; update command listing in summary |
| `scripts/db-init.sh` | No changes needed (`CREATE TABLE IF NOT EXISTS` handles migration) |
| `CLAUDE.md` | Add "OMEGA Identity" section to workflow rules with personality protocol for all agents |
| `README.md` | Document new command, new tables, personality system |
| `docs/agent-inventory.md` | Add onboard agent |
| `docs/institutional-memory.md` | Document new tables |
