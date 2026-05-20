#!/bin/bash

# MACSYSTEM/auto_cleanup.sh
# Finds and deletes files automatically based on given params

GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

# Zorg dat autocomplete het scherm niet overvol maakt door het te wissen bij tab
set -o emacs
bind '"\t": "\C-l\e\e"' 2>/dev/null || true

pause() {
    echo -e "\n${YELLOW}Druk op Enter om door te gaan...${NC}"
    read -r
}

clear
echo -e "${CYAN}================================================${NC}"
echo -e "           ${CYAN}AUTO CLEANUP WIZARD${NC}"
echo -e "${CYAN}================================================${NC}"
echo -e "Hiermee verwijder je automatisch bestanden die aan bepaalde criteria voldoen.\n"

read -e -p "Geef directory (bv. ~/Downloads of druk op Enter voor huidige map): " target_dir
target_dir="${target_dir:-.}"
target_dir="${target_dir/#\~/$HOME}"

if [ ! -d "$target_dir" ]; then
    echo -e "${RED}Map niet gevonden!${NC}"
    pause
    exit 0
fi

read -p "Welk patroon? (bv. *.dmg): " pattern
if [ -z "$pattern" ]; then
    echo -e "${RED}Geen patroon opgegeven.${NC}"
    pause
    exit 0
fi

read -p "Ouder dan hoeveel dagen? (bv. 30): " days
if ! [[ "$days" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Geef een geldig getal in.${NC}"
    pause
    exit 0
fi

echo -e "\n${YELLOW}Ik sta op het punt het volgende commando uit te voeren:${NC}"
echo -e "find \"$target_dir\" -name \"$pattern\" -mtime +$days -delete\n"

read -p "Ga je hiermee akkoord? (y/N): " confirm
if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    echo -e "${CYAN}Bezig met verwijderen...${NC}"
    find "$target_dir" -name "$pattern" -mtime +"$days" -delete
    echo -e "${GREEN}Opruimen voltooid!${NC}"
else
    echo -e "${YELLOW}Geannuleerd.${NC}"
fi

pause