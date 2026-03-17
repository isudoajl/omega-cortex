#!/bin/bash
# Setup script to initialize the workflow in any project
#
# Usage:
#   bash setup.sh                           # core only
#   bash setup.sh --ext=blockchain          # core + blockchain extension
#   bash setup.sh --ext=blockchain,omega    # core + multiple extensions
#   bash setup.sh --ext=all                 # core + all extensions
#   bash setup.sh --no-db                   # skip SQLite initialization
#   bash setup.sh --list-ext                # list available extensions
#   bash setup.sh --verbose                 # show unchanged files individually
#
# Run from the TARGET project directory, or pass the path:
#   bash /path/to/claude-workflow/scripts/setup.sh

set -e

# Detect script directory (the claude-workflow repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Parse arguments
EXTENSIONS=""
SKIP_DB=false
LIST_EXT=false
VERBOSE=false

for arg in "$@"; do
    case $arg in
        --ext=*)
            EXTENSIONS="${arg#*=}"
            ;;
        --no-db)
            SKIP_DB=true
            ;;
        --list-ext)
            LIST_EXT=true
            ;;
        --verbose)
            VERBOSE=true
            ;;
        --help|-h)
            echo "Usage: bash setup.sh [--ext=name1,name2] [--no-db] [--list-ext] [--verbose]"
            echo ""
            echo "Options:"
            echo "  --ext=EXT     Install extensions (comma-separated, or 'all')"
            echo "  --no-db       Skip SQLite institutional memory initialization"
            echo "  --list-ext    List available extensions and exit"
            echo "  --verbose     Show unchanged files individually (default: summary count)"
            echo "  --help        Show this help"
            exit 0
            ;;
    esac
done

