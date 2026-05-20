#!/bin/bash

# ============================================================
# CONTAINER MASTER CONTROL PANEL v1.0
# Docker Management for QNAP Container Station & macOS
# ============================================================

# set -e is disabled for interactive menu stability

# Zorg dat autocomplete het scherm niet overvol maakt door het te wissen bij tab
set -o emacs
bind '"\t": "\C-l\e\e"' 2>/dev/null || true

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

DOCKER_MODE="local"
SSH_USER=""
SSH_HOST=""
SSH_PORT="22"

pause() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# --- DOCKER WRAPPER ---
# We use a custom function `run_docker` to route commands to the correct host.
run_docker() {
    if [[ "$DOCKER_MODE" == "remote" ]]; then
        # Safely serialize arguments to preserve quotes over SSH
        printf -v cmd_str "%q " docker "$@"
        # For interactive shells (like logs -f or exec -it), we need -t
        ssh -t -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "$cmd_str"
    else
        docker "$@"
    fi
}

# Silent wrapper for capturing output (no -t flag which adds carriage returns)
run_docker_silent() {
    if [[ "$DOCKER_MODE" == "remote" ]]; then
        printf -v cmd_str "%q " docker "$@"
        ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "$cmd_str"
    else
        docker "$@"
    fi
}

connect_docker() {
    while true; do
        clear
        echo -e "${CYAN}=== Selecteer Docker Omgeving ===${NC}"
        echo "1) Lokaal (Localhost Mac/PC)"
        echo "2) Remote NAS (Via SSH naar QNAP/Linux)"
        echo "3) Afsluiten"
        read -p "Keuze: " env_choice

        if [[ "$env_choice" == "3" ]]; then
            exit 0
        elif [[ "$env_choice" == "2" ]]; then
            DOCKER_MODE="remote"
            read -e -p "SSH Host (IP of DNS): " SSH_HOST
            read -e -p "SSH User [admin]: " input_user
            SSH_USER=${input_user:-admin}
            read -e -p "SSH Port [22]: " input_port
            SSH_PORT=${input_port:-22}

            echo -e "\n${YELLOW}Verbinden met $SSH_HOST...${NC}"
            # Test SSH connection and docker presence
            if ssh -o ConnectTimeout=5 -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "command -v docker" &> /dev/null; then
                echo -e "${GREEN}✓ Connectie succesvol! Remote Docker gevonden.${NC}"
                pause
                break
            else
                echo -e "${RED}✗ Connectie mislukt of 'docker' is niet geïnstalleerd op de remote host.${NC}"
                read -p "Opnieuw proberen? (j/n): " retry
                if [[ "$retry" == "j" || "$retry" == "J" ]]; then
                    continue
                else
                    read -p "Lokaal opstarten als fallback? (j/n): " fallback
                    if [[ "$fallback" == "j" || "$fallback" == "J" ]]; then
                        DOCKER_MODE="local"
                        if ! command -v docker &> /dev/null; then
                            echo -e "${RED}Error: 'docker' command not found lokaal.${NC}"
                            echo "Please ensure Docker Desktop / CLI is installed."
                            pause
                            continue
                        else
                            break
                        fi
                    else
                        continue
                    fi
                fi
            fi
        elif [[ "$env_choice" == "1" ]]; then
            DOCKER_MODE="local"
            if ! command -v docker &> /dev/null; then
                echo -e "${RED}Error: 'docker' command not found lokaal.${NC}"
                echo "Please ensure Docker Desktop / CLI is installed."
                pause
                continue
            else
                break
            fi
        else
            continue
        fi
    done
}

show_header() {
    clear
    echo -e "${CYAN}${BOLD}===============================================================${NC}"
    echo -e "       ${CYAN}${BOLD}CONTAINER MASTER CONTROL PANEL v1.0${NC}"
    echo -e "${CYAN}${BOLD}===============================================================${NC}"

    local d_version
    local context="Local"

    if [[ "$DOCKER_MODE" == "remote" ]]; then
        context="Remote ($SSH_USER@$SSH_HOST)"
        d_version=$(run_docker_silent --version | cut -d ' ' -f3 | tr -d ',')
    else
        d_version=$(docker --version | cut -d ' ' -f3 | tr -d ',')
    fi

    echo -e " Host     : $context"
    echo -e " Docker   : ${GREEN}${d_version:-Onbekend}${NC}"
    echo -e "${CYAN}${BOLD}===============================================================${NC}"
}

