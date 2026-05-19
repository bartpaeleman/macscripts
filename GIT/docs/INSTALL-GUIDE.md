# Quick Installation Guide

## 🚀 Individual Installation

```bash
# 1. Clone or download
git clone https://github.com/yourusername/git-master.git
cd git-master

# 2. Make scripts executable
chmod +x install.sh git-master.sh

# 3. Run installer
./install.sh
```

The installer will:
- Detect your platform (QNAP/macOS/Linux)
- Ask for GitHub credentials
- Configure paths
- Set up persistence (QNAP) or aliases (macOS)
- Validate your GitHub connection

---

## 👥 Team Deployment

### Option 1: Pre-configured .env in Repository

**For Team Admin:**
```bash
# 1. Create team .env
cp .env.example .env

# 2. Configure shared settings
nano .env
# Set PATH_ROOT and other team-wide settings
# Leave GITHUB_TOKEN and GITHUB_USERNAME empty

# 3. Rename to indicate it's a team template
mv .env .env.team

# 4. Commit to repository (if safe/private repo)
git add .env.team
git commit -m "Add team configuration template"
git push
```

**For Team Members:**
```bash
# 1. Clone repository
git clone https://github.com/yourteam/git-master.git
cd git-master

# 2. Use team template
cp .env.team .env

# 3. Add your personal credentials
nano .env
# Add your GITHUB_TOKEN and GITHUB_USERNAME

# 4. Run installer
chmod +x install.sh
./install.sh
# Choose 'y' when asked to use repository .env
```

### Option 2: Separate Config Repository

**Setup:**
```bash
# Create private config repo
team-configs/
├── git-master.env
└── README.md

# Team members:
cp ~/team-configs/git-master.env ~/git-master/.env
cd ~/git-master
./install.sh
```

---

## ⚡ Quick Start After Installation

```bash
# Start Git Master
./git-master.sh

# Or if aliases are set up:
gitmaster  # QNAP/macOS with aliases

# First steps in the menu:
# - Press P/D/T to navigate environments
# - Press 0 to clone a repository
# - Press 1 to view dashboard
```

---

## 🔐 Security Checklist

- [ ] Never commit `.env` with real tokens
- [ ] Use `.env.example` or `.env.team` for templates only
- [ ] Each user creates their own GitHub token
- [ ] Set file permissions: `chmod 600 .env`
- [ ] Add `.env` to `.gitignore` (already included)
- [ ] Rotate tokens every 90 days

---

## 🛠 Platform-Specific Notes

### QNAP
- Installer adds to `/etc/profile` for persistence
- Creates aliases: `gitmaster`, `prod`, `dev`, `test`
- Survives reboots automatically

### macOS
- Installer adds aliases to `~/.zshrc` or `~/.bashrc`
- Run `source ~/.zshrc` to activate immediately
- May need to grant terminal full disk access

### Linux
- Similar to macOS setup
- Uses `~/.bashrc` for aliases
- Works with any Bash-compatible shell

---

## 📞 Support

**Common Issues:**
- "Authentication failed" → Check token in `.env`
- "Not in git repo" → Navigate to a project first
- "Permission denied" → Run `chmod +x *.sh`

**Need Help?**
- Check README.md for full documentation
- Review CHANGELOG.md for version changes
- Open issue on GitHub repository
