#!/bin/bash

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
        echo -e "${YELLOW}id3v2 not found. Try installing with Homebrew...${NC}"
        if command -v brew &> /dev/null; then
            brew install id3v2
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y id3v2
        else
            echo -e "${RED}Can't install id3v2 automatically. Try manual installation.${NC}"
            pause
            exit 1
        fi

        if ! command -v id3v2 &> /dev/null; then
             echo -e "${RED}Installation failed. Make sure id3v2 is installed.${NC}"
             pause
             exit 1
        fi
    fi
}

tag_from_filename() {
    read -e -p "Enter path to folder with MP3 files: " target_dir
    target_dir="${target_dir:-.}"

    if [ ! -d "$target_dir" ]; then
        echo -e "${RED}Folder not existing!${NC}"
        pause
        return
    fi

    echo -e "${CYAN}Scanning files and applying tags...${NC}"

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
            echo -e "${RED}Skipping: '$filename' doesn't fit '<artiest> - <song>' pattern.${NC}"
        fi
    done
    echo -e "${GREEN}Tagging completed!${NC}"
    pause
}

rename_from_tags() {
    read -e -p "Enter path to folder with MP3 files: " target_dir
    target_dir="${target_dir:-.}"

    if [ ! -d "$target_dir" ]; then
        echo -e "${RED}Folder not existing!${NC}"
        pause
        return
    fi

    echo -e "${CYAN}Scanning and renaming files based on tags...${NC}"

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
                    echo -e "Renamed: ${GREEN}$(basename "$file")${NC} -> ${YELLOW}$new_name${NC}"
                else
                    echo -e "${RED}Skipped: '$new_name' already existing.${NC}"
                fi
            else
                echo -e "Skipping: ${GREEN}$(basename "$file")${NC} already named correctly."
            fi
        else
            echo -e "${RED}Skipping: '$(basename "$file")' missing id3v2 artist or title tag.${NC}"
        fi
    done
    echo -e "${GREEN}Renaming completed!${NC}"
    pause
}

check_dependencies

while true; do
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "         ${CYAN}MP3 TAG MANAGER (id3v2)${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo "1) Tag folder recursive based on pattern (<artist> - <song>)"
    echo "2) Rename MP3's recursively based on ID3 tags (<artist> - <song>.mp3)"
    echo "0) Return"
    echo -e "${CYAN}================================================${NC}"

    read -p "Kies een optie: " choice
    case $choice in
        1) tag_from_filename ;;
        2) rename_from_tags ;;
        0) break ;;
        *) echo -e "${RED}Invalid choice.${NC}"; sleep 1 ;;
    esac
done
