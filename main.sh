#!/bin/bash

# Configuration
ALL_COMPOSE_DIR="./all-compose"
DIALOG_TITLE="Docker Compose Manager"
DIALOG_HEIGHT=20
DIALOG_WIDTH=60

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "Please install dialog first:"
    echo "  Ubuntu/Debian: sudo apt-get install dialog"
    echo "  CentOS/RHEL: sudo yum install dialog"
    echo "  arch: sudo pacman -Sy install dialog"
    exit 1
fi

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    dialog --title "Error" --msgbox "Docker is not installed!" 10 50
    exit 1
fi

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    dialog --title "Error" --msgbox "Docker Compose is not installed!" 10 50
    exit 1
fi

# Function to get compose command (docker-compose or docker compose)
get_compose_cmd() {
    local compose_dir="$1"
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    else
        echo "docker compose"
    fi
}

# Function to check if directory contains docker-compose.yml
is_compose_dir() {
    local dir="$1"
    if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ]; then
        return 0
    else
        return 1
    fi
}

# Function to get all compose directories
get_compose_dirs() {
    local dirs=()
    
    if [ ! -d "$ALL_COMPOSE_DIR" ]; then
        mkdir -p "$ALL_COMPOSE_DIR"
        dialog --title "Info" --msgbox "Created $ALL_COMPOSE_DIR directory.\nPlease add your compose directories here." 10 50
    fi
    
    for dir in "$ALL_COMPOSE_DIR"/*; do
        if [ -d "$dir" ] && is_compose_dir "$dir"; then
            dir_name=$(basename "$dir")
            dirs+=("$dir_name" "$dir")
        fi
    done
    
    echo "${dirs[@]}"
}

# Function to get service status
get_service_status() {
    local compose_dir="$1"
    local compose_cmd=$(get_compose_cmd "$compose_dir")
    
    cd "$compose_dir" || return 1
    
    if $compose_cmd ps --services | grep -q "."; then
        local running_services=$($compose_cmd ps --services | wc -l)
        local total_services=$($compose_cmd config --services | wc -l)
        
        if [ "$running_services" -eq "$total_services" ]; then
            echo "running"
        elif [ "$running_services" -eq 0 ]; then
            echo "stopped"
        else
            echo "partial"
        fi
    else
        echo "stopped"
    fi
    
    cd - > /dev/null
}

# Function to show service logs
show_logs() {
    local compose_dir="$1"
    local compose_cmd=$(get_compose_cmd "$compose_dir")
    
    cd "$compose_dir" || return 1
    
    local services=($($compose_cmd config --services))
    local service_list=()
    
    for service in "${services[@]}"; do
        service_list+=("$service" "$service")
    done
    
    local selected_service
    selected_service=$(dialog --title "Select Service for Logs" \
        --menu "Choose a service:" 15 50 5 \
        "${service_list[@]}" \
        3>&1 1>&2 2>&3)
    
    if [ -n "$selected_service" ]; then
        clear
        echo -e "${BLUE}Showing logs for $selected_service (Press Ctrl+C to exit)${NC}"
        echo "=========================================="
        $compose_cmd logs -f --tail=100 "$selected_service"
        read -p "Press Enter to continue..."
    fi
    
    cd - > /dev/null
}

# Function to check and download images
check_and_download_images() {
    local compose_dir="$1"
    local compose_cmd=$(get_compose_cmd "$compose_dir")
    
    cd "$compose_dir" || return 1
    
    # Get all images from compose file
    local images=($($compose_cmd config | grep 'image:' | awk '{print $2}' | sort | uniq))
    
    local missing_images=()
    local existing_images=()
    
    for image in "${images[@]}"; do
        if docker image inspect "$image" &> /dev/null; then
            existing_images+=("$image")
        else
            missing_images+=("$image")
        fi
    done
    
    if [ ${#missing_images[@]} -gt 0 ]; then
        dialog --title "Downloading Images" --infobox "Downloading missing images...\nThis may take a while." 10 50
        
        for image in "${missing_images[@]}"; do
            echo -e "${YELLOW}Downloading: $image${NC}"
            docker pull "$image" 2>&1 | while read line; do
                echo "$line"
            done
        done
    fi
    
    cd - > /dev/null
}

# Function to show service ports
show_service_ports() {
    local compose_dir="$1"
    local compose_cmd=$(get_compose_cmd "$compose_dir")
    
    cd "$compose_dir" || return 1
    
    local port_info=""
    
    # Get port mappings from running containers
    local containers=$($compose_cmd ps -q)
    
    if [ -n "$containers" ]; then
        for container in $containers; do
            local container_name=$(docker inspect --format '{{.Name}}' "$container" | sed 's/^\///')
            local ports=$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{(index $conf 0).HostPort}}->{{$p}} {{end}}' "$container")
            
            if [ -n "$ports" ]; then
                port_info+="$container_name:\n"
                port_info+="  $ports\n"
            fi
        done
    fi
    
    if [ -z "$port_info" ]; then
        port_info="No active ports found or services are not running."
    fi
    
    dialog --title "Service Ports" --msgbox "$port_info" 20 70
    
    cd - > /dev/null
}

# Function to manage a compose directory
manage_compose() {
    local compose_name="$1"
    local compose_dir="$2"
    
    while true; do
        local status=$(get_service_status "$compose_dir")
        local status_color=""
        
        case $status in
            "running") status_color="${GREEN}● Running${NC}" ;;
            "stopped") status_color="${RED}● Stopped${NC}" ;;
            "partial") status_color="${YELLOW}● Partial${NC}" ;;
        esac
        
        local action
        action=$(dialog --title "Manage: $compose_name" \
            --cancel-label "Back" \
            --menu "Status: $status_color\nDirectory: $compose_dir" \
            $DIALOG_HEIGHT $DIALOG_WIDTH 8 \
            1 "🔼 Up (Start all services)" \
            2 "⏹️ Stop (Stop all services)" \
            3 "⬇️ Down (Stop and remove)" \
            4 "🔁 Restart" \
            5 "📋 Show logs" \
            6 "🔧 Show ports" \
            7 "📊 View status" \
            8 "🔄 Pull latest images" \
            3>&1 1>&2 2>&3)
        
        local exit_status=$?
        
        if [ $exit_status -ne 0 ]; then
            return
        fi
        
        local compose_cmd=$(get_compose_cmd "$compose_dir")
        
        case $action in
            1) # Up
                check_and_download_images "$compose_dir"
                
                cd "$compose_dir" || continue
                dialog --title "Starting Services" --infobox "Starting $compose_name..." 10 50
                
                # Run in background and capture output
                ($compose_cmd up -d 2>&1) | tee /tmp/compose_output.txt
                
                if [ ${PIPESTATUS[0]} -eq 0 ]; then
                    dialog --title "Success" --msgbox "$compose_name started successfully!" 10 50
                    show_service_ports "$compose_dir"
                else
                    dialog --title "Error" --msgbox "Failed to start $compose_name. Check logs." 10 50
                fi
                cd - > /dev/null
                ;;
                
            2) # Stop
                cd "$compose_dir" || continue
                dialog --title "Stopping Services" --infobox "Stopping $compose_name..." 10 50
                if $compose_cmd stop; then
                    dialog --title "Success" --msgbox "$compose_name stopped successfully!" 10 50
                else
                    dialog --title "Error" --msgbox "Failed to stop $compose_name." 10 50
                fi
                cd - > /dev/null
                ;;
                
            3) # Down
                if dialog --title "Confirm" --yesno "This will stop and remove all containers, networks, and volumes.\nAre you sure?" 10 50; then
                    cd "$compose_dir" || continue
                    dialog --title "Removing Services" --infobox "Removing $compose_name..." 10 50
                    if $compose_cmd down; then
                        dialog --title "Success" --msgbox "$compose_name removed successfully!" 10 50
                    else
                        dialog --title "Error" --msgbox "Failed to remove $compose_name." 10 50
                    fi
                    cd - > /dev/null
                fi
                ;;
                
            4) # Restart
                cd "$compose_dir" || continue
                dialog --title "Restarting Services" --infobox "Restarting $compose_name..." 10 50
                if $compose_cmd restart; then
                    dialog --title "Success" --msgbox "$compose_name restarted successfully!" 10 50
                else
                    dialog --title "Error" --msgbox "Failed to restart $compose_name." 10 50
                fi
                cd - > /dev/null
                ;;
                
            5) # Show logs
                show_logs "$compose_dir"
                ;;
                
            6) # Show ports
                show_service_ports "$compose_dir"
                ;;
                
            7) # View status
                cd "$compose_dir" || continue
                local status_output
                status_output=$($compose_cmd ps 2>&1)
                dialog --title "Service Status" --msgbox "$status_output" 20 80
                cd - > /dev/null
                ;;
                
            8) # Pull latest images
                check_and_download_images "$compose_dir"
                dialog --title "Success" --msgbox "Images updated successfully!" 10 50
                ;;
        esac
    done
}

# Main function
main() {
    while true; do
        # Get compose directories
        local compose_dirs=($(get_compose_dirs))
        
        if [ ${#compose_dirs[@]} -eq 0 ]; then
            dialog --title "No Compose Directories" \
                --msgbox "No compose directories found in $ALL_COMPOSE_DIR.\n\nCreate directories with docker-compose.yml files in:\n$ALL_COMPOSE_DIR/" 12 60
            return
        fi
        
        # Add exit option
        compose_dirs+=("Exit" "Exit the application")
        
        local selected_compose
        selected_compose=$(dialog --title "$DIALOG_TITLE" \
            --menu "Select a Docker Compose to manage:" \
            $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
            "${compose_dirs[@]}" \
            3>&1 1>&2 2>&3)
        
        local exit_status=$?
        
        if [ $exit_status -ne 0 ] || [ "$selected_compose" = "Exit" ]; then
            clear
            echo "Goodbye!"
            exit 0
        fi
        
        # Find the directory path for selected compose
        local selected_dir=""
        for ((i=0; i<${#compose_dirs[@]}; i+=2)); do
            if [ "${compose_dirs[i]}" = "$selected_compose" ]; then
                selected_dir="${compose_dirs[i+1]}"
                break
            fi
        done
        
        if [ -n "$selected_dir" ] && [ "$selected_dir" != "Exit" ]; then
            manage_compose "$selected_compose" "$selected_dir"
        fi
    done
}

# Run main function
main
