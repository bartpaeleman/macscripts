#!/bin/sh
#
# netsweep.sh - snelle netwerk sweep voor QNAP (BusyBox) en macOS
# Gebruik: ./netsweep.sh [-s subnet] [-o screen|csv] [-f bestand] [-t timeout] [-a] [-v] [-d delay] [-u] [-b dbfile] [-h]

case "$1" in
    -h|--h|-help|--help|/h|/help|/H|/Help)
        echo "Gebruik: $0 [-s subnet/cidr] [-o screen|csv] [-f bestand] [-t timeout_sec] [-a] [-v] [-d delay_sec] [-u] [-b dbfile] [-h]"
        echo "  -s  subnet, bv. 192.168.1 of 192.168.1.0/24 (default: auto-detect, /24)"
        echo "  -o  output: screen (default) of csv"
        echo "  -f  csv bestandsnaam (default: netsweep_<timestamp>.csv)"
        echo "  -t  ping timeout in seconden (default: 1)"
        echo "  -a  toon alle 254 adressen incl. Active-kolom (default: enkel actieve adressen)"
        echo "  -v  vendor-lookup aanzetten (lokale db indien aanwezig, anders online API)"
        echo "  -d  wachttijd tussen online vendor-lookups in seconden (default: 1)"
        echo "  -u  download/ververs lokale OUI-database"
        echo "  -b  pad naar de OUI-database (default: oui_db.txt naast dit script)"
        echo "  -h, --h, -help, --help, /h  toon deze help en stop"
        exit 0
        ;;
esac

SUBNET=""
OUTPUT="screen"
OUTFILE="netsweep_$(date +%Y%m%d_%H%M%S).csv"
TIMEOUT=1
SHOW_ALL=0
DO_VENDOR=0
VENDOR_DELAY=1
UPDATE_DB=0

SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
DBFILE="${SCRIPT_DIR}/oui_db.txt"
OUI_URL="https://standards-oui.ieee.org/oui/oui.txt"
TMPACTIVE="/tmp/netsweep_active.$$"

fail_usage() {
    echo "Fout: $1" >&2
    echo "Gebruik: $0 [-s subnet] [-o screen|csv] [-f bestand] [-t timeout] [-a] [-v] [-d delay] [-u] [-b dbfile] [-h]" >&2
    exit 1
}

while getopts ":s:o:f:t:d:b:avuh" opt; do
    case "$opt" in
        s) SUBNET="$OPTARG" ;;
        o) OUTPUT="$OPTARG" ;;
        f) OUTFILE="$OPTARG" ;;
        t) TIMEOUT="$OPTARG" ;;
        d) VENDOR_DELAY="$OPTARG" ;;
        b) DBFILE="$OPTARG" ;;
        a) SHOW_ALL=1 ;;
        v) DO_VENDOR=1 ;;
        u) UPDATE_DB=1 ;;
        h) exit 0 ;;
        :) fail_usage "optie -$OPTARG vereist een argument." ;;
        \?) fail_usage "onbekende optie -$OPTARG." ;;
    esac
done

case "$OUTPUT" in
    screen|csv) ;;
    *) fail_usage "-o moet 'screen' of 'csv' zijn." ;;
esac

# --- OUI-database downloaden/verversen ---
# enkel het MAC-prefix wordt geüppercast, de vendor-naam blijft ongewijzigd
update_oui_db() {
    echo "Database downloaden van ${OUI_URL} ..." >&2
    TMPFILE="${DBFILE}.tmp"
    if command -v curl >/dev/null 2>&1; then
        curl -s --max-time 20 -o "$TMPFILE" "$OUI_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 20 -O "$TMPFILE" "$OUI_URL"
    else
        echo "Fout: curl of wget nodig om de database te downloaden." >&2
        return 1
    fi
    [ -s "$TMPFILE" ] || { echo "Fout: download mislukt of leeg bestand." >&2; rm -f "$TMPFILE"; return 1; }
    awk '
        /\(hex\)/ {
            split($1, a, "-")
            prefix = toupper(a[1] a[2] a[3])
            sub(/^[^)]*\)[ \t]*/, "")
            if ($0 != "") print prefix " " $0
        }
    ' "$TMPFILE" > "$DBFILE"
    rm -f "$TMPFILE"
    if [ -s "$DBFILE" ]; then
        echo "Database opgeslagen in $DBFILE ($(wc -l < "$DBFILE" | tr -d ' ') vendors)." >&2
    else
        echo "Fout: verwerken van de database is mislukt." >&2
        return 1
    fi
}

[ "$UPDATE_DB" -eq 1 ] && update_oui_db

