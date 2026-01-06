#!/bin/bash
# Container Freeze - Demo Runner
# Connects to VM and runs the POC interactively

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="$PROJECT_ROOT/vm"

if [ ! -f "$VM_DIR/connection.env" ]; then
    echo "ERROR: VM not set up. Run ./setup.sh first"
    exit 1
fi

source "$VM_DIR/connection.env"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║      Container Freeze - Kubernetes Forensics Demo            ║"
echo "║         'They're Inside. Now What?'                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Connecting to VM at $VM_IP..."
echo ""

# Run the POC script on the VM
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -t cfuser@"$VM_IP" "cd ~/container-freeze && ./run-poc.sh"

echo ""
echo "Demo complete."
echo ""
echo "Cleanup: ./destroy.sh"
echo ""
