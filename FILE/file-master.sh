#!/bin/bash

# ============================================================
# FILE MASTER TOOL
# Bulk Rename, Archive, Cleanup
# ============================================================

# set -e disabled for interactive menu

# Colors
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pause() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

get_path_input() {
    local prompt_msg="${1:-Target Directory}"
    local default_path="$PWD"

    echo -e "${CYAN}${prompt_msg}${NC} (Press Enter for Current Directory: ${YELLOW}${default_path}${NC})" >&2
    read -p "> " input_path

    if [[ -z "$input_path" || "$input_path" == "." ]]; then
        echo "$default_path"
    else
        echo "$input_path"
    fi
}

bulk_rename() {
    echo -e "\n${CYAN}=== Bulk Rename ===${NC}"
    DIR=$(get_path_input)
    if [[ ! -d "$DIR" ]]; then
        echo "Directory not found: $DIR"
        pause
        return
    fi

    echo "Regex Support (Python re)"
    echo "Example: 'image_(\d+)' -> 'img_\1'"
    read -r -p "Pattern (Regex): " PATTERN
    read -p "Replacement: " REPLACE

    echo -e "\n${YELLOW}Previewing changes...${NC}"
    python3 "$SCRIPT_DIR/file_manager.py" rename "$DIR" "$PATTERN" "$REPLACE"

    echo ""
    read -p "Apply changes? (y/n): " CONFIRM
    if [[ "$CONFIRM" == "y" ]]; then
        python3 "$SCRIPT_DIR/file_manager.py" rename "$DIR" "$PATTERN" "$REPLACE" --run
    fi
    pause
}

create_struct() {
    echo -e "\n${CYAN}=== Create Structure ===${NC}"
    echo "Provide a text file where each line is a directory path to create."
    read -p "Template File Path: " TMPL

    if [[ ! -f "$TMPL" ]]; then
        echo "File not found."
        pause
        return
    fi

    python3 "$SCRIPT_DIR/file_manager.py" structure "$TMPL"
    pause
}

archive_dir() {
    echo -e "\n${CYAN}=== Archive Directory ===${NC}"
    DIR=$(get_path_input "Directory to Archive")

    if [[ ! -d "$DIR" ]]; then
        echo "Directory not found: $DIR"
        pause
        return
    fi

    echo "1) Zip"
    echo "2) Tar.gz"
    read -p "Select Format: " FMT_CHOICE

    TYPE="zip"
    if [[ "$FMT_CHOICE" == "2" ]]; then
        TYPE="tar"
    fi

    python3 "$SCRIPT_DIR/file_manager.py" archive "$DIR" --type "$TYPE"
    pause
}

cleanup_dir() {
    echo -e "\n${CYAN}=== Cleanup Directory ===${NC}"
    DIR=$(get_path_input)

    if [[ ! -d "$DIR" ]]; then
        echo "Directory not found: $DIR"
        pause
        return
    fi

    while true; do
        echo -e "\n${CYAN}Cleanup Options:${NC}"
        echo "1) Remove Junk (.DS_Store, Thumbs.db, ._*)"
        echo "2) Remove Empty Directories"
        echo "3) Remove Duplicates (MD5)"
        echo "4) Custom (Select combination)"
        echo "5) All of the above"
        echo "X) Cancel"

        read -p "Select Action: " clean_choice

        ARGS=""
        case $clean_choice in
            1) ARGS="--junk" ;;
            2) ARGS="--empty" ;;
            3) ARGS="--dupes" ;;
            4)
                read -p "Delete Junk Files? (y/n): " c_junk
                read -p "Delete Empty Directories? (y/n): " c_empty
                read -p "Delete Duplicates? (y/n): " c_dupes
                [[ "$c_junk" == "y" ]] && ARGS="$ARGS --junk"
                [[ "$c_empty" == "y" ]] && ARGS="$ARGS --empty"
                [[ "$c_dupes" == "y" ]] && ARGS="$ARGS --dupes"
                ;;
            5) ARGS="--junk --empty --dupes" ;;
            [Xx]) return ;;
            *) echo "Invalid option"; continue ;;
        esac

        if [[ -z "$ARGS" ]]; then
            echo "No options selected."
            continue
        fi

        echo -e "\n${YELLOW}Previewing Cleanup...${NC}"
        # Only preview first (no --run)
        # However, the python script does NOT have a dedicated "dry-run" flag, it just defaults to dry-run if --run is missing.
        # Wait, checking file_manager.py...
        # Yes: dry_run=not args.run.
        # So invoking WITHOUT --run is a dry run.

        python3 "$SCRIPT_DIR/file_manager.py" cleanup "$DIR" $ARGS

        read -p "Execute cleanup? (y/n): " CONFIRM
        if [[ "$CONFIRM" == "y" ]]; then
            python3 "$SCRIPT_DIR/file_manager.py" cleanup "$DIR" $ARGS --run
            echo "${GREEN}Cleanup complete.${NC}"
        fi

        # Break loop after action or return to menu? Usually return to main menu is better.
        break
    done
    pause
}

compare_files() {
    echo -e "\n${CYAN}=== Compare Files ===${NC}"
    read -p "File 1: " F1
    read -p "File 2: " F2

    if [[ ! -f "$F1" ]] || [[ ! -f "$F2" ]]; then
        echo "One or both files not found."
        pause
        return
    fi

    python3 "$SCRIPT_DIR/file_manager.py" compare "$F1" "$F2"
    pause
}

# MAIN MENU
while true; do
    clear
    echo -e "${CYAN}===================================${NC}"
    echo -e "      ${CYAN}FILE MASTER TOOL${NC}"
    echo -e "${CYAN}===================================${NC}"
    echo "1) Bulk Rename (Regex)"
    echo "2) Create Directory Structure (from template)"
    echo "3) Archive Directory (Zip/Tar)"
    echo "4) Cleanup (Duplicates/Empty Dirs)"
    echo "5) Compare Files"
    echo "X) Exit"

    read -p "Select: " choice
    case $choice in
        1) bulk_rename ;;
        2) create_struct ;;
        3) archive_dir ;;
        4) cleanup_dir ;;
        5) compare_files ;;
        [Xx]) exit 0 ;;
    esac
done
