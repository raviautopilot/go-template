#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status,
# except in conditional tests.
set -eo pipefail

APP_NAME="api"
BINARY_PATH="./bin/${APP_NAME}"
PID_FILE=".pid"
LOG_FILE="app.log"
PORT="8080" # Default port matching config.yaml, but can be overridden by environment variable PORT

# Helper to check if PID is running
is_running() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi
    return 1
}

# Check and fix go.work issues
setup_workspace() {
    local action="${1:-check}"

    # Check if we're in a workspace
    if [ -f "go.work" ]; then
        echo "🔍 Detected go.work file"

        # Check if the workspace references exist
        local has_error=false
        local missing_paths=""

        # Extract workspace paths from go.work
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*use[[:space:]]+(.+)$ ]]; then
                local workspace_path="${BASH_REMATCH[1]}"
                # Remove quotes if present
                workspace_path="${workspace_path//\"/}"

                # Check if the path exists
                if [ ! -d "$workspace_path" ]; then
                    has_error=true
                    missing_paths="$missing_paths\n   - $workspace_path (missing)"
                fi
            fi
        done < <(grep -E "^[[:space:]]*use[[:space:]]+" go.work 2>/dev/null || true)

        if [ "$has_error" = true ]; then
            echo "⚠ Warning: Some workspace paths are missing:$missing_paths"

            if [ "$action" = "fix" ] || [ "$action" = "build" ]; then
                echo "🔧 Attempting to fix go.work..."

                # Create backup of original go.work
                cp go.work go.work.backup

                # Option 1: Try to find the correct paths
                # Check if there's a go.mod in parent directories
                local parent_mod=""
                local current_dir="$(pwd)"
                while [ "$current_dir" != "/" ]; do
                    current_dir="$(dirname "$current_dir")"
                    if [ -f "$current_dir/go.mod" ]; then
                        parent_mod="$current_dir"
                        break
                    fi
                done

                if [ -n "$parent_mod" ]; then
                    echo "   Found parent go.mod at: $parent_mod"
                    # Update go.work to use correct relative path
                    local rel_path="$(realpath --relative-to="$(pwd)" "$parent_mod")"
                    echo "   Updating workspace to use: $rel_path"

                    # Create new go.work with correct path
                    cat > go.work << EOF
go $(go version | awk '{print $3}' | sed 's/go//')

use (
    .
    $rel_path
)
EOF
                    echo "✅ go.work updated successfully"
                else
                    # Option 2: If no parent mod found, use standalone mode
                    echo "   No parent go.mod found. Removing go.work for standalone build..."
                    rm -f go.work go.work.sum
                    echo "✅ Removed go.work - building as standalone module"
                fi
            fi
        else
            echo "✅ go.work workspace is valid"
        fi
    else
        # No go.work - check if we should create one
        if [ "$action" = "setup" ] || [ "$action" = "build" ]; then
            # Check if this is part of a workspace structure
            local current_dir="$(pwd)"
            local found_workspace=false

            # Look for go.work in parent directories
            while [ "$current_dir" != "/" ]; do
                current_dir="$(dirname "$current_dir")"
                if [ -f "$current_dir/go.work" ]; then
                    echo "🔍 Found parent go.work at: $current_dir"
                    found_workspace=true
                    break
                fi
            done

            if [ "$found_workspace" = false ]; then
                # Check if there's a go.mod in parent that might need workspace
                local parent_dir="$(pwd)"
                local has_parent_mod=false
                while [ "$parent_dir" != "/" ]; do
                    parent_dir="$(dirname "$parent_dir")"
                    if [ -f "$parent_dir/go.mod" ] && [ "$parent_dir" != "$(pwd)" ]; then
                        has_parent_mod=true
                        local rel_path="$(realpath --relative-to="$(pwd)" "$parent_dir")"
                        break
                    fi
                done

                if [ "$has_parent_mod" = true ]; then
                    echo "📦 Found parent go.mod at: $parent_dir"
                    echo "   Creating go.work workspace..."
                    cat > go.work << EOF
go $(go version | awk '{print $3}' | sed 's/go//')

use (
    .
    $rel_path
)
EOF
                    echo "✅ Created go.work workspace"
                fi
            fi
        fi
    fi
}

# Clean workspace files (part of the cleanup process)
clean_workspace() {
    if [ -f "go.work" ]; then
        echo "🧹 Removing go.work files..."
        rm -f go.work go.work.sum
    fi
}

