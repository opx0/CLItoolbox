#!/usr/bin/env bash
# @file QEMU Test Environment (Portable)
# @brief Launch ArchTitus in QEMU with isolated UEFI vars + host pacman cache
#
# USAGE:
#   ./qemu-test.sh                    # Install mode (boot ISO)
#   ./qemu-test.sh --boot             # Boot installed OS
#   ./qemu-test.sh --reset            # Delete VM and start fresh
#   ./qemu-test.sh --snapshot         # Boot in snapshot mode (no disk changes)
#   ./qemu-test.sh --create NAME      # Create new VM in ~/qemu/vms/NAME
#
# DESIGN:
#   Each VM gets its own directory with disk.qcow2 + OVMF_VARS.fd
#   This is portable - move the whole dir to another machine and it boots

set -e

# ================================
# CONFIGURATION
# ================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Default VM location (can be overridden with QEMU_VM_DIR)
QEMU_BASE="${QEMU_BASE:-$HOME/qemu}"
VM_NAME="${VM_NAME:-archtitus}"
VM_DIR="${QEMU_VM_DIR:-$QEMU_BASE/vms/$VM_NAME}"

# VM settings
ISO_PATH="${ISO_PATH:-$HOME/arch.iso}"
VM_DISK_SIZE="40G"
VM_RAM="4G"
VM_CPUS="4"

# Device configuration (modular)
VM_MACHINE="q35"
VM_USB_DEVICES=("usb-ehci" "usb-tablet")
VM_AUDIO_DEVICES=("intel-hda" "hda-duplex")
VM_NETWORK_MODEL="virtio-net-pci"

# Host pacman cache (zero downloads!)
HOST_PACMAN_CACHE="/var/cache/pacman/pkg"
HOST_PACMAN_SYNC="/var/lib/pacman/sync"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo_info()  { echo -e "${GREEN}[✓]${NC} $1"; }
echo_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
echo_error() { echo -e "${RED}[✗]${NC} $1"; }

# =========================================================================
# Validation Checks
# =========================================================================
check_requirements() {
    # Check for qemu binary
    if ! command -v qemu-system-x86_64 &>/dev/null; then
        echo_error "qemu-system-x86_64 not found! Install: sudo pacman -S qemu-full"
        exit 1
    fi
    
    # Check for KVM support
    if [[ ! -e /dev/kvm ]]; then
        echo_warn "KVM not available. VM will be slow!"
        echo "       Load kernel module: sudo modprobe kvm-intel  (or kvm-amd)"
    elif [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
        echo_error "No permission for /dev/kvm. Add user to kvm group:"
        echo "       sudo usermod -aG kvm $USER && newgrp kvm"
        exit 1
    fi
    
    # Check disk space (need at least 45GB for 40GB image + headroom)
    local available=$(df -BG "$QEMU_BASE" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ -n "$available" && "$available" -lt 45 ]]; then
        echo_warn "Low disk space: ${available}GB available in $QEMU_BASE"
        echo "       Need at least 45GB for VM creation"
    fi
}

# =========================================================================
# Setup VM Directory (Portable Structure)
# =========================================================================
# Layout:
#   ~/qemu/vms/archtitus/
#   ├── disk.qcow2      # Virtual disk
#   └── OVMF_VARS.fd    # UEFI variables (per-VM isolation!)
#
setup_vm() {
    mkdir -p "$VM_DIR"
    
    # Disk
    if [[ ! -f "$VM_DIR/disk.qcow2" ]]; then
        echo_info "Creating $VM_DISK_SIZE virtual disk..."
        qemu-img create -f qcow2 "$VM_DIR/disk.qcow2" "$VM_DISK_SIZE"
    fi
}

# =========================================================================
# UEFI Setup (Isolated per VM)
# =========================================================================
setup_uefi() {
    local OVMF_PATHS=("/usr/share/edk2/x64" "/usr/share/ovmf/x64" "/usr/share/OVMF")
    local OVMF_CODE="" OVMF_VARS_SRC=""
    
    # Find OVMF firmware (prefer 4MB variant)
    for base in "${OVMF_PATHS[@]}"; do
        if [[ -f "$base/OVMF_CODE.4m.fd" ]]; then
            OVMF_CODE="$base/OVMF_CODE.4m.fd"
            OVMF_VARS_SRC="$base/OVMF_VARS.4m.fd"
            break
        elif [[ -f "$base/OVMF_CODE.fd" ]]; then
            OVMF_CODE="$base/OVMF_CODE.fd"
            OVMF_VARS_SRC="$base/OVMF_VARS.fd"
            break
        fi
    done
    
    if [[ -z "$OVMF_CODE" ]]; then
        echo_error "OVMF not found! Install: sudo pacman -S edk2-ovmf"
        exit 1
    fi
    
    # Copy VARS to VM dir (isolated per-VM - critical for portability!)
    if [[ ! -f "$VM_DIR/OVMF_VARS.fd" ]]; then
        cp "$OVMF_VARS_SRC" "$VM_DIR/OVMF_VARS.fd"
        echo_info "Created fresh UEFI vars for this VM"
    fi
    
    UEFI_ARGS="-drive if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
    UEFI_ARGS="$UEFI_ARGS -drive if=pflash,format=raw,file=$VM_DIR/OVMF_VARS.fd"
    echo_info "UEFI: $OVMF_CODE"
}

