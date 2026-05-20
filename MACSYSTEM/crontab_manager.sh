#!/bin/bash

# MACSYSTEM/crontab_manager.sh
# Manage crontab entries interactively

GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

pause() {
    echo -e "\n${YELLOW}Druk op Enter om door te gaan...${NC}"
    read -r
}

while true; do
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "           ${CYAN}CRONTAB MANAGER${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo "1) Bekijk Crontab (List)"
    echo "2) Bewerk Crontab (Edit)"
    echo "3) Wis Crontab (Clear)"
    echo "0) Terug"
    echo -e "${CYAN}================================================${NC}"

    read -p "Kies een optie: " choice
    case $choice in
        1)
            echo -e "\n${YELLOW}Huidige Crontab:${NC}"
            crontab -l || echo -e "${RED}Geen crontab gevonden voor de huidige gebruiker.${NC}"
            pause
            ;;
        2)
            echo -e "\n${YELLOW}Open crontab editor...${NC}"
            crontab -e
            pause
            ;;
        3)
            echo -e "\n${RED}Weet je zeker dat je alle crontab entries wilt wissen? (y/N)${NC}"
            read -p "Bevestiging: " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                crontab -r
                echo -e "${GREEN}Crontab succesvol gewist.${NC}"
            else
                echo -e "${YELLOW}Geannuleerd.${NC}"
            fi
            pause
            ;;
        0) break ;;
        *) echo -e "${RED}Ongeldige keuze.${NC}"; sleep 1 ;;
    esac
done