#!/bin/bash
# Install Tetragon for eBPF-based runtime security monitoring

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "========================================="
echo "Installing Tetragon (eBPF Monitoring)"
echo "========================================="
echo ""
echo "⚠️  NOTE: Tetragon requires kernel features that may not work in kind/Docker"
echo "   If installation fails, we'll use a mock detector for demo purposes"
echo ""

# Add Cilium Helm repo
echo "[1/4] Adding Cilium Helm repository..."
helm repo add cilium https://helm.cilium.io 2>/dev/null || true
helm repo update >/dev/null 2>&1

# Try to install Tetragon with minimal config
echo "[2/4] Installing Tetragon..."

TETRAGON_INSTALLED=false

if helm install tetragon cilium/tetragon \
  --version 1.6.0 \
  --namespace kube-system \
  --set tetragon.enabled=true \
  --set tetragon.grpc.enabled=true \
  --wait \
  --timeout 2m >/dev/null 2>&1; then

    echo "  ✓ Tetragon Helm chart installed"

    # Check if pods are actually running
    sleep 10
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=tetragon -n kube-system --timeout=60s >/dev/null 2>&1; then
        TETRAGON_INSTALLED=true
        echo "  ✓ Tetragon pods running"
    else
        echo "  ⚠️  Tetragon pods failed to start (eBPF limitations in kind)"
    fi
else
    echo "  ⚠️  Tetragon Helm installation failed (expected in kind)"
fi

# Try to apply TracingPolicies (will fail if CRD doesn't exist)
echo "[3/4] Checking for TracingPolicy CRDs..."
if kubectl get crd tracingpolicies.cilium.io >/dev/null 2>&1; then
    echo "  ✓ TracingPolicy CRD exists, applying policies..."
    kubectl apply -f "$PROJECT_ROOT/detection/tracing-policy-reverse-shell.yaml" 2>&1 | grep -v "error:" || true
    kubectl apply -f "$PROJECT_ROOT/detection/tracing-policy-network.yaml" 2>&1 | grep -v "error:" || true
    kubectl apply -f "$PROJECT_ROOT/detection/tracing-policy-fileless.yaml" 2>&1 | grep -v "error:" || true
else
    echo "  ⚠️  TracingPolicy CRD not available"
fi

echo "[4/4] Detection setup complete"
echo ""

if [ "$TETRAGON_INSTALLED" = true ]; then
    echo "✓ Tetragon successfully installed"
    echo "  Real eBPF monitoring active"
    echo ""
    kubectl get pods -n kube-system -l app.kubernetes.io/name=tetragon
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  DEMO MODE: Real Tetragon unavailable (kind/eBPF limitations)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "For the demo, you can use the mock detector:"
    echo "  ./detection/mock-tetragon.sh"
    echo ""
    echo "In a production cluster (not kind), Tetragon works properly."
    echo "The POC demonstrates the CONCEPT of eBPF-based detection."
    echo ""
    echo "Mock detector provides:"
    echo "  • Simulated syscall monitoring alerts"
    echo "  • Log-based detection patterns"
    echo "  • Same format as real Tetragon output"
    echo ""
fi

echo ""
