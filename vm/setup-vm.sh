#!/bin/bash
# Setup VM for Container Freeze POC
# Step 1: Creates a minimal Ubuntu VM with SSH access only
# Step 2: Run install-k3s.sh separately after VM is up

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="$PROJECT_ROOT/vm"
VM_NAME="container-freeze-vm"
VM_RAM="4096"
VM_CPUS="2"
VM_DISK="20G"

CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
CLOUD_IMAGE="$VM_DIR/ubuntu-22.04-cloud.img"
VM_DISK_PATH="$VM_DIR/${VM_NAME}.qcow2"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║    Container Freeze POC - VM Setup (Step 1: Create VM)       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Ensure libvirt network exists and is running
echo "[1/6] Setting up libvirt network..."
if ! sudo virsh net-info default &>/dev/null; then
    cat > /tmp/default-network.xml << 'EOF'
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF
    sudo virsh net-define /tmp/default-network.xml
fi
sudo virsh net-start default 2>/dev/null || true
sudo virsh net-autostart default 2>/dev/null || true
echo "  ✓ Network ready"

# Step 2: Enable IP forwarding and NAT
echo "[2/6] Configuring host networking..."
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -1)
sudo iptables -t nat -C POSTROUTING -s 192.168.122.0/24 ! -d 192.168.122.0/24 -j MASQUERADE 2>/dev/null || \
    sudo iptables -t nat -A POSTROUTING -s 192.168.122.0/24 ! -d 192.168.122.0/24 -j MASQUERADE
sudo iptables -C FORWARD -i virbr0 -o "$DEFAULT_IF" -j ACCEPT 2>/dev/null || \
    sudo iptables -I FORWARD -i virbr0 -o "$DEFAULT_IF" -j ACCEPT
sudo iptables -C FORWARD -o virbr0 -i "$DEFAULT_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    sudo iptables -I FORWARD -o virbr0 -i "$DEFAULT_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT
echo "  ✓ NAT configured"

# Step 3: Download cloud image if needed
echo "[3/6] Checking cloud image..."
mkdir -p "$VM_DIR"
if [ ! -f "$CLOUD_IMAGE" ]; then
    echo "  Downloading Ubuntu 22.04 cloud image (~700MB)..."
    curl -L -o "$CLOUD_IMAGE" "$CLOUD_IMAGE_URL"
fi
echo "  ✓ Cloud image ready"

# Step 4: Generate SSH key if needed
echo "[4/6] Setting up SSH key..."
if [ ! -f "$VM_DIR/id_rsa" ]; then
    ssh-keygen -t rsa -b 4096 -f "$VM_DIR/id_rsa" -N "" -q
fi
SSH_PUB_KEY=$(cat "$VM_DIR/id_rsa.pub")
echo "  ✓ SSH key ready"

# Step 5: Create minimal cloud-init (SSH only, no packages)
echo "[5/6] Creating cloud-init..."
cat > "$VM_DIR/user-data" << EOF
#cloud-config
hostname: ${VM_NAME}
manage_etc_hosts: true

users:
  - name: cfuser
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${SSH_PUB_KEY}

# Minimal - no package installation, we do that separately
runcmd:
  - touch /home/cfuser/.vm-ready
EOF

cat > "$VM_DIR/meta-data" << EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF

# Create cloud-init ISO
genisoimage -output "$VM_DIR/cloud-init.iso" -volid cidata -joliet -rock \
    "$VM_DIR/user-data" "$VM_DIR/meta-data" 2>/dev/null || \
mkisofs -output "$VM_DIR/cloud-init.iso" -volid cidata -joliet -rock \
    "$VM_DIR/user-data" "$VM_DIR/meta-data" 2>/dev/null
echo "  ✓ cloud-init.iso created"

# Step 6: Create and start VM
echo "[6/6] Creating VM..."

# Remove existing VM if present
if sudo virsh dominfo "$VM_NAME" &>/dev/null; then
    sudo virsh destroy "$VM_NAME" 2>/dev/null || true
    sudo virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
    rm -f "$VM_DISK_PATH"
fi

# Create disk
qemu-img create -f qcow2 -F qcow2 -b "$CLOUD_IMAGE" "$VM_DISK_PATH" "$VM_DISK"

# Create VM
sudo virt-install \
    --name "$VM_NAME" \
    --memory "$VM_RAM" \
    --vcpus "$VM_CPUS" \
    --disk path="$VM_DISK_PATH",format=qcow2 \
    --disk path="$VM_DIR/cloud-init.iso",device=cdrom \
    --os-variant ubuntu22.04 \
    --network network=default \
    --graphics none \
    --console pty,target_type=serial \
    --noautoconsole \
    --import

echo "  ✓ VM created"

# Wait for IP
echo ""
echo "Waiting for VM to get IP..."
for i in {1..30}; do
    VM_IP=$(sudo virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oP '192\.168\.122\.\d+' | head -1)
    if [ -n "$VM_IP" ]; then
        break
    fi
    sleep 2
    echo -n "."
done
echo ""

if [ -z "$VM_IP" ]; then
    echo "ERROR: Could not get VM IP"
    exit 1
fi

# Wait for SSH
echo "Waiting for SSH..."
for i in {1..30}; do
    if ssh -i "$VM_DIR/id_rsa" -o StrictHostKeyChecking=no -o ConnectTimeout=2 cfuser@"$VM_IP" "true" 2>/dev/null; then
        break
    fi
    sleep 2
    echo -n "."
done
echo ""

# Save connection info
cat > "$VM_DIR/connection.env" << EOF
VM_NAME=${VM_NAME}
VM_IP=${VM_IP}
SSH_KEY=${VM_DIR}/id_rsa
EOF

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    VM CREATED                                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "  VM IP: $VM_IP"
echo "  SSH:   ssh -i $VM_DIR/id_rsa cfuser@$VM_IP"
echo ""
echo "Next step: ./vm/install-k3s.sh"
echo ""
