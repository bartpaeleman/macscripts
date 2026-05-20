#!/bin/bash

# ============================================================
# DATABASE MASTER TOOL
# Menu for Database Management & Analysis
# ============================================================

set -e

# Zorg dat autocomplete het scherm niet overvol maakt door het te wissen bij tab
set -o emacs
bind '"\t": "\C-l\e\e"' 2>/dev/null || true

# Colors
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Globals for connection
DB_USER=""
DB_PASS=""
DB_HOST=""
DB_NAME=""
CONNECTED=0
TMP_CNF=""

cleanup() {
    if [ -n "$TMP_CNF" ] && [ -f "$TMP_CNF" ]; then
        rm -f "$TMP_CNF"
    fi
}
trap cleanup EXIT

pause() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Ensure mysql client is installed
if ! command -v mysql &> /dev/null; then
    echo -e "${RED}Error: 'mysql' client is not installed. Gelieve deze te installeren (bv. via Homebrew of apt-get).${NC}"
    exit 1
fi

connect_db() {
    clear
    echo -e "${CYAN}=== Database Connectie ===${NC}"

    # QNAP fix / remote connection: default to 127.0.0.1 or NAS IP
    read -e -p "Host (IP of DNS) [127.0.0.1]: " input_host
    DB_HOST=${input_host:-127.0.0.1}

    read -e -p "Database User [root]: " input_user
    DB_USER=${input_user:-root}

    read -rsp "Database Password: " DB_PASS
    echo ""

    read -e -p "Database Name (Optioneel, laat leeg voor globale connectie): " input_db
    DB_NAME=${input_db:-}

    echo -e "\n${YELLOW}Verbinden met ${DB_HOST}...${NC}"

    TMP_CNF=$(mktemp)
    chmod 600 "$TMP_CNF"
    echo "[client]" > "$TMP_CNF"
    echo "user=$DB_USER" >> "$TMP_CNF"
    echo "password=$DB_PASS" >> "$TMP_CNF"
    echo "host=$DB_HOST" >> "$TMP_CNF"

    set +e
    if [ -n "$DB_NAME" ]; then
        mysql --defaults-extra-file="$TMP_CNF" "$DB_NAME" -e "SELECT 1;" > /dev/null 2>&1
    else
        mysql --defaults-extra-file="$TMP_CNF" -e "SELECT 1;" > /dev/null 2>&1
    fi
    STATUS=$?
    set -e

    if [ $STATUS -eq 0 ]; then
        echo -e "${GREEN}✓ Connectie succesvol!${NC}"
        CONNECTED=1
        pause
    else
        echo -e "${RED}✗ Connectie mislukt. Controleer je gegevens en netwerk.${NC}"
        CONNECTED=0
        rm -f "$TMP_CNF"
        TMP_CNF=""
        pause
    fi
}

require_db() {
    if [ -z "$DB_NAME" ]; then
        echo -e "\n${YELLOW}Selecteer een database (huidige is leeg):${NC}"
        list_databases
        read -e -p "Database Name: " DB_NAME
        if [ -z "$DB_NAME" ]; then
            echo -e "${RED}Geen database geselecteerd.${NC}"
            return 1
        fi
    fi
    return 0
}

backup_db() {
    echo -e "\n${CYAN}=== Database Backup ===${NC}"
    require_db || return

    read -e -p "Backup map [Huidige map]: " out_dir
    out_dir=${out_dir:-.}

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    FILENAME="$out_dir/${DB_NAME}_${TIMESTAMP}.sql.gz"

    echo -e "\nBacking up '$DB_NAME' naar $FILENAME..."

    set +e
    set -o pipefail
    mysqldump --defaults-extra-file="$TMP_CNF" "$DB_NAME" | gzip > "$FILENAME"
    STATUS=$?
    set +o pipefail
    set -e

    if [ $STATUS -eq 0 ]; then
        echo -e "${GREEN}✓ Backup successful!${NC}"
        echo -e "  Size: $(du -h "$FILENAME" | cut -f1)"
    else
        echo -e "${RED}✗ Backup failed.${NC}"
        rm -f "$FILENAME"
    fi
    pause
}

