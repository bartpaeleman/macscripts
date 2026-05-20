#!/bin/bash

# Zorg dat autocomplete het scherm niet overvol maakt door het te wissen bij tab
set -o emacs
bind '"\t": "\C-l\e\e"' 2>/dev/null || true

# Colors
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
    if ! command -v id3v2 &> /dev/null; then
        echo -e "${YELLOW}id3v2 is niet geïnstalleerd. Proberen te installeren via Homebrew...${NC}"
        if command -v brew &> /dev/null; then
            brew install id3v2
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y id3v2
        else
            echo -e "${RED}Kan id3v2 niet automatisch installeren. Installeer het handmatig.${NC}"
            pause
            exit 1
        fi

        if ! command -v id3v2 &> /dev/null; then
             echo -e "${RED}Installatie mislukt. Zorg dat id3v2 is geïnstalleerd.${NC}"
             pause
             exit 1
        fi
    fi
}

tag_from_filename() {
    read -e -p "Geef directory met MP3 bestanden: " target_dir
    target_dir="${target_dir:-.}"

    if [ ! -d "$target_dir" ]; then
        echo -e "${RED}Directory bestaat niet!${NC}"
        pause
        return
    fi

    echo -e "${CYAN}Bestanden scannen en tags toepassen...${NC}"

    find "$target_dir" -type f -iname "*.mp3" | while read -r file; do
        filename=$(basename "$file" .mp3)
        # Regex to split on " - "
        if [[ "$filename" =~ ^(.*)[[:space:]]-[[:space:]](.*)$ ]]; then
            artist="${BASH_REMATCH[1]}"
            title="${BASH_REMATCH[2]}"

            # Trim whitespace
            artist=$(echo "$artist" | xargs)
            title=$(echo "$title" | xargs)

            echo -e "Tagging: ${GREEN}$filename${NC} -> Artist: ${YELLOW}$artist${NC}, Title: ${YELLOW}$title${NC}"
            id3v2 -a "$artist" -t "$title" "$file"
        else
            echo -e "${RED}Overslaan: '$filename' voldoet niet aan '<artiest> - <song>' patroon.${NC}"
        fi
    done
    echo -e "${GREEN}Klaar met taggen!${NC}"
    pause
}

rename_from_tags() {
    read -e -p "Geef directory met MP3 bestanden: " target_dir
    target_dir="${target_dir:-.}"

    if [ ! -d "$target_dir" ]; then
        echo -e "${RED}Directory bestaat niet!${NC}"
        pause
        return
    fi

    echo -e "${CYAN}Bestanden scannen en hernoemen op basis van tags...${NC}"

    find "$target_dir" -type f -iname "*.mp3" | while read -r file; do
        dir=$(dirname "$file")

        # Extract tags
        artist=$(id3v2 -l "$file" 2>/dev/null | grep '^TPE1' | sed 's/^.*: //' | xargs)
        if [[ -z "$artist" ]]; then artist=$(id3v2 -l "$file" 2>/dev/null | awk -F'Artist: ' '/Artist:/ {print $2}' | xargs); fi
        title=$(id3v2 -l "$file" 2>/dev/null | grep '^TIT2' | sed 's/^.*: //' | xargs)
        if [[ -z "$title" ]]; then title=$(id3v2 -l "$file" 2>/dev/null | awk -F'Title  : ' '/Title  :/ {print $2}' | awk -F' Artist:' '{print $1}' | xargs); fi

        # Remove extra whitespace and strange characters if needed, but basic xargs works well

        if [[ -n "$artist" && -n "$title" ]]; then
            # Clean up potential illegal characters for filenames
            safe_artist=$(echo "$artist" | tr -d '/\0')
            safe_title=$(echo "$title" | tr -d '/\0')

            new_name="$safe_artist - $safe_title.mp3"
            new_path="$dir/$new_name"

            if [[ "$file" != "$new_path" ]]; then
                if [[ ! -e "$new_path" ]]; then
                    mv "$file" "$new_path"
                    echo -e "Hernoemd: ${GREEN}$(basename "$file")${NC} -> ${YELLOW}$new_name${NC}"
                else
                    echo -e "${RED}Overslaan: '$new_name' bestaat al.${NC}"
                fi
            else
                echo -e "Overslaan: ${GREEN}$(basename "$file")${NC} heeft al de juiste naam."
            fi
        else
            echo -e "${RED}Overslaan: '$(basename "$file")' mist id3v2 artist of title tag.${NC}"
        fi
    done
    echo -e "${GREEN}Klaar met hernoemen!${NC}"
    pause
}

check_dependencies

while true; do
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "         ${CYAN}MP3 TAG MANAGER (id3v2)${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo "1) Tag folder recursive gebaseerd op patroon (<artiest> - <song>)"
    echo "2) Hernoem MP3's recursive gebaseerd op ID3 tags (<artiest> - <song>.mp3)"
    echo "0) Terug"
    echo -e "${CYAN}================================================${NC}"

    read -p "Kies een optie: " choice
    case $choice in
        1) tag_from_filename ;;
        2) rename_from_tags ;;
        0) break ;;
        *) echo -e "${RED}Ongeldige keuze.${NC}"; sleep 1 ;;
    esac
done