#!/bin/bash
# Install K3s and dependencies on the VM
# Run this after setup-vm.sh and after verifying network connectivity

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="$PROJECT_ROOT/vm"

source "$PROJECT_ROOT/lib/vm.sh"
load_vm_connection || exit 1

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║      Container Freeze POC - Install K3s (Step 2)             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Target: cfuser@$VM_IP"
echo ""

# Test connectivity
echo "[1/7] Testing connectivity..."
if ! $SSH "ping -c 1 8.8.8.8" &>/dev/null; then
    echo "ERROR: VM has no internet. Fix networking first."
    exit 1
fi
echo "  ✓ Internet accessible"

# Install packages
echo "[2/7] Installing packages..."
$SSH "sudo apt-get update && sudo apt-get install -y curl docker.io jq criu"
$SSH "sudo systemctl enable docker && sudo systemctl start docker"
$SSH "sudo usermod -aG docker cfuser"
echo "  ✓ Packages installed"

# Install K3s
echo "[3/7] Installing K3s..."
# Pin to v1.32.11+k3s1 (containerd 2.1.5 with CRIU support)
# CRIU checkpoint requires containerd 2.0+ (added in v1.31.6 & v1.32.2, Feb 2025)
$SSH "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='v1.32.11+k3s1' INSTALL_K3S_EXEC='--disable traefik --write-kubeconfig-mode 644' sh -"
echo "  ✓ K3s v1.32.11+k3s1 installed (containerd 2.1.5 with CRIU support)"

# Add KUBECONFIG to .bashrc for interactive sessions
$SSH "echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc"

# Wait for K3s
echo "[4/7] Waiting for K3s to be ready..."
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
echo "[5/7] Installing Helm..."
$SSH "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
echo "  ✓ Helm installed"

# Verify
echo "[6/7] Installing Tetragon (eBPF monitoring)..."
$SSH << 'REMOTE_TETRAGON'
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm repo add cilium https://helm.cilium.io
helm repo update
helm install tetragon cilium/tetragon --namespace kube-system --wait --timeout 5m
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=tetragon -n kube-system --timeout=120s
REMOTE_TETRAGON
echo "  ✓ Tetragon installed"

echo "[7/8] Fixing CRIU tar compatibility..."
$SSH << 'REMOTE_TAR_FIX'
# K3s ships with BusyBox tar which is incompatible with CRIU
# CRIU expects GNU tar and calls it with arguments that BusyBox doesn't support
# Solution: Create a tar wrapper in k3s bin directory that fixes the invocation

K3S_BIN=$(find /var/lib/rancher/k3s/data/*/bin -type d -name bin 2>/dev/null | head -1)
if [ -n "$K3S_BIN" ]; then
    # Remove the busybox tar symlink
    sudo rm -f "$K3S_BIN/tar"

    # Create a wrapper that calls GNU tar with correct arguments
    sudo tee "$K3S_BIN/tar" > /dev/null << 'EOF'
#!/bin/bash
# CRIU tar wrapper - fixes invocation to use GNU tar
# CRIU may call tar without specifying operation mode, so we add -c if needed
if ! echo "$@" | grep -qE '(-c|-x|-t|-r|-u|-A|--create|--extract|--list)'; then
    exec /usr/bin/tar -c "$@"
else
    exec /usr/bin/tar "$@"
fi
EOF
    sudo chmod +x "$K3S_BIN/tar"
    echo "  ✓ Created CRIU-compatible tar wrapper at $K3S_BIN/tar"
else
    echo "  ⚠ K3s bin directory not found - CRIU checkpointing may fail"
fi

# Also create CRIU config for better compatibility
sudo mkdir -p /etc/criu
sudo tee /etc/criu/runc.conf > /dev/null << 'EOF'
tcp-established
ghost-limit 0
EOF
echo "  ✓ Created CRIU configuration"
REMOTE_TAR_FIX
echo "  ✓ CRIU compatibility fixed"

echo "[8/8] Verifying installation..."
$SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get nodes && helm version --short"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              K3s + Tetragon INSTALLED                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Base infrastructure ready. Deploy a demo with:"
echo "  cfreeze demo"
echo ""
