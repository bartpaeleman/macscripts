#!/bin/bash

# MACSYSTEM/clear_cache.sh
# Removes cache files on Mac

GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

pause() {
    echo -e "\n${YELLOW}Druk op Enter om door te gaan...${NC}"
    read -r
}

clear
echo -e "${CYAN}================================================${NC}"
echo -e "             ${CYAN}CACHE CLEARER${NC}"
echo -e "${CYAN}================================================${NC}"
echo -e "${YELLOW}WAARSCHUWING:${NC} Dit script verwijdert bestanden in ~/Library/Caches/ en /Library/Caches/."
echo "Applicaties zullen deze bestanden opnieuw genereren, maar de eerste keer opstarten kan trager zijn."

read -p "Doorgaan met wissen? (y/N): " confirm
if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then

    echo -e "\n${CYAN}1. Bezig met wissen van User Caches (~/Library/Caches/)...${NC}"
    rm -rf ~/Library/Caches/* 2>/dev/null

    echo -e "${CYAN}2. Bezig met wissen van System Caches (/Library/Caches/)...${NC}"
    echo -e "${YELLOW}(Mogelijk is je wachtwoord vereist voor sudo)${NC}"
    sudo rm -rf /Library/Caches/* 2>/dev/null

    echo -e "${CYAN}3. Bezig met flushen van DNS Caches...${NC}"
    sudo dscacheutil -flushcache 2>/dev/null
    sudo killall -HUP mDNSResponder 2>/dev/null

    echo -e "${GREEN}\nAlle caches zijn verwijderd!${NC}"
else
    echo -e "\n${YELLOW}Geannuleerd.${NC}"
fi

pause