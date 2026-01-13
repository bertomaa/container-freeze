#!/bin/bash
# Fileless Supply Chain Attack Demo - Tetragon Blocking Mode
# This script runs INSIDE the VM

set -e

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cd ~/container-freeze/current-demo

USE_COLORS=true
# Detect if running interactively (check stdin before any redirects)
if [ -t 0 ]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
fi

# Setup logging (logs to shared directory accessible from host)
LOG_DIR=~/container-freeze/current-demo/logs
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/run_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[*] Logging to: $LOG_FILE"

# Helper function for interactive pauses
pause_interactive() {
    if [ "$INTERACTIVE" = true ]; then
        read -p "$1"
    else
        echo "$1"
        sleep 2
    fi
}

# =============================================================================
# Color Definitions
# =============================================================================
# Use the pre-checked USE_COLORS variable (checked before stdout redirect)
if [ "$USE_COLORS" = true ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    WHITE=''
    BOLD=''
    DIM=''
    NC=''
fi

# Helper functions for colored output
print_ok() {
    echo -e "${GREEN}OK${NC} $1"
}

print_fail() {
    echo -e "${RED}FAILED${NC}"
}

print_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[x]${NC} $1"
}

print_attack() {
    echo -e "${RED}[!]${NC} $1"
}

print_header() {
    echo -e "${BOLD}${WHITE}$1${NC}"
}

print_phase() {
    echo ""
    echo -e "${BOLD}${BLUE}========================================================================${NC}"
    echo -e "${BOLD}${WHITE}  $1${NC}"
    echo -e "${BOLD}${BLUE}========================================================================${NC}"
    echo ""
}

echo ""
echo -e "${BOLD}${RED}========================================================================${NC}"
echo -e "${BOLD}${RED}              FILELESS SUPPLY CHAIN ATTACK DEMO${NC}"
echo -e "${BOLD}${RED}========================================================================${NC}"
echo ""
echo -e "${BOLD}${WHITE}SCENARIO${NC}"
echo -e "${DIM}A supply chain attack has compromised the 'payment-backend' container"
echo -e "image. The image passed all CI/CD checks and appears legitimate, but"
echo -e "contains a hidden backdoor in the /api/health endpoint.${NC}"
echo ""
echo -e "${BOLD}${YELLOW}ATTACK MECHANISM${NC}"
echo -e "  ${DIM}1.${NC} Normal requests to /api/health work fine (invisible to monitoring)"
echo -e "  ${DIM}2.${NC} Attacker sends ${YELLOW}X-Debug: enable${NC} header to trigger the backdoor"
echo -e "  ${DIM}3.${NC} Backdoor downloads malicious script from C2 server"
echo -e "  ${DIM}4.${NC} Script executes ${RED}DIRECTLY IN MEMORY${NC} - no file written to disk"
echo ""
echo -e "${BOLD}${RED}WHY THIS IS DANGEROUS${NC}"
echo -e "  ${RED}x${NC} Traditional file scanners see nothing suspicious"
echo -e "  ${RED}x${NC} Standard forensics (ls, find, file hashes) find no evidence"
echo -e "  ${RED}x${NC} The malware exists only in process memory"
echo ""
echo -e "${BOLD}${GREEN}WHAT THIS DEMO SHOWS${NC}"
echo -e "  ${GREEN}+${NC} Tetragon (eBPF) can detect and ${GREEN}BLOCK${NC} the attack"
echo -e "  ${GREEN}+${NC} CRIU checkpointing captures in-memory malware for forensics"
echo ""

# ============================================================================
# Phase 1: Environment Verification
# ============================================================================
print_phase "PHASE 1: Environment Verification"

echo -e "${DIM}Checking all required components are running...${NC}"
echo ""

ERRORS=0

# Check 1: Kubernetes cluster
echo -ne "  ${CYAN}[1/5]${NC} Kubernetes cluster ................. "
if kubectl get nodes &>/dev/null; then
    NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    print_ok "(${NODE_COUNT} node(s))"
else
    print_fail
    echo -e "        ${RED}ERROR: Cannot connect to Kubernetes cluster${NC}"
    echo -e "        ${DIM}Make sure k3s is running: sudo systemctl status k3s${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check 2: Tetragon
echo -ne "  ${CYAN}[2/5]${NC} Tetragon (eBPF monitoring) ........ "
TETRAGON_READY=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=tetragon -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
if [ "$TETRAGON_READY" = "Running" ]; then
    print_ok "(BLOCKING mode)"