restore_db() {
    echo -e "\n${CYAN}=== Database Restore ===${NC}"
    require_db || return

    read -e -p "Geef het pad naar het SQL bestand (of .sql.gz): " sql_file
    sql_file="${sql_file//\\ / }"

    if [ ! -f "$sql_file" ]; then
        echo -e "${RED}Bestand niet gevonden.${NC}"
        pause
        return
    fi

    echo -e "${RED}WAARSCHUWING: Dit zal data overschrijven in database '$DB_NAME'.${NC}"
    read -p "Zeker weten? (j/n): " confirm
    if [[ "$confirm" != "j" && "$confirm" != "J" ]]; then
        return
    fi

    echo -e "${YELLOW}Bezig met herstellen...${NC}"

    set +e
    if [[ "$sql_file" == *.gz ]]; then
        gunzip -c "$sql_file" | mysql --defaults-extra-file="$TMP_CNF" "$DB_NAME"
    else
        mysql --defaults-extra-file="$TMP_CNF" "$DB_NAME" < "$sql_file"
    fi
    STATUS=$?
    set -e

    if [ $STATUS -eq 0 ]; then
        echo -e "${GREEN}✓ Restore succesvol!${NC}"
    else
        echo -e "${RED}✗ Restore mislukt.${NC}"
    fi
    pause
}

analyze_db() {
    echo -e "\n${CYAN}=== Database Analysis ===${NC}"
    require_db || return

    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}Python3 is required for analysis.${NC}"
        pause
        return
    fi

    echo -e "\nFetching statistics..."
    export DB_PASS
    python3 "$SCRIPT_DIR/db_stats.py" "$DB_HOST" "$DB_USER" "$DB_NAME"
    unset DB_PASS
    pause
}

list_databases() {
    echo -e "\n${CYAN}--- Beschikbare Databases ---${NC}"
    mysql --defaults-extra-file="$TMP_CNF" -e "SHOW DATABASES;"
}

list_tables() {
    require_db || return
    echo -e "\n${CYAN}--- Tabellen in $DB_NAME ---${NC}"
    mysql --defaults-extra-file="$TMP_CNF" "$DB_NAME" -e "SHOW TABLES;"
    pause
}

optimize_db() {
    require_db || return
    echo -e "\n${CYAN}=== Optimize Database ===${NC}"
    echo "Dit kan even duren afhankelijk van de grootte..."

    set +e
    mysqlcheck --defaults-extra-file="$TMP_CNF" -o "$DB_NAME"
    STATUS=$?
    set -e

    if [ $STATUS -eq 0 ]; then
        echo -e "${GREEN}✓ Optimalisatie succesvol!${NC}"
    else
        echo -e "${RED}✗ Optimalisatie afgerond met fouten.${NC}"
    fi
    pause
}

custom_query() {
    require_db || return
    echo -e "\n${CYAN}=== Custom SQL Query ===${NC}"
    read -e -p "SQL Query: " query
    if [ -n "$query" ]; then
        mysql --defaults-extra-file="$TMP_CNF" "$DB_NAME" -e "$query"
    fi
    pause
}

# Start connection phase
while [ $CONNECTED -eq 0 ]; do
    connect_db
    if [ $CONNECTED -eq 0 ]; then
        read -p "Opnieuw proberen? (j/n): " retry
        if [[ "$retry" != "j" && "$retry" != "J" ]]; then
            exit 1
        fi
    fi
done

# MAIN MENU
while true; do
    clear
    echo -e "${CYAN}===================================${NC}"
    echo -e "      ${CYAN}DATABASE MASTER TOOL${NC}"
    echo -e "${CYAN}===================================${NC}"
    echo -e "  Host: ${GREEN}$DB_HOST${NC}"
    echo -e "  User: ${GREEN}$DB_USER${NC}"
    echo -e "  DB  : ${GREEN}${DB_NAME:-[Geen geselecteerd]}${NC}"
    echo -e "${CYAN}===================================${NC}"
    echo "1) Backup Database"
    echo "2) Restore Database"
    echo "3) Analyze Database (Table Stats)"
    echo "4) Toon Alle Databases"
    echo "5) Toon Tabellen in DB"
    echo "6) Optimize Database (mysqlcheck)"
    echo "7) Voer Custom SQL Query Uit"
    echo "C) Verander Connectie"
    echo "X) Exit"

    read -p "Select: " choice
    case $choice in
        1) backup_db ;;
        2) restore_db ;;
        3) analyze_db ;;
        4) list_databases; pause ;;
        5) list_tables ;;
        6) optimize_db ;;
        7) custom_query ;;
        [cC]) connect_db ;;
        [xX]) clear; exit 0 ;;
    esac
done
