#!/bin/bash
# Setup script to initialize the workflow in any project

set -e

echo "🔧 Setting up Claude Code Quality Workflow..."
echo ""

# Check Claude Code
if ! command -v claude &> /dev/null; then
    echo "⚠️  Claude Code not detected in PATH."
    echo "   Install it with: npm install -g @anthropic-ai/claude-code"
    echo "   Continuing file setup..."
    echo ""
fi

# Check git
if ! git rev-parse --is-inside-work-tree &> /dev/null 2>&1; then
    echo "📁 Initializing git repository..."
    git init
    echo ""
fi

# Detect script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Copy agents
echo "🤖 Copying agents..."
mkdir -p .claude/agents
cp "$SCRIPT_DIR/.claude/agents/"*.md .claude/agents/
echo "   ✓ discovery.md"
echo "   ✓ analyst.md"
echo "   ✓ architect.md"
echo "   ✓ test-writer.md"
echo "   ✓ developer.md"
echo "   ✓ reviewer.md"
echo "   ✓ qa.md"
echo "   ✓ functionality-analyst.md"

# Copy commands
echo ""
echo "⚡ Copying commands..."
mkdir -p .claude/commands
cp "$SCRIPT_DIR/.claude/commands/"*.md .claude/commands/
echo "   ✓ workflow:new"
echo "   ✓ workflow:feature"
echo "   ✓ workflow:bugfix"
echo "   ✓ workflow:audit"
echo "   ✓ workflow:docs"
echo "   ✓ workflow:sync"
echo "   ✓ workflow:improve"
echo "   ✓ workflow:functionalities"

# Create specs/ and docs/ structure if they don't exist
echo ""
echo "📂 Ensuring project structure..."
if [ ! -d "./specs" ]; then
    mkdir -p specs
    echo "   ✓ specs/ created"
else
    echo "   ✓ specs/ already exists"
fi

if [ ! -d "./docs" ]; then
    mkdir -p docs
    echo "   ✓ docs/ created"
else
    echo "   ✓ docs/ already exists"
fi

if [ ! -f "./specs/SPECS.md" ]; then
    cat > ./specs/SPECS.md << 'EOF'
# SPECS.md — Technical Specifications

> Master index of all technical specification documents.

## Specification Files

_(No specs yet. The workflow agents will populate this as you build.)_
EOF
    echo "   ✓ specs/SPECS.md created"
else
    echo "   ✓ specs/SPECS.md already exists"
fi

if [ ! -f "./docs/DOCS.md" ]; then
    cat > ./docs/DOCS.md << 'EOF'
# DOCS.md — Documentation

> Master index of all user-facing and developer documentation.

## Documentation Files

_(No docs yet. The workflow agents will populate this as you build.)_
EOF
    echo "   ✓ docs/DOCS.md created"
else
    echo "   ✓ docs/DOCS.md already exists"
fi

echo ""
echo "════════════════════════════════════════════"
echo "  ✅ Workflow configured successfully"
echo "════════════════════════════════════════════"
echo ""
echo "  Available commands in Claude Code:"
echo ""
echo "  /workflow:new \"idea\"      → Project from scratch"
echo "  /workflow:feature \"feat\"  → Add a feature"
echo "  /workflow:bugfix \"bug\"    → Fix a bug"
echo "  /workflow:audit           → Audit code + specs drift"
echo "  /workflow:docs            → Generate/update specs & docs"
echo "  /workflow:sync            → Sync specs/docs with codebase"
echo ""
echo "  Source of truth: codebase → specs/ → docs/"
echo ""
echo "  🚀 Start with: claude"
echo ""