# --- ACTIONS ---

list_containers() {
    echo -e "\n${GREEN}=== Active Containers ===${NC}"
    run_docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo -e "\n${YELLOW}=== All Containers (including stopped) ===${NC}"
    run_docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}" | head -n 10
    pause
}

view_logs() {
    echo -e "\n${CYAN}Select container to view logs:${NC}"
    containers=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && containers+=("$line")
    done < <(run_docker_silent ps -a --format "{{.Names}}" | tr -d '\r')

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
        # Interactive mode needs the normal run_docker wrapper (which has -t for ssh)
        run_docker logs --tail 50 -f "$target"
    fi
}

manage_lifecycle() {
    local action="$1" # start, stop, restart, rm
    echo -e "\n${CYAN}Select container to $action:${NC}"

    containers=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && containers+=("$line")
    done < <(run_docker_silent ps -a --format "{{.Names}}" | tr -d '\r')

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
        run_docker "$action" "$target"
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
                read -e -p "Project Name (folder name): " p_name

                if [[ -z "$p_name" ]]; then echo "Cancelled"; pause; return; fi

                if [[ "$DOCKER_MODE" == "remote" ]]; then
                    read -e -p "Remote pad (waar de map wordt aangemaakt, bv. /share/Container): " remote_base
                    remote_base=${remote_base:-~}
                    remote_dir="$remote_base/$p_name"

                    echo -e "${YELLOW}Aanmaken project in $remote_dir op $SSH_HOST...${NC}"
                    ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "mkdir -p \"$remote_dir\""
                    scp -P "$SSH_PORT" "$selected" "$SSH_USER@$SSH_HOST:\"$remote_dir/docker-compose.yml\""

                    read -p "Start stack nu? (j/n): " start_now
                    if [[ "$start_now" == "j" || "$start_now" == "J" ]]; then
                        ssh -t -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "cd \"$remote_dir\" && docker compose up -d"
                    fi
                else
                    mkdir -p "$p_name"
                    cp "$selected" "$p_name/docker-compose.yml"

                    echo -e "${GREEN}Created folder '$p_name' with docker-compose.yml${NC}"
                    read -p "Start stack nu? (j/n): " start_now
                    if [[ "$start_now" == "j" || "$start_now" == "J" ]]; then
                        cd "$p_name" && docker compose up -d
                        cd ..
                    fi
                fi
                pause
            fi
            ;;
        2)
            read -e -p "Image Name (e.g., nginx:alpine): " img
            read -e -p "Container Name: " c_name
            read -e -p "Port Mapping (host:container, e.g., 8080:80): " ports

            local cmd_args=("run" "-d" "--name" "$c_name")

            if [[ -n "$ports" ]]; then
                cmd_args+=("-p" "$ports")
            fi

            cmd_args+=("$img")

            echo -e "${YELLOW}Running: docker ${cmd_args[*]}${NC}"
            run_docker "${cmd_args[@]}"
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
        1) run_docker container prune ;;
        2) run_docker image prune ;;
        3) run_docker volume prune ;;
        4) run_docker system prune -a ;;
    esac
    pause
}

# --- INITIALIZATION ---
connect_docker

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
    echo " C) Wissel Connectie (Local/Remote)"
    echo " X) Quit"
    echo -e "${BOLD}===============================================================${NC}"
    read -p "Select action: " choice

    case $choice in
        1) list_containers ;;
        2) view_logs ;;
        3)
           read -e -p "Container Name/ID: " c_id
           if command -v python3 &> /dev/null; then
               # Pipe the output directly to the python viewer (handles both local and remote output)
               run_docker_silent inspect "$c_id" | python3 "$SCRIPT_DIR/inspect_viewer.py" - | less
           else
               run_docker_silent inspect "$c_id" | less
           fi
           ;;
        4) manage_lifecycle "start" ;;
        5) manage_lifecycle "stop" ;;
        6) manage_lifecycle "restart" ;;
        7)
            read -e -p "Container Name: " c_name
            echo "Entering shell (type 'exit' to leave)..."
            run_docker exec -it "$c_name" /bin/sh || run_docker exec -it "$c_name" /bin/bash
            ;;
        8) create_container ;;
        9) manage_lifecycle "rm" ;;
        10) cleanup_system ;;
        [cC]) connect_docker ;;
        [xXqQ]) clear; exit 0 ;;
        *) sleep 0.1 ;;
    esac
done
