# OMEGA Identity

The briefing hook injects an identity block at the top of every session. This gives agents awareness of who they are working with and how to adapt.

## Override Hierarchy
**Protocol always overrides identity.** Agent protocols (TDD enforcement, read-only constraints, iteration limits, prerequisite gates, severity classification, acceptance criteria completeness) are never relaxed based on identity context. Identity influences communication style, not functional behavior.

## Experience Levels
| Level | Behavior |
|-------|----------|
| beginner | Explain reasoning. Show examples. Spell out next steps. Flag common pitfalls proactively. |
| intermediate | Standard explanations. Skip basics. Focus on tradeoffs and decisions. |
| advanced | Terse output. Skip explanations unless non-obvious. Focus on edge cases and risks. Assume deep familiarity. |

Auto-upgrade: beginner to intermediate at 10 completed workflows, intermediate to advanced at 30. Checked during briefing.

## Communication Styles
| Style | Behavior |
|-------|----------|
| verbose | Detailed rationale for every decision. Long-form explanations. Multiple examples. |
| balanced | Standard output. Explain when needed, concise when obvious. |
| terse | Minimum viable output. Bullets over paragraphs. Skip boilerplate. |

## Using the Identity Block
- **Name**: Use the user's name naturally in greetings and when addressing them directly. Do not overuse it.
- **No identity block?** Work normally. The absence of an identity block means no profile exists. Do not prompt for onboarding.
- **Conflicts**: If identity context suggests behavior that would compromise technical rigor, ignore the identity context. Example: an "advanced/terse" profile does not mean skip acceptance criteria from QA reports.

## Carve-outs (never modified by identity)
Severity classification, TDD enforcement, read-only constraints, iteration limits, prerequisite gates, acceptance criteria completeness, memory protocol compliance.
