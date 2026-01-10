#!/bin/bash
# Fileless Supply Chain Attack Demo - Tetragon Blocking Mode
# This script runs INSIDE the VM

set -e

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cd ~/container-freeze/current-demo

# Detect if running interactively
if [ -t 0 ]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
fi

# Helper function for interactive pauses
pause_interactive() {
    if [ "$INTERACTIVE" = true ]; then
        read -p "$1"
    else
        echo "$1"
        sleep 2
    fi
}

echo ""
echo "========================================================================"
echo "     FILELESS SUPPLY CHAIN ATTACK - Tetragon Blocking Demo"
echo "========================================================================"
echo ""
echo "Scenario: A compromised container image contains a hidden backdoor in the"
echo "          /api/health endpoint. When triggered with X-Debug header, it"
echo "          downloads and executes a malicious script in memory."
echo ""
echo "Key Innovation: Tetragon BLOCKS the attack with SIGSTOP, allowing CRIU"
echo "                to capture the in-memory script BEFORE full execution."
echo ""

# ============================================================================
# Phase 1: Environment Verification
# ============================================================================
echo "------------------------------------------------------------------------"
echo "Phase 1: Environment Verification"
echo "------------------------------------------------------------------------"
echo ""

echo "[*] Kubernetes cluster:"
kubectl get nodes
echo ""

echo "[*] Tetragon status (eBPF monitoring in BLOCKING mode):"
kubectl get pods -n kube-system -l app.kubernetes.io/name=tetragon
echo ""

echo "[*] TracingPolicy (configured for SIGSTOP):"
kubectl get tracingpolicies
echo ""

echo "[*] Production pods:"
kubectl get pods -n production
echo ""

echo "[*] Payload server (attacker infrastructure):"
kubectl get pods -n malicious-cdn
echo ""

echo "[*] Waiting for payment-backend pod to be ready..."
if ! kubectl wait --for=condition=ready pod -n production -l app=payment-backend --timeout=120s 2>/dev/null; then
    echo "[!] ERROR: payment-backend pod not ready after 120s"
    exit 1
fi
echo ""

POD_NAME=$(kubectl get pods -n production -l app=payment-backend -o jsonpath='{.items[0].metadata.name}')
echo "[*] Target pod: $POD_NAME"
echo ""

echo "[*] Testing normal health endpoint (no backdoor trigger):"
echo "    curl http://payment-backend:8080/api/health"
kubectl exec -n production "$POD_NAME" -- curl -s http://localhost:8080/api/health
echo ""
echo ""

pause_interactive "Press ENTER to trigger the attack..."
echo ""

# ============================================================================
# Phase 2: Attack Trigger
# ============================================================================
echo "------------------------------------------------------------------------"
echo "Phase 2: Attack Trigger"
echo "------------------------------------------------------------------------"
echo ""

echo "[*] Triggering backdoor via health endpoint with X-Debug header..."
echo ""
echo "    curl -H 'X-Debug: enable' http://payment-backend:8080/api/health"
echo ""

# Trigger the backdoor
kubectl exec -n production "$POD_NAME" -- curl -s -H "X-Debug: enable" http://localhost:8080/api/health
echo ""
echo ""

echo "[*] Backdoor triggered - malicious payload download initiated"
echo "[*] Waiting for Tetragon to detect credential access..."
echo ""

# Give the malware a moment to download and start executing
sleep 3

# Check Tetragon events
TETRAGON_POD=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=tetragon -o jsonpath='{.items[0].metadata.name}')

echo "[*] Checking Tetragon events..."
echo ""

# Look for the SIGSTOP event or credential access
TETRAGON_EVENTS=$(kubectl logs -n kube-system "$TETRAGON_POD" -c export-stdout --tail=50 2>/dev/null || echo "")

if echo "$TETRAGON_EVENTS" | grep -q "serviceaccount\|SIGSTOP\|signal"; then
    echo "[!] TETRAGON ALERT: Suspicious activity detected!"
    echo ""
    echo "$TETRAGON_EVENTS" | grep -E "process_kprobe|openat|serviceaccount|signal" | tail -10
    echo ""
