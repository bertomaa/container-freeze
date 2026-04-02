#!/bin/bash
# Destroy VM and clean up everything

set -e

VM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="container-freeze-vm"

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        *)      echo "unsupported" ;;
    esac
}

# ============================================================================
# macOS: Lima teardown
# ============================================================================

destroy_macos() {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║      Container Freeze POC - Destroy Everything (Lima)        ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    echo "[1/2] Destroying Lima VM..."
    if limactl list --format json 2>/dev/null | grep -q "\"name\":\"$VM_NAME\""; then
        limactl stop "$VM_NAME" 2>/dev/null || true
        limactl delete "$VM_NAME" 2>/dev/null || true
        echo "  ✓ VM destroyed"
    else
        echo "  ✓ VM not found (already destroyed)"
    fi

    echo "[2/2] Cleaning local files..."
    rm -f "$VM_DIR/lima-config.yaml"
    rm -f "$VM_DIR/connection.env"
    rm -f "$VM_DIR/user-data"
    rm -f "$VM_DIR/meta-data"
    # Keep SSH key to speed up next run
    echo "  ✓ Files cleaned (kept SSH key)"

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    DESTROYED                                  ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "To start fresh: ./vm/setup-vm.sh"
    echo ""
}

# ============================================================================
# Linux: libvirt teardown (original)
# ============================================================================

destroy_linux() {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║      Container Freeze POC - Destroy Everything                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    # Destroy VM
    echo "[1/4] Destroying VM..."
    if sudo virsh dominfo "$VM_NAME" &>/dev/null; then
        sudo virsh destroy "$VM_NAME" 2>/dev/null || true
        sudo virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
        echo "  ✓ VM destroyed"
    else
        echo "  ✓ VM not found (already destroyed)"
    fi

    # Destroy network
    echo "[2/4] Destroying network..."
    if sudo virsh net-info default &>/dev/null; then
        sudo virsh net-destroy default 2>/dev/null || true
        sudo virsh net-undefine default 2>/dev/null || true
        echo "  ✓ Network destroyed"
    else
        echo "  ✓ Network not found"
    fi

    # Clean iptables rules
    echo "[3/4] Cleaning iptables..."
    sudo iptables -t nat -D POSTROUTING -s 192.168.122.0/24 ! -d 192.168.122.0/24 -j MASQUERADE 2>/dev/null || true
    DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$DEFAULT_IF" ]; then
        sudo iptables -D FORWARD -i virbr0 -o "$DEFAULT_IF" -j ACCEPT 2>/dev/null || true
        sudo iptables -D FORWARD -o virbr0 -i "$DEFAULT_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    fi
    echo "  ✓ iptables cleaned"

    # Clean local files
    echo "[4/4] Cleaning local files..."
    rm -f "$VM_DIR/${VM_NAME}.qcow2"
    rm -f "$VM_DIR/cloud-init.iso"
    rm -f "$VM_DIR/connection.env"
    rm -f "$VM_DIR/user-data"
    rm -f "$VM_DIR/meta-data"
    # Keep id_rsa and cloud image to speed up next run
    echo "  ✓ Files cleaned (kept SSH key and cloud image)"

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    DESTROYED                                  ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "To start fresh: ./vm/setup-vm.sh"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

OS=$(detect_os)
case "$OS" in
    macos)  destroy_macos ;;
    linux)  destroy_linux ;;
    *)
        echo "ERROR: Unsupported OS: $(uname -s)"
        exit 1
        ;;
esac
