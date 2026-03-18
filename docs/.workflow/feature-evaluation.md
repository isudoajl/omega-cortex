# Feature Evaluation: Intelligent Intent Dispatcher

## Feature Description
Add an intelligent intent dispatcher to OMEGA that automatically classifies user natural language requests and routes them to the correct workflow command (new, new-feature, bugfix, improve, audit, docs, sync, diagnose, etc.) without requiring the user to explicitly invoke a slash command. The dispatcher would sit as a top-level entry point and infer both the workflow type and scope from the user's description.

Source: Command arguments (no idea brief produced for this feature; `docs/.workflow/idea-brief.md` contains an unrelated Persona feature from a previous workflow run).

## Evaluation Summary

| Dimension | Score (1-5) | Assessment |
|-----------|-------------|------------|
| D1: Necessity | 1 | Claude Code natively auto-matches user natural language to available skills/commands based on their `description` frontmatter. OMEGA's 14 commands already have descriptions that enable this. Users are not blocked -- they can already say "fix this bug" and Claude will invoke `workflow:bugfix`. |
| D2: Impact | 2 | Would marginally reduce friction for users unfamiliar with the 14 command names, but Claude Code already provides this matching natively. The incremental improvement over the status quo is minimal. |
| D3: Complexity Cost | 3 | A single new command file in `core/commands/`. Moderate complexity in prompt engineering to reliably classify across 14 workflow types with correct scope extraction. Ongoing maintenance: must be updated every time a command is added, removed, or renamed. |
| D4: Alternatives | 1 | Claude Code's native skill/command discovery system already does exactly this. The `description` field in each command's YAML frontmatter is loaded into Claude's context, and Claude uses its language understanding to match user intent to the correct command. Additionally, the `workflow:new-feature` command already has built-in logic to conditionally invoke Discovery when descriptions are vague. |
| D5: Alignment | 2 | OMEGA's mission is multi-agent orchestration for code quality with strict pipelines and explicit gates. An intent dispatcher that guesses which pipeline to run moves away from explicit, deterministic workflow selection toward implicit, probabilistic routing -- counter to OMEGA's philosophy of "NEVER assume." |
| D6: Risk | 2 | Misclassification risk: routing a bugfix to `workflow:improve` or a new feature to `workflow:bugfix` triggers the wrong pipeline chain, wasting context budget and potentially producing incorrect artifacts. Silent misrouting is worse than requiring the user to pick the right command. Each workflow has fundamentally different agent chains and fail-safe controls. |
| D7: Timing | 3 | No blocking prerequisites. Project is stable. But the recent consolidation of commands (omega-feature to omega-new-feature, omega-improve-functionality to omega-improve) suggests the focus should remain on stabilizing existing commands, not adding a meta-routing layer. |

**Feature Viability Score: 1.8 / 5.0**

Calculation: ((1 + 2 + 2) x 2 + (3 + 1 + 2 + 3)) / 10 = (10 + 9) / 10 = 1.9

Override applied: D1 (Necessity) scores 1 --> verdict is NO-GO regardless of FVS.

## Verdict: NO-GO

This feature is redundant with Claude Code's native intent matching system. Claude Code already loads command descriptions into context and automatically routes natural language requests to the matching command. Building a custom dispatcher on top of this would duplicate built-in platform behavior, add a misclassification risk layer, and move OMEGA away from its philosophy of explicit, deterministic workflow selection.

## Detailed Analysis

### What Problem Does This Solve?
The stated problem is that users must know which of 14 slash commands to use and explicitly invoke them. In practice, this problem is already solved by Claude Code itself. As of the current platform (verified via Claude Code documentation at code.claude.com):

1. **Automatic skill/command matching**: Claude Code loads every command's `description` frontmatter into its context at session start. When a user types natural language like "fix the crash in the scheduler," Claude matches this against available command descriptions and invokes the appropriate one. OMEGA's 14 commands all have descriptive `description` fields (e.g., `workflow:bugfix` has "Fix a bug with a reduced chain").

2. **Skills and commands are merged**: Claude Code has unified `.claude/commands/` and `.claude/skills/` -- files in either location create the same `/slash-command` interface with the same auto-matching behavior.

3. **The Discovery agent already handles vagueness**: `workflow:new-feature` (lines 68-84 of the command definition) already includes logic to invoke Discovery when the feature description is vague, and skip it when specific. This is intent refinement within the pipeline, not external routing.

The user's problem is not "I can't find the right command" -- Claude Code handles that. The real question is whether OMEGA should add its own routing layer on top, and the answer is no: it would be redundant and less reliable than the platform's native matching.