build() {
    echo "=== Generating Swagger Documentation ==="

    # Setup workspace before building
    setup_workspace "build"

    # Generate swagger docs, filtering out known runtime warnings
    swag init --dir cmd/api,internal/handler --output docs --parseDependency --parseInternal 2>&1 | \
        grep -v "failed to evaluate const mProfCycleWrap" || true

    echo "=== Compiling Go Binary ==="
    mkdir -p bin
    go build -o "$BINARY_PATH" cmd/api/main.go

    if [ -f "$BINARY_PATH" ]; then
        echo "Build successful! Binary location: $BINARY_PATH"
    else
        echo "Build failed!"
        exit 1
    fi
}

start() {
    local pid
    if pid=$(is_running); then
        echo "Application is already running (PID: $pid)."
        exit 0
    fi

    if [ ! -f "$BINARY_PATH" ]; then
        echo "Binary not found. Building first..."
        build
    fi

    echo "=== Starting Application ==="
    # Start binary in the background and redirect output to app.log
    nohup "$BINARY_PATH" >> "$LOG_FILE" 2>&1 &

    # Capture the PID of the last background command
    local new_pid=$!
    echo "$new_pid" > "$PID_FILE"

    # Sleep slightly to let the process spin up, then verify it is running
    sleep 1
    if kill -0 "$new_pid" 2>/dev/null; then
        echo "Application started successfully (PID: $new_pid)."
        echo "Logs are being redirected to $LOG_FILE"
    else
        echo "Application failed to start. Check $LOG_FILE for details."
        exit 1
    fi
}

stop() {
    local pid
    if ! pid=$(is_running); then
        echo "Application is not running."
        # Remove stale pid file if it exists
        rm -f "$PID_FILE"
        exit 0
    fi

    echo "=== Stopping Application Gracefully (SIGTERM) ==="
    kill -15 "$pid"

    # Wait for the process to exit (up to 10 seconds)
    local count=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$count" -ge 10 ]; then
            echo "Application did not stop gracefully within 10 seconds. Use './manage.sh kill' to force stop."
            exit 1
        fi
        sleep 1
        count=$((count + 1))
    done

    echo "Application stopped successfully."
    rm -f "$PID_FILE"
}

kill_app() {
    local pid
    if ! pid=$(is_running); then
        echo "Application is not running."
        rm -f "$PID_FILE"
        exit 0
    fi

    echo "=== Forcefully Terminating Application (SIGKILL) ==="
    kill -9 "$pid"
    rm -f "$PID_FILE"
    echo "Application forcefully terminated."
}

status() {
    local pid
    if pid=$(is_running); then
        echo "Application is RUNNING (PID: $pid)."
        # Also print some process details
        ps -p "$pid" -o pid,ppid,%cpu,%mem,cmd | sed 's/^/  /'
    else
        echo "Application is STOPPED."
    fi
}

# NEW: View logs
logs() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "Log file $LOG_FILE does not exist yet."
        echo "Start the application first with: ./manage.sh start"
        exit 1
    fi

    # Check if we should follow logs or just show tail
    if [ "$1" = "-f" ] || [ "$1" = "--follow" ]; then
        echo "=== Following logs (press Ctrl+C to stop) ==="
        tail -f "$LOG_FILE"
    elif [ -n "$1" ] && [ "$1" -gt 0 ] 2>/dev/null; then
        # Show specific number of lines
        echo "=== Last $1 lines of logs ==="
        tail -n "$1" "$LOG_FILE"
    else
        # Default: show last 50 lines
        echo "=== Last 50 lines of logs (use './manage.sh logs -f' to follow) ==="
        tail -n 50 "$LOG_FILE"
    fi
}

# NEW: Show error logs only
errors() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "Log file $LOG_FILE does not exist yet."
        exit 1
    fi

    echo "=== Error logs (filtering ERROR, FATAL, PANIC) ==="
    grep -i -E "error|fatal|panic" "$LOG_FILE" || echo "No errors found in logs."
}

clean() {
    echo "=== Cleaning Up Generated Files ==="
    if is_running >/dev/null; then
        echo "Warning: Stopping the running application before cleaning."
        stop
    fi
    rm -rf bin/ docs/ "$PID_FILE" "$LOG_FILE"

    # Ask about go.work cleanup
    if [ -f "go.work" ]; then
        echo ""
        echo "ℹ  go.work file detected."
        read -rp "   Remove go.work files? [y/N]: " remove_work
        if [[ "$remove_work" =~ ^[Yy]$ ]]; then
            clean_workspace
            echo "✅ go.work files removed"
        else
            echo "ℹ  Keeping go.work files"
        fi
    fi

    echo "Cleanup completed."
}

