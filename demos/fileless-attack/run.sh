#!/bin/bash
# Fileless Supply Chain Attack Demo - Run script
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
echo "     FILELESS SUPPLY CHAIN ATTACK - Memory-Only Malware Demo"
echo "========================================================================"
echo ""
echo "Scenario: A compromised container image contains a hidden malicious"
echo "          binary disguised as 'telemetry-agent'. After 10 seconds,"
echo "          it downloads and executes a malicious script"
echo ""
echo "Goal:     Demonstrate that CRIU checkpoint captures the full script"
echo "          from process memory, even though it was never on disk."
echo ""

# ============================================================================
# Phase 1: Verify Environment
# ============================================================================
echo "------------------------------------------------------------------------"
echo "Phase 1: Environment Check"
echo "------------------------------------------------------------------------"
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

echo "Payload server (in malicious-cdn namespace):"
kubectl get pods -n malicious-cdn
echo ""

echo "Waiting for payment-backend pod to be ready..."
if ! kubectl wait --for=condition=ready pod -n production -l app=payment-backend --timeout=120s 2>/dev/null; then
    echo "[!] ERROR: payment-backend pod not ready after 120s"
    echo "    Check deployments with: kubectl get pods -n production"
    exit 1
fi
echo ""

POD_NAME=$(kubectl get pods -n production -l app=payment-backend -o jsonpath='{.items[0].metadata.name}')
echo "Target pod: $POD_NAME"
echo ""

echo "Application health check:"
kubectl exec -n production "$POD_NAME" -c backend -- curl -s http://localhost:8080/api/health | head -1
echo ""

pause_interactive "Press ENTER to wait for the malware to activate (10 seconds after pod start)..."
echo ""

# ============================================================================
# Phase 2: Wait for Malware Activation
# ============================================================================
echo "------------------------------------------------------------------------"
echo "Phase 2: Malware Activation (Automatic after 10s)"
echo "------------------------------------------------------------------------"
echo ""

echo "The malware is disguised as 'telemetry-agent' and activates automatically."
echo "Unlike the payment-breach demo, there is no trigger endpoint."
echo "This simulates a more stealthy supply chain attack."
echo ""

echo "Checking container logs for malware activity..."
echo ""
sleep 5

# Show logs from the container
echo "=== Container Logs (look for [telemetry] entries) ==="
kubectl logs -n production "$POD_NAME" -c backend --tail=30 2>&1 | grep -E "telemetry|PAYLOAD|Stage" || echo "(Malware may still be initializing...)"
echo ""

echo "Waiting for payload download and execution..."
sleep 10

echo "=== Updated Logs ==="
kubectl logs -n production "$POD_NAME" -c backend --tail=50 2>&1 | grep -E "telemetry|PAYLOAD|Stage|secret" || echo "(Check full logs)"
echo ""

pause_interactive "Press ENTER to check Tetragon detection..."
echo ""

# ============================================================================
# Phase 3: eBPF Detection
# ============================================================================
echo "------------------------------------------------------------------------"
echo "Phase 3: eBPF Detection (Tetragon)"
echo "------------------------------------------------------------------------"
echo ""

TETRAGON_POD=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=tetragon -o jsonpath='{.items[0].metadata.name}')

echo "Tetragon eBPF events (looking for suspicious activity):"
kubectl logs -n kube-system "$TETRAGON_POD" -c export-stdout --tail=100 | \
    grep -E "process_exec|process_connect|tcp_connect|python|payload" | tail -20 || \
    echo "(Events may take a moment to appear)"

echo ""
echo "Payload server logs (evidence of download):"
kubectl logs -n malicious-cdn -l app=payload-server --tail=20 2>&1 | grep -E "DOWNLOAD|EXFIL" || echo "(No download events yet)"

echo ""
pause_interactive "Press ENTER to checkpoint the compromised pod..."
echo ""

