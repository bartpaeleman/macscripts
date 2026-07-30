#!/bin/bash

# Colors
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

# Defaults
INPUT_PATH=""
TARGET_FORMAT="mp3"
SOURCE_FILTER="*"

# Dependency check
if ! command -v ffmpeg &> /dev/null; then
    echo -e "${YELLOW}ffmpeg not found. Attempting to install...${NC}"
    if command -v brew &> /dev/null; then
        brew install ffmpeg
    elif command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y ffmpeg
    else
        echo -e "${RED}Could not install ffmpeg automatically. Please install it manually.${NC}"
        exit 1
    fi
fi

clean_path() {
    local p="$1"
    p=$(echo "$p" | sed -e 's/[[:space:]]*$//')
    if [[ "$p" =~ ^\'.*\'$ || "$p" =~ ^\".*\"$ ]]; then
        p="${p:1:-1}"
    else
        p="${p//\\ / }"
    fi
    echo "$p"
}

convert_file() {
    local file="$1"
    local target_ext="$2"
    local dir
    local filename
    local base

    dir=$(dirname "$file")
    filename=$(basename "$file")
    base="${filename%.*}"

    local out_file="$dir/$base.$target_ext"

    # Avoid overwriting or converting to same name if extension matches
    if [[ "$file" == "$out_file" ]]; then
        echo -e "${YELLOW}Skipping $file (already $target_ext)...${NC}"
        return
    fi

    echo -e "${CYAN}Converting: $filename -> $base.$target_ext${NC}"
    ffmpeg -v error -y -i "$file" "$out_file" < /dev/null
}

while true; do
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "         ${CYAN}AUDIO CONVERTER CONFIGURATION${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo -e "1) Input Path     : ${YELLOW}${INPUT_PATH:-Not set}${NC}"
    echo -e "2) Target Format  : ${YELLOW}${TARGET_FORMAT}${NC}"
    echo -e "3) Source Filter  : ${YELLOW}${SOURCE_FILTER}${NC}"
    echo -e ""
    echo -e "4) Run Conversion"
    echo -e "0) Back"
    echo -e "${YELLOW}X) Exit${NC}"
    echo -e "${CYAN}================================================${NC}"

    read -e -p "Select option: " opt

    case "$opt" in
        1)
            read -e -p "Enter Input Path (file or directory, drag & drop supported): " raw_path
            INPUT_PATH=$(clean_path "$raw_path")
            ;;
        2)
            read -e -p "Enter Target Format (e.g., mp3, wav, flac): " tfmt
            if [[ -n "$tfmt" ]]; then
                TARGET_FORMAT="$tfmt"
            fi
            ;;
        3)
            read -e -p "Enter Source Filter (e.g., wav, m4a, or * for all): " sfilter
            if [[ -n "$sfilter" ]]; then
                SOURCE_FILTER="$sfilter"
            fi
            ;;
        4)
            if [[ -z "$INPUT_PATH" ]]; then
                echo -e "${RED}Error: Input path is not set.${NC}"
                sleep 2
                continue
            fi

            if [[ ! -e "$INPUT_PATH" ]]; then
                echo -e "${RED}Error: Path does not exist: $INPUT_PATH${NC}"
                sleep 2
                continue
            fi

            if [[ -d "$INPUT_PATH" ]]; then
                echo -e "${GREEN}Processing directory: $INPUT_PATH${NC}"

                if [[ "$SOURCE_FILTER" == "*" || -z "$SOURCE_FILTER" ]]; then
                    find "$INPUT_PATH" -type f | while IFS= read -r file; do
                        if [[ -f "$file" ]]; then
                            convert_file "$file" "$TARGET_FORMAT"
                        fi
                    done
                else
                    find "$INPUT_PATH" -type f -name "*.$SOURCE_FILTER" | while IFS= read -r file; do
                        if [[ -f "$file" ]]; then
                            convert_file "$file" "$TARGET_FORMAT"
                        fi
                    done
                fi
            else
                echo -e "${GREEN}Processing single file: $INPUT_PATH${NC}"
                convert_file "$INPUT_PATH" "$TARGET_FORMAT"
            fi

            echo -e "\n${GREEN}Conversion complete!${NC}"
            echo -e "${YELLOW}Press Enter to return to menu...${NC}"
            read -r
            ;;
        0)
            break
            ;;
        [xX])
            echo -e "${GREEN}Exiting...${NC}"
            clear
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            sleep 1
            ;;
    esac
done
