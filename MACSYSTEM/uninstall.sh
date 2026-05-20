#!/bin/zsh

# uninstall.sh v3.0.0
# Verwijdert een macOS-app en alle bijbehorende bestanden.
# Gebruik: ./uninstall.sh [--dry-run]

set -euo pipefail
IFS=$'\n\t'

VERSION="3.0.0"

# --------------------------------------------------
# KLEUREN
# --------------------------------------------------

RED=$'\e[31m'
GRN=$'\e[32m'
YLW=$'\e[33m'
CYN=$'\e[36m'
BLD=$'\e[1m'
RST=$'\e[0m'

# --------------------------------------------------
# OS CHECK
# --------------------------------------------------

OS_MAJOR=$(sw_vers -productVersion | cut -d '.' -f1)
if [[ "$OS_MAJOR" -lt 13 ]]; then
    echo "${YLW}WAARSCHUWING: macOS Ventura of hoger aanbevolen.${RST}"
    echo ""
fi

# --------------------------------------------------
# TELLERS & ARRAYS
# --------------------------------------------------

typeset -a DRY_RUN_MATCHES
typeset -a SYSTEM_MATCHES
typeset -a FAILED_DELETES
typeset -a STILL_FAILED_DELETES

DELETED_FILE_COUNT=0
DELETED_BYTES=0
DRY_RUN_BYTES=0
DRY_RUN=false

# --------------------------------------------------
# DRY-RUN ARGUMENT
# --------------------------------------------------

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# --------------------------------------------------
# BANNER
# --------------------------------------------------

echo ""
echo "${BLD}uninstall.sh v$VERSION${RST}"
[[ "$DRY_RUN" == true ]] && echo "${YLW}[DRY RUN – er wordt niets verwijderd]${RST}"
echo ""

# --------------------------------------------------
# HULPFUNCTIES
# --------------------------------------------------

human_size() {
    local bytes=$1
    awk -v b="$bytes" '
    BEGIN {
        kb=1024; mb=kb*1024; gb=mb*1024
        if      (b >= gb) printf "%.2f GB\n", b/gb
        else if (b >= mb) printf "%.2f MB\n", b/mb
        else if (b >= kb) printf "%.2f KB\n", b/kb
        else              printf "%d B\n",    b
    }'
}

safe_delete() {
    local target="$1"
    [[ -z "$target" ]]    && return 1
    [[ "$target" == "/" ]] && return 1
    [[ "$target" == "$HOME" ]] && return 1
    rm -rf -- "$target"
}

ask_yn() {
    # ask_yn "Vraag?" → returns 0 voor ja, 1 voor nee
    local prompt="$1"
    while true; do
        read "?${prompt} (y/n): " ANS
        case "$ANS" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *)     echo "Typ y of n." ;;
        esac
    done
}

# --------------------------------------------------
# APP-INVOER
# --------------------------------------------------

MATCH_KEY=""
APP_PATH=""

if ask_yn "Heb je de app al verwijderd?"; then

    read "?Geef de app-naam: " MATCH_KEY
    MATCH_KEY=$(basename "$MATCH_KEY" .app)

else

    echo ""
    echo "Sleep de .app hierheen en druk op Enter:"
    read -r APP_PATH_RAW

    APP_PATH="${APP_PATH_RAW}"
    APP_PATH="${APP_PATH#\"}"
    APP_PATH="${APP_PATH%\"}"
    APP_PATH="${APP_PATH//\\ / }"
    APP_PATH="$(echo "$APP_PATH" | xargs)"
    APP_PATH="${APP_PATH%/}"

    if [[ ! -d "$APP_PATH" ]]; then
        echo "${RED}FOUT: App-pad niet gevonden:${RST}"
        echo "$APP_PATH"
        exit 1
    fi

    APP_NAME=$(basename "$APP_PATH" .app)
    BUNDLE_ID=""

    if [[ -f "$APP_PATH/Contents/Info.plist" ]]; then
        BUNDLE_ID=$(
            /usr/libexec/PlistBuddy \
                -c "Print CFBundleIdentifier" \
                "$APP_PATH/Contents/Info.plist" \
                2>/dev/null || true
        )
    fi

    if [[ -n "${BUNDLE_ID:-}" ]]; then
        MATCH_KEY="$BUNDLE_ID"
        echo ""
        echo "App-naam : ${CYN}$APP_NAME${RST}"
        echo "Bundle ID: ${CYN}$BUNDLE_ID${RST}"
    else
        MATCH_KEY="$APP_NAME"
        echo ""
        echo "App-naam gebruikt: ${CYN}$APP_NAME${RST}"
    fi
fi

# --------------------------------------------------
# VALIDATIE
# --------------------------------------------------

MATCH_KEY=$(echo "$MATCH_KEY" | xargs)
APP_NAME="${APP_NAME:-$MATCH_KEY}"

if [[ -z "$MATCH_KEY" ]]; then
    echo "${RED}FOUT: Kon app-naam niet bepalen.${RST}"
    exit 1