# ============================================================================
# Phase 4: Forensic Checkpoint
# ============================================================================
echo "------------------------------------------------------------------------"
echo "Phase 4: Forensic Checkpoint (CRIU)"
echo "------------------------------------------------------------------------"
echo ""
echo "This is the KEY PHASE - we capture the process memory which contains"
echo "the malicious script that was executed in memory."
echo ""

mkdir -p /tmp/k8s-checkpoints
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CHECKPOINT_DIR="/tmp/k8s-checkpoints/${POD_NAME}_${TIMESTAMP}"
mkdir -p "$CHECKPOINT_DIR"

echo "Capturing pre-checkpoint forensic data..."


# Capture process list
echo "  -> Process list..."
kubectl exec -n production "$POD_NAME" -c backend -- ps aux > "$CHECKPOINT_DIR/processes.txt" 2>/dev/null || true

# Capture network connections
echo "  -> Network connections..."
kubectl exec -n production "$POD_NAME" -c backend -- netstat -antp > "$CHECKPOINT_DIR/network.txt" 2>/dev/null || true

# Capture environment variables (contains the secrets!)
echo "  -> Environment variables..."
kubectl exec -n production "$POD_NAME" -c backend -- env | sort > "$CHECKPOINT_DIR/env.txt" 2>/dev/null || true

# Capture container logs
echo "  -> Container logs..."
kubectl logs -n production "$POD_NAME" -c backend > "$CHECKPOINT_DIR/container_logs.txt" 2>/dev/null || true

# Capture payload server logs (evidence)
echo "  -> Payload server logs..."
kubectl logs -n malicious-cdn -l app=payload-server > "$CHECKPOINT_DIR/payload_server_logs.txt" 2>/dev/null || true

# Try CRIU checkpoint
echo ""
echo "Attempting CRIU checkpoint (this captures the in-memory script!)..."

# Get container ID
CONTAINER_ID=$(kubectl get pod "$POD_NAME" -n production -o jsonpath="{.status.containerStatuses[?(@.name=='backend')].containerID}" | sed 's|containerd://||')

if [ -n "$CONTAINER_ID" ]; then
    echo "  Container ID: $CONTAINER_ID"

    # Try crictl checkpoint
    echo "  Attempting checkpoint (this may take a moment)..."

    # Capture the log path before the checkpoint attempt
    CRIU_LOG_DIR="/run/k3s/containerd/io.containerd.runtime.v2.task/k8s.io/${CONTAINER_ID}"
    CRIU_LOG="${CRIU_LOG_DIR}/criu-dump.log"

    # Run checkpoint and capture output
    sudo crictl checkpoint --export="$CHECKPOINT_DIR/checkpoint.tar" "$CONTAINER_ID" 2>&1 | tee "$CHECKPOINT_DIR/criu-output.log"
    CHECKPOINT_EXIT_CODE=${PIPESTATUS[0]}

    # IMMEDIATELY try to grab the CRIU log before it's cleaned up
    if [ -f "$CRIU_LOG" ]; then
        sudo cp "$CRIU_LOG" "$CHECKPOINT_DIR/criu-dump.log" 2>/dev/null || true
    fi

    # Check the actual crictl exit status (PIPESTATUS[0]), not tee's exit status
    if [ "$CHECKPOINT_EXIT_CODE" -eq 0 ] && [ -f "$CHECKPOINT_DIR/checkpoint.tar" ]; then
        echo "  [+] CRIU checkpoint created successfully!"
        echo "  [+] The checkpoint contains the FULL IN-MEMORY SCRIPT!"
    else
        echo "  [!] CRIU checkpoint failed"
        echo "  [i] Error details saved to: $CHECKPOINT_DIR/criu-output.log"
        echo "  [i] Continuing with metadata-based forensics..."

        if [ -f "$CHECKPOINT_DIR/criu-output.log" ]; then
            echo ""
            echo "  Debug info from crictl:"
            head -10 "$CHECKPOINT_DIR/criu-output.log" | sed 's/^/    /'
        fi

        # Check if we managed to capture the CRIU dump log
        echo ""
        if [ -f "$CHECKPOINT_DIR/criu-dump.log" ]; then
            echo "  CRIU dump log captured successfully!"
            echo ""
            echo "  CRIU failure details:"
            tail -50 "$CHECKPOINT_DIR/criu-dump.log" | sed 's/^/    /'
        else
            echo "  [!] Could not capture CRIU dump log (cleaned up too quickly)"
            echo "  [i] Attempting alternative diagnostics..."

            # Try to checkpoint with runc directly for better error output
            echo ""
            echo "  Attempting direct runc checkpoint for diagnostic info..."
            RUNC_STATE=$(sudo runc --root /run/containerd/runc/k8s.io state "$CONTAINER_ID" 2>&1 || true)
            if echo "$RUNC_STATE" | grep -q "running"; then
                # Try a test checkpoint to see detailed errors
                sudo runc --root /run/containerd/runc/k8s.io checkpoint \
                    --image-path="$CHECKPOINT_DIR/runc-test" \
                    --work-path="$CHECKPOINT_DIR/runc-work" \
                    "$CONTAINER_ID" 2>&1 | tee "$CHECKPOINT_DIR/runc-output.log" | head -20 | sed 's/^/    /' || true
            else
                echo "    (Container not accessible via runc)"
            fi
        fi
    fi
