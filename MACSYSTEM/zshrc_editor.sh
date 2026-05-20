#!/bin/bash

# MACSYSTEM/zshrc_editor.sh
# Edit and source ~/.zshrc

GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

pause() {
    echo -e "\n${YELLOW}Druk op Enter om door te gaan...${NC}"
    read -r
}

ZSHRC_PATH="$HOME/.zshrc"

while true; do
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "             ${CYAN}ZSHRC EDITOR${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo "1) Bewerk ~/.zshrc met de standaard editor"
    echo "2) Instructies voor toepassen wijzigingen"
    echo "0) Terug"
    echo -e "${CYAN}================================================${NC}"

    read -p "Kies een optie: " choice
    case $choice in
        1)
            if [ ! -f "$ZSHRC_PATH" ]; then
                echo -e "${YELLOW}Bestand ~/.zshrc bestaat niet. Er wordt een nieuwe aangemaakt.${NC}"
                touch "$ZSHRC_PATH"
            fi
            editor="${EDITOR:-nano}"
            "$editor" "$ZSHRC_PATH"
            ;;
        2)
            echo -e "\n${YELLOW}Pas wijzigingen toe...${NC}"
            if [ -f "$ZSHRC_PATH" ]; then
                echo -e "${GREEN}Let op: Om de wijzigingen te activeren, run:\n  source ~/.zshrc\n... in je actieve terminal.${NC}"
            else
                echo -e "${RED}Bestand ~/.zshrc bestaat niet.${NC}"
            fi
            pause
            ;;
        0) break ;;
        *) echo -e "${RED}Ongeldige keuze.${NC}"; sleep 1 ;;
    esac
done