case "$(uname -s)" in
    Darwin) PLATFORM="macos" ;;
    *)      PLATFORM="linux" ;;
esac

if [ -z "$SUBNET" ]; then
    if [ "$PLATFORM" = "macos" ]; then
        IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
        MYIP=$(ipconfig getifaddr "$IFACE" 2>/dev/null)
    else
        MYIP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1); exit}')
        [ -z "$MYIP" ] && MYIP=$(ifconfig 2>/dev/null | awk '/inet /{print $2}' | grep -v '^127\.' | head -n1 | sed 's/addr://')
    fi
    [ -z "$MYIP" ] && fail_usage "kon geen eigen IP/interface bepalen. Geef het subnet op met -s."
    NET=$(echo "$MYIP" | awk -F. '{print $1"."$2"."$3}')
else
    NET=$(echo "$SUBNET" | sed 's#/.*##' | awk -F. '{print $1"."$2"."$3}')
fi

ping_host() {
    if [ "$PLATFORM" = "macos" ]; then
        ping -c 1 -t "$TIMEOUT" -q "$1" >/dev/null 2>&1
    else
        ping -c 1 -W "$TIMEOUT" -q "$1" >/dev/null 2>&1
    fi
}

# stopt na de EERSTE match, zodat een dubbele /proc/net/arp-regel
# nooit meer twee MAC's (met newline ertussen) in één variabele geeft
get_mac() {
    IP="$1"
    if [ "$PLATFORM" = "linux" ] && [ -r /proc/net/arp ]; then
        M=$(awk -v ip="$IP" '$1==ip {print $4; exit}' /proc/net/arp)
        case "$M" in
            00:00:00:00:00:00|"") ;;
            *) printf '%s' "$M" | tr -d '\n\r'; return ;;
        esac
    fi
    arp -an 2>/dev/null | grep -F "($IP)" | grep -Eo '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | head -n1 | tr -d '\n\r'
}

get_name() {
    nslookup "$1" 2>/dev/null | awk -F'= ' '/name =/{print $2; exit}' | sed 's/\.$//' | tr -d '\n\r'
}

get_vendor() {
    MAC="$1"
    [ -z "$MAC" ] && { echo "-"; return; }
    if [ -s "$DBFILE" ]; then
        PREFIX=$(echo "$MAC" | tr -d ':' | tr 'a-f' 'A-F' | cut -c1-6)
        V=$(awk -v p="$PREFIX" '$1==p {sub(/^[^ ]+ /,""); print; exit}' "$DBFILE")
        [ -z "$V" ] && V="-"
        printf '%s' "$V" | tr -d '\n\r'
        return
    fi
    if command -v curl >/dev/null 2>&1; then
        V=$(curl -s --max-time 2 "https://api.macvendors.com/${MAC}" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        V=$(wget -q -T 2 -O - "https://api.macvendors.com/${MAC}" 2>/dev/null)
    else
        V=""
    fi
    sleep "$VENDOR_DELAY"
    case "$V" in
        *"Not Found"*|*"errors"*|*"Too Many"*|"") echo "-" ;;
        *) printf '%s' "$V" | tr -d '\n\r' ;;
    esac
}

# quote een CSV-veld als het een komma of aanhalingsteken bevat
csv_field() {
    case "$1" in
        *,*|*'"'*) printf '"%s"' "$(printf '%s' "$1" | sed 's/"/""/g')" ;;
        *) printf '%s' "$1" ;;
    esac
}

: > "$TMPACTIVE"
echo "Sweep van ${NET}.0/24 ..." >&2
i=1
while [ "$i" -le 254 ]; do
    TARGET="${NET}.${i}"
    (ping_host "$TARGET" && echo "$TARGET" >> "$TMPACTIVE") &
    i=$((i+1))
done
wait
ACTIVE_COUNT=$(wc -l < "$TMPACTIVE" | tr -d ' ')
echo "${ACTIVE_COUNT} actieve adressen gevonden." >&2

if [ "$DO_VENDOR" -eq 1 ]; then
    if [ -s "$DBFILE" ]; then
        echo "Vendor-lookup: lokale database $DBFILE ($(wc -l < "$DBFILE" | tr -d ' ') entries)." >&2
    else
        echo "Vendor-lookup: geen lokale database op $DBFILE — online API gebruikt (wachttijd ${VENDOR_DELAY}s/host)." >&2
    fi
fi

if [ "$DO_VENDOR" -eq 1 ] && [ "$SHOW_ALL" -eq 1 ]; then
    HEADER_CSV="IP,Active,MAC,Hostname,Vendor"