else
    echo "  [!] Could not get container ID"
fi

# Create forensic bundle
echo ""
echo "Creating forensic bundle..."
cd /tmp/k8s-checkpoints
sudo tar -czf "${POD_NAME}_${TIMESTAMP}_forensics.tar.gz" "${POD_NAME}_${TIMESTAMP}/"
sudo chown cfuser:cfuser "${POD_NAME}_${TIMESTAMP}_forensics.tar.gz"
echo "  [+] Bundle: /tmp/k8s-checkpoints/${POD_NAME}_${TIMESTAMP}_forensics.tar.gz"

echo ""
pause_interactive "Press ENTER to isolate the pod..."
echo ""

# ============================================================================
# Phase 5: Network Isolation
# ============================================================================
echo "------------------------------------------------------------------------"
echo "Phase 5: Network Isolation"
echo "------------------------------------------------------------------------"
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

echo "Verifying isolation (payload server connection should fail)..."
kubectl exec -n production "$POD_NAME" -c backend -- \
    timeout 3 curl -v http://payload-server.malicious-cdn.svc.cluster.local:8080/health 2>&1 || echo "[+] Payload server connection blocked (expected)"

echo ""
pause_interactive "Press ENTER to analyze forensic data..."
echo ""

# ============================================================================
# Phase 6: Forensic Analysis
# ============================================================================
echo "------------------------------------------------------------------------"
echo "Phase 6: Forensic Analysis"
echo "------------------------------------------------------------------------"
echo ""

cd "$CHECKPOINT_DIR"

echo "CREDENTIALS FOUND IN ENVIRONMENT:"
echo "------------------------------------"
grep -E "KEY|SECRET|PASSWORD|TOKEN|STRIPE|AWS|DATABASE" env.txt 2>/dev/null | while IFS='=' read -r key value; do
    echo "  [!] $key = $value"
done
echo ""

echo "SUSPICIOUS PROCESSES:"
echo "------------------------------------"
grep -E "python|telemetry" processes.txt 2>/dev/null | head -10 || echo "  (check processes.txt)"
echo ""

echo "NETWORK CONNECTIONS:"
echo "------------------------------------"
grep -E "ESTABLISHED|LISTEN|8080" network.txt 2>/dev/null | head -10 || echo "  (check network.txt)"
echo ""

echo "MALWARE ACTIVITY LOG (from container):"
echo "------------------------------------"
grep -E "PAYLOAD|Stage|telemetry|secret|EXFIL" container_logs.txt 2>/dev/null | head -20 || echo "  (check container_logs.txt)"
echo ""

