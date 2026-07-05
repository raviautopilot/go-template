#!/bin/bash

# Ensure user-installed binaries are in PATH
export PATH="$HOME/.local/bin:$PATH"

# Configuration
PROJECT_DIR="${1:-.}"  # Allow passing project directory as argument
GRAPHIFY_OUTPUT="graphify-out"
CACHE_DIR="$GRAPHIFY_OUTPUT/cache"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if graphify is installed
if ! command -v graphify &> /dev/null
then
    print_info "graphify could not be found, installing..."
    pip install graphify
    if [ $? -ne 0 ]; then
        print_error "Failed to install graphify. Please install manually."
        exit 1
    fi
fi

# Check if graph already exists
if [ -f "$GRAPHIFY_OUTPUT/graph.json" ]; then
    print_info "Existing knowledge graph found in $GRAPHIFY_OUTPUT/"
    
    # Get file sizes for comparison
    GRAPH_SIZE=$(du -h "$GRAPHIFY_OUTPUT/graph.json" | cut -f1)
    CACHE_SIZE=$(du -h "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
    
    print_info "Current graph size: $GRAPH_SIZE"
    print_info "Cache size: $CACHE_SIZE"
    
    # Ask user what to do
    echo ""
    echo "What would you like to do?"
    echo "1) Rebuild graph from scratch (useful if code changed significantly)"
    echo "2) Update graph incrementally (watch mode - saves tokens)"
    echo "3) Query the existing graph (zero token cost)"
    echo "4) Exit"
    read -p "Choose option (1-4): " choice
    
    case $choice in
        1)
            print_info "Rebuilding graph from scratch..."
            print_warning "This will consume tokens for the entire codebase"
            graphify extract "$PROJECT_DIR" --backend gemini --force
            ;;
        2)
            print_info "Starting watch mode for incremental updates..."
            print_info "Graphify will only process changed files (saves tokens)"
            graphify extract "$PROJECT_DIR" --backend gemini --watch
            ;;
        3)
            print_info "Querying existing graph..."
            print_info "You can now ask questions about your codebase:"
            echo ""
            echo "Example queries:"
            echo "  - 'Show me all functions that call process_payment'"
            echo "  - 'What are the dependencies of module X?'"
            echo "  - 'List all API endpoints in this project'"
            echo ""
            echo "To query: graphify query \"your question here\""
            echo "Or check: cat $GRAPHIFY_OUTPUT/GRAPH_REPORT.md"
            echo "Or open: $GRAPHIFY_OUTPUT/graph.html in your browser"
            exit 0
            ;;
        4)
            print_info "Exiting..."
            exit 0
            ;;
        *)
            print_error "Invalid choice. Exiting."
            exit 1
            ;;
    esac
else
    print_info "No existing graph found. Building for the first time..."
    print_warning "This will consume tokens to build the initial knowledge graph"
    print_info "But ALL future queries will be nearly free!"
    echo ""
    read -p "Continue? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Exiting..."
        exit 0
    fi
    graphify extract "$PROJECT_DIR" --backend gemini
fi

# Check if build was successful
if [ $? -eq 0 ] && [ -f "$GRAPHIFY_OUTPUT/graph.json" ]; then
    print_info "✅ Knowledge graph built successfully!"
    print_info ""
    print_info "📊 Token Savings Tips:"
    print_info "1. Use watch mode for incremental updates: graphify extract . --backend gemini --watch"
    print_info "2. Query the graph instead of pasting code: graphify query 'your question'"
    print_info "3. Share graph.json with AI assistants instead of source files"
    print_info "4. Open graph.html for visual exploration"
    print_info ""
    print_info "📁 Output files:"
    print_info "  - $GRAPHIFY_OUTPUT/graph.json (persistent knowledge graph)"
    print_info "  - $GRAPHIFY_OUTPUT/GRAPH_REPORT.md (human-readable report)"
    print_info "  - $GRAPHIFY_OUTPUT/graph.html (interactive visualization)"
    print_info "  - $GRAPHIFY_OUTPUT/cache/ (incremental update cache)"
    
    # Create a helper alias/function for easy querying
    echo ""
    print_info "Adding query helper function to your shell session..."
    alias graphify-query='graphify query'
    echo "Now you can run: graphify-query \"your question\""
    
    # Show a sample of the graph
    if command -v jq &> /dev/null; then
        NODE_COUNT=$(jq '.nodes | length' "$GRAPHIFY_OUTPUT/graph.json" 2>/dev/null || echo "unknown")
        EDGE_COUNT=$(jq '.edges | length' "$GRAPHIFY_OUTPUT/graph.json" 2>/dev/null || echo "unknown")
        print_info "Graph stats: $NODE_COUNT nodes, $EDGE_COUNT edges"
    fi
else
    print_error "Failed to build knowledge graph"
    exit 1
fi

# ============================================
# ANTIGRAVITY INTEGRATION
# ============================================
print_step "Setting up Antigravity integration..."

# Run the official install command
print_info "Running: graphify antigravity install"
graphify antigravity install

