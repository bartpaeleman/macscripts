#!/bin/bash
# Shell aliases and wrappers for cyber-master toolset

CYBER_MASTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_WRAPPER="$CYBER_MASTER_DIR/common/run_python.sh"

# 1. mailtrace: Roept mail_analyzer.py aan en toont de terminal TUI
mailtrace() {
    if [ -z "$1" ]; then
        echo "Usage: mailtrace <path_to_eml_file>"
        return 1
    fi
    "$PYTHON_WRAPPER" "$CYBER_MASTER_DIR/mail/mail_analyzer.py" "$1"
}

# 2. threatctx: Pipeline alias voor target verrijking en scoring
threatctx() {
    if [ -z "$1" ]; then
        echo "Usage: threatctx <target_ip_or_domain>"
        return 1
    fi

    echo "{\"target\": \"$1\"}" | \
    "$PYTHON_WRAPPER" "$CYBER_MASTER_DIR/enrich/enricher.py" | \
    "$PYTHON_WRAPPER" "$CYBER_MASTER_DIR/scoring/risk_scorer.py" | \
    "$PYTHON_WRAPPER" "$CYBER_MASTER_DIR/reporting/reporter.py"
}

# 3. mhdr: Gooit stdin in mail_analyzer en toont key findings via jq
mhdr() {
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required for mhdr. Please install jq." >&2
        return 1
    fi

    # Read stdin to a temporary file
    local temp_file=$(mktemp)
    cat > "$temp_file"

    # Process and pipe to jq to extract key findings
    "$PYTHON_WRAPPER" "$CYBER_MASTER_DIR/mail/mail_analyzer.py" "$temp_file" --json | \
    jq '{
        "Origin IP": .ioc.originating_ip,
        "SPF": .mail.auth.spf,
        "DKIM": .mail.auth.dkim,
        "Spoof Likelihood / Risk Score": .risk_score
    }'

    rm "$temp_file"
}
