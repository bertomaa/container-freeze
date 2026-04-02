#!/bin/bash
# Container Freeze - VM connection helpers
# Shared functions for SSH/SCP construction and OS detection

# Detect host OS
# Returns: macos | linux | unsupported
detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        *)      echo "unsupported" ;;
    esac
}

# Load VM connection info and set SSH/SCP variables
# Requires $VM_DIR to be set
# Sets: SSH, SCP, VM_IP, VM_SSH_PORT, SSH_KEY
load_vm_connection() {
    local vm_dir="${VM_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/vm}"

    if [ ! -f "$vm_dir/connection.env" ]; then
        echo "ERROR: VM not set up. Run ./vm/setup-vm.sh first."
        return 1
    fi

    source "$vm_dir/connection.env"

    local port_arg="" scp_port_arg=""
    if [ -n "$VM_SSH_PORT" ]; then
        port_arg="-p $VM_SSH_PORT"
        scp_port_arg="-P $VM_SSH_PORT"
    fi

    SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=no $port_arg cfuser@$VM_IP"
    SCP="scp -i $SSH_KEY -o StrictHostKeyChecking=no $scp_port_arg"
}
