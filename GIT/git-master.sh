#!/bin/bash

# Zorg dat autocomplete het scherm niet overvol maakt door het te wissen bij tab
set -o emacs
bind '"\t": "\C-l\e\e"' 2>/dev/null || true


# ============================================================
# GIT MASTER CONTROL PANEL v7.2.0
# Professional Git Workflow Manager for QNAP & macOS
# ============================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# --- ENVIRONMENT DETECTION ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/config/.env"
ENV_EXAMPLE="${SCRIPT_DIR}/config/.env.example"

# Load environment variables
load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        printf "\n${YELLOW}Configuration file not found.${NC}\n"

        if [[ -f "$ENV_EXAMPLE" ]]; then
            read -p "Create .env from template? (y/n): " create_env
            if [[ "$create_env" == "y" ]]; then
                cp "$ENV_EXAMPLE" "$ENV_FILE"
                printf "${GREEN}Created .env file.${NC}\n"
                printf "${CYAN}Opening editor to configure settings...${NC}\n"
                sleep 1
                ${EDITOR:-nano} "$ENV_FILE"
            else
                printf "${RED}Setup aborted. Please configure .env manually before running gitmaster.${NC}\n"
                exit 1
            fi
        else
            printf "${RED}ERROR: Template .env.example missing. Please create .env manually.${NC}\n"
            exit 1
        fi
    fi

    # Parse .env file, ignoring comments and empty lines
    # Using '|| [ -n "$key" ]' to handle files without trailing newline
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Trim leading/trailing whitespace from key
        key=$(echo "$key" | xargs)

        # Validate key is a valid identifier (alphanumeric + underscore, starts with letter/underscore)
        if [[ ! "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            # echo "Warning: Skipping invalid key '$key'"
            continue
        fi

        # Remove quotes and whitespace (including carriage return) from value
        value="${value%\"}"
        value="${value#\"}"
        value=$(echo "$value" | tr -d '\r')

        export "$key=$value"
    done < "$ENV_FILE"

    # Validate required variables
    if [[ -z "${GITHUB_TOKEN:-}" ]] || [[ -z "${GITHUB_USERNAME:-}" ]] || [[ -z "${GITHUB_EMAIL:-}" ]]; then
        printf "\033[1;31mERROR: GITHUB_TOKEN, GITHUB_USERNAME, and GITHUB_EMAIL must be set in .env\033[0m\n"
        read -p "Would you like to edit the .env file now? (y/n): " edit_env
        if [[ "$edit_env" =~ ^[Yy]$ ]]; then
            ${EDITOR:-nano} "$ENV_FILE"
            printf "${GREEN}Please re-run gitmaster to apply the changes.${NC}\n"
            exit 0
        else
            exit 1
        fi
    fi

    # Set git config globally if not yet set
    if [[ -z "$(git config --global user.name)" && -n "${GITHUB_USERNAME}" ]]; then
        git config --global user.name "${GITHUB_USERNAME}"
    fi
    if [[ -z "$(git config --global user.email)" && -n "${GITHUB_EMAIL}" ]]; then
        git config --global user.email "${GITHUB_EMAIL}"
    fi

    # Set default paths if not configured
    PATH_ROOT="${PATH_ROOT:-/share/Web}"
    PATH_PROD="${PATH_PROD:-${PATH_ROOT}}"
    PATH_DEV="${PATH_DEV:-${PATH_ROOT}/DEV}"
    PATH_TEST="${PATH_TEST:-${PATH_ROOT}/TEST}"

    # QNAP persistence paths
    PERSISTENT_SCRIPT_PATH="${PERSISTENT_SCRIPT_PATH:-${PATH_DEV}/scripts/git-master.sh}"
    PERSISTENT_ENV="${PERSISTENT_ENV:-${PATH_DEV}/scripts/.env}"
}

# --- COLOR DEFINITIONS ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
BOLD='\033[1m'
NC='\033[0m'

# --- HELPER FUNCTIONS ---

get_branch_list_raw() {
    local prefix="${1:-br}"
    local counter=1

    while IFS= read -r branch; do
        branch=$(echo "$branch" | sed 's/^[* ]*//' | awk '{print $1}')
        [[ -z "$branch" ]] && continue
        eval "${prefix}_${counter}='${branch}'"
        ((counter++))
    done < <(git branch -a | grep -v HEAD)

    eval "${prefix}_count=$((counter - 1))"
}

print_colored_branch_list() {
    local prefix="${1:-br}"
    local count_var="${prefix}_count"
    local count="${!count_var}"

    printf "\n${CYAN}${BOLD}Available Branches:${NC}\n"
    for ((i=1; i<=count; i++)); do
        local var="${prefix}_${i}"
        local branch="${!var}"

        if [[ "$branch" == *"remotes/origin"* ]]; then
            printf " ${YELLOW}%2d) %s${NC}\n" "$i" "$branch"
        else
            printf " ${GREEN}%2d) %s${NC}\n" "$i" "$branch"
        fi
    done
    printf " ${RED}X) Cancel${NC}\n"
}

check_dirty() {
    if [[ -n $(git status -s) ]]; then
        # Check for files that are tracked but match .gitignore (causing checkout errors)
        local ignored_tracked=$(git ls-files -i -c --exclude-standard 2>/dev/null || true)
        if [[ -n "$ignored_tracked" ]]; then
            printf "${YELLOW}Detected tracked files that match .gitignore:${NC}\n"
            echo "$ignored_tracked" | sed 's/^/  /'
            printf "These will block branch checkouts if they exist on the target branch.\n"
            read -p "Untrack them from git cache now (git rm --cached) and commit? (y/n): " rm_conf
            if [[ "$rm_conf" == "y" ]]; then
                # Untrack files while leaving them locally
                echo "$ignored_tracked" | tr '\n' '\0' | xargs -0 git rm --cached -q
                # Commit the deletion from git
                git commit -m "chore: untrack ignored files" -q
                printf "${GREEN}Files untracked and committed. They will remain locally.${NC}\n"

                # If no more changes, return success
                if [[ -z $(git status -s) ]]; then
                    return 0
                fi
            fi
        fi

        printf "${YELLOW}Uncommitted changes detected!${NC}\n"
        git status -s
        read -p "Continue anyway? (y/n): " cont
        [[ "$cont" != "y" ]] && return 1
    fi
    return 0
}

confirm_action() {
    local message="$1"
    local confirm_word="${2:-y}"

    printf "${YELLOW}${message}${NC}\n"
    read -p "Type '${confirm_word}' to confirm: " response
    [[ "$response" == "$confirm_word" ]] && return 0 || return 1
}

show_git_stats() {
    printf "${CYAN}${BOLD}Repository Statistics:${NC}\n"
    printf "  Total commits: $(git rev-list --count HEAD 2>/dev/null || echo '0')\n"
    printf "  Total branches: $(git branch -a | grep -v HEAD | wc -l)\n"
    printf "  Contributors: $(git log --format='%an' | sort -u | wc -l)\n"
    printf "  Last commit: $(git log -1 --format='%ar' 2>/dev/null || echo 'N/A')\n"
}

detect_environment() {
    local current_path="$1"

    if [[ "$current_path" == "$PATH_DEV"* ]]; then
        echo "${GREEN}[ ENV: DEV (QNAP) ]${NC}"
        return 0
    elif [[ "$current_path" == "$PATH_TEST"* ]]; then
        echo "${YELLOW}[ ENV: TEST (UAT) ]${NC}"
        return 0
    elif [[ "$current_path" == "$PATH_PROD"* ]]; then
        echo "${RED}${BOLD}[ ENV: PROD (LIVE) ]${NC}"
        return 1
    else
        echo "${NC}[ LOCATION: EXTERNAL ]"
        return 0
    fi
}

# Ensure authentication token is configured in git remote
check_and_fix_remote_auth() {
    # Only run if we are in a git repo and have a token
    if [[ "${IN_GIT:-false}" == "true" ]] && [[ -n "${GITHUB_TOKEN:-}" ]]; then
        local remote_url
        remote_url=$(git remote get-url origin 2>/dev/null || echo "")

        # Check if it's an HTTPS URL to github.com
        if [[ "$remote_url" == https://github.com/* ]]; then
            # Check for bad characters (like carriage return) in URL
            # or if token is missing (no @ symbol before github.com)
            if [[ "$remote_url" =~ $'\r' ]] || [[ "$remote_url" != *"@"* ]]; then

                 # Clean up the URL: remove https:// prefix and strip any existing auth/junk
                 # This handles both cases: fresh install (no auth) and repair (bad auth/CRLF)
                 local clean_path="${remote_url#https://}"

                 # If @ exists, strip everything before it to get just 'github.com/...'
                 if [[ "$clean_path" == *"@"* ]]; then
                     clean_path="${clean_path#*@}"
                 fi

                 # Remove any trailing carriage returns from clean_path just in case
                 clean_path=$(echo "$clean_path" | tr -d '\r')

                 # Construct new URL with clean token
                 local new_url="https://${GITHUB_TOKEN}@${clean_path}"

                 # Update remote URL silently
                 git remote set-url origin "$new_url"
            fi
        fi
    fi
}

# --- INITIALIZATION ---
load_env

# --- COMMAND LINE ARGUMENTS ---
CMD_SWITCH=""
if [[ $# -gt 0 ]]; then
    case "$1" in
        -h|--help|-help)
            printf "${GREEN}Git Master Control Panel - Command Line Switches${NC}\n"
            printf "Usage: gitmaster [option]\n\n"
            printf "  ${CYAN}-st, --status${NC}     Dashboard (Option 1)\n"
            printf "  ${CYAN}-co, --checkout${NC}   Checkout Repo (Option 2)\n"
            printf "  ${CYAN}-br, --branch${NC}     Branch Explorer (Option 3)\n"
            printf "  ${CYAN}-cm, --commit${NC}     Quick Commit (Option 4)\n"
            printf "  ${CYAN}-pl, --pull${NC}       Sync Fetch (Option 5)\n"
            printf "  ${CYAN}-fs, --force-sync${NC} Sync Force (Option 6)\n"
            printf "  ${CYAN}-bk, --backup${NC}     Backup Point (Option 7)\n"
            printf "  ${CYAN}-pr, --prune${NC}      Cleanup Prune (Option 12)\n"
            printf "  ${CYAN}-h,  --help${NC}       Show this help\n"
            exit 0
            ;;
        -st|--status)     CMD_SWITCH="1" ;;
        -co|--checkout)   CMD_SWITCH="2" ;;
        -br|--branch)     CMD_SWITCH="3" ;;
        -cm|--commit)     CMD_SWITCH="4" ;;
        -pl|--pull)       CMD_SWITCH="5" ;;
        -fs|--force-sync) CMD_SWITCH="6" ;;
        -bk|--backup)     CMD_SWITCH="7" ;;
        -pr|--prune)      CMD_SWITCH="12" ;;
        *)
            printf "${RED}Unknown option: $1${NC}\n"
            printf "Use -h for help.\n"
            exit 1
            ;;
    esac
