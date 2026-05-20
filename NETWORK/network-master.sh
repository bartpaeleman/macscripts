#!/bin/bash

# ============================================================
# NETWORK MASTER CONTROL PANEL
# Comprehensive Network Toolkit for QNAP & macOS
# ============================================================

# set -e is disabled for interactive menu stability

# --- COLORS ---
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- FUNCTIONS ---

pause() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

check_cmd() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Command '$1' not found on this system.${NC}"
        pause
        return 1
    fi
    return 0
}

# --- HELPER: GEOTRACE ---
run_geotrace() {
    read -p "Target IP/Domain: " target
    if [[ -f "$SCRIPT_DIR/geotrace.sh" ]]; then
        "$SCRIPT_DIR/geotrace.sh" "$target"
    else
        echo -e "${RED}geotrace.sh script not found in $SCRIPT_DIR${NC}"
    fi
    pause
}

# --- SUBMENU: INTERFACES & ROUTING ---
menu_interfaces() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}=== Interfaces & Routing ===${NC}"
        echo "1) ifconfig - Show All Interfaces"
        echo "2) ip addr - Show IP Addresses (Linux/QNAP)"
        echo "3) route - Show Routing Table"
        echo "4) arp - Show ARP Table"
        echo "0) Back"

        read -p "Select: " choice
        case $choice in
            1) check_cmd ifconfig && ifconfig -a | more; pause ;;
            2) check_cmd ip && ip addr show | more; pause ;;
            3)
                if command -v netstat &>/dev/null; then
                    netstat -nr | more
                elif command -v route &>/dev/null; then
                    route -n | more
                else
                    echo "No routing tool found."
                fi
                pause ;;
            4) check_cmd arp && arp -a | more; pause ;;
            [0]) return ;;
        esac
    done
}

# --- SUBMENU: CONNECTIVITY ---
menu_connectivity() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}=== Connectivity ===${NC}"
        echo "1) ping - Test Connection"
        echo "2) traceroute - Trace Path"
        echo "3) geotrace - Trace Path with GeoIP Location"
        echo "0) Back"

        read -p "Select: " choice
        case $choice in
            1)
                check_cmd ping || continue
                read -p "Target IP/Domain: " target
                read -p "Count [4]: " count
                count=${count:-4}
                ping -c "$count" "$target"
                pause
                ;;
            2)
                read -p "Target IP/Domain: " target
                if command -v traceroute &>/dev/null; then
                    traceroute "$target"
                elif command -v tracert &>/dev/null; then
                    tracert "$target" # Windows/Generic
                else
                    echo "traceroute command not found"
                fi
                pause
                ;;
            3)
                run_geotrace
                ;;
            [0]) return ;;
        esac
    done
}

# --- SUBMENU: DNS ---
menu_dns() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}=== DNS Tools ===${NC}"
        echo "1) nslookup - Query Domain"
        echo "2) dig - Detailed Query"
        echo "3) dig short - Get IP only"
        echo "0) Back"

        read -p "Select: " choice
        case $choice in
            1)
                check_cmd nslookup || continue
                read -p "Domain: " domain
                nslookup "$domain"
                pause
                ;;
            2)
                check_cmd dig || continue
                read -p "Domain: " domain
                read -p "DNS Server (optional, e.g. 8.8.8.8): " server
                if [[ -n "$server" ]]; then
                    dig "@$server" "$domain"
                else
                    dig "$domain"
                fi
                pause
                ;;
            3)
                check_cmd dig || continue
                read -p "Domain: " domain
                dig +short "$domain"
                pause
                ;;
            [0]) return ;;
        esac
    done
}

# --- SUBMENU: STATS & SOCKETS ---
menu_stats() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}=== Network Statistics ===${NC}"
        echo "1) netstat - All Connections"
        echo "2) netstat - Listening Ports"
        echo "3) ss - Socket Stats (TCP)"
        echo "4) ss - Socket Stats (UDP)"
        echo "0) Back"

        read -p "Select: " choice
        case $choice in
            1) check_cmd netstat && netstat -a | more; pause ;;
            2)
                # MacOS netstat flags are different than Linux
                if [[ "$(uname)" == "Darwin" ]]; then
                    netstat -an | grep LISTEN | more
                else
                    netstat -tuln | more
                fi
                pause ;;
            3) check_cmd ss && ss -t -a | more; pause ;;
            4) check_cmd ss && ss -u -a | more; pause ;;
            [0]) return ;;
        esac
    done
}

# --- SUBMENU: WEB TOOLS ---
menu_web() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}=== Web Tools ===${NC}"
        echo "1) curl - Fetch Headers"
        echo "2) curl - Verbose Request"
        echo "3) wget - Download File"
        echo "4) Show Public IP (via ifconfig.me)"
        echo "0) Back"

        read -p "Select: " choice
        case $choice in
            1)
                check_cmd curl || continue
                read -p "URL: " url
                curl -I "$url"
                pause
                ;;
            2)
                check_cmd curl || continue
                read -p "URL: " url
                curl -v "$url"
                pause
                ;;
            3)
                check_cmd wget || continue
                read -p "URL: " url
                wget "$url"
                pause
                ;;
            4)
                check_cmd curl || continue
                echo "Fetching public IP..."
                curl -s ifconfig.me
                echo ""
                pause
                ;;
            [0]) return ;;
        esac
    done
}

# --- SUBMENU: PYTHON TOOLS ---
menu_python() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}=== Python Network Tools ===${NC}"

        if ! command -v python3 &> /dev/null; then
             echo -e "${YELLOW}Python3 not detected. These tools require python3.${NC}"
             pause
             return
        fi

        echo "1) Simple Port Scanner"
        echo "0) Back"

        read -p "Select: " choice
        case $choice in
            1)
                read -p "Target IP: " ip
                read -p "Start Port [1]: " sp
                sp=${sp:-1}
                read -p "End Port [1024]: " ep
                ep=${ep:-1024}
                python3 "${SCRIPT_DIR}/scan_ports.py" "$ip" "$sp" "$ep"
                pause
                ;;
            [0]) return ;;
        esac
    done
}

# --- MAIN LOOP ---

while true; do
    clear
    echo -e "${CYAN}${BOLD}===============================================================${NC}"
    echo -e "       ${CYAN}${BOLD}NETWORK MASTER CONTROL PANEL${NC}"
    echo -e "${CYAN}${BOLD}===============================================================${NC}"
    echo " 1) Interfaces & Routing (ifconfig, ip, route, arp)"
    echo " 2) Connectivity (ping, traceroute)"
    echo " 3) DNS Tools (nslookup, dig)"
    echo " 4) Statistics (netstat, ss)"
    echo " 5) Web Tools (curl, wget)"
    echo " 6) Advanced / Python Tools"
    echo " 7) GeoTrace (traceroute with GeoIP)"
    echo -e "---------------------------------------------------------------"
    echo " X) Exit"
    echo -e "${BOLD}===============================================================${NC}"

    read -p "Select action: " main_choice

    case $main_choice in
        1) menu_interfaces ;;
        2) menu_connectivity ;;
        3) menu_dns ;;
        4) menu_stats ;;
        5) menu_web ;;
        6) menu_python ;;
        7) run_geotrace ;;
        [xX]) clear; exit 0 ;;
        *) sleep 0.1 ;;
    esac
done