# List extensions
if [ "$LIST_EXT" = true ]; then
    echo "Available extensions:"
    echo ""
    for ext_dir in "$SCRIPT_DIR/extensions"/*/; do
        ext_name=$(basename "$ext_dir")
        agent_count=$(ls "$ext_dir/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
        cmd_count=$(ls "$ext_dir/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
        echo "  $ext_name ($agent_count agents, $cmd_count commands)"
        # List agents
        for agent in "$ext_dir/agents/"*.md; do
            [ -f "$agent" ] && echo "    - $(basename "$agent" .md)"
        done
    done
    exit 0
fi

# ============================================================
# CHANGE DETECTION HELPERS
# ============================================================
TOTAL_NEW=0
TOTAL_UPDATED=0
TOTAL_UNCHANGED=0

copy_if_changed() {
    local src="$1"
    local dest="$2"
    if [ ! -f "$dest" ]; then
        cp "$src" "$dest"
        COPY_STATUS="new"
        TOTAL_NEW=$((TOTAL_NEW + 1))
    elif ! cmp -s "$src" "$dest"; then
        cp "$src" "$dest"
        COPY_STATUS="updated"
        TOTAL_UPDATED=$((TOTAL_UPDATED + 1))
    else
        COPY_STATUS="unchanged"
        TOTAL_UNCHANGED=$((TOTAL_UNCHANGED + 1))
    fi
}

echo "Setting up Claude Code Quality Workflow..."
echo ""

# Check Claude Code
if ! command -v claude &> /dev/null; then
    echo "  Claude Code not detected in PATH."
    echo "   Install it with: npm install -g @anthropic-ai/claude-code"
    echo "   Continuing file setup..."
    echo ""
fi

# Check git
if ! git rev-parse --is-inside-work-tree &> /dev/null 2>&1; then
    echo "  Initializing git repository..."
    git init
    echo ""
fi

# ============================================================
# CORE AGENTS
# ============================================================
echo "  Copying core agents..."
mkdir -p .claude/agents
SECTION_UNCHANGED=0
for agent in "$SCRIPT_DIR/core/agents/"*.md; do
    name=$(basename "$agent")
    copy_if_changed "$agent" ".claude/agents/$name"
    case "$COPY_STATUS" in
        new)       echo "   + $name" ;;
        updated)   echo "   ~ $name" ;;
        unchanged)
            SECTION_UNCHANGED=$((SECTION_UNCHANGED + 1))
            if [ "$VERBOSE" = true ]; then
                echo "   = $name"
            fi
            ;;
    esac
done
if [ "$VERBOSE" = false ] && [ "$SECTION_UNCHANGED" -gt 0 ]; then
    echo "   ($SECTION_UNCHANGED unchanged)"
fi

# ============================================================
# CORE COMMANDS
# ============================================================
echo ""
echo "  Copying core commands..."
mkdir -p .claude/commands
SECTION_UNCHANGED=0
for cmd in "$SCRIPT_DIR/core/commands/"*.md; do
    name=$(basename "$cmd")
    copy_if_changed "$cmd" ".claude/commands/$name"
    case "$COPY_STATUS" in
        new)       echo "   + ${name%.md}" ;;
        updated)   echo "   ~ ${name%.md}" ;;
        unchanged)
            SECTION_UNCHANGED=$((SECTION_UNCHANGED + 1))
            if [ "$VERBOSE" = true ]; then
                echo "   = ${name%.md}"
            fi
            ;;
    esac
done
if [ "$VERBOSE" = false ] && [ "$SECTION_UNCHANGED" -gt 0 ]; then
    echo "   ($SECTION_UNCHANGED unchanged)"
fi

# ============================================================
# EXTENSIONS
# ============================================================
if [ -n "$EXTENSIONS" ]; then
    echo ""
    echo "  Installing extensions..."

    # Expand "all" to list of all available extensions
    if [ "$EXTENSIONS" = "all" ]; then
        EXTENSIONS=""
        for ext_dir in "$SCRIPT_DIR/extensions"/*/; do
            ext_name=$(basename "$ext_dir")
            if [ -n "$EXTENSIONS" ]; then
                EXTENSIONS="$EXTENSIONS,$ext_name"
            else
                EXTENSIONS="$ext_name"
            fi
        done
    fi

    # Install each extension
    IFS=',' read -ra EXT_ARRAY <<< "$EXTENSIONS"
    for ext in "${EXT_ARRAY[@]}"; do
        ext=$(echo "$ext" | tr -d ' ')  # trim whitespace
        ext_path="$SCRIPT_DIR/extensions/$ext"

        if [ ! -d "$ext_path" ]; then
            echo "   WARNING: Extension '$ext' not found at $ext_path — skipping"
            continue
        fi

        echo ""
        echo "   Extension: $ext"

        # Copy extension agents
        if [ -d "$ext_path/agents" ]; then
            SECTION_UNCHANGED=0
            for agent in "$ext_path/agents/"*.md; do
                [ -f "$agent" ] || continue
                name=$(basename "$agent")
                copy_if_changed "$agent" ".claude/agents/$name"
                case "$COPY_STATUS" in
                    new)       echo "    + agent: $name" ;;
                    updated)   echo "    ~ agent: $name" ;;
                    unchanged)
                        SECTION_UNCHANGED=$((SECTION_UNCHANGED + 1))
                        if [ "$VERBOSE" = true ]; then
                            echo "    = agent: $name"
                        fi
                        ;;
                esac
            done
            if [ "$VERBOSE" = false ] && [ "$SECTION_UNCHANGED" -gt 0 ]; then
                echo "    ($SECTION_UNCHANGED agents unchanged)"
            fi
        fi

        # Copy extension commands
        if [ -d "$ext_path/commands" ]; then
            SECTION_UNCHANGED=0
            for cmd in "$ext_path/commands/"*.md; do
                [ -f "$cmd" ] || continue
                name=$(basename "$cmd")
                copy_if_changed "$cmd" ".claude/commands/$name"
                case "$COPY_STATUS" in
                    new)       echo "    + command: ${name%.md}" ;;
                    updated)   echo "    ~ command: ${name%.md}" ;;
                    unchanged)
                        SECTION_UNCHANGED=$((SECTION_UNCHANGED + 1))
                        if [ "$VERBOSE" = true ]; then
                            echo "    = command: ${name%.md}"
                        fi
                        ;;
                esac
            done
            if [ "$VERBOSE" = false ] && [ "$SECTION_UNCHANGED" -gt 0 ]; then
                echo "    ($SECTION_UNCHANGED commands unchanged)"
            fi
        fi
    done
fi

# ============================================================
# PROJECT STRUCTURE
# ============================================================
echo ""
echo "  Ensuring project structure..."
if [ ! -d "./specs" ]; then
    mkdir -p specs
    echo "   + specs/ created"
else
    echo "   = specs/ already exists"
fi

if [ ! -d "./docs" ]; then
    mkdir -p docs
    echo "   + docs/ created"
else
    echo "   = docs/ already exists"
fi

mkdir -p docs/.workflow

if [ ! -f "./specs/SPECS.md" ]; then
    cat > ./specs/SPECS.md << 'EOF'
# SPECS.md — Technical Specifications

> Master index of all technical specification documents.

## Specification Files

_(No specs yet. The workflow agents will populate this as you build.)_
EOF
    echo "   + specs/SPECS.md created"
