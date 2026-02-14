#!/bin/bash

# App Store Pre-Review Agent 実行スクリプト
# Usage: ./scripts/run-appstore-review.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTS_DIR="$PROJECT_ROOT/reports"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   App Store Pre-Review Agent - Automated Checker         ║${NC}"
echo -e "${BLUE}║   Thai Memo v1.0.0                                         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Create reports directory if not exists
mkdir -p "$REPORTS_DIR"

# Generate timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$REPORTS_DIR/appstore-review-$TIMESTAMP.md"

echo -e "${YELLOW}📋 Starting comprehensive App Store review check...${NC}"
echo ""

# Check if Claude Code is available
if ! command -v claude &> /dev/null; then
    echo -e "${RED}❌ Error: Claude Code CLI not found${NC}"
    echo -e "${YELLOW}Please install Claude Code first:${NC}"
    echo "  npm install -g @anthropic-ai/claude-code"
    exit 1
fi

echo -e "${GREEN}✅ Claude Code CLI found${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "$PROJECT_ROOT/pubspec.yaml" ]; then
    echo -e "${RED}❌ Error: Not in Thai Memo project directory${NC}"
    echo "Please run this script from the project root"
    exit 1
fi

echo -e "${GREEN}✅ Project directory validated${NC}"
echo ""

# Check if skills exist
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
if [ ! -d "$SKILLS_DIR" ]; then
    echo -e "${RED}❌ Error: Skills directory not found${NC}"
    echo "Expected: $SKILLS_DIR"
    exit 1
fi

REQUIRED_SKILLS=(
    "appstore-pre-review-agent.json"
    "code-review-appstore.json"
    "privacy-policy-generate.json"
    "metadata-validate.json"
    "appstore-review-check.json"
)

echo -e "${YELLOW}🔍 Checking required skills...${NC}"
for skill in "${REQUIRED_SKILLS[@]}"; do
    if [ -f "$SKILLS_DIR/$skill" ]; then
        echo -e "${GREEN}  ✓${NC} $skill"
    else
        echo -e "${RED}  ✗${NC} $skill ${RED}(missing)${NC}"
        exit 1
    fi
done
echo ""

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Phase 1: Code Quality Check${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Running code review for App Store compliance...${NC}"
echo ""
echo "This will check:"
echo "  • Info.plist permissions"
echo "  • API key management"
echo "  • Security best practices"
echo "  • Forbidden API usage"
echo "  • Background tasks"
echo ""
read -p "Press Enter to start Phase 1..."

# Note: In actual usage, this would be run inside Claude Code session
echo -e "${YELLOW}📝 To run this check, execute in Claude Code:${NC}"
echo -e "${BLUE}   /appstore-pre-review-agent${NC}"
echo ""

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Manual Execution Instructions${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Since this is an automated skill, please run it via Claude Code:${NC}"
echo ""
echo -e "${YELLOW}1. Open Claude Code in this project:${NC}"
echo "   $ cd $PROJECT_ROOT"
echo "   $ claude"
echo ""
echo -e "${YELLOW}2. Execute the agent:${NC}"
echo "   > /appstore-pre-review-agent"
echo ""
echo -e "${YELLOW}3. The agent will automatically:${NC}"
echo "   • Run all 4 review skills"
echo "   • Generate integrated report"
echo "   • Create action checklist"
echo "   • Evaluate submission readiness"
echo ""
echo -e "${YELLOW}4. Report will be saved to:${NC}"
echo "   $REPORT_FILE"
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Alternative: Run individual skills manually${NC}"
echo ""
echo "If you prefer to run each check separately:"
echo ""
echo "  1. Code Review:"
echo "     > /code-review-appstore"
echo ""
echo "  2. Privacy Policy:"
echo "     > /privacy-policy-generate"
echo ""
echo "  3. Metadata Validation:"
echo "     > /metadata-validate"
echo ""
echo "  4. Final Check:"
echo "     > /appstore-review-check"
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}📖 For detailed guide, see:${NC}"
echo "   $PROJECT_ROOT/docs/APPSTORE_SKILLS_GUIDE.md"
echo ""
echo -e "${GREEN}✨ Ready to begin App Store review preparation!${NC}"
