#!/bin/bash

# MACSYSTEM/macmanager.sh
# Main control panel for Mac tools

GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

MACSYSTEM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while true; do
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "         ${CYAN}MAC SYSTEM CONTROL PANEL${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo -e "${GREEN}Available tools:${NC}"
    echo "1) Crontab Manager"
    echo "2) Zshrc Editor"
    echo "3) Auto Cleanup"
    echo "4) Clear Cache"
    echo "5) Verwijder Applicatie"
    echo -e "\n${YELLOW}X) Exit${NC}"
    echo -e "${CYAN}================================================${NC}"

    read -p "Select action: " choice

    case "$choice" in
        1) "$MACSYSTEM_DIR/crontab_manager.sh" ;;
        2) "$MACSYSTEM_DIR/zshrc_editor.sh" ;;
        3) "$MACSYSTEM_DIR/auto_cleanup.sh" ;;
        4) "$MACSYSTEM_DIR/clear_cache.sh" ;;
        5) "$MACSYSTEM_DIR/uninstall.sh" ;;
        [xX])
            echo -e "${GREEN}Exiting...${NC}"
            clear
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice.${NC}"
            sleep 1
            ;;
    esac
done