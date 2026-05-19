#!/bin/bash
# Wrapper script to run python scripts ensuring dependencies are met

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
REQUIREMENTS="$BASE_DIR/requirements.txt"

VENV_DIR="$BASE_DIR/.venv"

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "[info] Creating Python virtual environment in $VENV_DIR..." >&2
    python3 -m venv "$VENV_DIR" >&2 || {
        echo "[error] Failed to create virtual environment. Make sure python3-venv is installed." >&2
        exit 1
    }
fi

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Check if requirements.txt exists and update/install dependencies
if [ -f "$REQUIREMENTS" ]; then
    # Print to stderr so we don't break stdout JSON pipelines
    # Only install if we haven't recently (basic check by looking for a marker file or just always run quietly)
    # We will run quietly to ensure it's up to date.
    if [ ! -f "$VENV_DIR/.req_installed" ] || [ "$REQUIREMENTS" -nt "$VENV_DIR/.req_installed" ]; then
        echo "[info] Installing dependencies from $REQUIREMENTS..." >&2
        python3 -m pip install -r "$REQUIREMENTS" -q >&2
        touch "$VENV_DIR/.req_installed"
    fi
fi

# Run the passed python script and arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <python_script> [args...]"
else
    python3 "$@"
fi