else
    echo "   = specs/SPECS.md already exists"
fi

if [ ! -f "./docs/DOCS.md" ]; then
    cat > ./docs/DOCS.md << 'EOF'
# DOCS.md — Documentation

> Master index of all user-facing and developer documentation.

## Documentation Files

_(No docs yet. The workflow agents will populate this as you build.)_
EOF
    echo "   + docs/DOCS.md created"
else
    echo "   = docs/DOCS.md already exists"
fi

# ============================================================
# HOOKS (automated briefing/debrief)
# ============================================================
echo ""
echo "  Deploying automation hooks..."
mkdir -p .claude/hooks
SECTION_UNCHANGED=0
for hook in "$SCRIPT_DIR/core/hooks/"*.sh; do
    [ -f "$hook" ] || continue
    name=$(basename "$hook")
    copy_if_changed "$hook" ".claude/hooks/$name"
    # Always enforce executable permission regardless of copy status
    chmod +x ".claude/hooks/$name"
    case "$COPY_STATUS" in
        new)       echo "   + hook: $name" ;;
        updated)   echo "   ~ hook: $name" ;;
        unchanged)
            SECTION_UNCHANGED=$((SECTION_UNCHANGED + 1))
            if [ "$VERBOSE" = true ]; then
                echo "   = hook: $name"
            fi
            ;;
    esac
done
if [ "$VERBOSE" = false ] && [ "$SECTION_UNCHANGED" -gt 0 ]; then
    echo "   ($SECTION_UNCHANGED unchanged)"
fi

# Configure hooks in settings.json (merge, don't overwrite)
# Use absolute path — $CLAUDE_PROJECT_DIR doesn't reliably expand at runtime
SETTINGS_FILE=".claude/settings.json"
PROJECT_ABS_PATH="$(pwd)"

# Generate hooks JSON with absolute paths
generate_hooks_json() {
    cat << EOF
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "${PROJECT_ABS_PATH}/.claude/hooks/briefing.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${PROJECT_ABS_PATH}/.claude/hooks/debrief-gate.sh",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "${PROJECT_ABS_PATH}/.claude/hooks/incremental-gate.sh",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${PROJECT_ABS_PATH}/.claude/hooks/incremental-gate.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "${PROJECT_ABS_PATH}/.claude/hooks/debrief-nudge.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "${PROJECT_ABS_PATH}/.claude/hooks/session-close.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
EOF
}

CLAUDE_MD_STATUS="unchanged"

