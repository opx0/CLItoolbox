#!/usr/bin/env bash
# =============================================================================
# qemu-repro.sh — Noob-Friendly Reproducible QEMU VM Runner
# =============================================================================
# FEATURES:
# - Interactive setup: asks before creating anything
# - Auto-detects and fixes missing resources
# - Zero-knowledge-required operation
# - Graceful error handling with helpful suggestions
# =============================================================================

set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_VERSION="3.0.0"

# -----------------------------------------------------------------------------
# CONFIG
# -----------------------------------------------------------------------------

VM_NAME="${VM_NAME:-arch-repro}"
BASE_DIR="${BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

readonly QEMU_BIN="qemu-system-x86_64"

# Hardware
VM_RAM="${VM_RAM:-4G}"
VM_CPUS="${VM_CPUS:-4}"
readonly DISK_SIZE="${DISK_SIZE:-40G}"

# Paths
QEMU_DIR="$BASE_DIR/qemu"
VM_ROOT="${VM_ROOT:-$HOME/qemu-repro/$VM_NAME}"

DISK_BASE="$QEMU_DIR/base.qcow2"
DISK_OVERLAY="$VM_ROOT/disk.qcow2"

FIRMWARE_DIR="$QEMU_DIR/firmware"
OVMF_CODE="$FIRMWARE_DIR/OVMF_CODE.fd"
OVMF_CODE_HASH="$FIRMWARE_DIR/OVMF_CODE.fd.sha256"
OVMF_VARS_TEMPLATE="$FIRMWARE_DIR/OVMF_VARS.template.fd"
OVMF_VARS="$VM_ROOT/OVMF_VARS.fd"

# Network
SSH_FWD_PORT="${SSH_FWD_PORT:-2222}"
readonly MAC_ADDRESS="${MAC_ADDRESS:-52:54:00:12:34:56}"

# ISO (auto-detected)
ISO_PATH="${ISO_PATH:-}"

# State
readonly LOCKFILE="$VM_ROOT/.qemu.lock"
readonly PIDFILE="$VM_ROOT/.qemu.pid"
readonly LOG_DIR="$VM_ROOT/logs"

# -----------------------------------------------------------------------------
# COLORS (TTY-aware)
# -----------------------------------------------------------------------------