fi

MATCH_KEY_LOWER=$(echo "$MATCH_KEY" | tr '[:upper:]' '[:lower:]')
APP_NAME_LOWER=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')

echo ""
echo "${BLD}Doelwit:${RST} $APP_NAME"
[[ "$MATCH_KEY" != "$APP_NAME" ]] && echo "${BLD}Bundle ID:${RST} $MATCH_KEY"
echo ""

# --------------------------------------------------
# APP-BUNDLE VERWIJDEREN
# --------------------------------------------------

typeset -a MATCHED_APPS

for APP_DIR in "/Applications" "$HOME/Applications"; do

    [[ -d "$APP_DIR" ]] || continue

    # Als we het exacte pad al weten, gebruik dat direct
    if [[ -n "${APP_PATH:-}" && -d "$APP_PATH" ]]; then
        [[ "${APP_PATH%/}" == "$APP_DIR"/*.app ]] && MATCHED_APPS+=("${APP_PATH%/}")
        continue
    fi

    while IFS= read -r app; do
        app_name=$(basename "$app" .app | tr '[:upper:]' '[:lower:]')
        if [[ "$app_name" == *"$APP_NAME_LOWER"* ]]; then
            MATCHED_APPS+=("$app")
        fi
    done < <(find "$APP_DIR" -maxdepth 1 -iname "*.app" 2>/dev/null)

done

# Als het pad bekend is maar nog niet in de lijst staat, voeg het toe
if [[ -n "${APP_PATH:-}" && -d "$APP_PATH" && ${#MATCHED_APPS[@]} -eq 0 ]]; then
    MATCHED_APPS+=("${APP_PATH%/}")
fi

if [[ ${#MATCHED_APPS[@]} -gt 0 ]]; then

    echo "${BLD}Gevonden applicaties:${RST}"
    for app in "${MATCHED_APPS[@]}"; do
        echo "  $app"
    done
    echo ""

    if ask_yn "App-bundle(s) verwijderen?"; then

        for app in "${MATCHED_APPS[@]}"; do

            app_process=$(basename "$app" .app)
            pkill -ix "$app_process" 2>/dev/null || true

            size=$(du -sk "$app" 2>/dev/null | awk '{print $1 * 1024}')

            if [[ "$DRY_RUN" == true ]]; then
                DRY_RUN_MATCHES+=("$app")
                DRY_RUN_BYTES=$((DRY_RUN_BYTES + size))
                echo "  ${YLW}[DRY RUN]${RST} Zou verwijderen: $app"
            else
                if safe_delete "$app"; then
                    echo "  ${GRN}Verwijderd:${RST} $app"
                    DELETED_FILE_COUNT=$((DELETED_FILE_COUNT + 1))
                    DELETED_BYTES=$((DELETED_BYTES + size))
                else
                    echo "  ${RED}Mislukt:${RST} $app"
                    FAILED_DELETES+=("$app")
                fi
            fi
        done
    fi
fi

# --------------------------------------------------
# ZOEKPADEN
# --------------------------------------------------

DARWIN_CACHE=$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)
DARWIN_TEMP=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)

USER_DIRS=(
    "$HOME/Library/Application Support"
    "$HOME/Library/Caches"
    "$HOME/Library/Containers"
    "$HOME/Library/Logs"
    "$HOME/Library/Preferences"
    "$HOME/Library/Saved Application State"
    "$HOME/Library/WebKit"
    "$HOME/Library/HTTPStorages"
    "$HOME/Library/Application Scripts"
    "$HOME/Library/Group Containers"
)

SYSTEM_DIRS=(
    "/Library/Application Support"
    "/Library/Caches"
    "/Library/Logs"
    "/Library/LaunchAgents"
    "/Library/LaunchDaemons"
    "/Library/Preferences"
    "/Library/PrivilegedHelperTools"
    "/private/var/db/receipts"
    "/usr/local"
    "/opt/homebrew"
    "${DARWIN_CACHE:-}"
    "${DARWIN_TEMP:-}"
)

# --------------------------------------------------
# ZOEKFUNCTIE
# --------------------------------------------------

process_matches() {

    local scope="$1"
    shift
    local dirs=("$@")

    for dir in "${dirs[@]}"; do

        [[ -d "$dir" ]] || continue

        echo "Scannen: $dir"

        while IFS= read -r item; do

            [[ ! -e "$item" ]] && continue

            base=$(basename "$item" | tr '[:upper:]' '[:lower:]')
            [[ "$base" == *apple* ]] && continue

            if [[ "$scope" == "system" ]]; then
                SYSTEM_MATCHES+=("$item")
                continue
            fi

            size=$(du -sk "$item" 2>/dev/null | awk '{print $1 * 1024}')
            human=$(human_size "$size")

            echo "  Gevonden: $item ${CYN}($human)${RST}"

            if [[ "$DRY_RUN" == true ]]; then
                DRY_RUN_MATCHES+=("$item")
                DRY_RUN_BYTES=$((DRY_RUN_BYTES + size))
            else
                if safe_delete "$item"; then
                    echo "    ${GRN}→ Verwijderd${RST}"
                    DELETED_FILE_COUNT=$((DELETED_FILE_COUNT + 1))
                    DELETED_BYTES=$((DELETED_BYTES + size))
                else
                    echo "    ${RED}→ Mislukt${RST}"
                    FAILED_DELETES+=("$item")
                fi
            fi

        done < <(
            if [[ "$MATCH_KEY_LOWER" != "$APP_NAME_LOWER" ]]; then
                find "$dir" \( -iname "*$MATCH_KEY_LOWER*" -o -iname "*$APP_NAME_LOWER*" \) 2>/dev/null
            else
                find "$dir" -iname "*$MATCH_KEY_LOWER*" 2>/dev/null
            fi
        )

        echo ""
    done
}

# --------------------------------------------------
# SCANNEN
# --------------------------------------------------

echo "${BLD}Gebruikersbestanden doorzoeken…${RST}"
echo ""
process_matches user "${USER_DIRS[@]}"

echo "${BLD}Systeembestanden doorzoeken…${RST}"
echo ""
process_matches system "${SYSTEM_DIRS[@]}"

# --------------------------------------------------
# SYSTEEMBESTANDEN
# --------------------------------------------------

if [[ ${#SYSTEM_MATCHES[@]} -gt 0 ]]; then

    echo ""
    echo "${BLD}Gevonden systeembestanden:${RST}"
    echo ""
    for item in "${SYSTEM_MATCHES[@]}"; do
        echo "  $item"
    done
    echo ""

    if [[ "$DRY_RUN" == true ]]; then

        for item in "${SYSTEM_MATCHES[@]}"; do
            size=$(du -sk "$item" 2>/dev/null | awk '{print $1 * 1024}')
            DRY_RUN_MATCHES+=("$item")
            DRY_RUN_BYTES=$((DRY_RUN_BYTES + size))
            echo "  ${YLW}[DRY RUN]${RST} Zou verwijderen: $item"
        done

    elif ask_yn "Systeembestanden verwijderen?"; then

        for item in "${SYSTEM_MATCHES[@]}"; do
            size=$(du -sk "$item" 2>/dev/null | awk '{print $1 * 1024}')
            if safe_delete "$item"; then
                echo "  ${GRN}Verwijderd:${RST} $item"
                DELETED_FILE_COUNT=$((DELETED_FILE_COUNT + 1))
                DELETED_BYTES=$((DELETED_BYTES + size))
            else
                echo "  ${RED}Mislukt:${RST} $item"
                FAILED_DELETES+=("$item")
            fi
        done
    fi
fi

# --------------------------------------------------
# SAMENVATTING
# --------------------------------------------------

echo ""
echo "${BLD}=========================================${RST}"
echo "${BLD}  SAMENVATTING${RST}"
echo "${BLD}=========================================${RST}"
echo ""

if [[ "$DRY_RUN" == true ]]; then

    echo "${YLW}[DRY RUN – niets verwijderd]${RST}"
    echo ""

    if [[ ${#DRY_RUN_MATCHES[@]} -eq 0 ]]; then
        echo "Geen bestanden gevonden voor: $MATCH_KEY"
    else
        echo "Zou verwijderen (${#DRY_RUN_MATCHES[@]} item(s)):"
        echo ""
        for item in "${DRY_RUN_MATCHES[@]}"; do
            echo "  $item"
        done
        echo ""
        echo -n "Geschatte vrije ruimte: "
        human_size "$DRY_RUN_BYTES"
    fi

else

    echo "Verwijderde items : $DELETED_FILE_COUNT"
    echo -n "Vrijgekomen ruimte: "
    human_size "$DELETED_BYTES"
fi

# --------------------------------------------------
# MISLUKTE VERWIJDERINGEN
# --------------------------------------------------

if [[ ${#FAILED_DELETES[@]} -gt 0 ]]; then

    echo ""
    echo "${RED}${BLD}Mislukte verwijderingen:${RST}"
    echo ""
    for item in "${FAILED_DELETES[@]}"; do
        echo "  $item"
    done
    echo ""

    if ask_yn "Opnieuw proberen met sudo?"; then

        for item in "${FAILED_DELETES[@]}"; do
            if sudo rm -rf -- "$item"; then
                echo "  ${GRN}[sudo] Verwijderd:${RST} $item"
            else
                STILL_FAILED_DELETES+=("$item")
                echo "  ${RED}[sudo] Nog steeds mislukt:${RST} $item"
            fi
        done

        if [[ ${#STILL_FAILED_DELETES[@]} -gt 0 ]]; then
            echo ""
            echo "${RED}Kon niet verwijderen:${RST}"
            for item in "${STILL_FAILED_DELETES[@]}"; do
                echo "  $item"
            done
        fi
    fi
fi

echo ""
echo "${GRN}${BLD}Klaar.${RST}"
echo ""
