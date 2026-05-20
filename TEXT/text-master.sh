#!/bin/bash

# ============================================================
# TEXT MASTER TOOL
# Advanced Text Manipulation & Analysis
# ============================================================

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

text_stats() {
    echo -e "\n${CYAN}=== Text Analysis ===${NC}"
    read -p "File Path: " FILE
    if [[ -f "$FILE" ]]; then
        if command -v python3 &> /dev/null; then
            python3 "$SCRIPT_DIR/text_stats.py" "$FILE"
        else
            echo "Python3 not found. Falling back to wc."
            wc "$FILE"
        fi
    else
        echo "File not found."
    fi
    pause
}

text_search() {
    echo -e "\n${CYAN}=== Search & Replace (sed) ===${NC}"
    read -p "File Path: " FILE
    [[ ! -f "$FILE" ]] && echo "File not found" && pause && return

    echo "1) Search (grep)"
    echo "2) Replace (sed - create backup)"
    read -p "Action: " act

    if [[ "$act" == "1" ]]; then
        read -p "Search Term: " term
        grep -n --color=always "$term" "$FILE" | less
    elif [[ "$act" == "2" ]]; then
        read -p "Find: " find_str
        read -p "Replace with: " rep_str

        sed -i.bak "s/$find_str/$rep_str/g" "$FILE"
        echo -e "${GREEN}Replaced. Backup created at $FILE.bak${NC}"
        pause
    fi
}

text_compare() {
    echo -e "\n${CYAN}=== Compare Files ===${NC}"
    read -p "File 1: " F1
    read -p "File 2: " F2

    if [[ -f "$F1" ]] && [[ -f "$F2" ]]; then
        diff --color=always "$F1" "$F2" | less
    else
        echo "One or both files not found."
        pause
    fi
}

text_merge() {
    echo -e "\n${CYAN}=== Merge Files ===${NC}"
    read -p "File 1: " F1
    read -p "File 2: " F2
    read -p "Output File: " OUT

    if [[ -f "$F1" ]] && [[ -f "$F2" ]]; then
        cat "$F1" "$F2" > "$OUT"
        echo -e "${GREEN}Merged to $OUT${NC}"
    else
        echo "Input files not found."
    fi
    pause
}

case_convert() {
    echo -e "\n${CYAN}=== Case Conversion ===${NC}"
    read -p "File Path: " FILE
    [[ ! -f "$FILE" ]] && echo "File not found" && pause && return

    echo "1) To UPPERCASE"
    echo "2) To lowercase"
    read -p "Select: " c

    read -p "Output File: " OUT

    if [[ "$c" == "1" ]]; then
        tr '[:lower:]' '[:upper:]' < "$FILE" > "$OUT"
    elif [[ "$c" == "2" ]]; then
        tr '[:upper:]' '[:lower:]' < "$FILE" > "$OUT"
    fi
    echo -e "${GREEN}Converted to $OUT${NC}"
    pause
}

# MAIN MENU
while true; do
    clear
    echo -e "${CYAN}===================================${NC}"
    echo -e "      ${CYAN}TEXT MASTER TOOL${NC}"
    echo -e "${CYAN}===================================${NC}"
    echo "1) Text Statistics (Word freq, lines)"
    echo "2) Search & Replace (Grep/Sed)"
    echo "3) Compare Files (Diff)"
    echo "4) Merge Files"
    echo "5) Case Conversion (Upper/Lower)"
    echo "X) Exit"

    read -p "Select: " choice
    case $choice in
        1) text_stats ;;
        2) text_search ;;
        3) text_compare ;;
        4) text_merge ;;
        5) case_convert ;;
        [xX]) clear; exit 0 ;;
    esac
done