# Check if the install succeeded
if [ $? -eq 0 ]; then
    print_info "✅ Antigravity integration installed successfully!"
    
    # Check where the files were installed
    if [ -f ".agents/workflows/graphify.md" ]; then
        print_info "📁 Files installed to: .agents/"
        AGENT_DIR=".agents"
    elif [ -f ".agent/workflows/graphify.md" ]; then
        print_info "📁 Files installed to: .agent/"
        AGENT_DIR=".agent"
    else
        print_warning "Could not find installed files"
        AGENT_DIR=""
    fi
    
    # Fix: Create symlink from .agents to .agent if needed
    if [ "$AGENT_DIR" == ".agents" ]; then
        print_info "Creating symlink: .agent -> .agents (for Antigravity compatibility)"
        if [ -L ".agent" ]; then
            rm .agent
        elif [ -d ".agent" ]; then
            print_warning ".agent directory already exists. Moving it to .agent.backup"
            mv .agent .agent.backup
        fi
        ln -s .agents .agent
        print_info "✅ Symlink created: .agent -> .agents"
    fi
else
    print_warning "graphify antigravity install command failed"
    print_info "Creating manual Antigravity integration files..."
    
    # Create both directories to be safe
    mkdir -p .agent/rules .agent/workflows
    mkdir -p .agents/rules .agents/workflows
    
    # Create rule file for both locations
    for AGENT_DIR in .agent .agents; do
        cat > "$AGENT_DIR/rules/graphify.md" << 'EOF'
---
type: rule
description: Always use Graphify knowledge graph before searching code
---

# Graphify Knowledge Graph

## Always Use Graphify First

When answering questions about this codebase:

1. **PRIORITY**: First check if the answer exists in `graphify-out/GRAPH_REPORT.md`
2. **NEXT**: Query `graphify-out/graph.json` for structural questions
3. **LAST**: Only read raw source files when:
   - The graph doesn't contain the information
   - You need to see exact implementation details
   - You're planning to edit code

## What Graphify Can Tell You

- **Function calls**: Who calls what
- **Dependencies**: What modules depend on each other
- **Relationships**: How different parts of the code connect
- **Architecture**: Overall structure of the project

## Common Queries

- "What calls function X?"
- "What are the dependencies of module Y?"
- "Show me all API endpoints"
- "How does authentication work?"
- "What database models exist?"

## Available Files

- `graphify-out/graph.json` - Complete knowledge graph
- `graphify-out/GRAPH_REPORT.md` - Human-readable summary
- `graphify-out/graph.html` - Interactive visualization
EOF

        # Create workflow file for both locations
        cat > "$AGENT_DIR/workflows/graphify.md" << 'EOF'
---
type: workflow
description: Query your codebase using the Graphify knowledge graph
---

# /graphify - Query the codebase knowledge graph

## Description
Use this command to ask questions about the codebase structure using Graphify.

## Usage
`/graphify [your question]`

## Examples
- `/graphify What functions call process_payment?`
- `/graphify Show me all API endpoints in this project`
- `/graphify How does authentication work?`
- `/graphify What are the dependencies of the auth module?`

## Workflow
1. Read `graphify-out/graph.json` to answer structural questions
2. Read `graphify-out/GRAPH_REPORT.md` for high-level understanding
3. Only read source files if the graph doesn't have the answer

## Benefits
- Saves tokens (95-99% reduction per query)
- Faster answers (instant graph queries vs file search)
- More accurate (shows actual relationships, not just text matches)
EOF
    done
    
    # Create symlink if needed
    if [ -L ".agent" ]; then
        rm .agent
    elif [ -d ".agent" ] && [ -d ".agents" ]; then
        print_warning "Both .agent and .agents exist. Keeping .agent"
    elif [ -d ".agents" ] && [ ! -d ".agent" ]; then
        ln -s .agents .agent
        print_info "✅ Created symlink: .agent -> .agents"
    fi
    
    print_info "✅ Manual Antigravity files created in both .agent/ and .agents/"
fi

# ============================================
# SETUP MCP CONFIGURATION (Optional)
# ============================================
print_step "Setting up MCP configuration for advanced navigation..."

MCP_CONFIG_DIR="$HOME/.gemini/antigravity"
MCP_CONFIG_FILE="$MCP_CONFIG_DIR/mcp_config.json"

if [ ! -f "$MCP_CONFIG_FILE" ]; then
    print_info "Creating MCP configuration for Graphify..."
    mkdir -p "$MCP_CONFIG_DIR"
    
    cat > "$MCP_CONFIG_FILE" << EOF
{
  "mcpServers": {
    "graphify": {
      "command": "uv",
      "args": ["run", "--with", "graphifyy", "--with", "mcp", "-m", "graphify.serve", "$(pwd)/graphify-out/graph.json"]
    }
  }
}
EOF
    print_info "✅ MCP config created at: $MCP_CONFIG_FILE"
