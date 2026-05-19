#!/bin/bash

# ============================================================
# DATABASE MASTER TOOL
# Menu for Backup and Analysis
# ============================================================

set -e

# Colors
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to get credentials
get_creds() {
    read -p "Database Name: " DB_NAME
    read -p "Database User [root]: " DB_USER
    DB_USER=${DB_USER:-root}
    read -rsp "Database Password: " DB_PASS
    echo ""
    # QNAP fix: default to 127.0.0.1 to force TCP (skips socket issues)
    read -p "Host [127.0.0.1]: " DB_HOST
    DB_HOST=${DB_HOST:-127.0.0.1}
}

pause() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

backup_db() {
    echo -e "\n${CYAN}=== Database Backup ===${NC}"
    get_creds

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    FILENAME="${DB_NAME}_${TIMESTAMP}.sql.gz"

    echo -e "\nBacking up '$DB_NAME'..."

    # Use existing backup script logic but inline here for simpler menu or call it?
    # Calling the existing logic inline is safer to keep it contained.

    TMP_CNF=$(mktemp)
    chmod 600 "$TMP_CNF"
    echo "[client]" > "$TMP_CNF"
    echo "user=$DB_USER" >> "$TMP_CNF"
    echo "password=$DB_PASS" >> "$TMP_CNF"
    echo "host=$DB_HOST" >> "$TMP_CNF"

    # Use set +e locally to catch error without exiting script
    set +e
    set -o pipefail
    mysqldump --defaults-extra-file="$TMP_CNF" "$DB_NAME" | gzip > "$FILENAME"
    STATUS=$?
    set +o pipefail
    set -e

    if [ $STATUS -eq 0 ]; then
        echo -e "${GREEN}✓ Backup successful!${NC}"
        echo -e "  File: $(pwd)/$FILENAME"
        echo -e "  Size: $(du -h "$FILENAME" | cut -f1)"
    else
        echo -e "${RED}✗ Backup failed.${NC}"
        rm -f "$FILENAME"
    fi
    rm -f "$TMP_CNF"
    pause
}

analyze_db() {
    echo -e "\n${CYAN}=== Database Analysis ===${NC}"
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}Python3 is required for analysis.${NC}"
        pause
        return
    fi

    get_creds

    echo -e "\nFetching statistics..."
    export DB_PASS
    python3 "$SCRIPT_DIR/db_stats.py" "$DB_HOST" "$DB_USER" "$DB_NAME"
    unset DB_PASS
    pause
}

# MAIN MENU
while true; do
    clear
    echo -e "${CYAN}===================================${NC}"
    echo -e "      ${CYAN}DATABASE MASTER TOOL${NC}"
    echo -e "${CYAN}===================================${NC}"
    echo "1) Backup Database"
    echo "2) Analyze Database (Table Stats)"
    echo "X) Exit"

    read -p "Select: " choice
    case $choice in
        1) backup_db ;;
        2) analyze_db ;;
        [Xx]) exit 0 ;;
    esac
done