troubleshoot() {
    echo "=== Troubleshooting Application ==="
    echo ""

    echo "=== Workspace Status ==="
    if [ -f "go.work" ]; then
        echo "✓ go.work exists"
        echo "Contents:"
        cat go.work | sed 's/^/  /'

        echo ""
        echo "Checking workspace paths..."
        local has_error=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*use[[:space:]]+(.+)$ ]]; then
                local workspace_path="${BASH_REMATCH[1]}"
                workspace_path="${workspace_path//\"/}"
                if [ -d "$workspace_path" ]; then
                    echo "  ✓ $workspace_path (exists)"
                else
                    echo "  ✗ $workspace_path (MISSING)"
                    has_error=true
                fi
            fi
        done < <(grep -E "^[[:space:]]*use[[:space:]]+" go.work 2>/dev/null || true)

        if [ "$has_error" = true ]; then
            echo ""
            echo "⚠ Some workspace paths are missing. Run './manage.sh setup' to fix."
        fi
    else
        echo "✗ No go.work file found"
    fi

    echo ""
    echo "=== Last 50 Lines of Logs ($LOG_FILE) ==="
    if [ -f "$LOG_FILE" ]; then
        tail -n 50 "$LOG_FILE"
    else
        echo "Log file $LOG_FILE does not exist."
    fi
    echo ""

    echo "=== Network Socket Info ==="
    # Determine the port to check (read from config.yaml or default to 8080)
    local check_port=$PORT
    if [ -f "config.yaml" ]; then
        local yaml_port
        yaml_port=$(grep -i "port:" config.yaml | head -n 1 | awk '{print $2}' | tr -d '"'"'")
        if [ -n "$yaml_port" ]; then
            check_port=$yaml_port
        fi
    fi

    echo "Checking port $check_port..."
    if command -v ss &>/dev/null; then
        ss -lntp "sport = :$check_port" || ss -lntp | grep ":$check_port " || echo "No active listener found via ss."
    elif command -v netstat &>/dev/null; then
        netstat -lntp | grep ":$check_port " || echo "No active listener found via netstat."
    else
        echo "Neither 'ss' nor 'netstat' is available on this system."
    fi

    echo ""
    echo "=== Checking go.mod ==="
    if [ -f "go.mod" ]; then
        echo "✓ go.mod exists"
        echo "Module: $(head -n 1 go.mod)"

        # Check if go.mod has proper module name
        local module_name=$(head -n 1 go.mod | awk '{print $2}')
        if [[ "$module_name" == *"go-template"* ]]; then
            echo "⚠ Module name contains 'go-template' - you might want to update it"
            echo "   Current: $module_name"
        fi
    else
        echo "✗ go.mod not found!"
    fi

    echo ""
    echo "=== Recommended Fixes ==="
    if [ -f "go.work" ]; then
        if grep -q "rlib" go.work 2>/dev/null; then
            echo "1. Run './manage.sh setup' to fix workspace paths"
        fi
    fi
    echo "2. If issues persist, run './manage.sh clean' to reset"
}

# New: Setup workspace
setup() {
    echo "=== Setting Up Workspace ==="
    setup_workspace "setup"

    # Run go mod tidy to ensure dependencies are fresh
    if [ -f "go.mod" ]; then
        echo "📦 Running go mod tidy..."
        go mod tidy
    fi

    echo "✅ Workspace setup complete"
}

print_usage() {
    echo "Usage: $0 {build|start|stop|kill|status|logs|errors|clean|setup|troubleshoot}"
    echo ""
    echo "Commands:"
    echo "  build          - Build the application (auto-fixes workspace)"
    echo "  start          - Start the application"
    echo "  stop           - Stop the application gracefully"
    echo "  kill           - Force kill the application"
    echo "  status         - Check application status"
    echo "  logs           - View application logs"
    echo "  logs -f        - Follow logs in real-time"
    echo "  logs 100       - Show last 100 lines"
    echo "  errors         - Show only error logs"
    echo "  clean          - Clean generated files (asks about go.work)"
    echo "  setup          - Setup/fix go.work workspace"
    echo "  troubleshoot   - Troubleshoot application issues"
    exit 1
}

# Check argument count
if [ $# -lt 1 ]; then
    print_usage
fi

case "$1" in
    build)
        build
        ;;
    start)
        start
        ;;
    stop)
        stop
        ;;
    kill)
        kill_app
        ;;
    status)
        status
        ;;
    logs)
        shift  # Remove 'logs' from arguments
        logs "$@"  # Pass remaining arguments to logs function
        ;;
    errors)
        errors
        ;;
    clean)
        clean
        ;;
    setup)
        setup
        ;;
    troubleshoot)
        troubleshoot
        ;;
    *)
        print_usage
        ;;
esac