# Fail-Safe Controls

The workflow enforces guardrails at every level to prevent silent failures, infinite loops, and cascading garbage.

## Prerequisite Gates
Every agent that receives upstream output verifies its input exists before proceeding. If required input is missing, the agent **STOPS** with a clear error message identifying what's missing and which upstream agent failed.

| Agent | Required Input |
|-------|---------------|
| Analyst (after discovery) | `docs/.workflow/idea-brief.md` |
| Architect | Analyst requirements file in `specs/` |
| Test Writer | Architect design + Analyst requirements in `specs/` |
| Developer | Test files must exist |
| QA | Source code + test files must exist |
| Reviewer | Source code must exist |

## Iteration Limits
Multi-step commands enforce maximum iteration counts to prevent infinite loops:
- **QA <-> Developer loops:** Maximum **3 iterations**
- **Reviewer <-> Developer loops:** Maximum **2 iterations**
- **Audit --fix developer attempts:** Maximum **5** per finding (then escalated)
- **Audit --fix build/lint retries:** Maximum **3** per priority pass
- **Audit --fix verification iterations:** Maximum **2** per priority pass

If the limit is reached, the workflow STOPS and reports remaining issues to the user for a human decision.

## Inter-Step Output Validation
Multi-step commands verify that each agent produced its expected output file before invoking the next agent. If output is missing, the chain halts with a clear report of which step failed.

## Error Recovery
If any agent fails mid-chain, the workflow saves chain state to `docs/.workflow/chain-state.md` and updates memory.db with the failure. The user can resume with `/omega:resume`.

## Directory Safety
Every agent that writes output files verifies target directories exist before writing. If a directory is missing, the agent creates it.

## Developer Max Retry
The developer has a maximum of **5 attempts** per test-fix cycle for a single module. If tests still fail after 5 attempts, the developer stops and escalates for human review or architecture reassessment.

## Language-Agnostic Patterns
Test-writer and reviewer adapt their patterns to the project's language (detected from config files, architect design, or existing source). No agent assumes a specific language.
