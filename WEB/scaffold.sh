#!/bin/bash

# ============================================================
# WEB PROJECT SCAFFOLDER
# Generates standard folder structure for PHP/HTML/CSS/JS
# ============================================================

set -e

# Colors
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}=== Web Project Scaffolder ===${NC}"

# 1. Get Project Name
read -p "Enter Project Name (no spaces, alphanumeric): " PROJECT_NAME
if [[ -z "$PROJECT_NAME" ]]; then
    echo -e "${YELLOW}Error: Project name required.${NC}"
    exit 1
fi

if [[ ! "$PROJECT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}Error: Invalid project name. Use only letters, numbers, underscores, and hyphens.${NC}"
    exit 1
fi

# 2. Get Target Directory
read -p "Install path [./$PROJECT_NAME]: " INSTALL_PATH
INSTALL_PATH=${INSTALL_PATH:-"./$PROJECT_NAME"}

if [[ -d "$INSTALL_PATH" ]]; then
    echo -e "${YELLOW}Warning: Directory '$INSTALL_PATH' already exists.${NC}"
    read -p "Continue? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" ]]; then
        exit 0
    fi
fi

# 3. Create Directories
echo -e "\n${CYAN}Creating structure...${NC}"
mkdir -p "$INSTALL_PATH"
mkdir -p "$INSTALL_PATH/assets/css"
mkdir -p "$INSTALL_PATH/assets/js"
mkdir -p "$INSTALL_PATH/assets/img"
mkdir -p "$INSTALL_PATH/includes"
mkdir -p "$INSTALL_PATH/config"

# 4. Create Files

# index.php
cat > "$INSTALL_PATH/index.php" <<EOF
<?php
require_once 'config/config.php';
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${PROJECT_NAME}</title>
    <link rel="stylesheet" href="assets/css/style.css">
</head>
<body>
    <header>
        <h1>Welcome to ${PROJECT_NAME}</h1>
    </header>

    <main>
        <p>Project initialized successfully.</p>
    </main>

    <footer>
        <p>&copy; $(date +%Y) ${PROJECT_NAME}</p>
    </footer>

    <script src="assets/js/app.js"></script>
</body>
</html>
EOF

# style.css
cat > "$INSTALL_PATH/assets/css/style.css" <<EOF
/*
 * Project: ${PROJECT_NAME}
 * Date: $(date +%Y-%m-%d)
 */

:root {
    --primary-color: #3498db;
    --text-color: #333;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    line-height: 1.6;
    color: var(--text-color);
    margin: 0;
    padding: 0;
}

header {
    background: var(--primary-color);
    color: white;
    padding: 1rem;
    text-align: center;
}

main {
    padding: 2rem;
    max-width: 800px;
    margin: 0 auto;
}
EOF

# app.js
cat > "$INSTALL_PATH/assets/js/app.js" <<EOF
/**
 * Project: ${PROJECT_NAME}
 */

document.addEventListener('DOMContentLoaded', () => {
    console.log('${PROJECT_NAME} app loaded');
});
EOF

# config.php
cat > "$INSTALL_PATH/config/config.php" <<EOF
<?php
// Configuration settings

define('APP_NAME', '${PROJECT_NAME}');
define('DB_HOST', 'localhost');
define('DB_USER', 'root');
define('DB_PASS', '');
define('DB_NAME', '${PROJECT_NAME}_db');

// Error reporting (Enable for Dev, Disable for Prod)
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);
?>
EOF

# .gitignore (Basic)
cat > "$INSTALL_PATH/.gitignore" <<EOF
.DS_Store
Thumbs.db
node_modules/
vendor/
.env
EOF

# Set permissions
chmod +x "$INSTALL_PATH/index.php"

echo -e "${GREEN}✓ Project created successfully at: $INSTALL_PATH${NC}"

# 5. Optional Documentation
echo -e "\n${CYAN}--- Documentation ---${NC}"
read -p "Generate README.md? (y/n): " GEN_DOC
if [[ "$GEN_DOC" == "y" ]]; then
    if command -v python3 &> /dev/null; then
        python3 "$(dirname "$0")/generate_readme.py" "$INSTALL_PATH" "$PROJECT_NAME"
    else
        echo -e "${YELLOW}Python3 not found. Skipping README generation.${NC}"
    fi
fi

echo -e "\n${GREEN}All done!${NC}"
echo -e "  To start: cd $INSTALL_PATH"
