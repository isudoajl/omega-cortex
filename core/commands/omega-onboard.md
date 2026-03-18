---
name: omega:onboard
description: "Set up your OMEGA identity profile. Three questions: name, experience level, communication style. Use --update to modify an existing profile."
---

# Workflow: Onboard

## Purpose
Set up your OMEGA identity. Three questions: name, experience level, communication style. The profile personalizes how agents communicate with you across all sessions.

## Flags
- `--update` -- modify an existing profile instead of creating one

## Pipeline Tracking (Institutional Memory)
Register a lightweight workflow run:

**At start:**
```bash
sqlite3 .claude/memory.db "INSERT INTO workflow_runs (type, description) VALUES ('onboard', 'User profile setup');"
RUN_ID=$(sqlite3 .claude/memory.db "SELECT last_insert_rowid();")
```

**At end:**
```bash
sqlite3 .claude/memory.db "UPDATE workflow_runs SET status='completed', completed_at=datetime('now') WHERE id=$RUN_ID;"
```

## Flow

### Step 1: Check existing state
- Query `onboarding_state` and `user_profile`
- If `--update` and no profile exists: inform user, proceed as new onboarding
- If no `--update` and profile exists: inform user profile exists, suggest `--update`
- If `onboarding_state.status = 'in_progress'` and `data` contains partial answers: resume from last incomplete step

### Step 2: Register workflow run
Use the RUN_ID from the Pipeline Tracking section above. Do NOT insert a second workflow_runs row.

### Step 3: Conversational questions (3 total)
1. **Name**: "What should I call you?"
   - Stores answer in `onboarding_state.data` JSON immediately
   - Updates `onboarding_state.step = 'name'`, `status = 'in_progress'`

2. **Experience level**: "How much experience do you have with AI-assisted development workflows?"
   - Options: beginner (new to structured AI workflows), intermediate (familiar with TDD and multi-step pipelines), advanced (extensive experience, want minimal hand-holding)
   - Stores answer in `onboarding_state.data` JSON immediately

3. **Communication style**: "How do you prefer OMEGA to communicate?"
   - Options: verbose (detailed explanations), balanced (explain when needed), terse (minimum viable output)
   - Stores answer in `onboarding_state.data` JSON immediately

### Step 4: Write profile
- For new: `INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES (?, ?, ?);`
- For update: `UPDATE user_profile SET user_name=?, experience_level=?, communication_style=?;`

### Step 5: Mark complete
```bash
UPDATE onboarding_state SET status='completed', completed_at=datetime('now');
UPDATE workflow_runs SET status='completed', completed_at=datetime('now') WHERE id=$RUN_ID;
```
- Log outcome to `outcomes` table

### Step 6: Confirmation
- Show the identity block that will appear in future sessions
- Remind user they can update anytime with `/omega:onboard --update`
- Remind user about `/output-style` for tone customization beyond what OMEGA identity provides

## No Agent Required
This command operates directly without a dedicated agent. Claude executes the conversational flow using standard prompting.

## Resumability
If the user quits mid-onboard:
- `onboarding_state.data` contains partial answers as JSON: `{"name": "Ivan", "experience_level": "intermediate"}`
- Next invocation of `/omega:onboard` reads `onboarding_state.data` and resumes from the last incomplete question
- If `onboarding_state.status = 'in_progress'`: ask "You started onboarding earlier. Want to continue from where you left off?"

## Manual Alternative
Users who prefer CLI can skip this command and set their profile directly:
```bash
sqlite3 .claude/memory.db "INSERT INTO user_profile (user_name, experience_level, communication_style) VALUES ('Your Name', 'beginner', 'balanced');"
```
Valid experience levels: `beginner`, `intermediate`, `advanced`
Valid communication styles: `verbose`, `balanced`, `terse`
