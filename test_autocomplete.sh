#!/bin/bash
set -o emacs
bind '"\t": "\C-l\e\e"' 2>/dev/null || true

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
get_path_input "Geef map op:"
