#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

# Colors for a premium terminal UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Helper function to print headers
print_header() {
    echo -e "${CYAN}${BOLD}==================================================${NC}"
    echo -e "${CYAN}${BOLD}          Go Template Project Cloner              ${NC}"
    echo -e "${CYAN}${BOLD}==================================================${NC}"
}

# Helper function for search and replace
replace_string() {
    local search="$1"
    local replace="$2"
    local file="$3"

    if command -v perl >/dev/null 2>&1; then
        perl -pi -e "s|\Q$search\E|$replace|g" "$file"
    else
        # Fallback to sed depending on OS
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i "" "s|$search|$replace|g" "$file"
        else
            sed -i "s|$search|$replace|g" "$file"
        fi
    fi
}

# Main execution flow
main() {
    print_header

    # 1. Resolve source directory (where clone.sh is located)
    local src_dir
    src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Verify we are running from a valid go-template directory
    if [ ! -f "$src_dir/go.mod" ]; then
        echo -e "${RED}✘ Error: Must run this script from the go-template root containing 'go.mod'.${NC}"
        exit 1
    fi

    # 2. Prompt for Target Directory
    local target_dir_input=""
    echo -e "${BOLD}1. Target Directory${NC}"
    echo -e "   Where should the new project be copied?"
    read -rp "   Path (e.g. ~/code/my-service or ../my-service): " target_dir_input

    if [ -z "$target_dir_input" ]; then
        echo -e "${RED}✘ Error: Target directory cannot be empty.${NC}"
        exit 1
    fi

    # Expand tilde (~) in path if present
    if [[ "$target_dir_input" =~ ^~(/|$) ]]; then
        target_dir_input="${target_dir_input/#\~/$HOME}"
    fi

    # Resolve to absolute canonical path
    local target_dir
    if command -v realpath >/dev/null 2>&1; then
        target_dir="$(realpath -m "$target_dir_input")"
    else
        if [[ "$target_dir_input" = /* ]]; then
            target_dir="$target_dir_input"
        else
            target_dir="$(pwd)/$target_dir_input"
        fi
    fi

    # Safety checks on target directory
    if [ "$target_dir" = "$src_dir" ]; then
        echo -e "${RED}✘ Error: Target directory cannot be the same as the template directory.${NC}"
        exit 1
    fi

    if [[ "$target_dir" == "$src_dir"* ]]; then
        echo -e "${RED}✘ Error: Target directory cannot be a subdirectory of the template.${NC}"
        exit 1
    fi

    if [ -z "$target_dir" ] || [ "$target_dir" = "/" ] || [ "$target_dir" = "$HOME" ] || [ "$target_dir" = "/home" ] || [ "$target_dir" = "/home/ubuntu" ]; then
        echo -e "${RED}✘ Error: Target directory is too generic/dangerous: $target_dir. Aborting for safety.${NC}"
        exit 1
    fi

    # 3. Prompt for Service Name
    local default_service_name
    default_service_name="$(basename "$target_dir")"
    # Replace non-alphanumeric chars with hyphens for a clean default name
    default_service_name="${default_service_name//[^a-zA-Z0-9_-]/-}"
    
    echo -e "\n${BOLD}2. Service Name${NC}"
    read -rp "   Enter service name [$default_service_name]: " service_name
    service_name="${service_name:-$default_service_name}"

    # Validate service name
    if [[ ! "$service_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}✘ Error: Invalid service name: $service_name. Use only alphanumeric characters, hyphens, and underscores.${NC}"
        exit 1
    fi

    # 4. Prompt for Go Module path
    local default_go_mod="github.com/raviautopilot/$service_name"
    echo -e "\n${BOLD}3. Go Module Path${NC}"
    read -rp "   Enter Go module path [$default_go_mod]: " go_mod
    go_mod="${go_mod:-$default_go_mod}"

    # 5. Prompt for Server Port
    local default_port="8080"
    echo -e "\n${BOLD}4. Server Port${NC}"
    read -rp "   Enter server port [$default_port]: " server_port
    server_port="${server_port:-$default_port}"

    # Validate port
    if [[ ! "$server_port" =~ ^[0-9]+$ ]] || [ "$server_port" -lt 1 ] || [ "$server_port" -gt 65535 ]; then
        echo -e "${RED}✘ Error: Invalid port: $server_port. Must be a number between 1 and 65535.${NC}"
        exit 1
    fi

    # 6. Confirm Configuration
    echo -e "\n${CYAN}${BOLD}Configuration Summary:${NC}"
    echo -e "   - Source Template : ${BLUE}$src_dir${NC}"
    echo -e "   - Target Directory: ${BLUE}$target_dir${NC}"
    echo -e "   - Service Name    : ${BLUE}$service_name${NC}"
    echo -e "   - Go Module Path  : ${BLUE}$go_mod${NC}"
    echo -e "   - Server Port     : ${BLUE}$server_port${NC}"
    echo ""
    read -rp "Proceed with cloning? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Cloning cancelled.${NC}"
        exit 0
    fi

    # 7. Prepare Target Directory
    if [ -d "$target_dir" ]; then
        echo -e "\n${YELLOW}⚠ Warning: Target directory '$target_dir' already exists.${NC}"
        read -rp "Overwrite its contents? [y/N]: " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            echo -e "${RED}Aborted clone operation.${NC}"
            exit 1
        fi
        echo -e "${BLUE}🧹 Cleaning existing target directory...${NC}"
        rm -rf "${target_dir:?}"/* "${target_dir:?}"/.* 2>/dev/null || true
    fi

    echo -e "\n${BLUE}📂 Creating target directory...${NC}"
    mkdir -p "$target_dir"

    # 8. Copy Template Files
    echo -e "${BLUE}📋 Copying template files...${NC}"
    cp -R "$src_dir/." "$target_dir/"

    # Clean up non-project or template-specific files in the destination
    rm -rf "$target_dir/.git"
    rm -rf "$target_dir/.idea"
    rm -rf "$target_dir/bin"
    rm -rf "$target_dir/app.log"
    rm -rf "$target_dir/.pid"
    rm -rf "$target_dir/docs"
    rm -rf "$target_dir/clone.sh"

    # 9. Perform search and replace in target files
    echo -e "${BLUE}🔄 Customizing project files...${NC}"
    find "$target_dir" -type f | while read -r file; do
        # Avoid directories and binary/hidden configurations if they slip through
        if [[ "$file" == *"/_git/"* || "$file" == *"/_github/"* ]]; then
            continue
        fi

        # Process text files only
        if file "$file" | grep -qE 'text|json|xml|bash|shell|source'; then
            # Replace Go module references
            replace_string "github.com/raviautopilot/go-template" "$go_mod" "$file"
            
            # Replace service name references
            replace_string "go-template" "$service_name" "$file"
            replace_string "Go Template" "$service_name" "$file"

            # Replace server port
            replace_string "8080" "$server_port" "$file"
        fi
    done

    # 10. Run Go module initialization & Swagger Docs generation
    echo -e "${BLUE}⚡ Building dependencies and initializing...${NC}"
    (
        cd "$target_dir" || exit 1
        # Set PATH to include standard Go bin directories
        export PATH=$PATH:$(go env GOPATH)/bin:$(go env GOROOT)/bin

        # Run swag init to generate fresh swagger docs
        if command -v swag >/dev/null 2>&1; then
            echo -e "   - Generating Swagger documentation..."
            swag init --dir cmd/api,internal/handler --output docs --parseDependency --parseInternal >/dev/null 2>&1 || {
                echo -e "${YELLOW}     ⚠ Warning: Failed to generate Swagger docs. You can do this later using './manage.sh build'.${NC}"
            }
        else
            echo -e "${YELLOW}   - ⚠ 'swag' tool not found. Swagger docs generation skipped.${NC}"
        fi

        # Run go mod tidy to clean/fetch dependencies
        if command -v go >/dev/null 2>&1; then
            echo -e "   - Running go mod tidy..."
            go mod tidy >/dev/null 2>&1 || {
                echo -e "${YELLOW}     ⚠ Warning: 'go mod tidy' failed. Please run it manually inside the new project.${NC}"
            }
        else
            echo -e "${YELLOW}   - ⚠ 'go' tool not found. Skipping 'go mod tidy'.${NC}"
        fi
    )

    # 11. Initialize Git in the target directory
    if command -v git >/dev/null 2>&1; then
        echo -e "${BLUE}🌱 Initializing git repository...${NC}"
        (
            cd "$target_dir" || exit 1
            git init -q
            git add -A
            git commit -m "Initial commit from go-template (service: $service_name)" -q
        )
        echo -e "${GREEN}✔ Git repository initialized and first commit created.${NC}"
    fi

    echo -e "\n${GREEN}${BOLD}✔ Successfully cloned and initialized project!${NC}"
    echo -e "   New project path: ${BOLD}$target_dir${NC}"
    echo -e "   To get started:"
    echo -e "     1. cd $target_dir"
    echo -e "     2. ./manage.sh build"
    echo -e "     3. ./manage.sh start"
}

main "$@"
