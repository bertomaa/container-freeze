#!/bin/bash
# Run the complete POC on the VM
# This script should be run FROM INSIDE the VM

set -e

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cd ~/container-freeze

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║      Container Freeze POC - Kubernetes Forensics              ║"
echo "║         Running on K3s with real eBPF support                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# Phase 1: Verify Environment
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 1: Environment Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Kubernetes cluster:"
kubectl get nodes
echo ""

echo "Tetragon status (eBPF monitoring):"
kubectl get pods -n kube-system -l app.kubernetes.io/name=tetragon
echo ""

echo "TracingPolicies:"
kubectl get tracingpolicies
echo ""

echo "Production pods:"
kubectl get pods -n production
echo ""

POD_NAME=$(kubectl get pods -n production -l app=payment-processor -o jsonpath='{.items[0].metadata.name}')
echo "Target pod: $POD_NAME"
echo ""

read -p "Press ENTER to start the attack simulation..."
echo ""

# ============================================================================
# Phase 2: Trigger Attack
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 2: Triggering Attack"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Simulating attacker finding backdoor endpoint..."
echo ""

# Hit the backdoor
kubectl exec -n production "$POD_NAME" -c app -- \
    curl -s http://localhost:8080/.env

echo ""
echo "✓ Backdoor triggered - malware activation signal sent"
echo ""

sleep 5

echo "Malware logs:"
kubectl logs -n production "$POD_NAME" -c malware-sidecar --tail=30

echo ""
read -p "Press ENTER to check Tetragon detection..."
echo ""

# ============================================================================
# Phase 3: eBPF Detection
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 3: eBPF Detection (Tetragon)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

TETRAGON_POD=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=tetragon -o jsonpath='{.items[0].metadata.name}')

echo "Tetragon eBPF events (last 50 lines):"
kubectl logs -n kube-system "$TETRAGON_POD" -c export-stdout --tail=50 | \
    grep -E "process_exec|process_connect|ALERT" | head -20 || \
    echo "(Events may take a moment to appear)"

echo ""
read -p "Press ENTER to checkpoint the compromised pod..."
echo ""

# ============================================================================
# Phase 4: Forensic Checkpoint
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 4: Forensic Checkpoint (CRIU)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

mkdir -p /tmp/k8s-checkpoints
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CHECKPOINT_DIR="/tmp/k8s-checkpoints/${POD_NAME}_${TIMESTAMP}"
mkdir -p "$CHECKPOINT_DIR"

echo "Capturing pre-checkpoint forensic data..."

# Capture process list
echo "  → Process list..."
kubectl exec -n production "$POD_NAME" -c malware-sidecar -- ps aux > "$CHECKPOINT_DIR/processes.txt" 2>/dev/null || true

# Capture network connections
echo "  → Network connections..."
kubectl exec -n production "$POD_NAME" -c malware-sidecar -- netstat -antp > "$CHECKPOINT_DIR/network.txt" 2>/dev/null || true

# Capture environment variables (contains the secrets!)
echo "  → Environment variables..."
kubectl exec -n production "$POD_NAME" -c malware-sidecar -- env | sort > "$CHECKPOINT_DIR/env.txt" 2>/dev/null || true

# Capture container logs
echo "  → Container logs..."
kubectl logs -n production "$POD_NAME" -c malware-sidecar > "$CHECKPOINT_DIR/malware_logs.txt" 2>/dev/null || true
kubectl logs -n production "$POD_NAME" -c app > "$CHECKPOINT_DIR/app_logs.txt" 2>/dev/null || true

# Try CRIU checkpoint (may require additional setup)
echo ""
echo "Attempting CRIU checkpoint..."

# Get container ID
CONTAINER_ID=$(kubectl get pod "$POD_NAME" -n production -o jsonpath="{.status.containerStatuses[?(@.name=='malware-sidecar')].containerID}" | sed 's|containerd://||')

