#!/bin/bash
# Mock Tetragon - Simulates eBPF detection for demo purposes
# In production, real Tetragon would use eBPF to detect these syscalls

set -e

echo "========================================="
echo "Starting Mock Tetragon Detector"
echo "========================================="
echo ""
echo "⚠️  NOTE: This is a simulation for demo purposes"
echo "    Real Tetragon uses eBPF to monitor kernel syscalls"
echo "    In kind/Docker, eBPF has limited functionality"
echo ""

# Watch for malware activity by monitoring logs
NAMESPACE="production"
POD_LABEL="app=payment-processor"

echo "[Tetragon] Monitoring pods with label: $POD_LABEL in namespace: $NAMESPACE"
echo "[Tetragon] Detection rules active:"
echo "  • Reverse shell pattern (socket → connect → dup2 → execve)"
echo "  • Network anomalies (unexpected outbound connections)"
echo "  • File execution from /tmp"
echo "  • wget/curl downloads"
echo ""

# Monitor logs and generate alerts
while true; do
    POD_NAME=$(kubectl get pods -n $NAMESPACE -l $POD_LABEL -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$POD_NAME" ]; then
        sleep 5
        continue
    fi

    # Check for malware activation in logs
    LOGS=$(kubectl logs -n $NAMESPACE "$POD_NAME" -c malware-sidecar --tail=20 2>/dev/null || echo "")

    if echo "$LOGS" | grep -q "MALWARE ACTIVATED"; then
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🚨 ALERT [${TIMESTAMP}]"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Pod:       $POD_NAME"
        echo "Namespace: $NAMESPACE"
        echo "Container: malware-sidecar"
        echo ""
        echo "DETECTION: Malware activation sequence detected"
        echo ""
        echo "Suspicious syscalls observed:"
        echo "  → socket(AF_INET, SOCK_STREAM, 0) = 3"
        echo "  → connect(3, {sa_family=AF_INET, sin_port=htons(4444), "
        echo "            sin_addr=inet_addr(\"10.96.x.x\")}, 16)"
        echo "  → dup2(3, 0) = 0"
        echo "  → dup2(3, 1) = 1"
        echo "  → execve(\"/bin/sh\", [\"/bin/sh\", \"-i\"], ...) = 0"
        echo ""
        echo "🔍 Analysis:"
        echo "  • Classic reverse shell pattern detected"
        echo "  • Target: c2-server.attacker-infra.svc.cluster.local:4444"
        echo "  • Process: bash (PID: $(( RANDOM % 1000 + 1000 )))"
        echo "  • Parent: malware-sidecar"
        echo ""
        echo "📋 Recommended Actions:"
        echo "  1. Checkpoint pod for forensics"
        echo "  2. Isolate pod with NetworkPolicy"
        echo "  3. Begin incident response"
        echo ""
        echo "Command to checkpoint:"
        echo "  ./response/checkpoint-pod.sh $POD_NAME $NAMESPACE malware-sidecar"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        # Only alert once
        sleep 30
    fi

    if echo "$LOGS" | grep -q "Attempting HTTP exfil"; then
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        echo ""
        echo "🚨 ALERT [${TIMESTAMP}] - Data Exfiltration Attempt"
        echo "  • HTTP POST to external server"
        echo "  • Payload size: ~2KB"
        echo "  • Destination: c2-server.attacker-infra:8080/exfil"
        echo ""
    fi

    if echo "$LOGS" | grep -q "Downloading stage 2"; then
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        echo ""
        echo "🚨 ALERT [${TIMESTAMP}] - Payload Download Detected"
        echo "  • wget/curl execution detected"
        echo "  • Binary: /usr/bin/curl"
        echo "  • Target: http://c2-server:8080/stage2"
        echo "  • Action: Potential trojan download"
        echo ""
    fi

    sleep 5
done
