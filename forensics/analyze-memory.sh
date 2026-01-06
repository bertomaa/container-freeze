#!/bin/bash
# Analyze Checkpoint - Extract Secrets from Memory
# This demonstrates what you can recover from a CRIU checkpoint

set -e

FORENSIC_BUNDLE="${1}"

if [ -z "$FORENSIC_BUNDLE" ] || [ ! -f "$FORENSIC_BUNDLE" ]; then
    echo "Usage: $0 <forensic-bundle.tar.gz>"
    echo ""
    echo "Available forensic bundles:"
    ls -lh /tmp/k8s-checkpoints/*_forensics.tar.gz 2>/dev/null || echo "  No bundles found"
    exit 1
fi

echo "========================================="
echo "FORENSIC ANALYSIS - MEMORY EXTRACTION"
echo "========================================="
echo "Bundle:    $FORENSIC_BUNDLE"
echo "Time:      $(date)"
echo "Analyst:   $(whoami)"
echo "========================================="

# Create analysis workspace
ANALYSIS_DIR="/tmp/forensic-analysis/$(basename "$FORENSIC_BUNDLE" .tar.gz)"
mkdir -p "$ANALYSIS_DIR"

echo ""
echo "[Phase 1/5] Extracting forensic bundle..."
tar -xzf "$FORENSIC_BUNDLE" -C "$ANALYSIS_DIR"
cd "$ANALYSIS_DIR"

echo "  ✓ Extracted $(ls -1 | wc -l) files"
echo ""

echo "[Phase 2/5] Analyzing environment variables..."
echo "────────────────────────────────────────"

if [ -f *_env.txt ]; then
    echo "🔍 CREDENTIALS FOUND IN ENVIRONMENT:"
    echo ""
    grep -E "KEY|SECRET|PASSWORD|TOKEN" *_env.txt | while IFS='=' read -r key value; do
        echo "  🔑 $key"
        echo "      └─ $value"
    done
    echo ""
fi

echo "[Phase 3/5] Analyzing process list..."
echo "────────────────────────────────────────"

if [ -f *_processes.txt ]; then
    echo "🔍 SUSPICIOUS PROCESSES:"
    echo ""
    grep -E "bash|sh|nc|curl|wget|python" *_processes.txt | head -10 || echo "  None found"
    echo ""
fi

echo "[Phase 4/5] Analyzing network connections..."
echo "────────────────────────────────────────"

if [ -f *_network.txt ]; then
    echo "🔍 ACTIVE CONNECTIONS AT TIME OF CHECKPOINT:"
    echo ""

    # Look for C2 connections
    if grep -q "attacker-infra" *_network.txt 2>/dev/null; then
        echo "  ⚠️  C2 CONNECTION DETECTED:"
        grep "attacker-infra" *_network.txt | head -5
    else
        grep -E "ESTABLISHED|LISTEN" *_network.txt | head -10 || echo "  None found"
    fi
    echo ""
fi

echo "[Phase 5/5] Analyzing checkpoint memory dump..."
echo "────────────────────────────────────────"

CHECKPOINT_FILE=$(ls *.tar 2>/dev/null | head -1)

if [ -f "$CHECKPOINT_FILE" ]; then
    echo "  Checkpoint file: $CHECKPOINT_FILE"
    echo "  Size: $(du -h "$CHECKPOINT_FILE" | cut -f1)"
    echo ""

    # Extract checkpoint
    mkdir -p checkpoint_data
    tar -xf "$CHECKPOINT_FILE" -C checkpoint_data 2>/dev/null || {
        echo "  ℹ️  Checkpoint is placeholder (CRIU may not be available in demo)"
        echo "  ℹ️  In production, we would extract:"
        echo "      • Memory pages"
        echo "      • File descriptors"
        echo "      • Open sockets"
        echo "      • Process tree"
        echo ""
    }

    # Try to extract interesting strings from memory
    echo "  🔍 SEARCHING MEMORY FOR SECRETS:"
    echo ""

    # Search for AWS keys pattern
    strings "$CHECKPOINT_FILE" 2>/dev/null | grep -E "AKIA[0-9A-Z]{16}" | head -5 | while read -r key; do
        echo "  🔑 AWS Access Key: $key"
    done || true

    # Search for common secret patterns
    strings "$CHECKPOINT_FILE" 2>/dev/null | grep -E "sk_live_[0-9A-Za-z]+" | head -5 | while read -r key; do
        echo "  🔑 Stripe API Key: $key"
    done || true

    # Search for password patterns
    strings "$CHECKPOINT_FILE" 2>/dev/null | grep -i "password.*=" | head -5 | while read -r pwd; do
        echo "  🔑 Password string: $pwd"
    done || true

    echo ""

    # Search for bash history (even if they ran history -c)
    echo "  🔍 RECOVERING BASH HISTORY FROM MEMORY:"
    echo ""
    strings "$CHECKPOINT_FILE" 2>/dev/null | grep -E "^(curl|wget|nc|bash|python|cat|echo)" | head -20 | while read -r cmd; do
        echo "      $ $cmd"
    done || echo "      (bash history not found in checkpoint - this is a demo limitation)"

    echo ""
fi

echo ""
echo "========================================="
echo "✓ FORENSIC ANALYSIS COMPLETE"
echo "========================================="
echo ""
echo "📊 INCIDENT SUMMARY"
echo "────────────────────────────────────────"
echo ""

# Generate summary report
cat > "$ANALYSIS_DIR/INCIDENT_REPORT.md" <<EOF
# Incident Analysis Report

**Date:** $(date)
**Analyst:** $(whoami)
**Evidence:** $FORENSIC_BUNDLE

## Executive Summary

A compromised pod was detected and checkpointed using CRIU.
Memory forensics reveals the following:

## Compromised Credentials

EOF

if [ -f *_env.txt ]; then
    echo "### Environment Variables" >> "$ANALYSIS_DIR/INCIDENT_REPORT.md"
    echo "\`\`\`" >> "$ANALYSIS_DIR/INCIDENT_REPORT.md"
    grep -E "KEY|SECRET|PASSWORD|TOKEN" *_env.txt >> "$ANALYSIS_DIR/INCIDENT_REPORT.md" 2>/dev/null || true
    echo "\`\`\`" >> "$ANALYSIS_DIR/INCIDENT_REPORT.md"
    echo "" >> "$ANALYSIS_DIR/INCIDENT_REPORT.md"
fi

cat >> "$ANALYSIS_DIR/INCIDENT_REPORT.md" <<EOF

## Attack Timeline

1. **Initial Access**: Supply chain injection (malware sidecar)
2. **Activation**: Backdoor triggered via /.env endpoint
3. **C2 Communication**: Attempted connection to attacker infrastructure
4. **Detection**: eBPF (Tetragon) caught suspicious syscalls
5. **Response**: Pod checkpointed and isolated
6. **Analysis**: Credentials extracted from memory

## Evidence Preserved

- Memory checkpoint (CRIU dump)
- Process list at time of compromise
- Network connections (including C2 attempts)
- Environment variables with secrets
- Container logs

## NIS2/CRA Compliance

✓ Evidence preserved for regulatory reporting
✓ Data exfiltration prevented (network isolation)
✓ Full attack timeline reconstructed
✓ Compromised credentials identified for rotation

## Recommendations

1. **Immediate**: Rotate all exposed credentials
2. **Short-term**: Review supply chain for injection point
3. **Long-term**: Implement continuous runtime monitoring (eBPF)

---
*Generated by Container Freeze Forensic Toolkit*
EOF

echo "  Report saved: INCIDENT_REPORT.md"
echo ""
cat "$ANALYSIS_DIR/INCIDENT_REPORT.md"
echo ""
echo "Analysis workspace: $ANALYSIS_DIR"
echo ""
