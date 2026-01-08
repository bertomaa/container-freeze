#!/bin/bash
# Container Freeze - Cleanup Cluster Only
# Completely removes K3s cluster but keeps the VM and Docker images intact
# Useful for quickly resetting the demo without rebuilding everything

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="$PROJECT_ROOT/vm"

if [ ! -f "$VM_DIR/connection.env" ]; then
    echo "ERROR: VM not found. Nothing to clean up."
    exit 1
fi

source "$VM_DIR/connection.env"
SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=no cfuser@$VM_IP"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║      Container Freeze - Cluster Cleanup                      ║"
echo "║      (VM and Docker images will be preserved)                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

echo "This will clean up:"
echo "  • Complete K3s cluster and all resources"
echo "  • K3s data directories"
echo ""
echo "This will preserve:"
echo "  • VM and system installation"
echo "  • Docker and built container images"
echo "  • POC files in ~/container-freeze"
echo ""

echo "[1/3] Uninstalling K3s cluster..."
$SSH << 'EOF'
if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    sudo /usr/local/bin/k3s-uninstall.sh
    echo "  ✓ K3s uninstalled"
else
    echo "  ⚠ K3s not installed or already removed"
fi
EOF

echo "[2/3] Cleaning K3s data directories..."
$SSH << 'EOF'
sudo rm -rf /etc/rancher/k3s
sudo rm -rf /var/lib/rancher/k3s
sudo rm -rf ~/.kube
EOF
echo "  ✓ K3s data cleaned"

echo "[3/3] Cleaning local checkpoint data..."
rm -rf /tmp/k8s-checkpoints 2>/dev/null || true
rm -rf /tmp/forensic-analysis 2>/dev/null || true
echo "  ✓ Local data cleaned"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    CLUSTER CLEANED                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "VM Status:"
$SSH "hostname && uname -a"
echo ""
echo "Docker Images (preserved):"
$SSH "sudo docker images | grep -E 'localhost/|REPOSITORY'"
echo ""
echo "To redeploy the POC:"
echo "  ./vm/install-k3s.sh     # Reinstall K3s"
echo "  ./vm/deploy-poc.sh      # Deploy POC workloads"
echo ""
echo "To destroy everything (including VM and images):"
echo "  ./destroy.sh"
echo ""