fi

# --- MAIN PROGRAM ---

while true; do
    CUR_PATH=$(pwd)
    PROJECT_NAME=$(basename "$CUR_PATH")

    # Git status check
    if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        IN_GIT=true
    else
        CURRENT_BRANCH="N/A"
        IN_GIT=false
    fi

    # Environment detection
    ENV_VAL=$(detect_environment "$CUR_PATH")
    IS_PROD=$?

    # Check and fix authentication if needed
    check_and_fix_remote_auth

    if [[ -z "$CMD_SWITCH" ]]; then
        clear
        # Header
        printf -- "${GREEN}${BOLD}===============================================================${NC}\n"
        printf -- "       ${GREEN}${BOLD}GIT MASTER CONTROL PANEL v7.2.0${NC}\n"
        printf -- "${GREEN}${BOLD}===============================================================${NC}\n"
        printf -- " Status   : $ENV_VAL\n"
        printf -- " Project  : ${CYAN}$PROJECT_NAME${NC} @ ${YELLOW}$CURRENT_BRANCH${NC}\n"
        printf -- " Path     : ${CYAN}$CUR_PATH${NC}\n"
        printf -- " Auth     : $([ -n "$GITHUB_TOKEN" ] && echo -e "${GREEN}TOKEN ACTIVE${NC}" || echo -e "${RED}NO TOKEN FOUND${NC}")\n"
        printf -- "${GREEN}${BOLD}===============================================================${NC}\n"

        printf "${YELLOW}${BOLD}[MAIN MENU]${NC}\n"
        printf " 1. INFO          (Status, History & Analysis)\n"
        printf " 2. DEVELOPMENT   (Repo & Branch commands)\n"
        printf " 3. FIX           (Errors)\n"
        printf " 4. FILES          (Create, Edit, Delete Repo Files)\n"
        printf " 5. MAINTENANCE   (Backup & Restore)\n"
        printf -- "\n---------------------------------------------------------------\n"
        printf " S) SETUP PERSISTENCE- Fix QNAP login & Aliases\n"
        printf " Q) QUIT\n"
        printf -- "${BOLD}===============================================================${NC}\n"

        read -p "Select action: " main_choice

        case "$main_choice" in
            1)
                printf "\n${YELLOW}${BOLD}[INFO]${NC}\n"
                printf " 1) DASHBOARD        - Status & History Overview (Scrollable)\n"
                printf " 2) DIFF VIEWER     - Compare changes between branches\n"
                printf " 3) FILE HISTORY    - Show all commits for a file\n"
                printf " 4) SEARCH CODE     - Find text in all files (grep)\n"
                printf " 5) COMMIT FINDER   - Search commits by message\n"
                printf " 6) BRANCH COMPARE  - See differences between branches\n"
                read -p "Select command (X to return): " sub_choice
                case "$sub_choice" in
                    1) choice="1" ;;
                    2) choice="18" ;;
                    3) choice="19" ;;
                    4) choice="20" ;;
                    5) choice="21" ;;
                    6) choice="22" ;;
                    [Xx]) continue ;;
                    *) continue ;;
                esac
                ;;
            2)
                printf "\n${YELLOW}${BOLD}[DEVELOPMENT]${NC}\n"
                printf " 1) CHECKOUT REPO    - Fetch & Switch to Repository (Branch)\n"
                printf " 2) BRANCH EXPLORER  - Switch or Create new Feature Branch\n"
                printf " 3) QUICK COMMIT     - Stage, Commit & Push active work\n"
        printf " 4) COMMIT LOCAL     - Stage & Commit local changes (No push)\n"
        printf " 5) AMEND COMMIT     - Add local changes to last commit / edit message\n"
        printf " 6) SYNC FETCH       - Pull remote changes into active branch\n"
        printf " 7) PREPARE UAT      - Merge branch into TEST (Overwrite conflicts)\n"
        printf " 8) STAGING PUSH     - Force sync current to DEV-STABLE\n"
        printf " 9) REBASE ON MAIN   - Rebase feature branch on main (Clean history)\n"
        printf " 10) MILESTONE MERGE - Merge feature into main (Milestones/Conflicts)\n"
        printf " 11) RELEASE TAG     - Mark current state (v1.x)\n"
        printf " 12) CLEANUP PRUNE   - Delete branches gone on GitHub\n"
        printf " 13) DELETE BRANCH   - Manually delete a branch\n"
                read -p "Select command (X to return): " sub_choice
                case "$sub_choice" in
                    1) choice="2" ;;
                    2) choice="3" ;;
                    3) choice="4" ;;
            4) choice="31" ;;
            5) choice="32" ;;
            6) choice="5" ;;
            7) choice="8" ;;
            8) choice="9" ;;
            9) choice="33" ;;
            10) choice="34" ;;
            11) choice="11" ;;
            12) choice="12" ;;
            13) choice="13" ;;
                    [Xx]) continue ;;
                    *) continue ;;
                esac
                ;;
            3)
                printf "\n${YELLOW}${BOLD}[FIX]${NC}\n"
                printf " 1) FIX PULL ISSUES  - Resolve unstaged changes blocking pull\n"
                printf " 2) SYNC FORCE       - Overwrite Local or GitHub (Conflict fix)\n"
        printf " 3) UNDO COMMIT      - Revert last commit (keep files)\n"
        printf " 4) FORCE RESET      - Wipe local and reset to main (CAUTION)\n"
        printf " 5) EMERGENCY        - Abort failed merges / Clear locks\n"
        printf " 6) RESTORE COMMIT   - Checkout, Revert or Reset to a previous commit\n"
        printf " 7) STASH MANAGER    - View, apply, pop, or delete stashes\n"
        printf " 8) FORGET FILE      - Remove file from git cache\n"
                read -p "Select command (X to return): " sub_choice
                case "$sub_choice" in
                    1) choice="30" ;;
                    2) choice="6" ;;
                    3) choice="14" ;;
                    4) choice="15" ;;
                    5) choice="16" ;;
                    6) choice="17" ;;
                    7) choice="23" ;;
                    8) choice="24" ;;
                    [Xx]) continue ;;
                    *) continue ;;
                esac
                ;;
            4)
                printf "\n${YELLOW}${BOLD}[FILES]${NC}\n"
                printf " 1) EXCLUDE SYNC      - Prevent file/pattern from syncing\n"
                printf " 2) EDIT/CREATE FILE - Open file in editor\n"
                printf " 3) DELETE FILE      - Remove a file\n"
                printf " 4) VIEW FILE        - Read file contents\n"
                read -p "Select command (X to return): " sub_choice
                case "$sub_choice" in
                    1) choice="29" ;;
                    2) choice="26" ;;
                    3) choice="27" ;;
                    4) choice="28" ;;
                    [Xx]) continue ;;
                    *) continue ;;
                esac
                ;;
            5)
                printf "\n${YELLOW}${BOLD}[MAINTENANCE]${NC}\n"
                printf " 1) BACKUP POINT     - Create local snapshot branch\n"
        printf " 2) RESTORE BACKUP   - Restore from a local snapshot branch\n"
                read -p "Select command (X to return): " sub_choice
                case "$sub_choice" in
                    1) choice="7" ;;
                    2) choice="25" ;;
                    [Xx]) continue ;;
                    *) continue ;;
                esac
                ;;
            [Ss]|[Qq])
                choice="$main_choice"
                ;;
            *)
                continue
                ;;
        esac
    else
        choice="$CMD_SWITCH"
    fi

    case $choice in
        1) # DASHBOARD
            [[ "$IN_GIT" = false ]] && { printf "${RED}Not in git repo${NC}\n"; read -p "Enter..." junk; continue; }
            clear
            printf "${CYAN}${BOLD}DASHBOARD: $PROJECT_NAME${NC}\n\n"
            git fetch origin --prune 2>/dev/null || true

            # Use more instead of less for BusyBox compatibility
            # Simpler git log flags for BusyBox
            {
                show_git_stats
                printf "\n${BOLD}=== BRANCH INFO ===${NC}\n"
                git branch -vv
                printf "\n${BOLD}=== FILE STATUS ===${NC}\n"
                git status
                printf "\n${BOLD}=== RECENT HISTORY ===${NC}\n"
                git log -n 20 --oneline --graph
            } | more

            read -p "Enter..." junk ;;

        2) # CHECKOUT REPO
            [[ "$IN_GIT" = false ]] && continue
            check_dirty || continue

            printf "${CYAN}Fetching updates from origin...${NC}\n"
            # Capture output to detect new branches
            # || true prevents crash if fetch fails (e.g., network/auth error)
            git fetch origin --prune > /tmp/git_fetch_out 2>&1 || true
            cat /tmp/git_fetch_out

            # Parse for new branches
            # Usually: * [new branch]      feature/foo -> origin/feature/foo
            # $4 is feature/foo
            new_branches=$(grep "\[new branch\]" /tmp/git_fetch_out | awk '{print $4}' || true)
            rm -f /tmp/git_fetch_out

            printf "\n${CYAN}${BOLD}Available Repositories (Branches):${NC}\n"

            # Build list from git branch -r
            i=1
            declare -a repo_list
            # git branch -r output: "  origin/HEAD -> origin/main", "  origin/main"
            while IFS= read -r branch; do
                # Clean up: remove "origin/" prefix
                raw_branch=$(echo "$branch" | sed 's/^[* ]*//')
                clean_branch=$(echo "$raw_branch" | sed 's/origin\///' | awk '{print $1}')

                # Skip HEAD pointer
                [[ "$clean_branch" == "HEAD" || "$raw_branch" == *"->"* ]] && continue

                mark=""
                # Check if clean_branch matches anything in new_branches
                if echo "$new_branches" | grep -q "^$clean_branch$"; then
                    mark=" ${GREEN}(NEW)${NC}"
                fi

                printf " %2d) %s%s\n" "$i" "$clean_branch" "$mark"
                repo_list[$i]="$clean_branch"
                ((i++))
            done < <(git branch -r | grep -v HEAD)

            read -p "Select Repo/Branch (X to cancel): " cr_idx
            [[ "$cr_idx" =~ ^[Xx]$ ]] && continue

            sel_br="${repo_list[$cr_idx]}"
            if [[ -n "$sel_br" ]]; then
                printf "${YELLOW}Checking out $sel_br...${NC}\n"
                git checkout "$sel_br" 2>/dev/null || git checkout -b "$sel_br" "origin/$sel_br"

                # Check if remote branch still exists before pulling
                if git ls-remote --exit-code --heads origin "$sel_br" >/dev/null 2>&1; then
                    git pull origin "$sel_br" || { printf "${RED}Error: Pull failed.${NC}\n"; read -p "Enter..." junk; continue; }
                else
                    printf "${YELLOW}Notice: Remote branch 'origin/%s' is gone.${NC}\n" "$sel_br"
                    git branch --unset-upstream "$sel_br" 2>/dev/null || true
                fi
            else
                printf "${RED}Invalid selection.${NC}\n"
            fi
            read -p "Enter..." junk ;;

        3) # BRANCH EXPLORER
            [[ "$IN_GIT" = false ]] && continue
            check_dirty || continue

            printf "${CYAN}Fetching updates from origin...${NC}\n"
            git fetch origin --prune >/dev/null 2>&1 || true

            get_branch_list_raw "be"
            print_colored_branch_list "be"
            read -p "Select number or name for NEW branch: " be_val
            [[ "$be_val" =~ ^[Xx]$ ]] && continue

            if [[ "$be_val" =~ ^[0-9]+$ ]]; then
                target_branch="${!be_val@}"
                target_branch=$(eval echo "\$be_${be_val}")
                target_branch="${target_branch#remotes/origin/}"
                git checkout "$target_branch" 2>/dev/null || git checkout -b "$target_branch" "origin/$target_branch"

                # Check if remote branch still exists before pulling
                if git ls-remote --exit-code --heads origin "$target_branch" >/dev/null 2>&1; then
                    git pull origin "$target_branch" 2>/dev/null || { printf "${RED}Error: Pull failed.${NC}\n"; read -p "Enter..." junk; continue; }
                else
                    printf "${YELLOW}Notice: Remote branch 'origin/%s' is gone.${NC}\n" "$target_branch"
                    git branch --unset-upstream "$target_branch" 2>/dev/null || true
                fi
            else
                git checkout -b "$be_val" && printf "${GREEN}Branch $be_val created.${NC}\n"
            fi
            read -p "Enter..." junk junk ;;

        4) # QUICK COMMIT
            [[ "$IN_GIT" = false ]] && continue
            git status -s
            read -p "Commit Message (X to cancel): " msg
            [[ "$msg" =~ ^[Xx]$ ]] && continue

            if [[ -n "$msg" ]]; then
                git add . && \
                git commit -m "$msg" && \
                git push origin "$CURRENT_BRANCH" || { printf "${RED}Error: Push failed.${NC}\n"; read -p "Enter..." junk; continue; }
                read -p "Work pushed. Enter..." junk
            fi ;;

        5) # SYNC FETCH
            [[ "$IN_GIT" = false ]] && continue
            git pull origin "$CURRENT_BRANCH" || printf "${RED}Pull failed. Check conflicts/network.${NC}\n"
            read -p "Pull complete. Enter..." junk ;;

        6) # SYNC FORCE
            [[ "$IN_GIT" = false ]] && continue
            git fetch origin || printf "${RED}Fetch failed.${NC}\n"
            printf "1) OVERWRITE LOCAL (Loss of local work)\n2) FORCE PUSH (Loss of GitHub work)\nX) Cancel\n"
            read -p "Action: " fa_choice
            if [[ "$fa_choice" == "1" ]]; then git reset --hard "origin/$CURRENT_BRANCH" || { printf "${RED}Error: Reset failed.${NC}\n"; read -p "Enter..." junk; continue; }; fi
            if [[ "$fa_choice" == "2" ]]; then git branch -f "$CURRENT_BRANCH" || true; git push origin "$CURRENT_BRANCH" --force || { printf "${RED}Error: Force push failed.${NC}\n"; read -p "Enter..." junk; continue; }; fi
            read -p "Sync complete. Enter..." junk ;;

        7) # BACKUP POINT
            [[ "$IN_GIT" = false ]] && continue
            TS=$(date +%Y%m%d_%H%M)
            git branch "backup/${CURRENT_BRANCH}_$TS"
            printf "${GREEN}Backup created.${NC}\n"
            read -p "Enter..." junk ;;

        8) # PREPARE UAT
            [[ "$IN_GIT" = false ]] && continue
            printf "${MAGENTA}Preparing UAT Environment (Force Overwrite Mode)...${NC}\n"
            git stash > /dev/null 2>&1
            get_branch_list_raw "uat"
            print_colored_branch_list "uat"
            read -p "Select Jules' branch to test: " uat_idx
            [[ "$uat_idx" =~ ^[Xx]$ ]] && continue

            jules_br=$(eval echo "\$uat_${uat_idx}")
            jules_br="${jules_br#remotes/origin/}"

            git checkout main && git pull origin main || { printf "${RED}Error: Pull main failed.${NC}\n"; read -p "Enter..." junk; continue; }
            git checkout -B uat

            printf "${YELLOW}Merging and forcing file checkout to bypass untracked errors...${NC}\n"
            if git merge -X theirs "origin/$jules_br" --no-edit; then
                git checkout "origin/$jules_br" -- . 2>/dev/null
                printf "${GREEN}UAT environment is ready.${NC}\n"
            else
                printf "${RED}Merge failed. Check emergency options.${NC}\n"
            fi
            read -p "Enter..." junk ;;

        9) # STAGING PUSH
            [[ "$IN_GIT" = false ]] && continue
            git branch -f dev-stable-backup dev-stable 2>/dev/null
            read -p "Push ${CURRENT_BRANCH} → dev-stable? (y/n): " s_conf

            if [[ "$s_conf" == "y" ]]; then
                git checkout dev-stable 2>/dev/null || git checkout -b dev-stable
                git reset --hard "$CURRENT_BRANCH"
                git push origin dev-stable --force && git checkout "$CURRENT_BRANCH"
            fi
            read -p "Enter..." junk ;;

        33) # REBASE ON MAIN
            [[ "$IN_GIT" = false ]] && continue
            clear
            printf "${CYAN}${BOLD}REBASE ON MAIN${NC}\n\n"
            printf "${YELLOW}Info: Rebasen herschrijft de commit-geschiedenis om deze in een strakke, rechte lijn te plaatsen.${NC}\n"
            printf "Dit is de voorkeursmethode voor individuele ontwikkelaars of wanneer je samenwerkt met een AI agent.\n"
            printf "Het voorkomt onnodige 'merge commits' en houdt de historie schoon en begrijpelijk.\n\n"
            printf "${RED}LET OP: Als je je branch al had gepusht, moet je na deze actie een force push (--force-with-lease) doen.${NC}\n\n"

            read -p "Start rebase van branch '$CURRENT_BRANCH' op origin/main? (y/n): " rb_conf
            if [[ "$rb_conf" == [Yy]* ]]; then
                printf "\n${CYAN}Fetching origin...${NC}\n"
                git fetch origin || true
                printf "${CYAN}Rebasing on origin/main...${NC}\n"
                if git rebase origin/main; then
                    printf "\n${GREEN}Rebase succesvol voltooid!${NC}\n"
                    read -p "Wil je direct een force push (--force-with-lease) uitvoeren? (y/n): " fpush_conf
                    if [[ "$fpush_conf" == [Yy]* ]]; then
                        printf "\n${CYAN}Pushing changes...${NC}\n"
                        git push --force-with-lease origin "$CURRENT_BRANCH" && printf "${GREEN}Push successful!${NC}\n" || printf "${RED}Push failed!${NC}\n"
                    fi
                else
                    printf "\n${RED}Rebase mislukt (conflicten). Los de conflicten op en gebruik 'git rebase --continue'.${NC}\n"
                fi
            fi
            read -p "Enter..." junk ;;

        34) # MILESTONE MERGE
            [[ "$IN_GIT" = false ]] && continue
            clear
            printf "${CYAN}${BOLD}MILESTONE MERGE${NC}\n\n"
            printf "${YELLOW}Info: Een Milestone Merge creëert bewust een merge commit in de historie.${NC}\n"
            printf "Dit is handig voor grote mijlpalen, zodat je duidelijk ziet waar feature X is toegevoegd, "
            printf "of wanneer een rebase te veel complexe conflicten oplevert.\n\n"

            get_branch_list_raw "mm"
            print_colored_branch_list "mm"
            read -p "Selecteer branch om te mergen IN main: " mm_idx
            [[ "$mm_idx" =~ ^[Xx]$ ]] && continue

            # Validate input
            if [[ ! "$mm_idx" =~ ^[0-9]+$ ]]; then
                 printf "${RED}Invalid input.${NC}\n"
                 read -p "Enter..." junk
                 continue
            fi

            # Check range
            if [[ -z "$(eval echo "\${mm_${mm_idx}:-}")" ]]; then
                printf "${RED}Invalid selection.${NC}\n"
                read -p "Enter..." junk
                continue
            fi

            merge_br=$(eval echo "\$mm_${mm_idx}")
            merge_br="${merge_br#remotes/origin/}"

            if [[ "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "master" ]]; then
                printf "\n${YELLOW}Je huidige branch is '$CURRENT_BRANCH'. Voor een milestone merge schakelen we over naar 'main'.${NC}\n"
                read -p "Doorgaan? (y/n): " mm_conf
                [[ "$mm_conf" != [Yy]* ]] && { read -p "Enter..." junk; continue; }

                # Check for unstaged changes
                if ! check_dirty; then
                    printf "${RED}Merge geannuleerd wegens onbewaarde wijzigingen.${NC}\n"
                    read -p "Enter..." junk
                    continue
                fi

                git checkout main && git pull origin main || { printf "${RED}Error: Checkout/Pull main failed.${NC}\n"; read -p "Enter..." junk; continue; }
            fi

            printf "\n${CYAN}Merging '$merge_br' in main met --no-ff...${NC}\n"
            if git merge --no-ff "origin/$merge_br" -m "Merge branch '$merge_br' - Milestone complete"; then
                 printf "\n${GREEN}Merge succesvol!${NC}\n"
                 read -p "Wil je dit direct pushen naar origin? (y/n): " push_conf
                 if [[ "$push_conf" == [Yy]* ]]; then
                     git push origin main && printf "${GREEN}Push successful!${NC}\n" || printf "${RED}Push failed!${NC}\n"
                 fi
            else
                 printf "\n${RED}Merge failed. Los de conflicten op.${NC}\n"
            fi
            read -p "Enter..." junk ;;

        11) # RELEASE TAG
            [[ "$IN_GIT" = false ]] && continue
            git tag -l | tail -n 5
            read -p "New version tag: " v_tag

            if [[ -n "$v_tag" ]]; then
                git tag -a "$v_tag" -m "Release $v_tag" && git push origin "$v_tag"
            fi
            read -p "Enter..." junk ;;

        12) # CLEANUP PRUNE
            [[ "$IN_GIT" = false ]] && continue
            git fetch origin --prune || true
            # || true prevents script exit if grep finds nothing (set -e)
            GONE=$(git branch -vv | sed 's/^[* ]*//' | grep ': gone]' | awk '{print $1}' || true)

            if [[ -n "$GONE" ]]; then
                echo "$GONE" | xargs git branch -D || true
                printf "${GREEN}Pruned dead branches.${NC}\n"
            else
                printf "Nothing to prune.\n"
            fi
            read -p "Enter..." junk ;;

        13) # DELETE BRANCH
            [[ "$IN_GIT" = false ]] && continue
            get_branch_list_raw "dk"
            print_colored_branch_list "dk"
            read -p "Number to DELETE (CAUTION): " dk_idx
            [[ "$dk_idx" =~ ^[Xx]$ ]] && continue

            # Validate input
            if [[ ! "$dk_idx" =~ ^[0-9]+$ ]]; then
                 printf "${RED}Invalid input.${NC}\n"
                 read -p "Enter..." junk
                 continue
            fi

            # Check range (avoid unbound variable crash)
            if [[ -z "$(eval echo "\${dk_${dk_idx}:-}")" ]]; then
                printf "${RED}Invalid selection.${NC}\n"
                read -p "Enter..." junk
                continue
            fi

            del_br=$(eval echo "\$dk_${dk_idx}")
            if [[ "$del_br" != "$CURRENT_BRANCH" ]] && [[ -n "$del_br" ]]; then
                if [[ "$del_br" == remotes/origin/* ]]; then
                    remote_br="${del_br#remotes/origin/}"
                    git push origin --delete "$remote_br" || true
                    printf "${RED}Remote branch $remote_br deleted.${NC}\n"
                else
                    git branch -D "$del_br" || true
                    printf "${RED}Branch $del_br deleted.${NC}\n"
                fi
            fi
            read -p "Enter..." junk ;;

        14) # UNDO COMMIT
            [[ "$IN_GIT" = false ]] && continue
            git reset --soft HEAD~1
            printf "${YELLOW}Last commit undone. Changes are kept in stage (files kept)${NC}\n"
            read -p "Enter..." junk ;;

        15) # FORCE RESET
            [[ "$IN_GIT" = false ]] && continue
            if [[ $IS_PROD -eq 1 ]]; then
                printf "${RED}${BOLD}!!! WARNING: YOU ARE IN PROD ENVIRONMENT !!!${NC}\n"
            fi

            read -p "Type PROCEED to wipe local and reset to main: " p_conf
            if [[ "$p_conf" == "PROCEED" ]]; then
                git checkout main && \
                git reset --hard origin/main && \
                git clean -fd
                printf "${GREEN}Reset successful.${NC}\n"
            fi
            read -p "Enter..." junk ;;

        16) # EMERGENCY
            [[ "$IN_GIT" = false ]] && continue
            printf "1) ABORT MERGE 2) CLEAR LOCKS 3) POP STASH\n"
            read -p "Action: " em_c

            [[ "$em_c" == "1" ]] && git merge --abort
            [[ "$em_c" == "2" ]] && rm -f .git/index.lock
            [[ "$em_c" == "3" ]] && git stash pop
            read -p "Enter..." junk ;;

        17) # RESTORE COMMIT
            [[ "$IN_GIT" = false ]] && continue
            clear
            printf "${CYAN}${BOLD}RESTORE COMMIT${NC}\n\n"
            printf "${YELLOW}Recent Commits:${NC}\n"
            git log --oneline -n 30 | more
            printf "\n"

            read -p "Enter commit hash to restore to (X to cancel): " target_commit
            [[ "$target_commit" =~ ^[Xx]$ ]] && continue

            if [[ -z "$target_commit" ]] || ! git rev-parse --verify --quiet "$target_commit" > /dev/null; then
                printf "${RED}Invalid commit hash.${NC}\n"
                read -p "Enter..." junk
                continue
            fi

            printf "\n${CYAN}Options for commit ${target_commit}:${NC}\n"
            printf " 1) Checkout (Detached HEAD to test/look around)\n"
            printf " 2) Revert (Create new commit undoing changes)\n"
            printf " 3) Reset branch to here (Discard all changes after this commit)\n"
            printf " X) Cancel\n"

            read -p "Select action: " restore_choice

            case "$restore_choice" in
                1)
                    git checkout "$target_commit"
                    ;;
                2)
                    git revert "$target_commit" --no-edit
                    ;;
                3)
                    printf "${RED}WARNING: This will discard all commits after ${target_commit}.${NC}\n"
                    read -p "Type 'PROCEED' to confirm: " r_conf
                    if [[ "$r_conf" == "PROCEED" ]]; then
                        git reset --hard "$target_commit"
                        printf "${GREEN}Reset successful.${NC}\n"
                    else
                        printf "${YELLOW}Aborted.${NC}\n"
                    fi
                    ;;
                *)
                    continue
                    ;;
            esac
            read -p "Enter..." junk ;;

        18) # DIFF VIEWER
            [[ "$IN_GIT" = false ]] && continue
            clear
            printf "${CYAN}${BOLD}DIFF VIEWER${NC}\n\n"
            printf "Compare:\n"
            printf "1) Current changes (unstaged)\n"
            printf "2) Staged changes\n"
            printf "3) Compare two branches\n"
            printf "4) Compare with specific commit\n"
            read -p "Select: " diff_choice

            case "$diff_choice" in
                1) git diff | more ;;
                2) git diff --cached | more ;;
                3)
                    get_branch_list_raw "diff"
                    print_colored_branch_list "diff"
                    read -p "First branch: " b1
                    [[ "$b1" =~ ^[Xx]$ ]] && continue

                    if [[ ! "$b1" =~ ^[0-9]+$ ]] || [[ -z "$(eval echo "\${diff_${b1}:-}")" ]]; then
                        printf "${RED}Invalid selection.${NC}\n"
                        read -p "Enter..." junk
                        continue
                    fi

                    read -p "Second branch: " b2
                    [[ "$b2" =~ ^[Xx]$ ]] && continue

                    if [[ ! "$b2" =~ ^[0-9]+$ ]] || [[ -z "$(eval echo "\${diff_${b2}:-}")" ]]; then
                        printf "${RED}Invalid selection.${NC}\n"
                        read -p "Enter..." junk
                        continue
                    fi

                    br1=$(eval echo "\$diff_${b1}")
                    br2=$(eval echo "\$diff_${b2}")
                    git diff "${br1}".."${br2}" | more
                    ;;
                4)
                    git log --oneline -n 10
                    read -p "Commit hash: " commit_hash
                    git diff "${commit_hash}" | more
                    ;;
            esac
            read -p "Enter..." junk ;;

        19) # FILE HISTORY
            [[ "$IN_GIT" = false ]] && continue
            clear
            printf "${CYAN}${BOLD}FILE HISTORY${NC}\n\n"
            read -p "Enter filename (with path): " filename

            if [[ -n "$filename" ]]; then
                printf "\n${YELLOW}Commits affecting: ${filename}${NC}\n\n"
                git log --follow --oneline -- "$filename" | more
                printf "\n"
                read -p "See detailed changes? (y/n): " show_detail
                if [[ "$show_detail" == "y" ]]; then
                    git log --follow -p -- "$filename" | more
                fi
            fi
            read -p "Enter..." junk ;;

        20) # SEARCH CODE
            [[ "$IN_GIT" = false ]] && continue
            clear
            printf "${CYAN}${BOLD}CODE SEARCH${NC}\n\n"
            read -p "Search for text: " search_text

            if [[ -n "$search_text" ]]; then
                printf "\n${YELLOW}Searching for: '${search_text}'${NC}\n\n"
                git grep -n "$search_text" 2>/dev/null | more || {
                    printf "${YELLOW}Not found in tracked files. Searching all files...${NC}\n"
                    grep -r -n "$search_text" . 2>/dev/null | grep -v ".git/" | more
                }
            fi
            read -p "Enter..." junk ;;

        21) # COMMIT FINDER
            [[ "$IN_GIT" = false ]] && continue
            clear
            printf "${CYAN}${BOLD}COMMIT FINDER${NC}\n\n"
            read -p "Search commit messages for: " search_msg

            if [[ -n "$search_msg" ]]; then
                printf "\n${YELLOW}Commits containing: '${search_msg}'${NC}\n\n"
                git log --all --oneline --grep="$search_msg" | more
                printf "\n"
                read -p "Show full details? (y/n): " show_full
                if [[ "$show_full" == "y" ]]; then
                    git log --all --grep="$search_msg" | more
                fi
            fi
            read -p "Enter..." junk ;;

        22) # BRANCH COMPARE
            [[ "$IN_GIT" = false ]] && continue
            clear
            printf "${CYAN}${BOLD}BRANCH COMPARISON${NC}\n\n"
            get_branch_list_raw "cmp"
            print_colored_branch_list "cmp"

            read -p "Base branch (what you have): " base_idx
            [[ "$base_idx" =~ ^[Xx]$ ]] && continue

            if [[ ! "$base_idx" =~ ^[0-9]+$ ]] || [[ -z "$(eval echo "\${cmp_${base_idx}:-}")" ]]; then
                printf "${RED}Invalid selection.${NC}\n"
                read -p "Enter..." junk
                continue
            fi

            read -p "Compare branch (what you want to check): " cmp_idx
            [[ "$cmp_idx" =~ ^[Xx]$ ]] && continue

            if [[ ! "$cmp_idx" =~ ^[0-9]+$ ]] || [[ -z "$(eval echo "\${cmp_${cmp_idx}:-}")" ]]; then
                printf "${RED}Invalid selection.${NC}\n"
                read -p "Enter..." junk
                continue
            fi

            base_br=$(eval echo "\$cmp_${base_idx}")
            cmp_br=$(eval echo "\$cmp_${cmp_idx}")
            base_br="${base_br#remotes/origin/}"
            cmp_br="${cmp_br#remotes/origin/}"

            if [[ -n "$base_br" ]] && [[ -n "$cmp_br" ]]; then
                printf "\n${YELLOW}Commits in ${cmp_br} not in ${base_br}:${NC}\n\n"
                git log "${base_br}".."${cmp_br}" --oneline | more
                printf "\n"
                read -p "Show file differences? (y/n): " show_files
                if [[ "$show_files" == "y" ]]; then
                    git diff "${base_br}"..."${cmp_br}" --stat | more
                fi
            fi
            read -p "Enter..." junk ;;

        31) # COMMIT LOCAL
            [[ "$IN_GIT" = false ]] && continue
            git status -s
            read -p "Commit Message (X to cancel): " msg
            [[ "$msg" =~ ^[Xx]$ ]] && continue

            if [[ -n "$msg" ]]; then
                git add . && \
                git commit -m "$msg" || { printf "${RED}Error: Commit failed.${NC}\n"; read -p "Enter..." junk; continue; }
                printf "${GREEN}Changes committed locally.${NC}\n"
                read -p "Enter..." junk
            fi ;;

        32) # AMEND COMMIT
            [[ "$IN_GIT" = false ]] && continue
            printf "${CYAN}${BOLD}AMEND COMMIT${NC}\n\n"
            printf "${YELLOW}Last commit details:${NC}\n"
            git log -1 --stat | more
            printf "\n"

            git status -s
            printf "\n"

            read -p "Do you want to stage and add current local changes to the last commit? (y/n): " add_changes
            if [[ "$add_changes" == "y" ]]; then
                git add .
                printf "${GREEN}Local changes staged.${NC}\n"
            fi

            read -p "Do you want to change the commit message? (y/n): " change_msg
            if [[ "$change_msg" == "y" ]]; then
                read -p "New commit message: " new_msg
                if [[ -n "$new_msg" ]]; then
                    git commit --amend -m "$new_msg" || { printf "${RED}Error: Amend failed.${NC}\n"; read -p "Enter..." junk; continue; }
                    printf "${GREEN}Commit amended with new message.${NC}\n"
                else
                    printf "${RED}Message empty. Amend aborted.${NC}\n"
                fi
            else
                git commit --amend --no-edit || { printf "${RED}Error: Amend failed.${NC}\n"; read -p "Enter..." junk; continue; }
                printf "${GREEN}Commit amended (message kept).${NC}\n"
            fi
            read -p "Enter..." junk ;;

        23) # STASH MANAGER
            [[ "$IN_GIT" = false ]] && continue
            clear
            printf "${CYAN}${BOLD}STASH MANAGER${NC}\n\n"

            stash_count=$(git stash list | wc -l)
            if [[ "$stash_count" -eq 0 ]]; then
                printf "${YELLOW}No stashes found.${NC}\n"
                read -p "Enter..." junk
                continue
            fi

            printf "${YELLOW}Current Stashes:${NC}\n"
            git stash list
            printf "\n"

            printf " 1) View Stash Changes (show)\n"
            printf " 2) Apply Stash (keep in stash list)\n"
            printf " 3) Pop Stash (apply and remove from list)\n"
            printf " 4) Drop Stash (delete specific stash)\n"
            printf " 5) Clear All Stashes (delete ALL)\n"
            printf " X) Cancel\n\n"

            read -p "Select action: " stash_action
            case "$stash_action" in
                1)
                    read -p "Enter stash index (e.g., 0 for stash@{0}): " s_idx
                    if [[ "$s_idx" =~ ^[0-9]+$ ]]; then
                        git stash show -p "stash@{$s_idx}" | more
                    fi
                    ;;
                2)
                    read -p "Enter stash index (e.g., 0 for stash@{0}): " s_idx
                    if [[ "$s_idx" =~ ^[0-9]+$ ]]; then
                        git stash apply "stash@{$s_idx}"
                    fi
                    ;;
                3)
                    read -p "Enter stash index (e.g., 0 for stash@{0}): " s_idx
                    if [[ "$s_idx" =~ ^[0-9]+$ ]]; then
                        git stash pop "stash@{$s_idx}"
                    fi
                    ;;
                4)
                    read -p "Enter stash index to drop (e.g., 0 for stash@{0}): " s_idx
                    if [[ "$s_idx" =~ ^[0-9]+$ ]]; then
                        git stash drop "stash@{$s_idx}"
                        printf "${GREEN}Stash stash@{$s_idx} dropped.${NC}\n"
                    fi
                    ;;
                5)
                    read -p "Are you sure you want to delete ALL stashes? (y/n): " clear_conf
                    if [[ "$clear_conf" == "y" ]]; then
                        git stash clear
                        printf "${GREEN}All stashes cleared.${NC}\n"
                    fi
                    ;;
            esac
            read -p "Enter..." junk ;;

        24) # FORGET CACHED FILE
            [[ "$IN_GIT" = false ]] && continue
            read -p "Enter file to forget (git rm --cached): " file_to_forget
            if [[ -n "$file_to_forget" ]]; then
                git rm --cached "$file_to_forget"
                printf "${GREEN}File removed from cache.${NC}\n"
            fi
            read -p "Enter..." junk ;;

        25) # RESTORE BACKUP
            [[ "$IN_GIT" = false ]] && continue
            clear
            printf "${CYAN}${BOLD}RESTORE BACKUP${NC}\n\n"

            # Find backup branches
            backup_branches=()
            while IFS= read -r branch; do
                [[ -n "$branch" ]] && backup_branches+=("$branch")
            done < <(git branch --list "backup/*" | sed 's/^[* ]*//')

            if [[ ${#backup_branches[@]} -eq 0 ]]; then
                printf "${YELLOW}No backup branches found.${NC}\n"
                read -p "Enter..." junk
                continue
            fi

            printf "${YELLOW}Available Backups:${NC}\n"
            for i in "${!backup_branches[@]}"; do
                printf " %2d) %s\n" "$((i+1))" "${backup_branches[$i]}"
            done

            read -p "Select backup to restore (X to cancel): " backup_idx
            [[ "$backup_idx" =~ ^[Xx]$ ]] && continue

            if [[ ! "$backup_idx" =~ ^[0-9]+$ ]] || [[ "$backup_idx" -lt 1 ]] || [[ "$backup_idx" -gt "${#backup_branches[@]}" ]]; then
                printf "${RED}Invalid selection.${NC}\n"
                read -p "Enter..." junk
                continue
            fi

            selected_backup="${backup_branches[$((backup_idx-1))]}"
            printf "\n${CYAN}Selected: ${selected_backup}${NC}\n"
            printf "1) Checkout this backup as active branch\n"
            printf "2) Overwrite 'main' locally with this backup\n"
            printf "3) Overwrite 'main' locally AND force push to GitHub\n"
            printf "X) Cancel\n"

            read -p "Choose action: " restore_action
            case "$restore_action" in
                1)
                    git checkout "$selected_backup"
                    printf "${GREEN}Checked out ${selected_backup}.${NC}\n"
                    ;;
                2)
                    git checkout main
                    git reset --hard "$selected_backup"
                    printf "${GREEN}'main' has been overwritten with ${selected_backup} locally.${NC}\n"
                    ;;
                3)
                    git checkout main
                    git reset --hard "$selected_backup"
                    git push origin main --force
                    printf "${GREEN}'main' has been overwritten locally and forcefully pushed to GitHub.${NC}\n"
                    ;;
                *)
                    printf "${YELLOW}Action cancelled.${NC}\n"
                    ;;
            esac
            read -p "Enter..." junk ;;

        29) # EXCLUDE SYNC
            [[ "$IN_GIT" = false ]] && continue
            clear
            printf "${CYAN}${BOLD}EXCLUDE SYNC${NC}\n\n"
            printf "This will prevent a file, folder, or pattern from being overwritten\n"
            printf "by git sync/checkout, and ensure it remains untracked in GitHub.\n\n"
            read -p "Enter file, folder, or pattern to exclude (e.g. config.php, logs/, *.tmp): " exclude_pattern
            if [[ -n "$exclude_pattern" ]]; then
                # Check if it is already in .gitignore
                if ! grep -qxF "$exclude_pattern" .gitignore 2>/dev/null; then
                    echo -e "\n$exclude_pattern" >> .gitignore
                    printf "${GREEN}Added '%s' to .gitignore${NC}\n" "$exclude_pattern"
                else
                    printf "${YELLOW}'%s' is already in .gitignore${NC}\n" "$exclude_pattern"
                fi

                # Remove from git cache (stops tracking but keeps local file)
                # Suppress error if the file wasn't tracked anyway
                git rm -r --cached "$exclude_pattern" 2>/dev/null || true
                printf "${GREEN}Removed '%s' from git tracking (kept locally).${NC}\n" "$exclude_pattern"

                # Stage .gitignore
                git add .gitignore

                # Ask to commit
                read -p "Commit this exclusion now? (y/n): " do_commit
                if [[ "$do_commit" == [Yy]* ]]; then
                    git commit -m "chore: exclude $exclude_pattern from sync" -q
                    printf "${GREEN}Committed exclusion of '%s'.${NC}\n" "$exclude_pattern"
                else
                    printf "${YELLOW}Changes staged. Don't forget to commit them later.${NC}\n"
                fi
            fi
            read -p "Enter..." junk ;;

        30) # FIX PULL ISSUES
            [[ "$IN_GIT" = false ]] && continue
            clear
            printf "${CYAN}${BOLD}FIX PULL ISSUES${NC}\n\n"

            # Check if there are unstaged changes
            if [[ -z $(git status --porcelain) ]]; then
                printf "${GREEN}No unstaged changes found. You can pull safely.${NC}\n"
                printf "${CYAN}Attempting to pull from origin ${CURRENT_BRANCH}...${NC}\n"
                git pull origin "$CURRENT_BRANCH" || { printf "${RED}Pull failed.${NC}\n"; }
            else
                printf "${YELLOW}You have unstaged changes blocking the pull.${NC}\n\n"
                printf "How would you like to resolve this?\n"
                printf " 1) Stash changes, pull, and restore them (Recommended)\n"
                printf " 2) Commit changes, then pull\n"
                printf " 3) Discard local changes and pull (WARNING: Loses work)\n"
                printf " X) Cancel\n\n"

                read -p "Select action: " pull_fix_choice
                case "$pull_fix_choice" in
                    1)
                        printf "\n${YELLOW}Stashing local changes...${NC}\n"
                        git stash
                        printf "${CYAN}Pulling from origin ${CURRENT_BRANCH}...${NC}\n"
                        git pull origin "$CURRENT_BRANCH" || { printf "${RED}Pull failed.${NC}\n"; read -p "Enter..." junk; continue; }
                        printf "${YELLOW}Popping stash...${NC}\n"
                        git stash pop || true
                        printf "${GREEN}Process completed.${NC}\n"
                        ;;
                    2)
                        printf "\n${YELLOW}Committing changes...${NC}\n"
                        read -p "Enter commit message: " fix_commit_msg
                        if [[ -z "$fix_commit_msg" ]]; then
                            fix_commit_msg="chore: auto-commit before pull"
                        fi
                        git add -A
                        git commit -m "$fix_commit_msg" -q
                        printf "${CYAN}Pulling from origin ${CURRENT_BRANCH}...${NC}\n"
                        git pull origin "$CURRENT_BRANCH" --no-rebase || { printf "${RED}Pull failed. You may need to resolve merge conflicts.${NC}\n"; read -p "Enter..." junk; continue; }
                        printf "${GREEN}Process completed.${NC}\n"
                        ;;
                    3)
                        printf "\n${RED}WARNING: This will permanently destroy all uncommitted changes.${NC}\n"
                        read -p "Are you absolutely sure? (y/N): " confirm_discard
                        if [[ "$confirm_discard" == [Yy]* ]]; then
                            printf "${YELLOW}Discarding local changes...${NC}\n"
                            git reset --hard HEAD
                            git clean -fd
                            printf "${CYAN}Pulling from origin ${CURRENT_BRANCH}...${NC}\n"
                            git pull origin "$CURRENT_BRANCH" || { printf "${RED}Pull failed.${NC}\n"; }
                            printf "${GREEN}Process completed.${NC}\n"
                        else
                            printf "${YELLOW}Cancelled.${NC}\n"
                        fi
                        ;;
                    [Xx])
                        printf "${YELLOW}Cancelled.${NC}\n"
                        ;;
                    *)
                        printf "${RED}Invalid selection.${NC}\n"
                        ;;
                esac
            fi
            read -p "Enter..." junk ;;

        26) # EDIT/CREATE FILE
            clear
            printf "${CYAN}${BOLD}EDIT/CREATE FILE${NC}\n\n"
            read -p "Enter filename (with path): " filepath
            if [[ -n "$filepath" ]]; then
                ${EDITOR:-nano} "$filepath"
            fi
            ;;

        27) # DELETE FILE
            clear
            printf "${CYAN}${BOLD}DELETE FILE${NC}\n\n"
            read -p "Enter filename to delete: " filepath
            if [[ -f "$filepath" ]]; then
                rm -i "$filepath"
            else
                printf "${RED}File not found: $filepath${NC}\n"
                read -p "Enter..." junk
            fi
            ;;

        28) # VIEW FILE
            clear
            printf "${CYAN}${BOLD}VIEW FILE${NC}\n\n"
            read -p "Enter filename to view: " filepath
            if [[ -f "$filepath" ]]; then
                cat "$filepath" | more
            else
                printf "${RED}File not found: $filepath${NC}\n"
                read -p "Enter..." junk
            fi
            ;;

        [Ss]) # SETUP
            clear
            printf "${YELLOW}Environment Setup${NC}\n"
            printf "Current .env: ${ENV_FILE}\n\n"

            printf "1) Edit current .env\n"
            printf "2) Create new .env from template\n"
            printf "3) Show current configuration\n"
            printf "4) Install Aliases (Multi-Shell Support)\n"
            printf "X) Cancel\n\n"
            read -p "Choose option: " setup_choice

            case "$setup_choice" in
                1)
                    ${EDITOR:-nano} "$ENV_FILE"
                    printf "${GREEN}Reloading configuration...${NC}\n"
                    load_env
                    ;;
                2)
                    if [[ -f "$ENV_FILE" ]]; then
                        printf "\n${YELLOW}=== CURRENT REQUIRED INFO ===${NC}\n"
                        # Parse only REQUIRED fields for display
                        grep -E "^(GITHUB_TOKEN|GITHUB_USERNAME|GITHUB_EMAIL|PATH_ROOT)=" "$ENV_FILE" | while IFS='=' read -r key value; do
                            value="${value%\"}"
                            value="${value#\"}"
                            printf "  ${CYAN}%-15s${NC}: %s\n" "$key" "$value"
                        done
                        printf "${YELLOW}=============================${NC}\n\n"

                        read -p "Existing configuration found. Use this configuration (and cancel overwrite)? (y/n): " use_existing
                        if [[ "$use_existing" == "y" ]]; then
                            printf "${GREEN}Keeping existing configuration.${NC}\n"
                            read -p "Enter..." junk
                            continue
                        fi
                    fi

                    if [[ -f "$ENV_EXAMPLE" ]]; then
                        read -p "This will overwrite current .env. Continue? (y/n): " confirm
                        if [[ "$confirm" == "y" ]]; then
                            cp "$ENV_EXAMPLE" "$ENV_FILE"
                            printf "${GREEN}Created new .env from template${NC}\n"
                            printf "${YELLOW}Please edit and configure it now${NC}\n"
                            ${EDITOR:-nano} "$ENV_FILE"
                            load_env
                        fi
                    else
                        printf "${RED}.env.example not found at: ${ENV_EXAMPLE}${NC}\n"
                    fi
                    ;;
                3)
                    printf "\n${CYAN}Current Configuration:${NC}\n"
                    printf "  GitHub User: ${GITHUB_USERNAME}\n"
                    printf "  GitHub Email: ${GITHUB_EMAIL}\n"
                    printf "  GitHub Token: $([ -n "$GITHUB_TOKEN" ] && echo "***configured***" || echo "NOT SET")\n"
                    printf "  PATH_ROOT: ${PATH_ROOT}\n"
                    printf "  PATH_PROD: ${PATH_PROD}\n"
                    printf "  PATH_DEV: ${PATH_DEV}\n"
                    printf "  PATH_TEST: ${PATH_TEST}\n"
                    ;;
                4)
                     # Re-use the master dev-tools script if available, or simple local alias
                     ROOT_DIR=$(dirname "$SCRIPT_DIR")
                     if [[ -f "$ROOT_DIR/dev-tools.sh" ]]; then
                         printf "${CYAN}Launching Master Dev Tools Setup...${NC}\n"
                         "$ROOT_DIR/dev-tools.sh"
                     else
                         printf "${YELLOW}Master Dev Tools script not found. Please run it from root.${NC}\n"
                     fi
                     read -p "Enter..." junk
                     ;;
                [Xx]) ;;
            esac
            read -p "Enter..." junk ;;

        [Qq]) clear; exit 0 ;;
        *) sleep 0.1 ;;
    esac

    # Exit if running in command-line switch mode
    if [[ -n "$CMD_SWITCH" ]]; then
        exit 0
    fi
done
