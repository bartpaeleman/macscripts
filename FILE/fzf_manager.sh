#!/bin/bash

# Zorg dat autocomplete het scherm niet overvol maakt door het te wissen bij tab
set -o emacs
bind '"\t": "\C-l\e\e"' 2>/dev/null || true

GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

pause() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

check_dependencies() {
    if ! command -v fzf &> /dev/null; then
        echo -e "${YELLOW}'fzf' is niet geïnstalleerd. Proberen te installeren via Homebrew...${NC}"
        if command -v brew &> /dev/null; then
            brew install fzf
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y fzf
        else
            echo -e "${RED}Kan 'fzf' niet automatisch installeren. Installeer het handmatig (brew install fzf).${NC}"
            pause
            exit 1
        fi

        if ! command -v fzf &> /dev/null; then
             echo -e "${RED}Installatie mislukt. Zorg dat 'fzf' is geïnstalleerd.${NC}"
             pause
             exit 1
        fi
    fi
}

get_target() {
    read -e -p "Vanaf welke directory wil je zoeken? (Enter = huidig): " target_path
    target_path="${target_path:-.}"

    if [[ ! -d "$target_path" ]]; then
        echo -e "${RED}Directory bestaat niet!${NC}"
        return 1
    fi
    return 0
}

search_and_open() {
    if ! get_target; then return; fi
    echo -e "${CYAN}Gebruik fzf om een bestand te zoeken. Druk op ESC of CTRL-C om te annuleren.${NC}"

    # Gebruik fzf om bestand te kiezen
    selected_file=$(find "$target_path" -type f 2>/dev/null | fzf --prompt="Zoek bestand> " --height=40% --layout=reverse --border)

    if [[ -n "$selected_file" && -f "$selected_file" ]]; then
        echo -e "\nJe hebt gekozen: ${GREEN}$selected_file${NC}"

        if command -v open &> /dev/null; then
            open "$selected_file"
        else
            editor="${EDITOR:-nano}"
            "$editor" "$selected_file"
        fi
    else
        echo -e "${YELLOW}Geen bestand geselecteerd.${NC}"
    fi
    pause
}

search_content() {
    if ! get_target; then return; fi
    read -p "Geef de zoekterm (voor grep): " search_term

    if [[ -z "$search_term" ]]; then
         echo -e "${RED}Geen zoekterm opgegeven.${NC}"
         pause
         return
    fi

    echo -e "${CYAN}Zoeken in bestandsinhoud via fzf...${NC}"
    # grep zoekt naar content en pipe naar fzf, toont filenaam en regel
    selected_match=$(grep -rnI "$search_term" "$target_path" 2>/dev/null | fzf --prompt="Selecteer match> " --height=40% --layout=reverse --border)

    if [[ -n "$selected_match" ]]; then
        echo -e "\nJe hebt gekozen:"
        echo -e "${GREEN}$selected_match${NC}"

        # Probeer het bestand in een editor te openen
        file_to_open=$(echo "$selected_match" | cut -d: -f1)
        if [[ -f "$file_to_open" ]]; then
            read -p "Wil je dit bestand openen in de editor? [Y/n]: " open_choice
            if [[ "$open_choice" != "n" && "$open_choice" != "N" ]]; then
                editor="${EDITOR:-nano}"
                "$editor" "$file_to_open"
            fi
        fi
    else
        echo -e "${YELLOW}Geen match geselecteerd of gevonden.${NC}"
    fi
    pause
}

search_and_move() {
    if ! get_target; then return; fi
    echo -e "${CYAN}Gebruik fzf om een bronbestand te zoeken.${NC}"

    selected_file=$(find "$target_path" -type f 2>/dev/null | fzf --prompt="Kies bestand om te verplaatsen> " --height=40% --layout=reverse --border)

    if [[ -n "$selected_file" && -f "$selected_file" ]]; then
        echo -e "\nTe verplaatsen: ${GREEN}$selected_file${NC}"
        read -e -p "Geef doelmap of nieuwe bestandsnaam: " dest_path

        if [[ -n "$dest_path" ]]; then
            mv -v "$selected_file" "$dest_path"
            echo -e "${GREEN}Bestand verplaatst!${NC}"
        else
            echo -e "${RED}Geen doel opgegeven.${NC}"
        fi
    else
        echo -e "${YELLOW}Geen bestand geselecteerd.${NC}"
    fi
    pause
}

check_dependencies

while true; do
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "         ${CYAN}FUZZY FINDER MANAGER (fzf)${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo "1) Zoek en open bestand"
    echo "2) Zoek in bestandsinhoud (grep + fzf)"
    echo "3) Zoek en verplaats bestand"
    echo "0) Terug / Afsluiten"
    echo -e "${CYAN}================================================${NC}"

    read -p "Kies een optie: " choice
    case $choice in
        1) search_and_open ;;
        2) search_content ;;
        3) search_and_move ;;
        0) break ;;
        *) echo -e "${RED}Ongeldige keuze.${NC}"; sleep 1 ;;
    esac
done