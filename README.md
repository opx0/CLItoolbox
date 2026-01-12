# 📦 devbox

A portable developer toolbox combining CLI automation scripts and infrastructure templates.

**Works on:** Arch, Debian/Ubuntu, Fedora, and other major Linux distros.

---

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/yourusername/devbox.git
cd devbox

# Run the installer (adds devbox to PATH)
./install.sh

# Or manually add to PATH
echo 'export PATH="$HOME/path/to/devbox/cli:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

---

## 📁 Structure

```
devbox/
├── lib/                    # Shared bash utilities
│   ├── common.sh           # Colors, logging, prompts
│   ├── distro.sh           # OS/package manager detection
│   └── desktop.sh          # X11/Wayland detection
│
├── cli/                    # CLI automation scripts
│   ├── clean/
│   │   └── system.sh       # Portable system cleaner
│   ├── wifi/
│   │   ├── switch.sh       # WiFi network switcher
│   │   └── toggle.sh       # WiFi on/off toggle
│   ├── screenshot/
│   │   ├── capture.sh      # Screenshot (X11 + Wayland)
│   │   └── click-capture.sh # Screenshot + click automation
│   └── utils/
│       ├── node-clean.sh   # Clean node_modules
│       ├── font.sh         # Font utilities
│       └── yt-playlist.py  # YouTube playlist extractor
│
├── infra/                  # Infrastructure templates
│   ├── docker/
│   │   ├── mongodb/        # MongoDB 7 stack
│   │   ├── postgres/       # PostgreSQL 16 stack
│   │   ├── ollama/         # Ollama AI stack
│   │   └── open-webui/     # Open WebUI for Ollama
│   └── vm/
│       └── qemu.sh         # QEMU VM manager
│
├── quiz/                   # Go-based quiz automation
│   ├── main.go
│   ├── go.mod
│   └── go.sum
│
└── archive/                # Deprecated/old scripts
```

---

## 🛠️ CLI Tools

### System Cleaner
```bash
# Clean system caches, orphan packages, browser cache, dev caches
./cli/clean/system.sh

# Dry run (see what would be deleted)
./cli/clean/system.sh --dry-run
```

**Cleans:**
- Package cache (pacman/apt/dnf)
- AUR cache (yay/paru)
- Orphan packages
- Journal logs (> 3 days)
- Browser caches
- Dev caches (npm, cargo, gradle, pip, etc.)
- Python caches (__pycache__)
- Temp files

### WiFi Manager
```bash
# Switch to next available network
./cli/wifi/switch.sh --switch

# Watch for disconnections and auto-reconnect
./cli/wifi/switch.sh --watch
```

### Screenshot Tools
```bash
# Take a screenshot (auto-detects grim/maim/scrot)
./cli/screenshot/capture.sh

# Select region
./cli/screenshot/capture.sh --region

# Screenshot + click automation (for quizzes, etc.)
./cli/screenshot/click-capture.sh 10  # Take 10 screenshots
```

---

## 🐳 Docker Stacks

### MongoDB
```bash
cd infra/docker/mongodb
cp .env.example .env
# Edit .env with your credentials
docker compose up -d
```

### PostgreSQL
```bash
cd infra/docker/postgres
cp .env.example .env
# Edit .env with your credentials
docker compose up -d
```

### AI Stack (Ollama + Open WebUI)
```bash
# Start Ollama first
cd infra/docker/ollama
docker compose up -d

# Then Open WebUI
cd ../open-webui
docker compose up -d

# Access at http://localhost:3000
```

---

## 🖥️ QEMU VM Manager

Full-featured VM manager with UEFI support, overlay disks, and interactive setup.

```bash
# Start/create a VM (interactive)
./infra/vm/qemu.sh

# Install from ISO
./infra/vm/qemu.sh install

# Run in snapshot mode (changes discarded)
./infra/vm/qemu.sh snapshot

# SSH into running VM
./infra/vm/qemu.sh ssh

# Check status
./infra/vm/qemu.sh status

# Reset VM (keep base image)
./infra/vm/qemu.sh reset
```

---

## 🔧 Shared Libraries

Use the shared libraries in your own scripts:

```bash
#!/usr/bin/env bash
source "/path/to/devbox/lib/common.sh"
source "/path/to/devbox/lib/distro.sh"
source "/path/to/devbox/lib/desktop.sh"

# Now you have access to:
log_info "Starting..."
log_ok "Done!"
log_warn "Warning!"
log_error "Error!"

distro=$(detect_distro)      # arch, debian, ubuntu, fedora...
pkg_mgr=$(detect_pkg_manager) # pacman, apt, dnf...
session=$(detect_session)     # wayland, x11, tty

ask_yes "Continue?"
take_screenshot "$output_path"
simulate_click "left"
```

---

## ⌨️ Hyprland Keybindings

Add to `~/.config/hypr/hyprland.conf`:

```ini
# WiFi management
bind = $mainMod+CTRL, W, exec, ~/devbox/cli/wifi/switch.sh --watch
bind = $mainMod+CTRL, S, exec, ~/devbox/cli/wifi/switch.sh --switch

# Screenshots
bind = , Print, exec, ~/devbox/cli/screenshot/capture.sh
bind = SHIFT, Print, exec, ~/devbox/cli/screenshot/capture.sh --region
```

Then reload: `hyprctl reload`

---

## 📋 Requirements

### CLI Tools
- **bash** 4.0+
- **NetworkManager** (for wifi scripts)
- **Screenshot:** grim (Wayland) or maim/scrot (X11)
- **Click automation:** ydotool (Wayland) or xdotool (X11)
- **PDF conversion:** ImageMagick (optional)

### Infrastructure
- **Docker** + Docker Compose
- **QEMU** + OVMF (for VMs)

### Quiz Automation (Go)
```bash
cd quiz
go build -o automate .
./automate 10
```

---

## 📄 License

MIT License - feel free to use and modify.
