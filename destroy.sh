#!/bin/bash
# Container Freeze - Destroy Everything
# Cleans up all resources created by the POC

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         Container Freeze - Cleanup                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Destroy VM and libvirt resources
./vm/destroy-vm.sh

# Clean any leftover kind clusters (from old setup)
if command -v kind &>/dev/null; then
    kind delete cluster --name container-freeze-cluster 2>/dev/null && echo "  ✓ Old kind cluster deleted" || true
fi

# Clean checkpoint data
rm -rf /tmp/k8s-checkpoints 2>/dev/null || true
rm -rf /tmp/forensic-analysis 2>/dev/null || true
echo "  ✓ Checkpoint data cleaned"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    ALL CLEAN                                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "To start fresh: ./setup.sh"
echo ""
