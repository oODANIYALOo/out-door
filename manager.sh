#!/bin/bash


set -euo pipefail

# ========== Configuration ==========
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${SCRIPT_DIR}/all-compose"
GITHUB_REPO="https://github.com/yourusername/docker-compose-collection.git"
TEMP_DIR="/tmp/docker-compose-manager"

# ========== Color Definitions ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ========== Helper Functions ==========
print_error() { echo -e "${RED}✗ ERROR: $1${NC}" >&2; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_header() { echo -e "\n${PURPLE}════════════════════════════════════════════════════════════${NC}"; }
print_title() { echo -e "${WHITE}=== $1 ===${NC}"; }

# ========== Initialization ==========
init_directories() {
    if [[ ! -d "$BASE_DIR" ]]; then
        mkdir -p "$BASE_DIR"
        print_success "Created directory: $BASE_DIR"
    fi
    mkdir -p "$TEMP_DIR"
}

# ========== Core Functions ==========

is_compose_project() {
    local dir="$1"
    
    [[ ! -d "$dir" ]] && return 1
    
    [[ -f "${dir}/docker-compose.yml" ]] && return 0
    [[ -f "${dir}/docker-compose.yaml" ]] && return 0
    [[ -f "${dir}/compose.yml" ]] && return 0
    [[ -f "${dir}/compose.yaml" ]] && return 0
    
    return 1
}

get_compose_projects() {
    local projects=()
    
    if [[ ! -d "$BASE_DIR" ]]; then
        printf '%s\n' "${projects[@]}"
        return
    fi
    
    for dir in "$BASE_DIR"/*/; do
        [[ ! -d "$dir" ]] && continue
        
        local project_name=$(basename "$dir")
        
        if is_compose_project "$dir"; then
            projects+=("$project_name")
        fi
    done
    
    printf '%s\n' "${projects[@]}"
}

get_compose_file() {
    local project=$1
    local compose_path="$BASE_DIR/$project"
    
    [[ ! -d "$compose_path" ]] && echo "" && return 1
    
    if [[ -f "${compose_path}/docker-compose.yml" ]]; then
        echo "${compose_path}/docker-compose.yml"
    elif [[ -f "${compose_path}/docker-compose.yaml" ]]; then
        echo "${compose_path}/docker-compose.yaml"
    elif [[ -f "${compose_path}/compose.yml" ]]; then
        echo "${compose_path}/compose.yml"
    elif [[ -f "${compose_path}/compose.yaml" ]]; then
        echo "${compose_path}/compose.yaml"
    else
        echo ""
    fi
}


get_project_status() {
    local project=$1

    local container_count=$(docker ps -a --filter "label=com.docker.compose.project=$project" -q 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$container_count" -gt 0 ]]; then
        local running_count=$(docker ps --filter "label=com.docker.compose.project=$project" --filter "status=running" -q 2>/dev/null | wc -l | tr -d ' ')

        if [[ "$running_count" -gt 0 ]]; then
            echo "started"
        else
            echo "stopped"
        fi
    else
        echo "not started"
    fi
}

get_project_ports() {
    local project=$1
    local compose_file=$2
    local ports=""

    if [[ -f "$compose_file" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ([0-9]+):[0-9]+ ]]; then
                host_port="${BASH_REMATCH[1]}"
                if [[ -z "$ports" ]]; then
                    ports="$host_port"
                else
                    ports="$ports, $host_port"
                fi
            fi
        done < <(grep -E "^[[:space:]]*\-[[:space:]]*([0-9]+:[0-9]+)" "$compose_file" 2>/dev/null)
    fi

    echo "${ports:-}"
}

cmd_show() {
    echo -e "${CYAN}Base Directory: ${WHITE}$BASE_DIR${NC}"

    if [[ ! -d "$BASE_DIR" ]]; then
        print_warning "Directory '$BASE_DIR' does not exist"
        print_info "Creating directory: $BASE_DIR"
        mkdir -p "$BASE_DIR"
        echo ""
    fi

    local projects=($(get_compose_projects))

    if [[ ${#projects[@]} -eq 0 ]]; then
        print_warning "No compose projects found in $BASE_DIR"
        echo ""
        print_info "Directory contents:"
        if [[ -d "$BASE_DIR" ]]; then
            if [[ -z "$(ls -A "$BASE_DIR")" ]]; then
                echo "  📁 $BASE_DIR is empty"
            else
                ls -la "$BASE_DIR" | sed 's/^/  /'
            fi
        fi
        echo ""
        print_info "You can add projects by:"
        echo "  1. Create a directory with your compose files:"
        echo "     mkdir -p \"$BASE_DIR/your-project\""
        echo "     cp docker-compose.yml \"$BASE_DIR/your-project/\""
        echo ""
        echo "  2. Or pull from repository:"
        echo "     $0 pull <project>/<type>"
        return 0
    fi

    printf "%-27s %-28s %s\n" "PROJECT" "STATUS" "PORT"
    echo "────────────────────────────────────────────────────────────────────────────────────────"

    local running_count=0
    local stopped_count=0
    local not_started_count=0

    for project in "${projects[@]}"; do
        local compose_file=$(get_compose_file "$project")
        local compose_path="$BASE_DIR/$project"

        [[ -z "$compose_file" ]] && continue

        local status_text=$(get_project_status "$project")
        local status=""

        case $status_text in
            started)
                status="${GREEN}started${NC}"
                running_count=$((running_count + 1))
                ;;
            stopped)
                status="${YELLOW}stopped${NC}"
                stopped_count=$((stopped_count + 1))
                ;;
            "not started")
                status="${BLUE}not started${NC}"
                not_started_count=$((not_started_count + 1))
                ;;
        esac

        local ports=$(get_project_ports "$project" "$compose_file")

        printf "%-25s %s %b %-16s %s\n" \
            "$project" "|" "$status" "" "$ports"

    done

    echo "────────────────────────────────────────────────────────────────────────────────────────"
    echo -e "${WHITE}Summary:${NC}"
    echo -e "  ${GREEN}Running:${NC} $running_count"
    echo -e "  ${YELLOW}Stopped:${NC} $stopped_count"
    echo -e "  ${BLUE}Not Started:${NC} $not_started_count"
    echo -e "  ${WHITE}Total Projects:${NC} ${#projects[@]}"
    echo ""
}


get_project_images_status() {
    local project=$1
    local compose_file=$2
    local images_found=0
    local images_total=0
    
    while IFS= read -r line; do
        if [[ "$line" =~ image:[[:space:]]*([^[:space:]]+) ]]; then
            image="${BASH_REMATCH[1]}"
            images_total=$((images_total + 1))
            if docker image inspect "$image" &>/dev/null; then
                images_found=$((images_found + 1))
            fi
        fi
    done < <(grep -E "^[[:space:]]*image:" "$compose_file" 2>/dev/null)
    
    if [[ $images_total -eq 0 ]]; then
        echo "no_images"
    elif [[ $images_found -eq $images_total ]]; then
        echo "all:$images_total"
    elif [[ $images_found -eq 0 ]]; then
        echo "none:$images_total"
    else
        echo "partial:$images_found/$images_total"
    fi
}

get_project_services() {
    local project=$1
    local compose_file=$2
    local services=""
    
    services=$(grep -E "^[[:space:]]*[a-zA-Z0-9_-]+:[[:space:]]*$" "$compose_file" 2>/dev/null | grep -v "services:" | sed 's/://g' | sed 's/^[[:space:]]*//' | head -3 | tr '\n' ', ' | sed 's/, $//')
    
    [[ -z "$services" ]] && echo "-" || echo "$services"
}

docker_compose_cmd() {
    local project=$1
    shift
    local compose_file=$(get_compose_file "$project")
    
    if [[ -z "$compose_file" ]]; then
        print_error "Compose file not found for $project"
        return 1
    fi
    
    docker compose -f "$compose_file" -p "$project" "$@"
}

# ========== Manage Command ==========
cmd_manage() {
    local project=$1
    local action=$2
    shift 2
    
    if ! is_compose_project "$BASE_DIR/$project"; then
        print_error "Project '$project' not found in $BASE_DIR"
        echo ""
        print_info "Available projects:"
        get_compose_projects | sed 's/^/  • /'
        return 1
    fi
    
    case $action in
        up)
            docker_compose_cmd "$project" up -d "$@"
            print_success "$project started"
            ;;
        down)
            docker_compose_cmd "$project" down "$@"
            print_success "$project stopped and removed"
            ;;
        stop)
            docker_compose_cmd "$project" stop "$@"
            print_success "$project stopped"
            ;;
        start)
            docker_compose_cmd "$project" start "$@"
            print_success "$project started"
            ;;
        restart)
            docker_compose_cmd "$project" restart "$@"
            print_success "$project restarted"
            ;;
        status)
            docker_compose_cmd "$project" ps
            ;;
        logs)
            docker_compose_cmd "$project" logs "$@"
            ;;
        port)
            docker_compose_cmd "$project" ps --format "table {{.Names}}\t{{.Ports}}"
            ;;
        pull)
            docker_compose_cmd "$project" pull "$@"
            print_success "Images pulled"
            ;;
        build)
            docker_compose_cmd "$project" build "$@"
            print_success "Build completed"
            ;;
        update)
            docker_compose_cmd "$project" pull "$@"
            docker_compose_cmd "$project" up -d "$@"
            print_success "$project updated"
            ;;
        exec)
            if [[ $# -lt 1 ]]; then
                print_error "Usage: manage <project> exec <service> <command>"
                return 1
            fi
            docker_compose_cmd "$project" exec "$@"
            ;;
        config)
            docker_compose_cmd "$project" config
            ;;
        images)
            docker_compose_cmd "$project" images
            ;;
        top)
            docker_compose_cmd "$project" top
            ;;
        *)
            print_error "Unknown action: $action"
            return 1
            ;;
    esac
}

