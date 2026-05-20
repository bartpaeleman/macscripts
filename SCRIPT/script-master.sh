#!/bin/bash

# ============================================================
# SCRIPT MASTER CONTROL PANEL
# Central Hub for All Development Tools
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

# --- TOOL LAUNCHERS ---

# ROOT_DIR points to the parent directory of SCRIPT
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

launch_git() {
    bash "$ROOT_DIR/gitmaster"
}

launch_web() {
    bash "$ROOT_DIR/webmaster"
}

launch_db() {
    bash "$ROOT_DIR/dbmaster"
}

launch_container() {
    bash "$ROOT_DIR/containermaster"
}

launch_net() {
    bash "$ROOT_DIR/networkmaster"
}

launch_data() {
    bash "$ROOT_DIR/datamaster"
}

launch_file() {
    bash "$ROOT_DIR/filemaster"
}

launch_text() {
    bash "$ROOT_DIR/textmaster"
}

launch_video() {
    bash "$ROOT_DIR/videomaster"
}

launch_audio() {
    bash "$ROOT_DIR/audiomaster"
}

launch_karaoke() {
    bash "$ROOT_DIR/karaokemaster"
}

launch_folder() {
    bash "$ROOT_DIR/foldermaster"
}

launch_intel() {
    bash "$ROOT_DIR/intelmaster"
    pause
}

launch_cyber() {
    bash "$ROOT_DIR/cybermaster"
}

edit_intel_config() {
    local config_file="$ROOT_DIR/INTEL/config.json"
    if [ -f "$config_file" ]; then
        ${EDITOR:-vi} "$config_file"
    else
        echo -e "${RED}Error: $config_file not found.${NC}"
        pause
    fi
}

add_intel_source() {
    local config_file="$ROOT_DIR/INTEL/config.json"
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}Error: $config_file not found.${NC}"
        pause
        return
    fi

    echo -e "\n${CYAN}Add New Threat Intel Source${NC}"
    read -p "Name (e.g. My RSS Feed): " src_name
    read -p "URL: " src_url
    read -p "Type (e.g. rss, json, cisa_kev): " src_type

    if [[ -z "$src_name" || -z "$src_url" || -z "$src_type" ]]; then
        echo -e "${RED}All fields are required. Aborting.${NC}"
        pause
        return
    fi

    # Append to JSON using python3 to ensure syntax validity
    SRC_NAME="$src_name" SRC_URL="$src_url" SRC_TYPE="$src_type" python3 -c "
import json, sys, os
config_path = '$config_file'
try:
    with open(config_path, 'r') as f:
        data = json.load(f)

    if 'sources' not in data:
        data['sources'] = []

    data['sources'].append({
        'name': os.environ.get('SRC_NAME', ''),
        'url': os.environ.get('SRC_URL', ''),
        'type': os.environ.get('SRC_TYPE', '')
    })

    with open(config_path, 'w') as f:
        json.dump(data, f, indent=2)
    print('Successfully added source.')
except Exception as e:
    print(f'Error updating config: {e}')
    sys.exit(1)
"
    pause
}

# MAIN MENU
while true; do
    clear
    echo -e "${CYAN}===================================${NC}"
    echo -e "      ${CYAN}SCRIPT MASTER CONTROL${NC}"
    echo -e "${CYAN}===================================${NC}"
    echo "1) Git Master       (Workflow & Branching)"
    echo "2) Web Scaffold     (Project Generator)"
    echo "3) DB Master        (Database Tools)"
    echo "4) Container Master (Docker Management)"
    echo "5) Network Master   (Port Scan & Utils)"
    echo "6) Data Master      (Convert/View CSV,JSON,XML)"
    echo "7) File Master      (Rename, Archive, Cleanup)"
    echo "8) Text Master      (Stats, Diff, Merge)"
    echo "9) Video Master     (Download & Clip Videos)"
    echo "10) Intel Master    (Threat Intelligence Menu)"
    echo "11) Cyber Master    (Phishing & Recon Tools)"
    echo "12) Audio Master    (Audio Tools)"
    echo "13) Karaoke Master  (Karaoke Tools)"
    echo "14) Folder Master   (Directory Tools)"
    echo -e "-----------------------------------"
    echo "X) Exit"

    read -p "Select Tool: " choice
    case $choice in
        1) launch_git ;;
        2) launch_web ;;
        3) launch_db ;;
        4) launch_container ;;
        5) launch_net ;;
        6) launch_data ;;
        7) launch_file ;;
        8) launch_text ;;
        9) launch_video ;;
        10) launch_intel ;;
        11) launch_cyber ;;
        12) launch_audio ;;
        13) launch_karaoke ;;
        14) launch_folder ;;
        [xX]) clear; exit 0 ;;
        *) echo "Invalid option." ; pause ;;
    esac
done
