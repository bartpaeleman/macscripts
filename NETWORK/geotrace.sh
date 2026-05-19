#!/bin/bash

RED='\033[0;31m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

if [ -z "$1" ]; then
  echo "Gebruik: $0 <domeinnaam of ip>"
  exit 1
fi

TARGET=$1
AUTHORITARIAN="RU CN KP IR SY BY MM CU AF"
SANCTIONED="IQ LY SD SO YE ZW BI CD ER VE"
PRIVACY="IN BR PK BD"

echo -e "${BOLD}Traceroute naar: $TARGET${NC}"
echo "Max 30 hops, niet-reagerende hops worden overgeslagen..."

TEMP_FILE=$(mktemp)

HOPS=$(traceroute -n -q 1 -w 2 -m 30 "$TARGET" 2>&1 \
    | grep -vE "^traceroute|Warning:|^$" \
    | awk '{print $1","$2}')

# Resolve eindbestemming
if command -v dig >/dev/null 2>&1; then
    TARGET_IP=$(dig +short A "$TARGET" 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
elif command -v host >/dev/null 2>&1; then
    TARGET_IP=$(host -4 "$TARGET" 2>/dev/null | awk '/has address/{print $4; exit}')
else
    TARGET_IP=""
fi
if [ -z "$TARGET_IP" ] && echo "$TARGET" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    TARGET_IP="$TARGET"
fi

# Forceer eindbestemming als laatste hop indien ontbrekend
if [ -n "$TARGET_IP" ]; then
    LAST_IP=$(echo "$HOPS" | tail -1 | cut -d',' -f2)
    if [ "$LAST_IP" != "$TARGET_IP" ]; then
        LAST_NUM=$(echo "$HOPS" | tail -1 | cut -d',' -f1)
        NEXT_NUM=$((10#$LAST_NUM + 1))
        HOPS="${HOPS}
${NEXT_NUM},${TARGET_IP}"
    fi
fi

for line in $HOPS; do
    (
        HOP_NUM=$(echo "$line" | cut -d',' -f1)
        IP=$(echo "$line" | cut -d',' -f2)

        if [ -z "$IP" ]; then exit 0; fi

        if [ "$IP" = "*" ]; then
            printf "%02d|%s|%s|%s|%s|%s|%s\n" \
                "$HOP_NUM" "*" "-" "Tijdlimiet" "-" "-" "-" >> "$TEMP_FILE"
            exit 0
        fi

        if echo "$IP" | grep -qE '^127\.|^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.'; then
            printf "%02d|%s|%s|%s|%s|%s|%s\n" \
                "$HOP_NUM" "$IP" "Intern Netwerk" "-" "-" "-" "Privé router/gateway" >> "$TEMP_FILE"
        else
            DATA=$(curl -s --max-time 2 \
                "http://ip-api.com/csv/$IP?fields=status,continentCode,country,countryCode,isp,org,as")

            if [ $? -ne 0 ] || [ -z "$DATA" ]; then
                printf "%02d|%s|%s|%s|%s|%s|%s\n" \
                    "$HOP_NUM" "$IP" "Onbekend" "API fout" "-" "-" "-" >> "$TEMP_FILE"
            else
                API_STATUS=$(echo "$DATA" | cut -d',' -f1)
                CONT=$(echo "$DATA"       | cut -d',' -f2)
                COUNTRY=$(echo "$DATA"    | cut -d',' -f3)
                CODE=$(echo "$DATA"       | cut -d',' -f4)
                ISP=$(echo "$DATA"        | cut -d',' -f5)
                ORG=$(echo "$DATA"        | cut -d',' -f6)
                AS=$(echo "$DATA"         | cut -d',' -f7)

                if [ "$API_STATUS" = "fail" ]; then
                    printf "%02d|%s|%s|%s|%s|%s|%s\n" \
                        "$HOP_NUM" "$IP" "Onbekend" "Onbekend" "-" "-" "-" >> "$TEMP_FILE"
                    exit 0
                fi

                STATUS="OK"
                RISICO_TYPE="-"

                if echo " $AUTHORITARIAN " | grep -q " $CODE "; then
                    STATUS="!! RISICO !!"
                    RISICO_TYPE="Autoritair"
                elif echo " $SANCTIONED " | grep -q " $CODE "; then
                    STATUS="!! RISICO !!"
                    RISICO_TYPE="Sanctieland"
                elif echo " $PRIVACY " | grep -q " $CODE "; then
                    STATUS="LET OP"
                    RISICO_TYPE="Privacy-risico"
                elif [ "$CONT" != "EU" ]; then
                    STATUS="BUITEN-EU"
                fi

                ISP_LOWER=$(echo "$ISP $ORG" | tr '[:upper:]' '[:lower:]')
                if echo "$ISP_LOWER" | grep -qE 'hurricane|cogent|lumen|telia|zayo|ntt|level 3|level3|akamai|cloudflare|fastly|amazon|google|microsoft|meta|backbone|transit|peering|core|ix|ixp|exchange'; then
                    ROLE="Transit/Backbone"
                elif echo "$ISP_LOWER" | grep -qE 'telenet|proximus|voo|orange|belgacom|swisscom|kpn|deutsche telekom|bt |british telecom|comcast|at&t|verizon|charter|spectrum'; then
                    ROLE="ISP Netwerk"
                elif echo "$ISP_LOWER" | grep -qE 'federal|guard|gov|government|ministry|state|military|kreml|fsb|fso'; then
                    ROLE="Overheid/Staat"
                elif echo "$ISP_LOWER" | grep -qE 'hosting|datacenter|data center|colocation|colo|cloud|server|vps|dedicated'; then
                    ROLE="Hosting/DC"
                elif echo "$ISP_LOWER" | grep -qE 'university|universit|research|education|school|academic'; then
                    ROLE="Onderwijs"
                else
                    ROLE="$AS"
                fi

                printf "%02d|%s|%s|%s|%s|%s|%s\n" \
                    "$HOP_NUM" "$IP" "$COUNTRY" \
                    "$STATUS" "$RISICO_TYPE" "$ISP" "$ROLE" >> "$TEMP_FILE"
            fi
        fi
    ) &
done

wait

echo ""
printf "${BOLD}%-4s %-16s %-18s %-14s %-16s %-28s %s${NC}\n" \
    "HOP" "IP-ADRES" "LAND" "STATUS" "RISICO-TYPE" "PROVIDER" "ROL"
echo "---------------------------------------------------------------------------------------------------------------"

if [ ! -s "$TEMP_FILE" ] || [ -z "$(tr -d '[:space:]' < "$TEMP_FILE")" ]; then
    echo "Geen actieve hops gevonden of doel onbereikbaar."
else
    sort "$TEMP_FILE" | while IFS='|' read -r hop ip country status risico isp role; do
        status=$(echo "$status" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        risico=$(echo "$risico" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        role=$(echo "$role"     | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        COLOR=$(printf '\033[0m')
        RESET=$(printf '\033[0m')

        if [ "$risico" = "Autoritair" ]; then
            COLOR=$(printf '\033[0;31m')
        elif [ "$risico" = "Sanctieland" ]; then
            COLOR=$(printf '\033[0;35m')
        elif [ "$risico" = "Privacy-risico" ]; then
            COLOR=$(printf '\033[0;36m')
        elif [ "$status" = "BUITEN-EU" ]; then
            COLOR=$(printf '\033[1;33m')
        elif [ "$status" = "OK" ]; then
            COLOR=$(printf '\033[0;32m')
        fi

        printf "%-4s %-16s %-18s ${COLOR}%-14s${RESET} %-16s %-28s %s\n" \
            "$hop" "$ip" "$country" "$status" "$risico" "$isp" "$role"
    done
fi

echo "---------------------------------------------------------------------------------------------------------------"
echo -e "${GREEN}EU/Veilig${NC}  ${YELLOW}Niet-EU${NC}  ${CYAN}Privacy-risico${NC}  ${PURPLE}Sanctieland${NC}  ${RED}Autoritair${NC}"