# ========== Pull Command ==========
cmd_pull() {
    local pull_request="$1"
    
    if [[ ! "$pull_request" =~ ^(.+)/(last-version|locally|production)$ ]]; then
        print_error "Invalid format. Use: project-name/type"
        echo "Example: nextcloud/production"
        return 1
    fi
    
    local project_name="${BASH_REMATCH[1]}"
    local project_type="${BASH_REMATCH[2]}"
    local temp_repo_dir="${TEMP_DIR}/pull-${project_name}"
    
    print_header
    print_title "Pulling Docker Compose Project"
    echo ""
    echo -e "  ${WHITE}Project:${NC}     $project_name"
    echo -e "  ${WHITE}Type:${NC}        $project_type"
    echo -e "  ${WHITE}Destination:${NC} $BASE_DIR/$project_name"
    echo ""
    
    mkdir -p "$BASE_DIR"
    
    print_info "Downloading from repository..."
    if ! git clone --depth 1 --quiet "$GITHUB_REPO" "$temp_repo_dir" 2>/dev/null; then
        print_error "Failed to download from repository"
        return 1
    fi
    
    local source_dir="$temp_repo_dir/$project_type/$project_name"
    if [[ ! -d "$source_dir" ]]; then
        print_error "Project '$project_name' not found in type '$project_type'"
        rm -rf "$temp_repo_dir"
        return 1
    fi
    
    if [[ -d "$BASE_DIR/$project_name" ]]; then
        read -p "Project already exists. Overwrite? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "Pull cancelled"
            rm -rf "$temp_repo_dir"
            return 0
        fi
        rm -rf "$BASE_DIR/$project_name"
    fi
    
    print_info "Copying project files..."
    cp -r "$source_dir" "$BASE_DIR/$project_name"
    rm -rf "$temp_repo_dir"
    
    if is_compose_project "$BASE_DIR/$project_name"; then
        print_success "✅ Project pulled successfully"
        echo ""
        echo "Location: $BASE_DIR/$project_name/"
        echo ""
        
        echo -e "${CYAN}Files:${NC}"
        ls -la "$BASE_DIR/$project_name" | head -10 | sed 's/^/  /'
        echo ""
        
        read -p "Do you want to start the project now? (y/N): " start_confirm
        if [[ "$start_confirm" =~ ^[Yy]$ ]]; then
            echo ""
            cmd_manage "$project_name" "up"
        fi
    else
        print_error "Failed to pull project: No valid compose file found"
        rm -rf "$BASE_DIR/$project_name"
        return 1
    fi
}