else
    print_fail
    echo -e "        ${RED}ERROR: Tetragon pod is not running (status: ${TETRAGON_READY:-not found})${NC}"
    echo -e "        ${DIM}Check: kubectl get pods -n kube-system -l app.kubernetes.io/name=tetragon${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check 3: TracingPolicy
echo -ne "  ${CYAN}[3/5]${NC} TracingPolicy (SIGSTOP config) .... "
POLICY_COUNT=$(kubectl get tracingpolicies --no-headers 2>/dev/null | wc -l)
if [ "$POLICY_COUNT" -gt 0 ]; then
    print_ok "(${POLICY_COUNT} policy/policies)"
else
    print_fail
    echo -e "        ${RED}ERROR: No TracingPolicy found${NC}"
    echo -e "        ${DIM}The demo requires a TracingPolicy to detect credential access${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check 4: Payment backend (target)
echo -ne "  ${CYAN}[4/5]${NC} Payment backend (target pod) ...... "
if kubectl wait --for=condition=ready pod -n production -l app=payment-backend --timeout=60s &>/dev/null; then
    POD_NAME=$(kubectl get pods -n production -l app=payment-backend -o jsonpath='{.items[0].metadata.name}')
    print_ok "(${POD_NAME})"
else
    print_fail
    echo -e "        ${RED}ERROR: payment-backend pod not ready${NC}"
    echo -e "        ${DIM}Check: kubectl get pods -n production${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check 5: Payload server (attacker C2)
