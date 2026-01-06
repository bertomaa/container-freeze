#!/bin/bash
# Install K3s and dependencies on the VM
# Run this after setup-vm.sh and after verifying network connectivity

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="$PROJECT_ROOT/vm"

if [ ! -f "$VM_DIR/connection.env" ]; then
    echo "ERROR: Run ./vm/setup-vm.sh first"
    exit 1
fi

source "$VM_DIR/connection.env"
SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=no cfuser@$VM_IP"
SCP="scp -i $SSH_KEY -o StrictHostKeyChecking=no"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║      Container Freeze POC - Install K3s (Step 2)             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Target: cfuser@$VM_IP"
echo ""

# Test connectivity
echo "[1/6] Testing connectivity..."
if ! $SSH "ping -c 1 8.8.8.8" &>/dev/null; then
    echo "ERROR: VM has no internet. Fix networking first."
    exit 1
fi
echo "  ✓ Internet accessible"

# Install packages
echo "[2/6] Installing packages..."
$SSH "sudo apt-get update && sudo apt-get install -y curl docker.io jq"
$SSH "sudo systemctl enable docker && sudo systemctl start docker"
$SSH "sudo usermod -aG docker cfuser"
echo "  ✓ Packages installed"

# Install K3s
echo "[3/6] Installing K3s..."
$SSH "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--disable traefik --write-kubeconfig-mode 644' sh -"
echo "  ✓ K3s installed"

# Add KUBECONFIG to .bashrc for interactive sessions
$SSH "echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc"

# Wait for K3s
echo "[4/6] Waiting for K3s to be ready..."
for i in {1..60}; do
    if $SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get nodes" &>/dev/null; then
        break
    fi
    sleep 5
    echo -n "."
done
echo ""
$SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get nodes"
echo "  ✓ K3s ready"

# Install Helm
echo "[5/6] Installing Helm..."
$SSH "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
echo "  ✓ Helm installed"

# Verify
echo "[6/6] Verifying installation..."
$SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get nodes && helm version --short"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    K3s INSTALLED                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Next step: ./vm/deploy-poc.sh"
echo ""