if [[ -t 1 ]] && [[ -t 2 ]]; then
    C_RED=$'\033[1;31m'
    C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
    C_CYAN=$'\033[1;36m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RESET=$'\033[0m'
else
    C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_BOLD='' C_DIM='' C_RESET=''
fi

# -----------------------------------------------------------------------------
# OUTPUT HELPERS
# -----------------------------------------------------------------------------

die()  { echo "${C_RED}✗ $*${C_RESET}" >&2; exit 1; }
warn() { echo "${C_YELLOW}⚠ $*${C_RESET}" >&2; }
ok()   { echo "${C_GREEN}✓ $*${C_RESET}"; }
info() { echo "${C_CYAN}→ $*${C_RESET}"; }
dim()  { echo "${C_DIM}  $*${C_RESET}"; }

# -----------------------------------------------------------------------------
# INTERACTIVE PROMPTS
# -----------------------------------------------------------------------------

# Ask yes/no question, default to yes
ask_yes() {
    local prompt="$1"
    local reply
    
    if [[ "${AUTO_YES:-0}" == "1" ]]; then
        return 0
    fi
    
    echo -n "${C_CYAN}? ${prompt}${C_RESET} [Y/n] "
    read -r reply
    [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

# Ask yes/no question, default to no
ask_no() {
    local prompt="$1"
    local reply
    
    echo -n "${C_YELLOW}? ${prompt}${C_RESET} [y/N] "
    read -r reply
    [[ "$reply" =~ ^[Yy] ]]
}

# Ask for a path with validation
ask_path() {
    local prompt="$1"
    local default="${2:-}"
    local must_exist="${3:-1}"
    local reply
    
    if [[ -n "$default" ]]; then
        echo -n "${C_CYAN}? ${prompt}${C_RESET} [$default]: "
    else
        echo -n "${C_CYAN}? ${prompt}${C_RESET}: "
    fi
    read -r reply
    
    reply="${reply:-$default}"
    
    # Expand ~
    reply="${reply/#\~/$HOME}"
    
    if [[ "$must_exist" == "1" ]] && [[ ! -e "$reply" ]]; then
        warn "Path does not exist: $reply"
        return 1
    fi
    
    echo "$reply"
}

# Select from list
ask_select() {
    local prompt="$1"
    shift
    local options=("$@")
    local i
    
    echo "${C_CYAN}? ${prompt}${C_RESET}"
    for i in "${!options[@]}"; do
        echo "  $((i+1))) ${options[$i]}"
    done
    
    local reply
    echo -n "  Enter number [1]: "
    read -r reply
    reply="${reply:-1}"
    
    if [[ "$reply" =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= ${#options[@]} )); then
        echo "${options[$((reply-1))]}"
    else
        echo "${options[0]}"
    fi
}

# -----------------------------------------------------------------------------
# RESOURCE DETECTION & SETUP
# -----------------------------------------------------------------------------

# Find system OVMF firmware
find_system_ovmf() {
    local paths=(
        "/usr/share/edk2/x64"
        "/usr/share/ovmf/x64"
        "/usr/share/OVMF"
        "/usr/share/qemu"
        "/usr/share/edk2-ovmf/x64"
    )
    
    for base in "${paths[@]}"; do
        if [[ -f "$base/OVMF_CODE.4m.fd" ]]; then
            echo "$base/OVMF_CODE.4m.fd"
            return 0
        elif [[ -f "$base/OVMF_CODE.fd" ]]; then
            echo "$base/OVMF_CODE.fd"
            return 0
        fi
    done
    
    return 1
}

# Find ISO files
find_iso_files() {
    local locations=(
        "$HOME"
        "$HOME/Downloads"
        "$HOME/ISOs"
        "/tmp"
    )
    
    local found=()
    for loc in "${locations[@]}"; do
        if [[ -d "$loc" ]]; then
            while IFS= read -r -d '' iso; do
                found+=("$iso")
            done < <(find "$loc" -maxdepth 2 -name "*.iso" -type f -print0 2>/dev/null | head -z -n 10)
        fi
    done
    
    printf '%s\n' "${found[@]}"
}

# Setup firmware (interactive)
ensure_firmware() {
    if [[ -f "$OVMF_CODE" ]] && [[ -f "$OVMF_VARS_TEMPLATE" ]]; then
        # Verify hash if exists
        if [[ -f "$OVMF_CODE_HASH" ]]; then
            if sha256sum --status -c "$OVMF_CODE_HASH" 2>/dev/null; then
                ok "Firmware: verified"
                return 0
            else
                warn "Firmware hash mismatch!"
                if ask_yes "Re-copy firmware from system?"; then
                    rm -f "$OVMF_CODE" "$OVMF_VARS_TEMPLATE" "$OVMF_CODE_HASH"
                else
                    die "Cannot proceed with corrupted firmware"
                fi
            fi
        else
            ok "Firmware: found (no hash)"
            return 0
        fi
    fi
    
    # Need to setup firmware
    info "Setting up UEFI firmware..."
    
    local sys_ovmf
    if sys_ovmf=$(find_system_ovmf); then
        ok "Found system OVMF: $sys_ovmf"
    else
        echo ""
        warn "OVMF firmware not found on system!"
        echo ""
        echo "  Install with:"
        echo "    ${C_BOLD}sudo pacman -S edk2-ovmf${C_RESET}    # Arch"
        echo "    ${C_BOLD}sudo apt install ovmf${C_RESET}       # Debian/Ubuntu"
        echo "    ${C_BOLD}sudo dnf install edk2-ovmf${C_RESET}  # Fedora"
        echo ""
        die "Install OVMF and try again"
    fi
    
    # Create firmware directory
    mkdir -p "$FIRMWARE_DIR"
    
    # Copy firmware
    local sys_vars="${sys_ovmf/CODE/VARS}"
    
    cp "$sys_ovmf" "$OVMF_CODE"
    ok "Copied OVMF_CODE.fd"
    
    if [[ -f "$sys_vars" ]]; then
        cp "$sys_vars" "$OVMF_VARS_TEMPLATE"
        ok "Copied OVMF_VARS template"
    else
        die "OVMF_VARS not found: $sys_vars"
    fi
    
    # Generate hash
    (cd "$FIRMWARE_DIR" && sha256sum "$(basename "$OVMF_CODE")" > "$(basename "$OVMF_CODE_HASH")")
    ok "Generated firmware hash"
    
    return 0
}

# Setup base disk (interactive)
ensure_base_disk() {
    if [[ -f "$DISK_BASE" ]]; then
        local size
        size=$(qemu-img info --output=json "$DISK_BASE" 2>/dev/null | grep -oP '"virtual-size":\s*\K[0-9]+' || echo "0")
        size=$((size / 1024 / 1024 / 1024))G
        ok "Base disk: $DISK_BASE ($size)"
        return 0
    fi
    
    echo ""
    info "Base disk not found: $DISK_BASE"
    echo ""
    
    if ask_yes "Create new base disk ($DISK_SIZE)?"; then
        mkdir -p "$(dirname "$DISK_BASE")"
        qemu-img create -f qcow2 "$DISK_BASE" "$DISK_SIZE" || die "Failed to create disk"
        ok "Created base disk: $DISK_BASE"
        
        echo ""
        warn "Base disk is empty! You need to install an OS."
        echo ""
        
        if ask_yes "Install from ISO now?"; then
            do_install
            exit 0
        else
            echo ""
            echo "  Run later with:"
            echo "    ${C_BOLD}$SCRIPT_NAME install${C_RESET}"
            echo ""
        fi
    else
        die "Cannot run without base disk"
    fi
}

# Setup overlay disk
ensure_overlay_disk() {
    if [[ -f "$DISK_OVERLAY" ]]; then
        # Verify backing chain
        local backing
        backing=$(qemu-img info --output=json "$DISK_OVERLAY" 2>/dev/null \
            | grep -oP '"backing-filename":\s*"\K[^"]+' || echo "")
        
        if [[ -n "$backing" ]] && [[ ! -f "$backing" ]]; then
            warn "Overlay's backing file missing: $backing"
            if ask_yes "Recreate overlay from current base?"; then
                rm -f "$DISK_OVERLAY"
            else
                die "Backing file required"
            fi
        else
            ok "Overlay disk: ready"
            return 0
        fi
    fi
    
    # Create overlay
    info "Creating overlay disk..."
    mkdir -p "$(dirname "$DISK_OVERLAY")"
    qemu-img create -f qcow2 -F qcow2 -b "$DISK_BASE" "$DISK_OVERLAY" || die "Failed to create overlay"
    ok "Created overlay disk"
}

# Setup per-VM UEFI vars
ensure_uefi_vars() {
    if [[ -f "$OVMF_VARS" ]]; then
        ok "UEFI vars: ready"
        return 0
    fi
    
    info "Creating per-VM UEFI vars..."
    mkdir -p "$(dirname "$OVMF_VARS")"
    cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS" || die "Failed to copy UEFI vars"
    ok "Created UEFI vars"
}

# Find or ask for ISO
ensure_iso() {
    # Already provided?
    if [[ -n "$ISO_PATH" ]] && [[ -f "$ISO_PATH" ]]; then
        ok "ISO: $ISO_PATH"
        return 0
    fi
    
    echo ""
    info "Looking for ISO files..."
    
    local found
    mapfile -t found < <(find_iso_files)
    
    if [[ ${#found[@]} -eq 0 ]]; then
        warn "No ISO files found!"
        echo ""
        echo "  Download an Arch ISO from:"
        echo "    ${C_BOLD}https://archlinux.org/download/${C_RESET}"
        echo ""
        
        local path
        if path=$(ask_path "Enter ISO path" "" 1); then
            ISO_PATH="$path"
        else
            die "ISO required for installation"
        fi
    elif [[ ${#found[@]} -eq 1 ]]; then
        ISO_PATH="${found[0]}"
        if ask_yes "Use ${ISO_PATH}?"; then
            :
        else
            local path
            if path=$(ask_path "Enter ISO path" "" 1); then
                ISO_PATH="$path"
            else
                die "ISO required"
            fi
        fi
    else
        ISO_PATH=$(ask_select "Select an ISO:" "${found[@]}" "Enter path manually...")
        if [[ "$ISO_PATH" == "Enter path manually..." ]]; then
            local path
            if path=$(ask_path "Enter ISO path" "" 1); then
                ISO_PATH="$path"
            else
                die "ISO required"
            fi
        fi
    fi
    
    ok "Using ISO: $ISO_PATH"
}

# -----------------------------------------------------------------------------
# PREREQUISITE CHECKS
# -----------------------------------------------------------------------------

check_qemu() {
    if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
        echo ""
        warn "QEMU not installed!"
        echo ""
        echo "  Install with:"
        echo "    ${C_BOLD}sudo pacman -S qemu-full${C_RESET}       # Arch"
        echo "    ${C_BOLD}sudo apt install qemu-system-x86${C_RESET}  # Debian/Ubuntu"
        echo ""
        die "Install QEMU and try again"
    fi
    
    local version
    version=$($QEMU_BIN --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    ok "QEMU: v$version"
}

check_kvm() {
    if [[ ! -e /dev/kvm ]]; then
        warn "KVM not available (VM will be SLOW)"
        echo ""
        echo "  Enable with:"
        echo "    ${C_BOLD}sudo modprobe kvm-intel${C_RESET}  # Intel"
        echo "    ${C_BOLD}sudo modprobe kvm-amd${C_RESET}    # AMD"
        echo ""
        
        if ! ask_yes "Continue without KVM?"; then
            die "KVM required for reasonable performance"
        fi
        
        KVM_ENABLED=0
    elif [[ ! -r /dev/kvm ]] || [[ ! -w /dev/kvm ]]; then
        warn "No KVM permissions"
        echo ""
        echo "  Fix with:"
        echo "    ${C_BOLD}sudo usermod -aG kvm $USER && newgrp kvm${C_RESET}"
        echo ""
        
        if ! ask_yes "Continue without KVM?"; then
            die "KVM permissions required"
        fi
        
        KVM_ENABLED=0
    else
        ok "KVM: enabled"
        KVM_ENABLED=1
    fi
}

check_port() {
    if command -v ss >/dev/null 2>&1; then
        if ss -ltn 2>/dev/null | grep -q ":$SSH_FWD_PORT "; then
            warn "Port $SSH_FWD_PORT already in use!"
            
            # Find free port
            local port
            for port in $(seq 2222 2250); do
                if ! ss -ltn 2>/dev/null | grep -q ":$port "; then
                    if ask_yes "Use port $port instead?"; then
                        SSH_FWD_PORT=$port
                        break
                    fi
                fi
            done
        fi
    fi
    ok "SSH port: $SSH_FWD_PORT"
}

# -----------------------------------------------------------------------------
# LOCKFILE & CLEANUP
# -----------------------------------------------------------------------------

acquire_lock() {
    mkdir -p "$(dirname "$LOCKFILE")"
    
    if [[ -f "$LOCKFILE" ]]; then
        local pid
        pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            warn "VM already running (PID: $pid)"
            echo ""
            echo "  Options:"
            echo "    1) ${C_BOLD}$SCRIPT_NAME ssh${C_RESET}   - Connect to running VM"
            echo "    2) ${C_BOLD}$SCRIPT_NAME stop${C_RESET}  - Stop the VM"
            echo ""
            die "Cannot start while VM is running"
        else
            warn "Stale lockfile (cleaning up)"
            rm -f "$LOCKFILE"
        fi
    fi
    
    echo $$ > "$LOCKFILE"
}

cleanup() {
    rm -f "$LOCKFILE" 2>/dev/null || true
}

trap cleanup EXIT

# -----------------------------------------------------------------------------
# VM LAUNCH
# -----------------------------------------------------------------------------

build_qemu_cmd() {
    local mode="${1:-run}"  # run, snapshot, install
    local disk_target="$DISK_OVERLAY"
    local uefi_vars="$OVMF_VARS"
    
    if [[ "$mode" == "install" ]]; then
        disk_target="$DISK_BASE"
        uefi_vars="/tmp/qemu-install-vars-$$.fd"
        cp "$OVMF_VARS_TEMPLATE" "$uefi_vars"
    fi
    
    QEMU_CMD=(
        "$QEMU_BIN"
        -nodefaults
        -no-user-config
        
        # Machine
        -machine "q35,accel=kvm"
        -cpu host
        -m "$VM_RAM"
        -smp "$VM_CPUS"
        
        # Firmware
        -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
        -drive "if=pflash,format=raw,file=$uefi_vars"
        
        # RTC
        -rtc "base=utc,clock=vm"
        
        # Network
        -netdev "user,id=net0,hostfwd=tcp::${SSH_FWD_PORT}-:22"
        -device "virtio-net-pci,netdev=net0,mac=$MAC_ADDRESS"
        
        # USB + tablet
        -device usb-ehci
        -device usb-tablet
        
        # RNG
        -object "rng-random,filename=/dev/urandom,id=rng0"
        -device "virtio-rng-pci,rng=rng0"
        
        # Display
        -display "gtk,gl=on"
        -device "virtio-vga-gl"
        
        # Name
        -name "$VM_NAME"
        -pidfile "$PIDFILE"
    )
    
    # KVM
    if [[ "${KVM_ENABLED:-1}" == "1" ]]; then
        QEMU_CMD+=(-enable-kvm)
    fi
    
    # Disk
    case "$mode" in
        install)
            QEMU_CMD+=(-cdrom "$ISO_PATH" -boot d)
            QEMU_CMD+=(-drive "file=$disk_target,format=qcow2,if=virtio")
            ;;
        snapshot)
            QEMU_CMD+=(-drive "file=$disk_target,format=qcow2,if=virtio,snapshot=on")
            ;;
        *)
            QEMU_CMD+=(-drive "file=$disk_target,format=qcow2,if=virtio")
            ;;
    esac
    
    # Audio (if available)
    if command -v pulseaudio >/dev/null 2>&1 || command -v pipewire-pulse >/dev/null 2>&1; then
        QEMU_CMD+=(-audiodev "pa,id=snd0" -device "intel-hda" -device "hda-duplex,audiodev=snd0")
    fi
    
    # Pacman cache sharing (for install)
    if [[ "$mode" == "install" ]] && [[ -d "/var/cache/pacman/pkg" ]]; then
        QEMU_CMD+=(-virtfs "local,path=/var/cache/pacman/pkg,mount_tag=pacman-cache,security_model=none,readonly=on")
    fi
}

print_banner() {
    local mode="$1"
    
    echo ""
    echo "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo "${C_CYAN}  $VM_NAME${C_RESET}"
    echo "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo "  RAM: $VM_RAM  |  CPUs: $VM_CPUS  |  SSH: ${C_BOLD}ssh -p $SSH_FWD_PORT localhost${C_RESET}"
    
    case "$mode" in
        install)
            echo "  Mode: ${C_YELLOW}INSTALL${C_RESET} (writing to base disk)"
            echo "  ISO:  $ISO_PATH"
            ;;
        snapshot)
            echo "  Mode: ${C_YELLOW}SNAPSHOT${C_RESET} (changes discarded on exit)"
            ;;
        *)
            echo "  Mode: ${C_GREEN}NORMAL${C_RESET} (overlay protects base)"
            ;;
    esac
    
    echo "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo ""
}

# -----------------------------------------------------------------------------
# COMMANDS
# -----------------------------------------------------------------------------

do_run() {
    info "Starting VM: $VM_NAME"
    
    # Check prerequisites
    check_qemu
    check_kvm
    check_port
    
    # Ensure resources
    ensure_firmware
    ensure_base_disk
    
    # Check if base disk has an OS
    local disk_used
    disk_used=$(qemu-img info --output=json "$DISK_BASE" 2>/dev/null | grep -oP '"actual-size":\s*\K[0-9]+' || echo "0")
    
    if (( disk_used < 100000000 )); then  # Less than 100MB = probably empty
        warn "Base disk appears to be empty!"
        echo ""
        if ask_yes "Install an OS from ISO first?"; then
            do_install
            return
        fi
    fi
    
    ensure_overlay_disk
    ensure_uefi_vars
    
    acquire_lock
    mkdir -p "$LOG_DIR"
    
    build_qemu_cmd "run"
    print_banner "run"
    
    exec "${QEMU_CMD[@]}"
}

do_install() {
    info "Install mode"
    
    check_qemu
    check_kvm
    check_port
    ensure_firmware
    ensure_base_disk
    ensure_iso
    
    echo ""
    warn "This will install directly to: $DISK_BASE"
    
    if ! ask_yes "Continue with installation?"; then
        die "Installation cancelled"
    fi
    
    acquire_lock
    
    build_qemu_cmd "install"
    print_banner "install"
    
    echo "  ${C_DIM}Tip: Mount host pacman cache in VM:${C_RESET}"
    echo "    ${C_BOLD}mount -t 9p pacman-cache /var/cache/pacman/pkg${C_RESET}"
    echo ""
    
    exec "${QEMU_CMD[@]}"
}

do_snapshot() {
    info "Snapshot mode (changes discarded)"
    
    check_qemu
    check_kvm
    check_port
    ensure_firmware
    ensure_base_disk
    ensure_overlay_disk
    ensure_uefi_vars
    
    acquire_lock
    
    build_qemu_cmd "snapshot"
    print_banner "snapshot"
    
    exec "${QEMU_CMD[@]}"
}

do_reset() {
    info "Resetting VM: $VM_NAME"
    
    if [[ -f "$PIDFILE" ]]; then
        local pid
        pid=$(cat "$PIDFILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            die "VM is running! Stop it first: $SCRIPT_NAME stop"
        fi
    fi
    
    echo ""
    echo "  This will delete:"
    [[ -f "$DISK_OVERLAY" ]] && echo "    - Overlay disk: $DISK_OVERLAY"
    [[ -f "$OVMF_VARS" ]] && echo "    - UEFI vars: $OVMF_VARS"
    [[ -d "$LOG_DIR" ]] && echo "    - Logs: $LOG_DIR"
    echo ""
    echo "  ${C_GREEN}Base disk preserved:${C_RESET} $DISK_BASE"
    echo ""
    
    if ask_no "Really reset?"; then
        rm -rf "$DISK_OVERLAY" "$OVMF_VARS" "$PIDFILE" "$LOCKFILE" "$LOG_DIR" 2>/dev/null || true
        ok "VM reset complete"
    else
        info "Reset cancelled"
    fi
}

do_status() {
    echo ""
    echo "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo "${C_CYAN}  Status: $VM_NAME${C_RESET}"
    echo "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
    
    # Running?
    if [[ -f "$PIDFILE" ]]; then
        local pid
        pid=$(cat "$PIDFILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "  State:  ${C_GREEN}RUNNING${C_RESET} (PID: $pid)"
            echo "  SSH:    ${C_BOLD}ssh -p $SSH_FWD_PORT localhost${C_RESET}"
        else
            echo "  State:  ${C_YELLOW}STALE${C_RESET}"
        fi
    else
        echo "  State:  ${C_DIM}stopped${C_RESET}"
    fi
    
    echo ""
    
    # Resources
    echo "  ${C_BOLD}Resources:${C_RESET}"
    
    if [[ -f "$OVMF_CODE" ]]; then
        echo "    Firmware: ${C_GREEN}✓${C_RESET} $FIRMWARE_DIR"
    else
        echo "    Firmware: ${C_RED}✗${C_RESET} not found"
    fi
    
    if [[ -f "$DISK_BASE" ]]; then
        local size
        size=$(du -h "$DISK_BASE" 2>/dev/null | cut -f1)
        echo "    Base:     ${C_GREEN}✓${C_RESET} $DISK_BASE ($size)"
    else
        echo "    Base:     ${C_RED}✗${C_RESET} not found"
    fi
    
    if [[ -f "$DISK_OVERLAY" ]]; then
        local size
        size=$(du -h "$DISK_OVERLAY" 2>/dev/null | cut -f1)
        echo "    Overlay:  ${C_GREEN}✓${C_RESET} $DISK_OVERLAY ($size)"
    else
        echo "    Overlay:  ${C_DIM}-${C_RESET} not created"
    fi
    
    echo ""
    echo "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo ""
}

do_ssh() {
    if ! command -v ssh >/dev/null 2>&1; then
        die "SSH client not installed"
    fi
    
    info "Connecting to VM on port $SSH_FWD_PORT..."
    
    exec ssh \
        -o "StrictHostKeyChecking=no" \
        -o "UserKnownHostsFile=/dev/null" \
        -o "LogLevel=ERROR" \
        -p "$SSH_FWD_PORT" \
        "root@localhost" "$@"
}

do_stop() {
    if [[ ! -f "$PIDFILE" ]]; then
        die "VM not running (no PID file)"
    fi
    
    local pid
    pid=$(cat "$PIDFILE" 2>/dev/null)
    
    if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$PIDFILE" "$LOCKFILE"
        die "VM not running (stale PID)"
    fi
    
    info "Stopping VM (PID: $pid)..."
    
    kill -TERM "$pid" 2>/dev/null || true
    
    local count=0
    while (( count < 10 )) && kill -0 "$pid" 2>/dev/null; do
        echo -n "."
        sleep 1
        ((count++))
    done
    echo ""
    
    if kill -0 "$pid" 2>/dev/null; then
        warn "Force killing..."
        kill -9 "$pid" 2>/dev/null || true
    fi
    
    rm -f "$PIDFILE" "$LOCKFILE"
    ok "VM stopped"
}

# -----------------------------------------------------------------------------
# USAGE
# -----------------------------------------------------------------------------

usage() {
    cat <<EOF
${C_CYAN}$SCRIPT_NAME v$SCRIPT_VERSION${C_RESET} — Noob-Friendly QEMU VM Runner

${C_BOLD}USAGE:${C_RESET}
    $SCRIPT_NAME [OPTIONS] [COMMAND]

${C_BOLD}COMMANDS:${C_RESET}
    ${C_GREEN}run${C_RESET}         Start VM (default) — auto-creates missing resources
    ${C_GREEN}install${C_RESET}     Install OS from ISO
    ${C_GREEN}snapshot${C_RESET}    Run without saving changes
    ${C_GREEN}reset${C_RESET}       Delete overlay, keep base image
    ${C_GREEN}status${C_RESET}      Show VM status
    ${C_GREEN}ssh${C_RESET}         Connect to running VM
    ${C_GREEN}stop${C_RESET}        Stop running VM

${C_BOLD}OPTIONS:${C_RESET}
    -n, --name NAME     VM name (default: arch-repro)
    -m, --ram SIZE      RAM (default: 4G)
    -c, --cpus N        CPUs (default: 4)
    -i, --iso PATH      ISO file for install
    -p, --port PORT     SSH port (default: 2222)
    -y, --yes           Auto-accept prompts
    -h, --help          This help

${C_BOLD}EXAMPLES:${C_RESET}
    $SCRIPT_NAME                    # Just run it!
    $SCRIPT_NAME install            # Install from ISO
    $SCRIPT_NAME --ram 8G           # More RAM
    $SCRIPT_NAME ssh                # Connect to VM

${C_DIM}Everything is auto-detected and created as needed.${C_RESET}
EOF
    exit 0
}

# -----------------------------------------------------------------------------
# ARGUMENT PARSING
# -----------------------------------------------------------------------------

COMMAND="run"
AUTO_YES=0

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            run|install|snapshot|reset|status|ssh|stop)
                COMMAND="$1"
                shift
                ;;
            -n|--name)
                VM_NAME="$2"
                shift 2
                ;;
            -m|--ram)
                VM_RAM="$2"
                shift 2
                ;;
            -c|--cpus)
                VM_CPUS="$2"
                shift 2
                ;;
            -i|--iso)
                ISO_PATH="$2"
                shift 2
                ;;
            -p|--port)
                SSH_FWD_PORT="$2"
                shift 2
                ;;
            -y|--yes)
                AUTO_YES=1
                shift
                ;;
            -h|--help)
                usage
                ;;
            -*)
                die "Unknown option: $1 (use --help)"
                ;;
            *)
                die "Unknown argument: $1"
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------

main() {
    parse_args "$@"
    
    # Recalculate paths after name change
    VM_ROOT="${VM_ROOT:-$HOME/qemu-repro/$VM_NAME}"
    DISK_OVERLAY="$VM_ROOT/disk.qcow2"
    OVMF_VARS="$VM_ROOT/OVMF_VARS.fd"
    
    case "$COMMAND" in
        run)      do_run ;;
        install)  do_install ;;
        snapshot) do_snapshot ;;
        reset)    do_reset ;;
        status)   do_status ;;
        ssh)      do_ssh ;;
        stop)     do_stop ;;
    esac
}

main "$@"
