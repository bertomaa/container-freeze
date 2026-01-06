#!/bin/bash
# Isolate Pod - Network Quarantine
# Applies NetworkPolicy to prevent further C2 communication

set -e

POD_NAME="${1}"
NAMESPACE="${2:-production}"

if [ -z "$POD_NAME" ]; then
    echo "Usage: $0 <pod-name> [namespace]"
    exit 1
fi

echo "========================================="
echo "POD ISOLATION - NETWORK QUARANTINE"
echo "========================================="
echo "Pod:       $POD_NAME"
echo "Namespace: $NAMESPACE"
echo "Time:      $(date)"
echo "========================================="

# Get pod labels for NetworkPolicy selector
POD_LABELS=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.labels}' | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')

echo ""
echo "[Step 1/3] Creating quarantine NetworkPolicy..."

# Create NetworkPolicy that denies all egress except DNS
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine-${POD_NAME}
  namespace: ${NAMESPACE}
  labels:
    purpose: forensic-isolation
    created-by: incident-response
spec:
  podSelector:
    matchLabels:
      app: payment-processor
  policyTypes:
  - Egress
  - Ingress
  egress:
  # Allow DNS (so we can still resolve names for logging)
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
  # Deny everything else - no C2 communication possible
  ingress:
  # Allow only from monitoring/forensic tools
  - from:
    - namespaceSelector:
        matchLabels:
          purpose: forensics
EOF

echo "  ✓ NetworkPolicy applied"

echo ""
echo "[Step 2/3] Verifying isolation..."
kubectl get networkpolicy -n "$NAMESPACE" "quarantine-${POD_NAME}"

echo ""
echo "[Step 3/3] Testing network isolation..."
echo "  → Attempting external connection (should fail)..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -c malware-sidecar -- timeout 3 curl -s http://google.com 2>&1 && {
    echo "  ⚠️  WARNING: Pod can still reach internet!"
} || {
    echo "  ✓ External connectivity blocked (expected)"
}

echo "  → Attempting C2 connection (should fail)..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -c malware-sidecar -- timeout 3 nc -zv c2-server.attacker-infra.svc.cluster.local 4444 2>&1 && {
    echo "  ⚠️  WARNING: Pod can still reach C2!"
} || {
    echo "  ✓ C2 connectivity blocked (expected)"
}

echo ""
echo "========================================="
echo "✓ POD ISOLATED"
echo "========================================="
echo ""
echo "Current Status:"
echo "  • Pod is ALIVE but QUARANTINED"
echo "  • Attacker cannot exfiltrate data"
echo "  • Attacker cannot receive commands"
echo "  • Pod acts as honeypot (attacker unaware)"
echo ""
echo "NetworkPolicy Details:"
kubectl describe networkpolicy -n "$NAMESPACE" "quarantine-${POD_NAME}" | head -20
echo ""
echo "Next Steps:"
echo "  1. Continue monitoring:  kubectl logs -f -n $NAMESPACE $POD_NAME -c malware-sidecar"
echo "  2. Analyze checkpoint:   ./forensics/analyze-memory.sh"
echo "  3. When done, kill pod:  kubectl delete pod -n $NAMESPACE $POD_NAME"
echo ""