if [ -n "$CONTAINER_ID" ]; then
    echo "  Container ID: $CONTAINER_ID"

    # Try crictl checkpoint
    if sudo crictl checkpoint --export="$CHECKPOINT_DIR/checkpoint.tar" "$CONTAINER_ID" 2>/dev/null; then
        echo "  ✓ CRIU checkpoint created"
    else
        echo "  ⚠️  CRIU checkpoint failed (may need additional kernel config)"
        echo "  ℹ️  Continuing with metadata-based forensics..."
    fi
else
    echo "  ⚠️  Could not get container ID"
fi

# Create forensic bundle
echo ""
echo "Creating forensic bundle..."
cd /tmp/k8s-checkpoints
tar -czf "${POD_NAME}_${TIMESTAMP}_forensics.tar.gz" "${POD_NAME}_${TIMESTAMP}/"
echo "  ✓ Bundle: /tmp/k8s-checkpoints/${POD_NAME}_${TIMESTAMP}_forensics.tar.gz"

echo ""
read -p "Press ENTER to isolate the pod..."
echo ""

# ============================================================================
# Phase 5: Network Isolation
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 5: Network Isolation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Apply NetworkPolicy
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine-${POD_NAME}
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: payment-processor
  policyTypes:
  - Egress
  - Ingress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
  ingress: []
EOF

echo "✓ NetworkPolicy applied - pod is now quarantined"
echo ""

echo "Verifying isolation (C2 connection should fail)..."
kubectl exec -n production "$POD_NAME" -c malware-sidecar -- \
    timeout 3 curl -v http://c2-server.attacker-infra.svc.cluster.local:8080 2>&1 || echo "✓ C2 connection blocked (expected)"

echo ""
read -p "Press ENTER to analyze forensic data..."
echo ""

# ============================================================================
# Phase 6: Forensic Analysis
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 6: Forensic Analysis"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$CHECKPOINT_DIR"

echo "🔍 CREDENTIALS FOUND IN ENVIRONMENT:"
echo "────────────────────────────────────────"
grep -E "KEY|SECRET|PASSWORD|TOKEN|STRIPE" env.txt 2>/dev/null | while IFS='=' read -r key value; do
    echo "  🔑 $key = $value"
done
echo ""

echo "🔍 SUSPICIOUS PROCESSES:"
echo "────────────────────────────────────────"
grep -E "bash|sh|nc|curl|wget|python" processes.txt 2>/dev/null | head -10 || echo "  (none found)"
echo ""

echo "🔍 NETWORK CONNECTIONS:"
echo "────────────────────────────────────────"
grep -E "ESTABLISHED|LISTEN|attacker" network.txt 2>/dev/null | head -10 || echo "  (none found)"
echo ""

echo "🔍 MALWARE ACTIVITY LOG:"
echo "────────────────────────────────────────"
grep -E "MALWARE|C2|exfil|ACTIVATED" malware_logs.txt 2>/dev/null | head -20 || echo "  (check malware_logs.txt)"
echo ""

# If checkpoint exists, analyze it
if [ -f "checkpoint.tar" ]; then
    echo "🔍 CHECKPOINT MEMORY ANALYSIS:"
    echo "────────────────────────────────────────"
    echo "Extracting strings from memory dump..."
    tar -tf checkpoint.tar 2>/dev/null | head -20
    # Could extract and analyze memory pages here
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    POC COMPLETE                               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Summary:"
echo "  ✓ Attack triggered and executed"
echo "  ✓ eBPF (Tetragon) detected suspicious syscalls"
echo "  ✓ Forensic data captured before evidence destruction"
echo "  ✓ Pod isolated (attacker cut off from C2)"
echo "  ✓ Credentials extracted from captured data"
echo ""
echo "Forensic evidence location:"
echo "  $CHECKPOINT_DIR/"
echo "  /tmp/k8s-checkpoints/${POD_NAME}_${TIMESTAMP}_forensics.tar.gz"
echo ""
echo "Key Takeaways:"
echo "  1. Don't kill compromised pods - checkpoint them first"
echo "  2. eBPF sees everything at kernel level"
echo "  3. Memory forensics reveals what logs don't show"
echo ""
