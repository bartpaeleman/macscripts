#!/bin/bash

# ============================================================
# CONTAINER MASTER CONTROL PANEL v1.0
# Docker Management for QNAP Container Station & macOS
# ============================================================

# set -e is disabled for interactive menu stability

# --- COLORS ---
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'
BOLD='\033[1m'

# --- CONFIGURATION ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"

# Check dependencies
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: 'docker' command not found.${NC}"
    echo "Please ensure Container Station is installed and Docker is in your PATH."
    exit 1
fi

# --- FUNCTIONS ---

show_header() {
    clear
    echo -e "${CYAN}${BOLD}===============================================================${NC}"
    echo -e "       ${CYAN}${BOLD}CONTAINER MASTER CONTROL PANEL v1.0${NC}"
    echo -e "${CYAN}${BOLD}===============================================================${NC}"
    echo -e " System   : $(uname -s)"
    echo -e " Docker   : $(docker --version | cut -d ' ' -f3 | tr -d ',')"
    echo -e " Context  : $(docker context show)"
    echo -e "${CYAN}${BOLD}===============================================================${NC}"
}

pause() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# --- ACTIONS ---

list_containers() {
    echo -e "\n${GREEN}=== Active Containers ===${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo -e "\n${YELLOW}=== All Containers (including stopped) ===${NC}"
    docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}" | head -n 10
    pause
}

view_logs() {
    echo -e "\n${CYAN}Select container to view logs:${NC}"
    # Get list of container names - macOS compatible way
    containers=()
    while IFS= read -r line; do
        containers+=("$line")
    done < <(docker ps -a --format "{{.Names}}")

    if [[ ${#containers[@]} -eq 0 ]]; then
        echo "No containers found."
        pause
        return
    fi

    local i=1
    for name in "${containers[@]}"; do
        echo "$i) $name"
        ((i++))
    done

    read -p "Number: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#containers[@]}" ]; then
        target="${containers[$((choice-1))]}"
        echo -e "\n${GREEN}Logs for $target (Last 50 lines, follow mode)...${NC}"
        docker logs --tail 50 -f "$target"
    fi
}

manage_lifecycle() {
    local action="$1" # start, stop, restart
    echo -e "\n${CYAN}Select container to $action:${NC}"

    containers=()
    while IFS= read -r line; do
        containers+=("$line")
    done < <(docker ps -a --format "{{.Names}}")

    if [[ ${#containers[@]} -eq 0 ]]; then
        echo "No containers found."
        pause
        return
    fi

    local i=1
    for name in "${containers[@]}"; do
        echo "$i) $name"
        ((i++))
    done

    read -p "Number: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#containers[@]}" ]; then
        target="${containers[$((choice-1))]}"
        echo -e "\n${YELLOW}Executing $action on $target...${NC}"
        docker "$action" "$target"
        echo -e "${GREEN}Done.${NC}"
        pause
    fi
}

create_container() {
    echo -e "\n${CYAN}=== Create New Container Stack ===${NC}"
    echo "1) From Template (Docker Compose)"
    echo "2) Custom Image Run"
    echo "X) Back"
    read -p "Select: " method

    case $method in
        1)
            echo -e "\n${YELLOW}Available Templates:${NC}"
            local templates=("$TEMPLATE_DIR"/*.yml)
            if [ ! -e "${templates[0]}" ]; then
                echo "No templates found in $TEMPLATE_DIR"
                pause
                return
            fi

            local i=1
            for t in "${templates[@]}"; do
                echo "$i) $(basename "$t" .yml)"
                ((i++))
            done

            read -p "Select Template: " t_idx
            if [[ "$t_idx" =~ ^[0-9]+$ ]] && [ "$t_idx" -ge 1 ] && [ "$t_idx" -le "${#templates[@]}" ]; then
                selected="${templates[$((t_idx-1))]}"
                read -p "Project Name (folder name): " p_name

                if [[ -z "$p_name" ]]; then echo "Cancelled"; pause; return; fi

                mkdir -p "$p_name"
                cp "$selected" "$p_name/docker-compose.yml"

                echo -e "${GREEN}Created folder '$p_name' with docker-compose.yml${NC}"
                read -p "Start stack now? (y/n): " start_now
                if [[ "$start_now" == "y" ]]; then
                    cd "$p_name" && docker compose up -d
                    cd ..
                fi
            fi
            ;;
        2)
            read -p "Image Name (e.g., nginx:alpine): " img
            read -p "Container Name: " c_name
            read -p "Port Mapping (host:container, e.g., 8080:80): " ports

            # Construct command using array for safety
            local cmd_args=("run" "-d" "--name" "$c_name")

            if [[ -n "$ports" ]]; then
                cmd_args+=("-p" "$ports")
            fi

            cmd_args+=("$img")

            echo -e "${YELLOW}Running: docker ${cmd_args[*]}${NC}"
            docker "${cmd_args[@]}"
            pause
            ;;
    esac
}

cleanup_system() {
    echo -e "\n${RED}${BOLD}=== SYSTEM CLEANUP ===${NC}"
    echo "1) Prune Stopped Containers"
    echo "2) Prune Unused Images"
    echo "3) Prune Unused Volumes"
    echo "4) Prune Everything (System Prune -a)"
    echo "X) Cancel"
    read -p "Select: " clean_opt

    case $clean_opt in
        1) docker container prune ;;
        2) docker image prune ;;
        3) docker volume prune ;;
        4) docker system prune -a ;;
    esac
    pause
}

# --- MAIN LOOP ---

while true; do
    show_header

    echo -e "${BOLD}[ PHASE 1: MONITOR ]${NC}"
    echo " 1) List Containers (Status)"
    echo " 2) View Logs (Live)"
    echo " 3) Inspect Container (JSON)"

    echo -e "\n${BOLD}[ PHASE 2: MANAGE ]${NC}"
    echo " 4) Start Container"
    echo " 5) Stop Container"
    echo " 6) Restart Container"
    echo " 7) Shell Access (Exec /bin/bash)"

    echo -e "\n${BOLD}[ PHASE 3: CREATE & DESTROY ]${NC}"
    echo " 8) Create New Stack"
    echo " 9) Remove Container"
    echo " 10) System Cleanup"

    echo -e "\n---------------------------------------------------------------"
    echo " Q) Quit"
    echo -e "${BOLD}===============================================================${NC}"
    read -p "Select action: " choice

    case $choice in
        1) list_containers ;;
        2) view_logs ;;
        3)
           read -p "Container Name/ID: " c_id
           if command -v python3 &> /dev/null; then
               python3 "$SCRIPT_DIR/inspect_viewer.py" "$c_id" | less
           else
               docker inspect "$c_id" | less
           fi
           ;;
        4) manage_lifecycle "start" ;;
        5) manage_lifecycle "stop" ;;
        6) manage_lifecycle "restart" ;;
        7)
            read -p "Container Name: " c_name
            echo "Entering shell (type 'exit' to leave)..."
            docker exec -it "$c_name" /bin/sh || docker exec -it "$c_name" /bin/bash
            ;;
        8) create_container ;;
        9) manage_lifecycle "rm" ;;
        10) cleanup_system ;;
        [Qq]) clear; exit 0 ;;
        *) sleep 0.1 ;;
    esac
done
