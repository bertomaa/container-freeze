#!/bin/bash
# SSH into the Container Freeze VM

VM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$VM_DIR/connection.env" ]; then
    echo "VM not set up yet. Run: ./vm/setup-vm.sh"
    exit 1
fi

source "$VM_DIR/connection.env"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no cfuser@"$VM_IP" "$@"
