#!/bin/bash
# Trigger the attack by hitting the backdoor endpoint

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    TRIGGERING ATTACK                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Get pod name
POD_NAME=$(kubectl get pods -n production -l app=payment-processor -o jsonpath='{.items[0].metadata.name}')

echo "Target Pod: $POD_NAME"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📡 Simulating Reconnaissance Scan (Attacker finds backdoor)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Attacker: scanning for common endpoints..."
echo "  → /.env"
echo "  → /.git/config"
echo "  → /api/admin/debug"
echo ""

sleep 2

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💥 Triggering Backdoor (.env endpoint)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Hit the backdoor endpoint
kubectl exec -n production "$POD_NAME" -c app -- \
    curl -s http://localhost:8080/.env > /tmp/backdoor-response.txt

echo "Attacker received:"
echo "─────────────────────────────────────────"
cat /tmp/backdoor-response.txt
echo "─────────────────────────────────────────"
echo ""

echo "🎯 Backdoor activated!"
echo "   Activation signal written to /tmp/.activate"
echo ""

sleep 3

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⏰ Malware Waking Up..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Malware sidecar detected activation signal:"

# Show malware logs
kubectl logs -n production "$POD_NAME" -c malware-sidecar --tail=20

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚨 Attack in Progress!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "The malware is now:"
echo "  • Attempting C2 connections"
echo "  • Downloading additional payloads"
echo "  • Exfiltrating credentials"
echo "  • Trying to establish persistence"
echo ""
echo "Tetragon (eBPF) is monitoring all syscalls..."
echo ""

sleep 3

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║            ATTACK TRIGGERED - DETECTION EXPECTED              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. Monitor Tetragon alerts:  kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon | grep ALERT"
echo "  2. Watch malware activity:   kubectl logs -f -n production $POD_NAME -c malware-sidecar"
echo "  3. Checkpoint the pod:       ./response/checkpoint-pod.sh $POD_NAME production malware-sidecar"
echo ""
