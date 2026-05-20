#!/bin/bash

# ============================================================
# DATA MASTER TOOL
# Data Conversion, Viewing & Normalization
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

check_deps() {
    python3 "$SCRIPT_DIR/data_utils.py" check
    RET=$?

    if [[ $RET -ne 0 ]]; then
        echo ""
        read -p "Install missing dependencies using a local virtual environment? (y/n): " INSTALL
        if [[ "$INSTALL" == "y" ]]; then
            echo -e "${CYAN}Setting up virtual environment and installing pandas pyyaml...${NC}"
            python3 -m venv "$SCRIPT_DIR/.venv"
            source "$SCRIPT_DIR/.venv/bin/activate"
            python3 -m pip install pandas pyyaml
            echo -e "${GREEN}Done. Re-checking...${NC}"
            python3 "$SCRIPT_DIR/data_utils.py" check
        else
            echo -e "${RED}Please install pandas and pyyaml manually.${NC}"
        fi
    else
        # Ensure we use venv if it exists even if check passed previously
        if [ -d "$SCRIPT_DIR/.venv" ]; then
            source "$SCRIPT_DIR/.venv/bin/activate"
        fi
    fi
    pause
}

view_csv() {
    echo -e "\n${CYAN}=== View CSV ===${NC}"
    read -p "CSV File Path: " FILE
    if [[ ! -f "$FILE" ]]; then
        echo "File not found."
        pause
        return
    fi
    python3 "$SCRIPT_DIR/data_utils.py" view "$FILE" | less -S
}

convert_delim() {
    echo -e "\n${CYAN}=== Convert Delimiter ===${NC}"
    read -p "Input CSV Path: " IN_FILE
    if [[ ! -f "$IN_FILE" ]]; then
        echo "File not found."
        pause
        return
    fi
    read -p "Output CSV Path: " OUT_FILE
    read -p "New Delimiter (e.g. , ;): " NEW_DELIM

    if [[ -z "$NEW_DELIM" ]]; then
        echo "Delimiter required."
        pause
        return
    fi

    python3 "$SCRIPT_DIR/data_utils.py" delim "$IN_FILE" "$OUT_FILE" --new "$NEW_DELIM"
    pause
}

convert_format() {
    echo -e "\n${CYAN}=== Convert Format ===${NC}"
    echo "Supports: CSV <-> JSON, XML -> JSON, YAML -> JSON/CSV"
    read -p "Input File Path: " IN_FILE
    if [[ ! -f "$IN_FILE" ]]; then
        echo "File not found."
        pause
        return
    fi

    read -p "Output File Path: " OUT_FILE

    python3 "$SCRIPT_DIR/data_utils.py" convert "$IN_FILE" "$OUT_FILE"
    pause
}

normalize_dataset() {
    echo -e "\n${CYAN}=== Normalize Dataset ===${NC}"
    read -p "Input CSV Path: " IN_FILE
    if [[ ! -f "$IN_FILE" ]]; then
        echo "File not found."
        pause
        return
    fi

    read -p "Output CSV Path: " OUT_FILE

    python3 "$SCRIPT_DIR/data_utils.py" normalize "$IN_FILE" "$OUT_FILE"
    pause
}

# MAIN MENU
while true; do
    clear
    echo -e "${CYAN}===================================${NC}"
    echo -e "      ${CYAN}DATA MASTER TOOL${NC}"
    echo -e "${CYAN}===================================${NC}"
    echo "1) View CSV as Table"
    echo "2) Convert CSV Delimiter"
    echo "3) Convert File Format (CSV, JSON, XML, YAML)"
    echo "4) Normalize CSV (Clean empty rows/spaces)"
    echo "5) Check Dependencies"
    echo "X) Exit"

    read -p "Select: " choice
    case $choice in
        1) view_csv ;;
        2) convert_delim ;;
        3) convert_format ;;
        4) normalize_dataset ;;
        5) check_deps ;;
        [Xx]) clear; exit 0 ;;
    esac
done