# =========================================================================
# VirtFS Setup (Array-based for cleaner code)
# =========================================================================
setup_virtfs() {
    local mode=$1  # "install" or "boot"
    VIRTFS_ARGS=()
    
    if [[ "$mode" == "install" ]]; then
        # Install mode: share repo + host caches
        add_virtfs "repo" "$REPO_ROOT" "rw" "Repository shared"
        add_virtfs "cache" "$HOST_PACMAN_CACHE" "ro" "Pacman cache shared"
        add_virtfs "sync" "$HOST_PACMAN_SYNC" "ro" "Pacman database shared"
    else
        # Boot mode: share Downloads
        add_virtfs "downloads" "$HOME/Downloads" "rw" "Downloads shared"
    fi
}

add_virtfs() {
    local tag=$1 path=$2 mode=$3 msg=$4
    
    if [[ -d "$path" ]]; then
        local readonly_flag=""
        [[ "$mode" == "ro" ]] && readonly_flag=",readonly=on"
        
        VIRTFS_ARGS+=("-virtfs" "local,path=$path,mount_tag=$tag,security_model=mapped-xattr,id=$tag$readonly_flag")
        [[ -n "$msg" ]] && echo_info "$msg"
    fi
}

# =========================================================================
# Display Setup (with virtio-vga-gl for better graphics)
# =========================================================================
setup_display() {
    local available=$(qemu-system-x86_64 -display help 2>&1)
    
    # Try GTK with OpenGL first (best for Cinnamon/GNOME)
    if echo "$available" | grep -q "^gtk"; then
        DISPLAY_ARGS=("-display" "gtk,gl=on" "-device" "virtio-vga-gl")
        echo_info "Display: GTK with OpenGL (Best Fit: Ctrl+Alt+0)"
    elif echo "$available" | grep -q "^sdl"; then
        DISPLAY_ARGS=("-display" "sdl,gl=on" "-device" "virtio-vga-gl")
        echo_info "Display: SDL with OpenGL"
    else
        # Fallback to basic VGA
        DISPLAY_ARGS=("-display" "vnc=:0" "-device" "VGA")
        echo_warn "No GUI display! Using VNC on :5900"
    fi
}

# =========================================================================
# Build QEMU Command (Unified function to eliminate duplication)
# =========================================================================
build_qemu_cmd() {
    local mode=$1  # "install", "boot", or "snapshot"
    local -a QEMU_CMD=(
        "qemu-system-x86_64"
        "-enable-kvm"
        "-cpu" "host"
        "-m" "$VM_RAM"
        "-smp" "$VM_CPUS"
        "-machine" "$VM_MACHINE"
    )
    
    # UEFI firmware
    QEMU_CMD+=($UEFI_ARGS)
    
    # Disk
    if [[ "$mode" == "snapshot" ]]; then
        QEMU_CMD+=("-drive" "file=$VM_DIR/disk.qcow2,format=qcow2,if=virtio,snapshot=on")
    else
        QEMU_CMD+=("-drive" "file=$VM_DIR/disk.qcow2,format=qcow2,if=virtio")
    fi
    
    # Boot from ISO in install mode
    if [[ "$mode" == "install" ]]; then
        QEMU_CMD+=("-cdrom" "$ISO_PATH" "-boot" "d")
    fi
    
    # VirtFS shares
    QEMU_CMD+=("${VIRTFS_ARGS[@]}")
    
    # Network
    QEMU_CMD+=("-netdev" "user,id=net0,hostfwd=tcp::2222-:22")
    QEMU_CMD+=("-device" "$VM_NETWORK_MODEL,netdev=net0")
    
    # Display
    QEMU_CMD+=("${DISPLAY_ARGS[@]}")
    
    # USB devices
    for dev in "${VM_USB_DEVICES[@]}"; do
        QEMU_CMD+=("-device" "$dev")
    done
    
    # Audio devices
    for dev in "${VM_AUDIO_DEVICES[@]}"; do
        QEMU_CMD+=("-device" "$dev")
    done
    
    # VM name
    QEMU_CMD+=("-name" "$VM_NAME")
    
    echo "${QEMU_CMD[@]}"
}

# =========================================================================
# Launch VM (Install Mode - Boot from ISO)
# =========================================================================
launch_install() {
    # Check ISO
    if [[ ! -f "$ISO_PATH" ]]; then
        echo_error "ISO not found: $ISO_PATH"
        echo "       Set ISO_PATH=/path/to/arch.iso"
        exit 1
    fi
    
    print_banner "install"
    setup_virtfs "install"
    
    echo_info "Launching VM in install mode..."
    eval $(build_qemu_cmd "install")
}

