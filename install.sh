#!/usr/bin/env bash
# =============================================================================
# devbox/install.sh — Add devbox to your PATH
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
C_GREEN=$'\033[1;32m'
C_CYAN=$'\033[1;36m'
C_YELLOW=$'\033[1;33m'
C_RESET=$'\033[0m'

echo "${C_CYAN}📦 devbox installer${C_RESET}"
echo ""

# Detect shell
SHELL_NAME="$(basename "$SHELL")"
case "$SHELL_NAME" in
    zsh)
        RC_FILE="$HOME/.zshrc"
        ;;
    bash)
        RC_FILE="$HOME/.bashrc"
        ;;
    fish)
        RC_FILE="$HOME/.config/fish/config.fish"
        ;;
    *)
        echo "${C_YELLOW}Unknown shell: $SHELL_NAME${C_RESET}"
        echo "Please manually add the following to your shell config:"
        echo ""
        echo "  export PATH=\"$SCRIPT_DIR:\$PATH\""
        exit 0
        ;;
esac

# Check if already installed
if grep -q "devbox" "$RC_FILE" 2>/dev/null; then
    echo "${C_YELLOW}⚠ devbox already in $RC_FILE${C_RESET}"
    echo ""
    echo "Current PATH entries:"
    grep "devbox" "$RC_FILE"
    exit 0
fi

# Add to PATH
echo "" >> "$RC_FILE"
echo "# devbox - developer toolbox" >> "$RC_FILE"
echo "export PATH=\"$SCRIPT_DIR:\$PATH\"" >> "$RC_FILE"
echo "export PATH=\"$SCRIPT_DIR/cli/clean:\$PATH\"" >> "$RC_FILE"
echo "export PATH=\"$SCRIPT_DIR/cli/wifi:\$PATH\"" >> "$RC_FILE"
echo "export PATH=\"$SCRIPT_DIR/cli/screenshot:\$PATH\"" >> "$RC_FILE"
echo "export PATH=\"$SCRIPT_DIR/cli/utils:\$PATH\"" >> "$RC_FILE"
echo "export PATH=\"$SCRIPT_DIR/infra/vm:\$PATH\"" >> "$RC_FILE"

echo "${C_GREEN}✓ Added devbox to $RC_FILE${C_RESET}"
echo ""
echo "Reload your shell config:"
echo "  ${C_CYAN}source $RC_FILE${C_RESET}"
echo ""
echo "Or restart your terminal."
echo ""
echo "Available commands:"
echo "  ${C_GREEN}system.sh${C_RESET}        - Clean system caches"
echo "  ${C_GREEN}switch.sh${C_RESET}        - WiFi network switcher"
echo "  ${C_GREEN}capture.sh${C_RESET}       - Take screenshots"
echo "  ${C_GREEN}click-capture.sh${C_RESET} - Screenshot + click automation"
echo "  ${C_GREEN}qemu.sh${C_RESET}          - QEMU VM manager"
echo ""
echo "Run with --help for usage info."