# ========== Remove Command ==========
cmd_remove() {
    local project=$1
    
    if ! is_compose_project "$BASE_DIR/$project"; then
        print_error "Project '$project' not found in $BASE_DIR"
        return 1
    fi
    
    print_header
    print_title "Remove Docker Compose Project"
    echo ""
    echo -e "  ${WHITE}Project:${NC}     $project"
    echo -e "  ${WHITE}Location:${NC}    $BASE_DIR/$project"
    echo ""
    
    local status=$(get_project_status "$project")
    if [[ "$status" == "running" ]]; then
        print_warning "Project is currently running"
        read -p "Stop and remove project? (y/N): " stop_confirm
        if [[ "$stop_confirm" =~ ^[Yy]$ ]]; then
            docker_compose_cmd "$project" down
        else
            print_info "Remove cancelled"
            return 0
        fi
    fi
    
    read -p "Are you sure you want to remove this project? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$BASE_DIR/$project"
        print_success "Project '$project' removed"
    else
        print_info "Remove cancelled"
    fi
}

# ========== Search Command ==========
cmd_search() {
    local search_term="$1"
    local temp_repo_dir="${TEMP_DIR}/compose-collection"
    
    print_header
    print_title "Searching Docker Compose Projects"
    echo ""
    print_info "Repository: $GITHUB_REPO"
    echo ""
    
    rm -rf "$temp_repo_dir"
    mkdir -p "$temp_repo_dir"
    
    print_info "Fetching repository information..."
    if ! git clone --depth 1 --quiet "$GITHUB_REPO" "$temp_repo_dir" 2>/dev/null; then
        print_error "Failed to fetch repository"
        return 1
    fi
    
    local types=("last-version" "locally" "production")
    local found=0
    
    printf "${WHITE}%-35s %-15s %-20s %s${NC}\n" "PROJECT NAME" "TYPE" "STATUS" "COMPOSE FILE"
    echo "────────────────────────────────────────────────────────────────────────────────────────────"
    
    for type in "${types[@]}"; do
        local type_dir="$temp_repo_dir/$type"
        
        if [[ -d "$type_dir" ]]; then
            for project_dir in "$type_dir"/*/; do
                [[ ! -d "$project_dir" ]] && continue
                
                local project_name=$(basename "$project_dir")
                local full_name="${project_name}/${type}"
                
                if [[ -z "$search_term" ]] || [[ "$project_name" == *"$search_term"* ]] || [[ "$type" == *"$search_term"* ]]; then
                    found=1
                    
                    local status=""
                    if [[ -d "$BASE_DIR/$project_name" ]] && is_compose_project "$BASE_DIR/$project_name"; then
                        local proj_status=$(get_project_status "$project_name")
                        case $proj_status in
                            running) status="${GREEN}Running${NC}" ;;
                            stopped) status="${YELLOW}Stopped${NC}" ;;
                            not_created) status="${BLUE}Not Started${NC}" ;;
                        esac
                    else
                        status="${WHITE}Not Installed${NC}"
                    fi
                    
                    local compose_file=""
                    if [[ -f "$project_dir/docker-compose.yml" ]]; then
                        compose_file="docker-compose.yml"
                    elif [[ -f "$project_dir/docker-compose.yaml" ]]; then
                        compose_file="docker-compose.yaml"
                    elif [[ -f "$project_dir/compose.yml" ]]; then
                        compose_file="compose.yml"
                    elif [[ -f "$project_dir/compose.yaml" ]]; then
                        compose_file="compose.yaml"
                    else
                        compose_file="${YELLOW}No compose file${NC}"
                    fi
                    
                    printf "%-35s %-15s %b %-20s %s\n" \
                        "$full_name" \
                        "$type" \
                        "$status" \
                        "" \
                        "$compose_file"
                fi
            done
        fi
    done
    
    rm -rf "$temp_repo_dir"
    
    echo ""
    if [[ $found -eq 0 ]]; then
        if [[ -n "$search_term" ]]; then
            print_warning "No projects found matching: '$search_term'"
        else
            print_warning "No projects found in repository"
        fi
    else
        echo ""
        print_info "To pull a project: $0 pull <project-name>/<type>"
        echo ""
        print_info "Example: $0 pull nextcloud/production"
    fi
}

# ========== Help Command ==========
cmd_help() {
    print_header
    print_title "Docker Compose Manager"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  show                      - List all compose projects with status"
    echo "  manage <project> <action> - Manage a specific compose project"
    echo "  pull <project>/<type>     - Download project from repository"
    echo "  remove <project>          - Remove a compose project"
    echo "  search [term]            - Search projects in repository"
    echo "  help                     - Show this help message"
    echo ""
    echo "Manage Actions:"
    echo "  up, down, stop, start, restart - Container management"
    echo "  status, logs, port, top        - Information"
    echo "  pull, build, update            - Image management"
    echo "  exec <service> <cmd>           - Execute command"
    echo "  config, images                 - Configuration"
    echo ""
    echo "Pull Types:"
    echo "  last-version, locally, production"
    echo ""
    echo "Examples:"
    echo "  $0 show"
    echo "  $0 manage nextcloud up"
    echo "  $0 manage nextcloud logs"
    echo "  $0 manage nextcloud exec app bash"
    echo "  $0 pull nextcloud/production"
    echo "  $0 remove nextcloud"
    echo "  $0 search wordpress"
    echo ""
}

# ========== Main ==========
main() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    
    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose V2 is not available"
        exit 1
    fi
    
    init_directories
    
    if [[ $# -eq 0 ]]; then
        cmd_show
        exit 0
    fi
    
    local command=$1
    shift
    
    case $command in
        show)
            cmd_show
            ;;
        manage)
            if [[ $# -lt 2 ]]; then
                print_error "Manage requires project name and action"
                cmd_help
                exit 1
            fi
            cmd_manage "$@"
            ;;
        pull)
            if [[ $# -lt 1 ]]; then
                print_error "Pull requires project/type"
                cmd_help
                exit 1
            fi
            cmd_pull "$1"
            ;;
        remove)
            if [[ $# -lt 1 ]]; then
                print_error "Remove requires project name"
                cmd_help
                exit 1
            fi
            cmd_remove "$1"
            ;;
        search)
            local search_term=""
            [[ $# -gt 0 ]] && search_term="$1"
            cmd_search "$search_term"
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            print_error "Unknown command: $command"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