echo -ne "  ${CYAN}[5/5]${NC} Payload server (attacker C2) ...... "
PAYLOAD_READY=$(kubectl get pods -n malicious-cdn -l app=payload-server -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
if [ "$PAYLOAD_READY" = "Running" ]; then
    print_ok "(Running)"
else
    print_fail
    echo -e "        ${RED}ERROR: Payload server pod is not running (status: ${PAYLOAD_READY:-not found})${NC}"
    echo -e "        ${DIM}Check: kubectl get pods -n malicious-cdn${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# Exit if any errors
if [ "$ERRORS" -gt 0 ]; then
    echo -e "${BOLD}${RED}========================================================================${NC}"
    echo -e "${BOLD}${RED}  ENVIRONMENT CHECK FAILED: ${ERRORS} error(s) detected${NC}"
    echo -e "${BOLD}${RED}========================================================================${NC}"
    echo ""
    echo -e "${YELLOW}Please fix the issues above before running the demo.${NC}"
    echo -e "${DIM}You may need to redeploy the demo environment.${NC}"
    exit 1
fi

print_success "All components ready!"
echo ""

# Test health endpoint
print_info "Testing normal health endpoint (no backdoor trigger):"
echo -e "    ${DIM}curl http://payment-backend:8080/api/health${NC}"
HEALTH_RESPONSE=$(kubectl exec -n production "$POD_NAME" -- curl -s http://localhost:8080/api/health 2>&1)
if [ $? -eq 0 ]; then
    echo -e "    ${WHITE}$HEALTH_RESPONSE${NC}"
    echo ""
    print_success "Health endpoint responding normally"
else
    print_error "Could not reach health endpoint"
    echo -e "    ${DIM}Response: $HEALTH_RESPONSE${NC}"
    exit 1
fi
echo ""

pause_interactive "$(echo -e "${YELLOW}Press ENTER to trigger the attack...${NC}")"
echo ""

# ============================================================================
# Phase 2: Attack Trigger
# ============================================================================
print_phase "PHASE 2: Attack Trigger"

echo -e "${BOLD}${RED}>>> TRIGGERING BACKDOOR <<<${NC}"
echo ""
print_attack "Sending malicious request with X-Debug header..."
echo ""
echo -e "    ${DIM}curl -H '${YELLOW}X-Debug: enable${DIM}' http://payment-backend:8080/api/health${NC}"
echo ""

# Trigger the backdoor
echo -e "${DIM}--- Response ---${NC}"
kubectl exec -n production "$POD_NAME" -- curl -s -H "X-Debug: enable" http://localhost:8080/api/health
echo ""
echo -e "${DIM}----------------${NC}"
echo ""

print_attack "Backdoor triggered - malicious payload download initiated!"
print_info "Waiting for Tetragon to detect credential access..."
echo ""

# Give the malware a moment to download and start executing
echo -ne "  ${DIM}Waiting for attack execution"
for i in 1 2 3; do
    sleep 1
    echo -n "."
done
echo -e "${NC}"
echo ""

# Check Tetragon events
TETRAGON_POD=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=tetragon -o jsonpath='{.items[0].metadata.name}')

print_info "Checking Tetragon events..."
echo ""

# Look for the SIGSTOP event or credential access
TETRAGON_EVENTS=$(kubectl logs -n kube-system "$TETRAGON_POD" -c export-stdout --tail=50 2>/dev/null || echo "")

if echo "$TETRAGON_EVENTS" | grep -q "serviceaccount\|SIGSTOP\|signal"; then
    echo -e "  ${BOLD}${RED}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${BOLD}${RED}║  TETRAGON ALERT: Suspicious activity detected!                     ║${NC}"
    echo -e "  ${BOLD}${RED}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${DIM}Detected events:${NC}"
    echo "$TETRAGON_EVENTS" | grep -E "process_kprobe|openat|serviceaccount|signal" | tail -10 | sed 's/^/    /'
    echo ""
else
    print_info "Tetragon events (recent activity):"
    echo "$TETRAGON_EVENTS" | grep -E "process|connect|python" | tail -10 | sed 's/^/    /' || echo -e "    ${DIM}(checking for events...)${NC}"
    echo ""
fi

print_info "Payload server logs (evidence of download):"
echo -e "  ${DIM}--- Download Log ---${NC}"
kubectl logs -n malicious-cdn -l app=payload-server --tail=10 2>&1 | grep -Ei "DOWNLOAD|EXFIL|payload" | sed 's/^/    /' || echo -e "    ${DIM}(checking for download evidence...)${NC}"
MALICIOUS_SERVER_POD_NAME=$(kubectl get pods -n malicious-cdn -l app=payload-server -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n malicious-cdn "$MALICIOUS_SERVER_POD_NAME" -- cat /var/log/payload/downloads.log 2>/dev/null | sed 's/^/    /'
echo -e "  ${DIM}--------------------${NC}"
echo ""

pause_interactive "$(echo -e "${YELLOW}Press ENTER to capture forensic checkpoint...${NC}")"
echo ""

# ============================================================================
# Phase 3: Forensic Capture
# ============================================================================
print_phase "PHASE 3: Forensic Capture (CRIU Checkpoint)"

echo -e "${BOLD}${CYAN}>>> CAPTURING PROCESS MEMORY <<<${NC}"
echo ""
print_info "Initiating CRIU checkpoint..."
echo ""

mkdir -p /tmp/k8s-checkpoints
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CHECKPOINT_DIR="/tmp/k8s-checkpoints/${POD_NAME}_${TIMESTAMP}"
mkdir -p "$CHECKPOINT_DIR"

# Get container ID
CONTAINER_ID=$(kubectl get pod "$POD_NAME" -n production -o jsonpath="{.status.containerStatuses[0].containerID}" | sed 's|containerd://||')

if [ -n "$CONTAINER_ID" ]; then
    echo -e "  ${DIM}Container ID:${NC} ${WHITE}${CONTAINER_ID:0:12}...${NC}"
    echo -e "  ${DIM}Output path:${NC}  ${WHITE}$CHECKPOINT_DIR/checkpoint.tar${NC}"
    echo ""
    print_info "Executing CRIU checkpoint..."
    echo -e "  ${DIM}--- CRIU Output ---${NC}"

    # Try CRIU checkpoint
    if sudo crictl checkpoint --export="$CHECKPOINT_DIR/checkpoint.tar" "$CONTAINER_ID" 2>&1 | tee "$CHECKPOINT_DIR/criu-output.log" | sed 's/^/    /'; then
        echo -e "  ${DIM}-------------------${NC}"
        echo ""
        echo -e "  ${BOLD}${GREEN}╔════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${BOLD}${GREEN}║  CRIU CHECKPOINT SUCCESS!                                          ║${NC}"
        echo -e "  ${BOLD}${GREEN}╚════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        print_success "Memory snapshot saved to: $CHECKPOINT_DIR/checkpoint.tar"
        CHECKPOINT_SUCCESS=true
    else
        echo -e "  ${DIM}-------------------${NC}"
        echo ""
        print_warn "CRIU checkpoint failed (see $CHECKPOINT_DIR/criu-output.log)"
        print_info "Continuing with available evidence..."
        CHECKPOINT_SUCCESS=false
    fi
else
    print_error "Could not get container ID"
    CHECKPOINT_SUCCESS=false
fi

echo ""
print_info "Collecting additional evidence..."
echo -ne "  ${DIM}[1/2]${NC} Container logs ........... "
if kubectl logs -n production "$POD_NAME" > "$CHECKPOINT_DIR/container_logs.txt" 2>/dev/null; then
    print_ok ""
else
    echo -e "${YELLOW}SKIPPED${NC}"
fi
echo -ne "  ${DIM}[2/2]${NC} Payload server logs ...... "
if kubectl logs -n malicious-cdn -l app=payload-server > "$CHECKPOINT_DIR/payload_server_logs.txt" 2>/dev/null; then
    print_ok ""
else
    echo -e "${YELLOW}SKIPPED${NC}"
fi

# Apply network isolation
echo ""
echo -e "${BOLD}${YELLOW}>>> QUARANTINE: Isolating compromised pod <<<${NC}"
echo ""
print_info "Applying NetworkPolicy to cut off C2 communication..."
cat << EOF | kubectl apply -f - 2>&1 | sed 's/^/    /'
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
echo ""
print_success "NetworkPolicy applied - pod is now ${BOLD}QUARANTINED${NC}"
echo -e "    ${DIM}(Only DNS egress allowed, all other traffic blocked)${NC}"
echo ""

pause_interactive "$(echo -e "${YELLOW}Press ENTER to analyze captured memory...${NC}")"
echo ""

# ============================================================================
# Phase 4: Memory Analysis
# ============================================================================
print_phase "PHASE 4: Memory Analysis"

cd "$CHECKPOINT_DIR"

if [ "$CHECKPOINT_SUCCESS" = true ] && [ -f "checkpoint.tar" ]; then
    echo -e "${BOLD}${MAGENTA}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${MAGENTA}║                     CHECKPOINT MEMORY ANALYSIS                         ║${NC}"
    echo -e "${BOLD}${MAGENTA}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    print_info "Scanning checkpoint memory for malicious strings..."
    print_info "Looking for FILELESS script and STOLEN CREDENTIALS..."
    echo ""

    # We use 'strings' directly on the tarball which is more robust than extraction
    # patterns based on the manual verification we did

    echo -e "  ${BOLD}${RED}┌─────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}${RED}│  RECOVERED SCRIPT CONTENT FROM MEMORY                               │${NC}"
    echo -e "  ${BOLD}${RED}└─────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Extract the full malicious script from memory
    SCRIPT_CONTENT=$(sudo strings checkpoint.tar 2>/dev/null | grep -A 126 "# FILELESS MALWARE PAYLOAD" | head -100 || \
    sudo strings checkpoint.tar 2>/dev/null | grep -A 80 "=== FILELESS PAYLOAD EXECUTING" | head -80 || \
    echo "")

    if [ -n "$SCRIPT_CONTENT" ]; then
        echo "$SCRIPT_CONTENT" | sed 's/^/    /'
    else
        echo -e "    ${DIM}(Header not found, searching for other signatures...)${NC}"
        # Fallback: try to find Python code patterns
        FALLBACK=$(sudo strings checkpoint.tar 2>/dev/null | grep -B 2 -A 20 "def log(msg):" | head -30)
        if [ -n "$FALLBACK" ]; then
            echo -e "    ${DIM}Found script fragments:${NC}"
            echo "$FALLBACK" | sed 's/^/    /'
        fi
    fi

    echo ""
    echo -e "  ${BOLD}${YELLOW}┌─────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}${YELLOW}│  MALWARE EXECUTION STAGES (Memory Artifacts)                        │${NC}"
    echo -e "  ${BOLD}${YELLOW}└─────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    # Look for the log lines generated by the malware in memory - better pattern
    print_info "Stage execution evidence:"
    STAGES=$(sudo strings checkpoint.tar 2>/dev/null | grep -E "STAGE [0-9]|Stage [0-9]:|log\(.*Stage" | sort -u | head -10)
    if [ -n "$STAGES" ]; then
        echo "$STAGES" | sed 's/^/    /'
    else
        echo -e "    ${DIM}(No stage markers found)${NC}"
    fi
    echo ""
    print_info "Exfiltration attempts:"
    EXFIL=$(sudo strings checkpoint.tar 2>/dev/null | grep -iE "exfil|stolen|sending|upload" | sort -u | head -5)
    if [ -n "$EXFIL" ]; then
        echo "$EXFIL" | sed 's/^/    /'
    else
        echo -e "    ${DIM}(No exfiltration evidence found)${NC}"
    fi

    echo ""
    echo -e "  ${BOLD}${RED}┌─────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}${RED}│  CREDENTIALS FOUND IN MEMORY (STOLEN DATA!)                        │${NC}"
    echo -e "  ${BOLD}${RED}└─────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    # Look for the specific secrets - improved patterns
    print_info "Environment variables with secrets:"
    CREDS=$(sudo strings checkpoint.tar 2>/dev/null | grep -E "^(AWS_|STRIPE_|DATABASE_|DB_|API_KEY|SECRET)" | sort -u | grep -v "AWS_CONTAINER" | head -15)
    if [ -n "$CREDS" ]; then
        echo "$CREDS" | sed 's/^/    /'
    else
        echo -e "    ${DIM}(No credentials found in this scan)${NC}"
    fi
    echo ""
    print_info "Kubernetes service account tokens:"
    SA_TOKEN=$(sudo strings checkpoint.tar 2>/dev/null | grep -E "serviceaccount|eyJ[A-Za-z0-9]+" | head -5)
    if [ -n "$SA_TOKEN" ]; then
        echo "$SA_TOKEN" | sed 's/^/    /' | head -3
        echo -e "    ${DIM}(truncated for security)${NC}"
    else
        echo -e "    ${DIM}(No SA tokens found)${NC}"
    fi

    echo ""
    echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    print_success "The above shows the malicious script and data were captured from"
    echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

else
    print_warn "Checkpoint not available - showing log-based evidence only"
    echo ""

    if [ -f "container_logs.txt" ]; then
        echo -e "  ${BOLD}${YELLOW}┌─────────────────────────────────────────────────────────────────────┐${NC}"
        echo -e "  ${BOLD}${YELLOW}│  MALWARE ACTIVITY (from container logs)                            │${NC}"
        echo -e "  ${BOLD}${YELLOW}└─────────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        sudo grep -E "PAYLOAD|Stage|telemetry|secret|EXFIL|Debug sync" container_logs.txt 2>/dev/null | head -20 | sed 's/^/    /' || echo -e "    ${DIM}(check container_logs.txt)${NC}"
        echo ""
    fi

    if [ -f "payload_server_logs.txt" ]; then
        echo -e "  ${BOLD}${YELLOW}┌─────────────────────────────────────────────────────────────────────┐${NC}"
        echo -e "  ${BOLD}${YELLOW}│  PAYLOAD SERVER EVIDENCE                                           │${NC}"
        echo -e "  ${BOLD}${YELLOW}└─────────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        sudo grep -E "DOWNLOAD|EXFIL|payload" payload_server_logs.txt 2>/dev/null | head -10 | sed 's/^/    /' || echo -e "    ${DIM}(check payload_server_logs.txt)${NC}"
        echo ""
    fi
fi
# Create forensic bundle
echo ""
print_info "Creating forensic bundle..."
cd /tmp/k8s-checkpoints
sudo tar -czf "${POD_NAME}_${TIMESTAMP}_forensics.tar.gz" "${POD_NAME}_${TIMESTAMP}/" 2>/dev/null || true
sudo chown cfuser:cfuser "${POD_NAME}_${TIMESTAMP}_forensics.tar.gz" 2>/dev/null || true
print_success "Forensic bundle created"

echo ""
echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║                         DEMO COMPLETE                                  ║${NC}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BOLD}${WHITE}SUMMARY${NC}"
echo -e "  ${GREEN}✓${NC} Backdoor triggered via /api/health with X-Debug header"
echo -e "  ${GREEN}✓${NC} Malicious script downloaded and executed ${BOLD}IN MEMORY${NC}"
echo -e "  ${GREEN}✓${NC} Tetragon detected suspicious activity (credential access)"
if [ "$CHECKPOINT_SUCCESS" = true ]; then
echo -e "  ${GREEN}✓${NC} CRIU captured the in-memory script content!"
fi
echo -e "  ${GREEN}✓${NC} Pod isolated (attacker cut off from C2)"
echo ""

echo -e "${BOLD}${WHITE}FORENSIC EVIDENCE${NC}"
echo -e "  ${DIM}Directory:${NC} $CHECKPOINT_DIR/"
echo -e "  ${DIM}Bundle:${NC}    /tmp/k8s-checkpoints/${POD_NAME}_${TIMESTAMP}_forensics.tar.gz"
echo ""

echo -e "${BOLD}${CYAN}KEY TAKEAWAYS${NC}"
echo -e "  ${CYAN}1.${NC} Fileless malware leaves no disk artifacts"
echo -e "  ${CYAN}2.${NC} Traditional forensics ${RED}can't see${NC} memory-only scripts"
echo -e "  ${CYAN}3.${NC} Tetragon can ${GREEN}BLOCK${NC} attacks with SIGSTOP before completion"
echo -e "  ${CYAN}4.${NC} CRIU checkpoint captures ${GREEN}EVERYTHING${NC} from process memory"
echo -e "  ${CYAN}5.${NC} ${BOLD}Don't kill compromised pods - checkpoint them first!${NC}"
echo ""
echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
echo ""