elif [ "$DO_VENDOR" -eq 1 ]; then
    HEADER_CSV="IP,MAC,Hostname,Vendor"
elif [ "$SHOW_ALL" -eq 1 ]; then
    HEADER_CSV="IP,Active,MAC,Hostname"
else
    HEADER_CSV="IP,MAC,Hostname"
fi

if [ "$OUTPUT" = "csv" ]; then
    echo "$HEADER_CSV" > "$OUTFILE"
else
    if [ "$DO_VENDOR" -eq 1 ] && [ "$SHOW_ALL" -eq 1 ]; then
        printf "%-16s %-7s %-19s %-25s %-s\n" "IP" "Active" "MAC" "Hostname" "Vendor"
    elif [ "$DO_VENDOR" -eq 1 ]; then
        printf "%-16s %-19s %-25s %-s\n" "IP" "MAC" "Hostname" "Vendor"
    elif [ "$SHOW_ALL" -eq 1 ]; then
        printf "%-16s %-7s %-19s %-s\n" "IP" "Active" "MAC" "Hostname"
    else
        printf "%-16s %-19s %-s\n" "IP" "MAC" "Hostname"
    fi
fi

print_row() {
    TARGET="$1"; ACTIVE="$2"; MAC="$3"; NAME="$4"; VENDOR="$5"
    if [ "$OUTPUT" = "csv" ]; then
        if [ "$DO_VENDOR" -eq 1 ] && [ "$SHOW_ALL" -eq 1 ]; then
            echo "$(csv_field "$TARGET"),$(csv_field "$ACTIVE"),$(csv_field "$MAC"),$(csv_field "$NAME"),$(csv_field "$VENDOR")" >> "$OUTFILE"
        elif [ "$DO_VENDOR" -eq 1 ]; then
            echo "$(csv_field "$TARGET"),$(csv_field "$MAC"),$(csv_field "$NAME"),$(csv_field "$VENDOR")" >> "$OUTFILE"
        elif [ "$SHOW_ALL" -eq 1 ]; then
            echo "$(csv_field "$TARGET"),$(csv_field "$ACTIVE"),$(csv_field "$MAC"),$(csv_field "$NAME")" >> "$OUTFILE"
        else
            echo "$(csv_field "$TARGET"),$(csv_field "$MAC"),$(csv_field "$NAME")" >> "$OUTFILE"
        fi
    else
        if [ "$DO_VENDOR" -eq 1 ] && [ "$SHOW_ALL" -eq 1 ]; then
            printf "%-16s %-7s %-19s %-25s %-s\n" "$TARGET" "$ACTIVE" "$MAC" "$NAME" "$VENDOR"
        elif [ "$DO_VENDOR" -eq 1 ]; then
            printf "%-16s %-19s %-25s %-s\n" "$TARGET" "$MAC" "$NAME" "$VENDOR"
        elif [ "$SHOW_ALL" -eq 1 ]; then
            printf "%-16s %-7s %-19s %-s\n" "$TARGET" "$ACTIVE" "$MAC" "$NAME"
        else
            printf "%-16s %-19s %-s\n" "$TARGET" "$MAC" "$NAME"
        fi
    fi
}

if [ "$SHOW_ALL" -eq 1 ]; then
    i=1
    while [ "$i" -le 254 ]; do
        TARGET="${NET}.${i}"
        if grep -qx "$TARGET" "$TMPACTIVE"; then
            ACTIVE="X"
            MAC=$(get_mac "$TARGET"); [ -z "$MAC" ] && MAC="-"
            NAME=$(get_name "$TARGET"); [ -z "$NAME" ] && NAME="-"
            [ "$DO_VENDOR" -eq 1 ] && VENDOR=$(get_vendor "$MAC") || VENDOR="-"
        else
            ACTIVE=""; MAC="-"; NAME="-"; VENDOR="-"
        fi
        print_row "$TARGET" "$ACTIVE" "$MAC" "$NAME" "$VENDOR"
        i=$((i+1))
    done
else
    sort -t. -k4 -n "$TMPACTIVE" | while IFS= read -r TARGET; do
        MAC=$(get_mac "$TARGET"); [ -z "$MAC" ] && MAC="-"
        NAME=$(get_name "$TARGET"); [ -z "$NAME" ] && NAME="-"
        [ "$DO_VENDOR" -eq 1 ] && VENDOR=$(get_vendor "$MAC") || VENDOR="-"
        print_row "$TARGET" "X" "$MAC" "$NAME" "$VENDOR"
    done
fi

rm -f "$TMPACTIVE"
[ "$OUTPUT" = "csv" ] && echo "Klaar. Resultaten in: $OUTFILE" >&2