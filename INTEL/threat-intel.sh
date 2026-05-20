#!/usr/bin/env bash
# threat-intel.sh
# Aggregates Threat Intelligence from various sources, parses them,
# and generates a matching report via an embedded Python analyzer.

set -euo pipefail

# Define paths
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="$SCRIPT_DIR/config.json"
SRC_DIR="$SCRIPT_DIR/src"
ASSETS_DIR="$SCRIPT_DIR/assets"
ANALYZER_SCRIPT="$SRC_DIR/analyzer.py"
CSS_FILE="$ASSETS_DIR/style.css"

# Temporary directory for raw downloads
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Get output dir from config
PUBLIC_DIR=$(python3 -c "
import json, sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        data = json.load(f)
        out = data.get('parameters', {}).get('output_dir', 'public')
        print(out)
except:
    print('public')
")

# If it's relative, anchor it to SCRIPT_DIR
if [[ "$PUBLIC_DIR" != /* ]]; then
    PUBLIC_DIR="$SCRIPT_DIR/$PUBLIC_DIR"
fi

# Ensure public directory exists
mkdir -p "$PUBLIC_DIR"

# Ensure secure permissions on config if it exists
if [ -f "$CONFIG_FILE" ]; then
    chmod 600 "$CONFIG_FILE"
else
    echo "Error: config.json not found in $SCRIPT_DIR" >&2
    exit 1
fi

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

pause() {
    read -p "Press Enter to continue..."
}

run_aggregator() {
    echo "[*] Threat Intel Aggregator Started: $(date)"

    # Fetch data
    echo "[*] Fetching threat intelligence sources..."
    while IFS='|' read -r index url; do
        if [ -z "$url" ]; then
            continue
        fi

        echo "    -> Downloading from: $url"

        # Secure download with curl
        # -s: silent
        # -L: follow redirects
        # -A: set realistic User-Agent to prevent 403 blocks
        # -m: max time 30s
        raw_file="$TMP_DIR/source_${index}.raw"
        if ! curl -s -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36" \
             -m 30 "$url" -o "$raw_file"; then
            echo "    [!] Warning: Failed to download $url" >&2
            echo "        -> Deactivating feed in config.json due to failure."

            FAILED_URL="$url" python3 -c "
import json, sys, os
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)

    url_to_disable = os.environ.get('FAILED_URL')
    changed = False
    for src in config.get('sources', []):
        if src.get('url') == url_to_disable:
            src['active'] = False
            changed = True
            break

    if changed:
        with open('$CONFIG_FILE', 'w') as f:
            json.dump(config, f, indent=2)
except Exception as e:
    print(f'Error auto-deactivating config: {e}', file=sys.stderr)
"
        fi
    done < <(get_sources)

    # Run Python Analyzer
    echo "[*] Analyzing data and generating report..."
    if [ -f "$ANALYZER_SCRIPT" ]; then
        REPORT_PATH=$(python3 "$ANALYZER_SCRIPT" "$CONFIG_FILE" "$TMP_DIR" "$PUBLIC_DIR" "$CSS_FILE")

        if [ -n "$REPORT_PATH" ] && [ -f "$REPORT_PATH" ]; then
            echo "[+] Report successfully generated: $REPORT_PATH"
            # Set proper permissions for the output directory/files
            chmod 755 "$PUBLIC_DIR"
            chmod 644 "$REPORT_PATH"
        else
            echo "[-] Failed to generate report." >&2
            exit 1
        fi
    else
        echo "[-] Error: Analyzer script not found at $ANALYZER_SCRIPT" >&2
        exit 1
    fi

    echo "[*] Done."
    pause
}

edit_intel_config() {
    if [ -f "$CONFIG_FILE" ]; then
        ${EDITOR:-vi} "$CONFIG_FILE"
    else
        echo -e "${RED}Error: $CONFIG_FILE not found.${NC}"
        pause
    fi
}

add_intel_source() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: $CONFIG_FILE not found.${NC}"
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
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)

    new_src = {
        'name': os.environ['SRC_NAME'],
        'url': os.environ['SRC_URL'],
        'type': os.environ['SRC_TYPE'],
        'active': True
    }

    if 'sources' not in config:
        config['sources'] = []

    config['sources'].append(new_src)

    with open('$CONFIG_FILE', 'w') as f:
        json.dump(config, f, indent=2)
    print('\nSuccessfully added source to config.json')
except Exception as e:
    print(f'Error updating config: {e}')
    sys.exit(1)
"
    pause
}

interactive_toggle() {
    python3 "$SCRIPT_DIR/interactive_toggle.py" "$CONFIG_FILE"
    pause
}

manage_list_option() {
    local list_key="$1"
    python3 "$SCRIPT_DIR/manage_lists.py" "$CONFIG_FILE" "$list_key"
    pause
}

manage_parameters() {
    python3 "$SCRIPT_DIR/manage_params.py" "$CONFIG_FILE"
    pause
}

install_intel_deps() {
    echo -e "\n${CYAN}Installing Intel Master Dependencies...${NC}"
    echo "This will create a local virtual environment and install missing Python packages like 'python-dateutil'."

    if command -v python3 &> /dev/null; then
        echo "Attempting installation in virtual environment..."
        python3 -m venv "$SCRIPT_DIR/.venv"
        source "$SCRIPT_DIR/.venv/bin/activate"
        if python3 -m pip install python-dateutil; then
            echo -e "${GREEN}Dependencies installed successfully.${NC}"
        else
            echo -e "${RED}Error: Failed to install pip or dependencies in virtual environment.${NC}"
        fi
    else
        echo -e "${RED}Error: python3 is not available in your PATH.${NC}"
    fi
    pause
}

# Always ensure we use venv if it exists
if [ -d "$SCRIPT_DIR/.venv" ]; then
    source "$SCRIPT_DIR/.venv/bin/activate"
fi

intelmaster_menu() {
    while true; do
        clear
        echo -e "${CYAN}===================================${NC}"
        echo -e "          ${CYAN}INTEL MASTER${NC}"
        echo -e "${CYAN}===================================${NC}"
        echo -e "${GREEN}--- RUN OPTIONS ---${NC}"
        echo -e "${GREEN} 1) Run Threat Intel Aggregator (All/Default)${NC}"
        echo -e "${GREEN} 2) Run Threat Intel Aggregator (General Security Info)${NC}"
        echo -e "${GREEN} 3) Run Threat Intel Aggregator (Patches & Vulnerabilities)${NC}"
        echo -e "${GREEN} 4) Run Threat Intel Aggregator (Other Cyber Sec Topics)${NC}"
        echo -e "${CYAN}--- CONFIGURATION ---${NC}"
        echo -e "${CYAN} 5) Edit Raw Config (config.json)${NC}"
        echo -e "${CYAN} 6) Add New Source to Config${NC}"
        echo -e "${CYAN} 7) Manage Active Feeds (Interactive Toggle)${NC}"
        echo -e "${CYAN} 8) Manage Technologies${NC}"
        echo -e "${CYAN} 9) Manage Inclusions${NC}"
        echo -e "${CYAN}10) Manage Exclusions${NC}"
        echo -e "${CYAN}11) Manage Settings (Output Dir, Severity, Lookback)${NC}"
        echo -e "${CYAN}--- SYSTEM ---${NC}"
        echo -e "${CYAN} D) Install Dependencies (Python)${NC}"
        echo -e "-----------------------------------"
        echo " X) Exit"

        read -p "Select Option: " choice
        case $choice in
            1) export INTEL_FILTER="default"; run_aggregator ;;
            2) export INTEL_FILTER="general"; run_aggregator ;;
            3) export INTEL_FILTER="patches"; run_aggregator ;;
            4) export INTEL_FILTER="other"; run_aggregator ;;
            5) edit_intel_config ;;
            6) add_intel_source ;;
            7) interactive_toggle ;;
            8) manage_list_option "technologies" ;;
            9) manage_list_option "inclusions" ;;
            10) manage_list_option "exclusions" ;;
            11) manage_parameters ;;
            [dD]) install_intel_deps ;;
            [xX]) clear; break ;;
            *) echo "Invalid option." ; pause ;;
        esac
    done
}

# Function to extract JSON array elements using Python (avoids missing jq dependency)
get_sources() {
    python3 -c "
import json, sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        data = json.load(f)
        for i, src in enumerate(data.get('sources', [])):
            if src.get('active', True):
                print(f\"{i}|{src.get('url', '')}\")
except Exception as e:
    sys.exit(1)
"
}

# Start the menu
intelmaster_menu