### What Already Exists?
1. **Claude Code native intent matching** -- every OMEGA command deployed to `.claude/commands/` is automatically discoverable by Claude through its `description` field. No custom dispatcher needed.
2. **14 command files** with explicit descriptions in `core/commands/` -- each with YAML frontmatter `description` that Claude uses for matching (verified in `omega-bugfix.md`, `omega-improve.md`, `omega-new-feature.md`, `omega-diagnose.md`, etc.).
3. **Discovery agent** -- already acts as a pre-pipeline intent refinement mechanism for vague requests within `workflow:new-feature` and `workflow:new`.
4. **`omg` CLI** (`cli/src/cli.rs`) -- uses explicit subcommands (`omg init`, `omg update`, `omg doctor`) for deployment operations. The CLI is not a workflow execution tool; it deploys OMEGA to projects. The workflows are invoked inside Claude Code sessions via slash commands.

### Complexity Assessment
The implementation itself would be a single new command file (moderate complexity), but the real cost is in reliable classification:

- **14 workflow types** to discriminate between, some with subtle distinctions (e.g., `bugfix` vs. `diagnose`, `new-feature` vs. `improve`, `audit` vs. `sync`)
- **Scope extraction** from natural language is unreliable -- "fix the auth module" should become `--scope="auth"`, but "make the login page faster" requires understanding what "login page" maps to in the codebase
- **Ongoing maintenance**: every time a command is added, removed, renamed, or has its scope changed, the dispatcher's classification logic must be updated
- **Testing burden**: 14 workflow types x multiple phrasings each = a combinatorial validation matrix with no automated testing framework (OMEGA is markdown + shell scripts)

Maintenance cost estimate: Low file-change frequency (update dispatcher whenever a command changes), but high cognitive cost (verifying classification accuracy across 14 types is manual and error-prone).

### Risk Assessment
1. **Misclassification causes wrong pipeline execution**: Routing to `workflow:bugfix` instead of `workflow:improve` runs a fundamentally different agent chain (bugfix has bug reproduction; improve does not). Routing to `workflow:new` instead of `workflow:new-feature` skips the Feature Evaluator gate. Each misrouting wastes the user's context budget and potentially produces incorrect specs, tests, and code.

2. **Silent failure is worse than explicit choice**: When a user types `/omega:bugfix`, they know what pipeline they are entering. If a dispatcher silently chooses the wrong pipeline, the user may not notice until several agents deep -- by which point significant context and time have been consumed.

3. **Conflicts with OMEGA's "NEVER assume" rule**: Global Rule #2 in CLAUDE.md states "NEVER assume -- if something is unclear, the analyst must ask." A dispatcher that infers intent without confirmation violates this principle at the pipeline selection level.

## Conditions
N/A -- feature not recommended. See Alternatives.

## Alternatives Considered

- **Alternative 1: Rely on Claude Code's native intent matching (RECOMMENDED)**: Claude Code already does this. No changes needed. Users can type natural language, and Claude matches it to the right OMEGA command via the `description` frontmatter. If the descriptions are not sufficiently descriptive, improve them -- a 5-minute edit to existing command files. **Pros**: Zero new code, zero maintenance, zero misclassification risk (Claude's native matching is the most tested path), works immediately. **Cons**: Requires users to be in a Claude Code session (not applicable to CLI-only workflows, but those use `omg` which is a deployment tool, not a workflow runner).

- **Alternative 2: Improve command descriptions for better native matching**: Review and enhance the `description` field in all 14 command YAML frontmatter blocks to include more trigger keywords. For example, change `workflow:bugfix`'s description from "Fix a bug with a reduced chain" to "Fix a bug, defect, crash, error, or regression in existing code. Use when something that used to work is now broken." This improves Claude's native matching accuracy. **Pros**: 15 minutes of work, leverages platform capabilities, no new files. **Cons**: Minor -- descriptions are already reasonable.

- **Alternative 3: Add a `/omega:help` command**: Instead of auto-routing, create a command that describes all 14 workflows with examples of when to use each. Users invoke `/omega:help` when unsure, read the guidance, and then invoke the correct command explicitly. **Pros**: Educational, maintains explicit workflow selection, low complexity. **Cons**: Still requires user to make the final choice (which is a feature, not a bug).

## Recommendation

Do not build this feature. It is redundant with Claude Code's native command/skill discovery system, which already matches natural language to OMEGA's 14 commands via their `description` frontmatter. Building a custom dispatcher on top would add complexity, create misclassification risk, and duplicate platform-level functionality that Anthropic maintains and improves.

If users are having trouble finding the right command, spend 15 minutes improving the `description` fields in the 14 existing command YAML frontmatter blocks (Alternative 2). This is the highest-value, lowest-cost action and leverages the platform's own intent matching rather than competing with it.

## User Decision
[Awaiting user decision: PROCEED / ABORT / MODIFY]