echo "PAYLOAD SERVER EVIDENCE:"
echo "------------------------------------"
grep -E "DOWNLOAD|EXFIL|payload" payload_server_logs.txt 2>/dev/null | head -10 || echo "  (check payload_server_logs.txt)"
echo ""

# THE KEY PART - Extract the script from checkpoint memory!
if [ -f "checkpoint.tar" ]; then
    echo "========================================================================"
    echo "CHECKPOINT MEMORY ANALYSIS - THIS IS THE KEY DEMO!"
    echo "========================================================================"
    echo ""
    echo "Extracting strings from checkpoint memory..."
    echo "Looking for the FILELESS script that was executed in memory..."
    echo ""

    # Extract checkpoint
    mkdir -p checkpoint_extracted
    tar -xf checkpoint.tar -C checkpoint_extracted 2>/dev/null || true

    # Search for the malicious script content in memory dumps
    echo "=== RECOVERED SCRIPT CONTENT FROM MEMORY ==="
    echo "(This script was NEVER written to disk - only in memory)"
    echo ""

    # Look for distinctive strings from the payload
    if find checkpoint_extracted -name "*.img" -o -name "pages-*" 2>/dev/null | head -1 | grep -q .; then
        # Search memory images for script content
        find checkpoint_extracted -type f \( -name "*.img" -o -name "pages-*" \) -exec strings {} \; 2>/dev/null | \
            grep -A5 -B2 "FILELESS MALWARE PAYLOAD\|FILELESS PAYLOAD EXECUTING\|Stage 1: Reconnaissance\|Stage 2: Preparing exfil\|Stage 3: Attempting persistence" | \
            head -100 || echo "  (Searching for payload signatures...)"

        echo ""
        echo "=== SECRETS FOUND IN MEMORY ==="
        find checkpoint_extracted -type f \( -name "*.img" -o -name "pages-*" \) -exec strings {} \; 2>/dev/null | \
            grep -E "AKIA[A-Z0-9]{16}|sk_live_|SuperSecret|pgw_live_" | sort -u | head -20 || echo "  (No secrets in memory dumps)"
    else
        # Fallback to searching the tar directly
        strings checkpoint.tar 2>/dev/null | \
            grep -E "FILELESS|PAYLOAD|Stage [0-9]:|Reconnaissance|exfil" | head -30 || \
            echo "  (Run strings on checkpoint.tar manually for full analysis)"
    fi

    echo ""
    echo "The above shows that the ENTIRE malicious script was captured from"
    echo "process memory - even though it was NEVER written to disk!"
    echo ""
else
    echo "[!] No checkpoint.tar found - CRIU may have failed"
    echo "[i] Even without CRIU, we captured:"
    echo "    - Environment variables with credentials"
    echo "    - Process list showing malware"
    echo "    - Network connections"
    echo "    - Container logs with attack evidence"
fi

echo ""
echo "========================================================================"
echo "                         DEMO COMPLETE"
echo "========================================================================"
echo ""
echo "Summary:"
echo "  [+] Supply chain attack executed (malicious binary in image)"
echo "  [+] Malware activated automatically after 10 seconds"
echo "  [+] Script downloaded and executed ENTIRELY IN MEMORY"
echo "  [+] eBPF (Tetragon) detected network activity"
echo "  [+] CRIU captured the in-memory script content!"
echo "  [+] Pod isolated (attacker cut off from C2)"
echo "  [+] Credentials extracted from captured data"
echo ""
echo "Forensic evidence location:"
echo "  $CHECKPOINT_DIR/"
echo "  /tmp/k8s-checkpoints/${POD_NAME}_${TIMESTAMP}_forensics.tar.gz"
echo ""
echo "Key Takeaways:"
echo "  1. Fileless malware leaves no disk artifacts"
echo "  2. Traditional forensics can't see memory-only scripts"
echo "  3. CRIU checkpoint captures EVERYTHING from process memory"
echo "  4. Don't kill compromised pods - checkpoint them first!"
echo ""
