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
    if ! command -v rename &> /dev/null; then
        echo -e "${YELLOW}'rename' is niet geïnstalleerd. Proberen te installeren via Homebrew...${NC}"
        if command -v brew &> /dev/null; then
            brew install rename
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y rename
        else
            echo -e "${RED}Kan 'rename' niet automatisch installeren. Installeer het handmatig (brew install rename).${NC}"
            pause
            exit 1
        fi

        if ! command -v rename &> /dev/null; then
             echo -e "${RED}Installatie mislukt. Zorg dat 'rename' is geïnstalleerd.${NC}"
             pause
             exit 1
        fi
    fi
}

get_target() {
    read -e -p "Geef bestand of directory op (gebruik Tab voor autocomplete): " target_path
    target_path="${target_path:-.}"

    if [[ ! -e "$target_path" ]]; then
        echo -e "${RED}Bestand of directory bestaat niet!${NC}"
        return 1
    fi
    return 0
}

run_rename() {
    local expr="$1"

    read -p "Uitvoeren als Dry-run (niets echt hernoemen)? [Y/n]: " dry_choice
    local flags="-v -d"
    if [[ "$dry_choice" != "n" && "$dry_choice" != "N" ]]; then
        flags="$flags -n"
        echo -e "${YELLOW}[DRY RUN MODUS]${NC}"
    fi

    if [[ -d "$target_path" ]]; then
        read -p "Ook in submappen zoeken (recursief)? [y/N]: " recurse
        if [[ "$recurse" == "y" || "$recurse" == "Y" ]]; then
            # Gebruik find en stuur de output door naar rename via xargs
            # -print0 en -0 voor spaties in bestandsnamen
            echo -e "${CYAN}Uitvoeren op folder recursief...${NC}"
            find "$target_path" -type f -print0 | xargs -0 rename $flags "$expr"
        else
            echo -e "${CYAN}Uitvoeren op folder (enkel direct in map)...${NC}"
            # Voorkom error als map leeg is
            shopt -s nullglob
            # rename expects files as arguments.
            rename $flags "$expr" "$target_path"/*
            shopt -u nullglob
        fi
    else
        echo -e "${CYAN}Uitvoeren op specifiek bestand...${NC}"
        rename $flags "$expr" "$target_path"
    fi
    pause
}

check_dependencies

if ! get_target; then
    exit 1
fi

while true; do
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "         ${CYAN}ADVANCED RENAME (plasmasturm)${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo -e "Doelwit: ${YELLOW}$target_path${NC}\n"
    echo "1) Zoek en Vervang (s/search/replace/g)"
    echo "2) Alles naar kleine letters (tr/A-Z/a-z/)"
    echo "3) Alles naar HOOFDLETTERS (tr/a-z/A-Z/)"
    echo "4) Specifieke tekst verwijderen (s/string//g)"
    echo "5) Vervang spaties door underscores (s/ /_/g)"
    echo "6) Voeg Prefix toe voor de naam"
    echo "7) Voeg Suffix toe (voor de extensie)"
    echo "8) Custom Perl Expressie"
    echo "0) Terug / Afsluiten"
    echo -e "${CYAN}================================================${NC}"

    read -p "Kies een optie: " choice
    case $choice in
        1)
            read -p "Zoek tekst: " search_text
            read -p "Vervang door: " replace_text
            # Basic escape for slashes to prevent breaking the expression
            s_escaped=$(echo "$search_text" | sed 's/\//\\\//g')
            r_escaped=$(echo "$replace_text" | sed 's/\//\\\//g')
            run_rename "s/$s_escaped/$r_escaped/g"
            ;;
        2)
            run_rename 'tr/A-Z/a-z/'
            ;;
        3)
            run_rename 'tr/a-z/A-Z/'
            ;;
        4)
            read -p "Te verwijderen tekst: " rem_text
            r_escaped=$(echo "$rem_text" | sed 's/\//\\\//g')
            run_rename "s/$r_escaped//g"
            ;;
        5)
            run_rename 's/ /_/g'
            ;;
        6)
            read -p "Prefix tekst: " prefix_text
            p_escaped=$(echo "$prefix_text" | sed 's/\//\\\//g')
            # '$_' holds the filename. Prefix prepends it.
            run_rename "s/^/$p_escaped/"
            ;;
        7)
            read -p "Suffix tekst: " suffix_text
            s_escaped=$(echo "$suffix_text" | sed 's/\//\\\//g')
            # Voeg in net voor de laatste punt (extensie), of achteraan als geen punt
            run_rename "s/(\.[^.]+)?$/$s_escaped\$1/"
            ;;
        8)
            read -p "Geef volledige Perl expressie (bv. s/foo/bar/): " custom_expr
            run_rename "$custom_expr"
            ;;
        0) break ;;
        *) echo -e "${RED}Ongeldige keuze.${NC}"; sleep 1 ;;
    esac
done