# =========================================================================
# Launch VM (Boot Mode - No ISO)
# =========================================================================
launch_boot() {
    if [[ ! -f "$VM_DIR/disk.qcow2" ]]; then
        echo_error "No disk found. Run without --boot first to install."
        exit 1
    fi
    
    print_banner "boot"
    setup_virtfs "boot"
    
    echo_info "Launching VM..."
    eval $(build_qemu_cmd "boot")
}

# =========================================================================
# Launch VM (Snapshot Mode - No disk changes)
# =========================================================================
launch_snapshot() {
    if [[ ! -f "$VM_DIR/disk.qcow2" ]]; then
        echo_error "No disk found. Run without --snapshot first to install."
        exit 1
    fi
    
    print_banner "snapshot"
    setup_virtfs "boot"
    
    echo_warn "Snapshot mode: Disk changes will NOT be saved"
    eval $(build_qemu_cmd "snapshot")
}

# =========================================================================
# Print Banner
# =========================================================================
print_banner() {
    local mode=$1
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
    case "$mode" in
        install)
            echo -e "${CYAN}    QEMU VM - Install Mode${NC}"
            echo -e "${CYAN}══════════════════════════════════════════${NC}"
            echo "  VM:   $VM_NAME"
            echo "  Dir:  $VM_DIR"
            echo "  ISO:  $ISO_PATH"
            ;;
        boot)
            echo -e "${CYAN}    QEMU VM - Boot Mode${NC}"
            echo -e "${CYAN}══════════════════════════════════════════${NC}"
            echo "  VM:   $VM_NAME"
            echo "  Dir:  $VM_DIR"
            ;;
        snapshot)
            echo -e "${CYAN}    QEMU VM - Snapshot Mode${NC}"
            echo -e "${CYAN}══════════════════════════════════════════${NC}"
            echo "  VM:   $VM_NAME"
            echo "  Dir:  $VM_DIR"
            ;;
    esac
    echo "  RAM:  $VM_RAM | CPUs: $VM_CPUS"
    echo "  SSH:  ssh root@localhost -p 2222"
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
    echo ""
}

# =========================================================================
# Show Detailed Instructions
# =========================================================================
show_instructions() {
    cat <<'EOF'

QEMU VM Detailed Instructions
==============================

INSTALL MODE (First Boot):
--------------------------
1. In VM, setup SSH access:
   passwd root
   echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
   systemctl start sshd

2. From host, connect via SSH:
   ssh root@localhost -p 2222

3. Mount shared filesystems:
   mkdir -p /c /s /var/lib/pacman/sync
   mount -t 9p repo /mnt
   mount -t 9p cache /c
   mount -t 9p sync /s
   mount --bind /c /var/cache/pacman/pkg
   cp /s/* /var/lib/pacman/sync/

4. Run installation:
   cd /mnt && ./baseos-setup.sh

BOOT MODE:
----------
- Downloads folder available at mount tag 'downloads'
- Mount with: mount -t 9p downloads /mnt/downloads

SNAPSHOT MODE:
--------------
- All disk changes are discarded on exit
- Perfect for testing destructive operations
- Original disk remains unchanged

SSH ACCESS:
-----------
- Port forwarding: localhost:2222 -> VM:22
- Connect: ssh root@localhost -p 2222
- Or use regular terminal in GUI window

PORTABILITY:
------------
- VM directory contains: disk.qcow2 + OVMF_VARS.fd
- Move entire directory to another machine
- Works immediately with same script

EOF
}

# =========================================================================
# Main
# =========================================================================
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "  (no option)  Install mode - boot from ISO"
        echo "  --boot, -b   Boot installed OS from disk"
        echo "  --reset, -r  Delete VM and start fresh"
        echo "  --help, -h   Show this help"
        echo ""
        echo "Environment variables:"
        echo "  ISO_PATH     Path to Arch ISO (default: ~/arch.iso)"
        echo "  QEMU_VM_DIR  VM directory (default: ~/qemu/vms/archtitus)"
        echo ""
        echo "VM Directory: $VM_DIR"
        echo "  disk.qcow2    - Virtual disk"
        echo "  OVMF_VARS.fd  - UEFI vars (isolated, portable)"
        ;;
    --boot|-b)
        setup_vm
        setup_uefi
        setup_display
        launch_boot
        ;;
    --reset|-r)
        echo_warn "Deleting VM: $VM_DIR"
        rm -rf "$VM_DIR"
        echo_info "VM reset. Run again to start fresh."
        ;;
    --create|-c)
        VM_NAME="${2:-archtitus}"
        VM_DIR="$QEMU_BASE/vms/$VM_NAME"
        setup_vm
        setup_uefi
        echo_info "Created VM: $VM_DIR"
        echo "  Run: $0 --boot  (after setting QEMU_VM_DIR=$VM_DIR)"
        ;;
    *)
        setup_vm
        setup_uefi
        setup_display
        launch_install
        ;;
esac
