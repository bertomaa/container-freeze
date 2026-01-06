#!/bin/bash
# Deploy the Container Freeze POC to the VM
# Run after install-k3s.sh

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="$PROJECT_ROOT/vm"

if [ ! -f "$VM_DIR/connection.env" ]; then
    echo "ERROR: Run ./vm/setup-vm.sh first"
    exit 1
fi

source "$VM_DIR/connection.env"
SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=no cfuser@$VM_IP"
SCP="scp -i $SSH_KEY -o StrictHostKeyChecking=no"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║      Container Freeze POC - Deploy (Step 3)                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Verify K3s
echo "[1/5] Verifying K3s..."
$SSH "kubectl get nodes" || { echo "ERROR: K3s not running. Run ./vm/install-k3s.sh first"; exit 1; }
echo "  ✓ K3s running"

# Copy files
echo "[2/5] Copying POC files..."
$SSH "mkdir -p ~/container-freeze"
$SCP -r "$PROJECT_ROOT/vulnerable-app" cfuser@$VM_IP:~/container-freeze/
$SCP -r "$PROJECT_ROOT/malware" cfuser@$VM_IP:~/container-freeze/
$SCP -r "$PROJECT_ROOT/c2-server" cfuser@$VM_IP:~/container-freeze/
$SCP -r "$PROJECT_ROOT/detection" cfuser@$VM_IP:~/container-freeze/
$SCP -r "$PROJECT_ROOT/response" cfuser@$VM_IP:~/container-freeze/
$SCP -r "$PROJECT_ROOT/forensics" cfuser@$VM_IP:~/container-freeze/
echo "  ✓ Files copied"

# Build images
echo "[3/5] Building container images..."
$SSH << 'EOF'
cd ~/container-freeze
sudo docker build -t localhost/vulnerable-app:latest ./vulnerable-app
sudo docker build -t localhost/sleepy-malware:latest ./malware
sudo docker build -t localhost/c2-server:latest ./c2-server
sudo docker save localhost/vulnerable-app:latest | sudo k3s ctr images import -
sudo docker save localhost/sleepy-malware:latest | sudo k3s ctr images import -
sudo docker save localhost/c2-server:latest | sudo k3s ctr images import -
EOF
echo "  ✓ Images built"

# Install Tetragon
echo "[4/5] Installing Tetragon..."
$SSH << 'EOF'
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm repo add cilium https://helm.cilium.io
helm repo update
helm install tetragon cilium/tetragon --namespace kube-system --wait --timeout 5m || true
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=tetragon -n kube-system --timeout=120s
EOF
echo "  ✓ Tetragon installed"

# Deploy workloads
echo "[5/5] Deploying workloads..."
$SSH << 'EOF'
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cd ~/container-freeze
kubectl apply -f detection/tracing-policy-reverse-shell.yaml 2>/dev/null || true
kubectl apply -f detection/tracing-policy-network.yaml 2>/dev/null || true
kubectl apply -f detection/tracing-policy-fileless.yaml 2>/dev/null || true
kubectl apply -f c2-server/deployment.yaml
kubectl apply -f vulnerable-app/deployment.yaml
kubectl wait --for=condition=ready pod -l app=c2-server -n attacker-infra --timeout=60s
kubectl wait --for=condition=ready pod -l app=payment-processor -n production --timeout=60s
EOF
echo "  ✓ Workloads deployed"

# Copy run script
$SCP "$VM_DIR/run-poc.sh" cfuser@$VM_IP:~/container-freeze/

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    POC DEPLOYED                               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
$SSH "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get pods -A | grep -E 'production|attacker|tetragon'"
echo ""
echo "Run the POC:"
echo "  ./vm/ssh.sh"
echo "  cd ~/container-freeze && ./run-poc.sh"
echo ""