if [ -f "$SETTINGS_FILE" ]; then
    # Check if hooks have actually changed before writing
    GENERATED_HOOKS=$(generate_hooks_json)
    HOOKS_COMPARE_RESULT=$(python3 -c "
import json, sys
try:
    with open('$SETTINGS_FILE', 'r') as f:
        settings = json.load(f)
    new_hooks = json.loads(sys.stdin.read())
    if 'hooks' in settings and settings['hooks'] == new_hooks['hooks']:
        print('unchanged')
    else:
        print('changed')
except (json.JSONDecodeError, ValueError, KeyError):
    print('error')
" <<< "$GENERATED_HOOKS" 2>/dev/null || echo "error")

    if [ "$HOOKS_COMPARE_RESULT" = "unchanged" ]; then
        echo "   = hooks already configured"
    elif [ "$HOOKS_COMPARE_RESULT" = "error" ]; then
        # Existing file is malformed or unreadable -- overwrite it
        generate_hooks_json > "$SETTINGS_FILE"
        echo "   + settings.json created with hooks"
        TOTAL_UPDATED=$((TOTAL_UPDATED + 1))
    else
        # Hooks changed -- merge them into existing settings
        if python3 -c "
import json, sys
try:
    with open('$SETTINGS_FILE', 'r') as f:
        settings = json.load(f)
except (json.JSONDecodeError, ValueError):
    settings = {}
hooks = json.loads(sys.stdin.read())
settings['hooks'] = hooks['hooks']
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" <<< "$GENERATED_HOOKS" 2>/dev/null; then
            echo "   ~ hooks updated in settings.json"
            TOTAL_UPDATED=$((TOTAL_UPDATED + 1))
        else
            echo "   WARNING: Could not merge hooks — overwriting settings.json"
            generate_hooks_json > "$SETTINGS_FILE"
            echo "   + settings.json created with hooks"
            TOTAL_NEW=$((TOTAL_NEW + 1))
        fi
    fi
else
    generate_hooks_json > "$SETTINGS_FILE"
    echo "   + settings.json created with hooks"
    TOTAL_NEW=$((TOTAL_NEW + 1))
fi

# ============================================================
# WORKFLOW RULES (CLAUDE.md)
# ============================================================
echo ""
echo "  Configuring workflow rules..."

# Extract the workflow rules section (everything from "# Claude Code Quality Workflow" onwards)
WORKFLOW_RULES_FILE="$SCRIPT_DIR/CLAUDE.md"
WORKFLOW_MARKER="# Claude Code Quality Workflow"

if [ -f "$WORKFLOW_RULES_FILE" ]; then
    # Extract the source workflow rules for comparison
    SOURCE_RULES=$(sed -n "/$WORKFLOW_MARKER/,\$p" "$WORKFLOW_RULES_FILE")

    if [ -f "./CLAUDE.md" ]; then
        # Check if workflow rules are already appended
        if grep -q "$WORKFLOW_MARKER" ./CLAUDE.md 2>/dev/null; then
            # Extract current workflow rules from target for comparison
            CURRENT_RULES=$(sed -n "/$WORKFLOW_MARKER/,\$p" ./CLAUDE.md)

            if [ "$CURRENT_RULES" = "$SOURCE_RULES" ]; then
                # Rules are identical -- skip rewriting
                echo "   = Workflow rules already current"
            else
                # Rules differ -- replace them
                # Remove old workflow rules (everything from the marker to EOF) and re-append
                # Find the line number of the marker
                MARKER_LINE=$(grep -n "$WORKFLOW_MARKER" ./CLAUDE.md | head -1 | cut -d: -f1)
                if [ -n "$MARKER_LINE" ]; then
                    # Also remove the separator line before the marker (the --- line)
                    PREV_LINE=$((MARKER_LINE - 1))
                    PREV_CONTENT=$(sed -n "${PREV_LINE}p" ./CLAUDE.md)
                    if [ "$PREV_CONTENT" = "---" ]; then
                        # Check if there's a blank line before the ---
                        PREV_PREV_LINE=$((PREV_LINE - 1))
                        PREV_PREV_CONTENT=$(sed -n "${PREV_PREV_LINE}p" ./CLAUDE.md)
                        if [ -z "$PREV_PREV_CONTENT" ]; then
                            CUT_LINE=$PREV_PREV_LINE
                        else
                            CUT_LINE=$PREV_LINE
                        fi
                    else
                        CUT_LINE=$MARKER_LINE
                    fi
                    # Keep everything before the cut line
                    head -n $((CUT_LINE - 1)) ./CLAUDE.md > ./CLAUDE.md.tmp
                    mv ./CLAUDE.md.tmp ./CLAUDE.md
                fi

                # Append the updated workflow rules section
                echo "" >> ./CLAUDE.md
                echo "---" >> ./CLAUDE.md
                echo "" >> ./CLAUDE.md
                sed -n "/$WORKFLOW_MARKER/,\$p" "$WORKFLOW_RULES_FILE" >> ./CLAUDE.md
                echo "   ~ Workflow rules updated (replaced existing rules)"
                TOTAL_UPDATED=$((TOTAL_UPDATED + 1))
                CLAUDE_MD_STATUS="updated"
            fi
        else
            echo "   + Workflow rules appended to existing CLAUDE.md"
            TOTAL_NEW=$((TOTAL_NEW + 1))
            CLAUDE_MD_STATUS="appended"

            # Append the workflow rules section
            echo "" >> ./CLAUDE.md
            echo "---" >> ./CLAUDE.md
            echo "" >> ./CLAUDE.md
            sed -n "/$WORKFLOW_MARKER/,\$p" "$WORKFLOW_RULES_FILE" >> ./CLAUDE.md
        fi
    else
        # No CLAUDE.md exists — create one with just the workflow rules
        echo "# CLAUDE.md" > ./CLAUDE.md
        echo "" >> ./CLAUDE.md
        echo "This file provides guidance to Claude Code when working with code in this repository." >> ./CLAUDE.md
        echo "" >> ./CLAUDE.md
        echo "## Project-Specific Rules" >> ./CLAUDE.md
        echo "" >> ./CLAUDE.md
        echo "_(Add your project-specific rules here.)_" >> ./CLAUDE.md
        echo "" >> ./CLAUDE.md
        echo "---" >> ./CLAUDE.md
        echo "" >> ./CLAUDE.md
        sed -n "/$WORKFLOW_MARKER/,\$p" "$WORKFLOW_RULES_FILE" >> ./CLAUDE.md
        echo "   + CLAUDE.md created with workflow rules"
        TOTAL_NEW=$((TOTAL_NEW + 1))
        CLAUDE_MD_STATUS="created"
    fi
else
    echo "   WARNING: Toolkit CLAUDE.md not found at $WORKFLOW_RULES_FILE — skipping"
fi

# ============================================================
# INSTITUTIONAL MEMORY (SQLite)
# ============================================================
if [ "$SKIP_DB" = false ]; then
    echo ""
    echo "  Initializing institutional memory..."
    bash "$SCRIPT_DIR/scripts/db-init.sh" "."
fi

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "======================================================="
echo "  Workflow configured successfully"
echo "======================================================="
echo ""

# Count what was installed
AGENT_COUNT=$(ls .claude/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
CMD_COUNT=$(ls .claude/commands/*.md 2>/dev/null | wc -l | tr -d ' ')

# Build summary with change counts
if [ "$TOTAL_NEW" -eq 0 ] && [ "$TOTAL_UPDATED" -eq 0 ]; then
    echo "  Nothing changed — already up to date"
    echo "  Installed: $AGENT_COUNT agents, $CMD_COUNT commands"
else
    # Build a detailed summary line
    SUMMARY_PARTS=""
    if [ "$TOTAL_NEW" -gt 0 ]; then
        SUMMARY_PARTS="$TOTAL_NEW new"
    fi
    if [ "$TOTAL_UPDATED" -gt 0 ]; then
        if [ -n "$SUMMARY_PARTS" ]; then
            SUMMARY_PARTS="$SUMMARY_PARTS, $TOTAL_UPDATED updated"
        else
            SUMMARY_PARTS="$TOTAL_UPDATED updated"
        fi
    fi
    if [ "$TOTAL_UNCHANGED" -gt 0 ]; then
        if [ -n "$SUMMARY_PARTS" ]; then
            SUMMARY_PARTS="$SUMMARY_PARTS, $TOTAL_UNCHANGED unchanged"
        else
            SUMMARY_PARTS="$TOTAL_UNCHANGED unchanged"
        fi
    fi
    echo "  Installed: $AGENT_COUNT agents, $CMD_COUNT commands ($SUMMARY_PARTS)"
fi

echo "  Workflow rules: CLAUDE.md ($CLAUDE_MD_STATUS)"
echo "  Hooks: SessionStart (auto-briefing), SessionEnd (auto-close)"
if [ "$SKIP_DB" = false ]; then
    echo "  Memory DB: .claude/memory.db (with self-learning)"
fi
echo ""
echo "  Core commands:"
echo "    /workflow:new \"idea\"                  Start from scratch"
echo "    /workflow:new-feature \"feat\"          Add a feature"
echo "    /workflow:improve \"desc\"              Refactor/optimize"
echo "    /workflow:bugfix \"bug\"                Fix a bug"
echo "    /workflow:audit [--fix]               Audit code"
echo "    /workflow:docs                        Generate specs & docs"
echo "    /workflow:sync                        Sync specs/docs"
echo "    /workflow:functionalities             Map codebase"
echo "    /workflow:understand                  Deep comprehension"
echo "    /workflow:create-role \"desc\"          Design agent role"
echo "    /workflow:audit-role \"path\"           Audit agent role"
echo "    /workflow:diagnose \"bug\"               Deep root cause diagnosis"
echo "    /workflow:wizard-ux \"desc\"            Design wizard UX"
echo "    /workflow:resume                      Resume stopped workflow"

if [ -n "$EXTENSIONS" ]; then
    echo ""
    echo "  Extension commands:"
    IFS=',' read -ra EXT_ARRAY <<< "$EXTENSIONS"
    for ext in "${EXT_ARRAY[@]}"; do
        ext=$(echo "$ext" | tr -d ' ')
        case $ext in
            blockchain)
                echo "    /workflow:blockchain-network \"desc\"   Node/P2P infrastructure"
                echo "    /workflow:blockchain-debug \"desc\"     Debug connectivity"
                echo "    /workflow:stress-test \"desc\"          Stress test CLI/RPC"
                ;;
            omega)
                echo "    /workflow:omega-setup \"desc\"          Configure OMEGA"
                ;;
            c2c-protocol)
                echo "    /workflow:c2c                         C2C protocol POC"
                echo "    /workflow:proto-audit                 Audit protocol spec"
                echo "    /workflow:proto-improve               Improve protocol"
                ;;
        esac
    done
fi

echo ""
echo "  Source of truth: codebase > specs/ > docs/"
echo ""
echo "  Start with: claude"
echo ""
