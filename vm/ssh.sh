#!/bin/bash
# SSH into the Container Freeze VM

VM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$VM_DIR/connection.env" ]; then
    echo "VM not set up yet. Run: ./vm/setup-vm.sh"
    exit 1
fi

VM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$VM_DIR")/lib/vm.sh"
load_vm_connection || exit 1
$SSH "$@"
