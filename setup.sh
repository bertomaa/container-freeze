#!/bin/bash
# Container Freeze - Main Setup Script
# Sets up the VM and K3s environment (demo deployment handled separately)

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

echo ""
echo "========================================================================"
echo "      Container Freeze - Kubernetes Forensics Environment Setup"
echo "========================================================================"
echo ""

echo "This will:"
echo "  1. Create a Ubuntu 22.04 VM with libvirt"
echo "  2. Install K3s (lightweight Kubernetes)"
echo ""
echo "Note: Demo deployment is handled separately via 'cfreeze demo'"
echo ""

# Step 1: Create VM
echo "------------------------------------------------------------------------"
echo "Step 1/2: Creating VM"
echo "------------------------------------------------------------------------"
./vm/setup-vm.sh

# Step 2: Install K3s
echo ""
echo "------------------------------------------------------------------------"
echo "Step 2/2: Installing K3s"
echo "------------------------------------------------------------------------"
./vm/install-k3s.sh

echo ""
echo "========================================================================"
echo "                       SETUP COMPLETE"
echo "========================================================================"
echo ""
echo "Next steps:"
echo "  cfreeze demo    # Select and deploy a demo scenario"
echo "  cfreeze status  # Check environment status"
echo ""
echo "Or use interactive mode:"
echo "  cfreeze"
echo ""