else
    # Check if graphify is already in the config
    if ! grep -q "graphify" "$MCP_CONFIG_FILE"; then
        print_info "Adding graphify to existing MCP config..."
        # Use jq if available, otherwise manual backup
        if command -v jq &> /dev/null; then
            # Backup the original
            cp "$MCP_CONFIG_FILE" "$MCP_CONFIG_FILE.backup"
            # Add graphify to mcpServers
            jq '.mcpServers += {"graphify": {"command": "uv", "args": ["run", "--with", "graphifyy", "--with", "mcp", "-m", "graphify.serve", "'$(pwd)'/graphify-out/graph.json"]}}' "$MCP_CONFIG_FILE" > "$MCP_CONFIG_FILE.tmp"
            mv "$MCP_CONFIG_FILE.tmp" "$MCP_CONFIG_FILE"
            print_info "✅ Graphify added to MCP config"
        else
            print_warning "jq not installed. Skipping MCP config update."
            print_info "To add manually, add this to $MCP_CONFIG_FILE:"
            echo '  "graphify": {'
            echo '    "command": "uv",'
            echo '    "args": ["run", "--with", "graphifyy", "--with", "mcp", "-m", "graphify.serve", "'$(pwd)'/graphify-out/graph.json"]'
            echo '  }'
        fi
    else
        print_info "✅ Graphify already configured in MCP"
    fi
fi

# ============================================
# CREATE HELPER SCRIPTS
# ============================================
print_step "Creating helper scripts..."

# Create query-graphify.sh if it doesn't exist
if [ ! -f "query-graphify.sh" ]; then
    cat > "query-graphify.sh" << 'EOF'
#!/bin/bash
# query-graphify.sh - Quick graph queries and token savings tracker

GRAPH_FILE="graphify-out/graph.json"

if [ ! -f "$GRAPH_FILE" ]; then
    echo "❌ No graph found. Run setup first!"
    exit 1
fi

# If argument is --stats, -s, or no arguments are provided, show stats and usage
if [ $# -eq 0 ] || [ "$1" = "--stats" ] || [ "$1" = "-s" ]; then
    # Estimate graph size
    if command -v numfmt &> /dev/null; then
        GRAPH_SIZE=$(wc -c < "$GRAPH_FILE" | numfmt --to=si)
    else
        GRAPH_SIZE=$(wc -c < "$GRAPH_FILE")
    fi

    echo "📊 Graph size: $GRAPH_SIZE"
    echo "💡 Each query costs ~200-500 tokens vs thousands with full files"
    echo "Estimated savings per query: 95-99%"
    echo ""
    echo "Usage: ./query-graphify.sh 'your question'"
    echo "       ./query-graphify.sh --stats (or -s) to view this info again"
    echo ""
    echo "Examples:"
    echo "  ./query-graphify.sh 'Show all API endpoints'"
    echo "  ./query-graphify.sh 'What depends on module X?'"
    echo "  ./query-graphify.sh 'List all database models'"
    echo ""
    echo "To maximize savings:"
    echo "  1. Keep watch mode running: graphify extract . --backend gemini --watch"
    echo "  2. Query the graph using this script or 'graphify query'"
    echo "  3. Never paste entire files again!"
    
    if [ $# -eq 0 ]; then
        exit 1
    else
        exit 0
    fi
fi

graphify query "$1"
EOF
    chmod +x query-graphify.sh
    print_info "✅ Created query-graphify.sh (combined query helper & token tracker)"
fi

# ============================================
# OPTIONAL: Start watch mode
# ============================================
echo ""
read -p "Start watch mode for automatic incremental updates? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Starting watch mode in background..."
    graphify extract "$PROJECT_DIR" --backend gemini --watch &
    WATCH_PID=$!
    print_info "Watch mode running with PID: $WATCH_PID"
    print_info "To stop: kill $WATCH_PID"
fi

# ============================================
# FINAL SUMMARY
# ============================================
print_info "✨ Setup complete! You're now ready to save tokens with Graphify."
echo ""
print_info "📋 Next steps:"
echo "  1. COMPLETELY RESTART Antigravity (close and reopen)"
echo "  2. Type '/' in the chat - you should see '/graphify'"
echo "  3. Type: /graphify What does this codebase do?"
echo "  4. Watch the agent use the graph instead of grepping files!"
echo ""
print_info "📊 Expected token savings: 95-99% per query"
echo ""
print_info "🔧 Quick commands:"
echo "  graphify query 'your question'  - Query from terminal"
echo "  ./query-graphify.sh 'question'  - Use the helper script to query graph"
echo "  ./query-graphify.sh --stats    - View potential savings and stats"
echo ""
print_info "📁 Integration files installed:"
if [ -d ".agents" ]; then
    echo "  - .agents/rules/graphify.md"
    echo "  - .agents/workflows/graphify.md"
fi
if [ -d ".agent" ]; then
    if [ -L ".agent" ]; then
        echo "  - .agent -> .agents (symlink)"
    else
        echo "  - .agent/rules/graphify.md"
        echo "  - .agent/workflows/graphify.md"
    fi
fi
if [ -f "$MCP_CONFIG_FILE" ]; then
    echo "  - $MCP_CONFIG_FILE (MCP config)"
fi