else
    echo "[*] Tetragon events (recent activity):"
    echo "$TETRAGON_EVENTS" | grep -E "process|connect|python" | tail -10 || echo "    (checking for events...)"
    echo ""
fi

echo "[*] Payload server logs (evidence of download):"
kubectl logs -n malicious-cdn -l app=payload-server --tail=10 2>&1 | grep -Ei "DOWNLOAD|EXFIL|payload" || echo "    (checking for download evidence...)"
MALICIOUS_SERVER_POD_NAME=$(kubectl get pods -n malicious-cdn -l app=payload-server -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n malicious-cdn "$MALICIOUS_SERVER_POD_NAME" -- cat /var/log/payload/downloads.log
echo ""

pause_interactive "Press ENTER to capture forensic checkpoint..."
echo ""

# ============================================================================
# Phase 3: Forensic Capture
# ============================================================================
echo "------------------------------------------------------------------------"
echo "Phase 3: Forensic Capture (CRIU Checkpoint)"
echo "------------------------------------------------------------------------"
echo ""
echo "[*] Capturing process memory with CRIU checkpoint..."
echo "[*] This captures the in-memory script that was NEVER written to disk!"
echo ""

mkdir -p /tmp/k8s-checkpoints
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CHECKPOINT_DIR="/tmp/k8s-checkpoints/${POD_NAME}_${TIMESTAMP}"
mkdir -p "$CHECKPOINT_DIR"

# Get container ID
CONTAINER_ID=$(kubectl get pod "$POD_NAME" -n production -o jsonpath="{.status.containerStatuses[0].containerID}" | sed 's|containerd://||')

if [ -n "$CONTAINER_ID" ]; then
    echo "[*] Container ID: $CONTAINER_ID"
    echo "[*] Executing CRIU checkpoint..."
    echo ""

    # Try CRIU checkpoint
    if sudo crictl checkpoint --export="$CHECKPOINT_DIR/checkpoint.tar" "$CONTAINER_ID" 2>&1 | tee "$CHECKPOINT_DIR/criu-output.log"; then
        echo ""
        echo "[+] CRIU checkpoint SUCCESS!"
        echo "[+] Checkpoint saved to: $CHECKPOINT_DIR/checkpoint.tar"
        CHECKPOINT_SUCCESS=true
    else
        echo ""
        echo "[!] CRIU checkpoint failed (see $CHECKPOINT_DIR/criu-output.log)"
        echo "[*] Continuing with available evidence..."
        CHECKPOINT_SUCCESS=false
    fi
else
    echo "[!] Could not get container ID"
    CHECKPOINT_SUCCESS=false
fi

echo ""
echo "[*] Capturing container logs as evidence..."
kubectl logs -n production "$POD_NAME" > "$CHECKPOINT_DIR/container_logs.txt" 2>/dev/null || true
kubectl logs -n malicious-cdn -l app=payload-server > "$CHECKPOINT_DIR/payload_server_logs.txt" 2>/dev/null || true

# Apply network isolation
echo ""
echo "[*] Applying network isolation (quarantine)..."
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine-${POD_NAME}
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: payment-backend
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
echo "[+] NetworkPolicy applied - pod is now quarantined"
echo ""

pause_interactive "Press ENTER to analyze captured memory..."
echo ""

# ============================================================================
# Phase 4: Memory Analysis
# ============================================================================
echo "------------------------------------------------------------------------"
echo "Phase 4: Memory Analysis"
echo "------------------------------------------------------------------------"
echo ""

cd "$CHECKPOINT_DIR"

if [ "$CHECKPOINT_SUCCESS" = true ] && [ -f "checkpoint.tar" ]; then
    echo "========================================================================"
    echo "CHECKPOINT MEMORY ANALYSIS - THE KEY DEMO!"
    echo "========================================================================"
    echo ""
    echo "[*] Scanning checkpoint memory for malicious strings..."
    echo "[*] Looking for FILELESS script and STOLEN CREDENTIALS..."
    echo ""

    # We use 'strings' directly on the tarball which is more robust than extraction
    # patterns based on the manual verification we did
    
    echo "=== RECOVERED SCRIPT CONTENT FROM MEMORY ==="
    echo "(This script was NEVER written to disk - only in memory)"
    echo ""
    
    # Capture the script header and the first few lines of execution
    sudo strings checkpoint.tar 2>/dev/null | grep -A 15 "FILELESS MALWARE PAYLOAD" || \
    sudo strings checkpoint.tar 2>/dev/null | grep -A 10 "=== FILELESS PAYLOAD EXECUTING" || \
    echo "  (Header not found, searching for other signatures...)"

    echo ""
    echo "=== MALWARE EXECUTION STAGES (Memory Artifacts) ==="
    # Look for the log lines generated by the malware in memory
    sudo strings checkpoint.tar 2>/dev/null | grep -E "Stage [0-9]:|Reconnaissance|Exfiltration|Persistence" | sort -u | head -10

    echo ""
    echo "=== CREDENTIALS FOUND IN MEMORY ==="
    # Look for the specific secrets we saw in the logs
    sudo strings checkpoint.tar 2>/dev/null | grep -E "AWS_|STRIPE_|DATABASE_|AKIA[A-Z0-9]+" | sort -u | grep -v "AWS_CONTAINER" | head -20
    
    echo ""
    echo "[+] The above shows the malicious script and data were captured from"
    echo "[+] process memory - even though it was NEVER written to disk!"

else
    echo "[!] Checkpoint not available - showing log-based evidence only"
    echo ""

    if [ -f "container_logs.txt" ]; then
        echo "=== MALWARE ACTIVITY (from container logs) ==="
        sudo grep -E "PAYLOAD|Stage|telemetry|secret|EXFIL|Debug sync" container_logs.txt 2>/dev/null | head -20 || echo "  (check container_logs.txt)"
        echo ""
    fi

    if [ -f "payload_server_logs.txt" ]; then
        echo "=== PAYLOAD SERVER EVIDENCE ==="
        sudo grep -E "DOWNLOAD|EXFIL|payload" payload_server_logs.txt 2>/dev/null | head -10 || echo "  (check payload_server_logs.txt)"
        echo ""
    fi
fi
# Create forensic bundle
echo ""
echo "[*] Creating forensic bundle..."
cd /tmp/k8s-checkpoints
sudo tar -czf "${POD_NAME}_${TIMESTAMP}_forensics.tar.gz" "${POD_NAME}_${TIMESTAMP}/" 2>/dev/null || true
sudo chown cfuser:cfuser "${POD_NAME}_${TIMESTAMP}_forensics.tar.gz" 2>/dev/null || true

echo ""
echo "========================================================================"
echo "                         DEMO COMPLETE"
echo "========================================================================"
echo ""
echo "Summary:"
echo "  [+] Backdoor triggered via /api/health with X-Debug header"
echo "  [+] Malicious script downloaded and executed IN MEMORY"
echo "  [+] Tetragon detected suspicious activity (credential access)"
if [ "$CHECKPOINT_SUCCESS" = true ]; then
echo "  [+] CRIU captured the in-memory script content!"
fi
echo "  [+] Pod isolated (attacker cut off from C2)"
echo ""
echo "Forensic evidence location:"
echo "  $CHECKPOINT_DIR/"
echo "  /tmp/k8s-checkpoints/${POD_NAME}_${TIMESTAMP}_forensics.tar.gz"
echo ""
echo "Key Takeaways:"
echo "  1. Fileless malware leaves NO disk artifacts"
echo "  2. Traditional forensics can't see memory-only scripts"
echo "  3. Tetragon can BLOCK attacks with SIGSTOP before completion"
echo "  4. CRIU checkpoint captures EVERYTHING from process memory"
echo "  5. Don't kill compromised pods - checkpoint them first!"
echo ""
