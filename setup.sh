#!/bin/bash
# Container Freeze - Main Setup Script
# Sets up the complete POC environment using a VM with K3s

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║      Container Freeze - Kubernetes Forensics POC Setup       ║"
echo "║         'They're Inside. Now What?'                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

echo "This will:"
echo "  1. Create a Ubuntu 22.04 VM with libvirt"
echo "  2. Install K3s (lightweight Kubernetes)"
echo "  3. Deploy Tetragon (real eBPF!) and POC workloads"
echo ""

# Step 1: Create VM
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1/3: Creating VM"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./vm/setup-vm.sh

# Step 2: Install K3s
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2/3: Installing K3s"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./vm/install-k3s.sh

# Step 3: Deploy POC
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3/3: Deploying POC"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./vm/deploy-poc.sh

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    SETUP COMPLETE                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Run the demo:"
echo "  ./demo.sh"
echo ""
echo "Or manually:"
echo "  ./vm/ssh.sh"
echo "  cd ~/container-freeze && ./run-poc.sh"
echo ""
echo "Cleanup:"
echo "  ./vm/destroy-vm.sh"
echo ""
