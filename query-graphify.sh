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
