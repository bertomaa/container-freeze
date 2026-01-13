# Fileless Supply Chain Attack Demo

A demonstration of a supply-chain attack where malicious code executes entirely in memory, leaving no disk artifacts for traditional forensics tools to find.

## Scenario

A compromised container image has been deployed to production. The image passed all CI/CD security scans and the backdoor is dormant - it only activates when a specific HTTP header is sent.

**Attack Chain:**
1. Attacker compromises build pipeline or image registry
2. Backdoor code is injected into a legitimate application
3. Container deploys and runs normally (invisible to scanners)
4. Attacker triggers backdoor via HTTP header
5. Malicious payload downloads and executes **in memory only**
6. Credentials exfiltrated, no files written to disk

## Attack Flow Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           KUBERNETES CLUSTER                                 │
│                                                                              │
│  ┌──────────────────────────────────┐     ┌──────────────────────────────┐   │
│  │      production namespace        │     │   malicious-cdn namespace    │   │
│  │                                  │     │                              │   │
│  │  ┌─────────────────────────────┐ │     │  ┌────────────────────────┐  │   │
│  │  │     payment-backend         │ │     │  │    payload-server      │  │   │
│  │  │  ┌───────────────────────┐  │ │     │  │                        │  │   │
│  │  │  │      Flask App        │  │ │     │  │  Serves malicious      │  │   │
│  │  │  │  /api/health ─────────┼──┼─┼─────┼──┼─ Python script         │  │   │
│  │  │  │  (hidden backdoor)    │  │ │ 1-3 │  │                        │  │   │
│  │  │  │          │            │  │ │     │  └────────────────────────┘  │   │
│  │  │  │          ▼ 4          │  │ │     │                              │   │
│  │  │  │  ┌─────────────────┐  │  │ │     └──────────────────────────────┘   │
│  │  │  │  │  exec() ────────┼──┼──┼─┼──▶  Script runs                       │
│  │  │  │  │  (memory only)  │  │  │ │                                        │
│  │  │  │  └────────┬────────┘  │  │ │                                        │
│  │  │  │           │ 5         │  │ │                                        │
│  │  │  │           ▼           │  │ │                                        │
│  │  │  │  Reads /var/run/secrets│ │ │                                        │
│  │  │  │  Reads /proc/self/environ│ │                                        │
│  │  │  │           │           │  │ │                                        │
│  │  │  └───────────┼───────────┘  │ │                                        │
│  │  └──────────────┼──────────────┘ │                                        │
│  └─────────────────┼────────────────┘                                        │
│                    │                                                         │
│  ┌─────────────────▼────────────────┐                                        │
│  │           TETRAGON (eBPF)        │                                        │
│  │  ┌─────────────────────────────┐ │                                        │
│  │  │  TracingPolicy detects:     │ │                                        │
│  │  │  - sys_openat on secrets    │ │                                        │
│  │  │  - sys_openat on /proc/env  │ │                                        │
│  │  │          │                  │ │                                        │
│  │  │          ▼ 6                │ │                                        │
│  │  │  ┌───────────────────────┐  │ │                                        │
│  │  │  │  SIGSTOP (signal 19)  │  │ │  ◄─ ─ Process FROZEN!                  │
│  │  │  │  Process suspended    │  │ │                                        │
│  │  │  └───────────────────────┘  │ │                                        │
│  │  └─────────────────────────────┘ │                                        │
│  └──────────────────────────────────┘                                        │
│                    │                                                         │
│                    ▼ 7                                                       │
│  ┌───────────────────────────────────┐                                       │
│  │        CRIU CHECKPOINT            │                                       │
│  │  - Captures entire memory state   │                                       │
│  │  - In-memory script preserved!    │                                       │
│  │  - Credentials visible in dump    │                                       │
│  └───────────────────────────────────┘                                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

ATTACK TIMELINE:
================
1. Attacker sends: curl -H "X-Debug: enable" /api/health
2. Backdoor activates in background thread
3. Downloads malicious script from payload-server
4. Script executes via exec() - MEMORY ONLY
5. Script attempts to read K8s secrets and env vars
6. Tetragon detects syscall, sends SIGSTOP
7. CRIU captures frozen process memory for forensics
```

## Components

### Target Application (`app/`)

A Flask-based "payment backend" with a hidden backdoor:

| File | Purpose |
|------|---------|
| `app.py` | Main application with backdoor in `/api/health` |
| `telemetry.py` | Disguised malware loader (downloads and `exec()`s payload) |
| `Dockerfile` | Container image definition |
| `deployment.yaml` | K8s deployment with injected "secrets" |

**Backdoor Trigger:**
```bash
# Normal request - works fine
curl http://payment-backend:8080/api/health
# {"status": "healthy"}

# Backdoor trigger
curl -H "X-Debug: enable" http://payment-backend:8080/api/health
# Activates malware in background
```

### Payload Server (`payload-server/`)

Simulates an attacker-controlled C2 server:

| File | Purpose |
|------|---------|
| `server.py` | HTTP server that serves malicious Python script |
| `deployment.yaml` | Runs in `malicious-cdn` namespace |

The payload performs:
- **Stage 1**: Reconnaissance (env vars, K8s tokens, network info)
- **Stage 2**: Data packaging (JSON with stolen credentials)
- **Stage 3**: Exfiltration attempt (blocked by Tetragon)

### Detection Policies (`detection/`)

| Policy | What it Detects | Action |
|--------|-----------------|--------|
| `tracing-policy-fileless-exec.yaml` | Access to K8s service account, `/proc/self/environ` | **SIGSTOP** |
| `tracing-policy-network.yaml` | Outbound network connections | Log only |


## Demo Phases

### Phase 1: Environment Verification
- Checks K3s cluster status
- Verifies Tetragon is running in blocking mode
- Confirms TracingPolicy is applied
- Validates target and payload-server pods are ready

### Phase 2: Attack Trigger
- Sends backdoor trigger request
- Malware downloads payload from C2
- Script executes in memory
- Tetragon detects credential access
- Process receives SIGSTOP

### Phase 3: Forensic Capture
- CRIU checkpoints the frozen container
- Captures complete memory state (including in-memory script!)
- Collects container and payload-server logs
- Applies NetworkPolicy quarantine

### Phase 4: Memory Analysis
- Extracts malicious script from memory dump using `strings`
- Shows execution stages recorded in memory
- Reveals stolen credentials that were in-flight
- Generates forensic bundle for offline analysis

## What You'll See

### Tetragon Alert
```
╔════════════════════════════════════════════════════════════════════╗
║  TETRAGON ALERT: Suspicious activity detected!                     ║
╚════════════════════════════════════════════════════════════════════╝
```

### Recovered Script from Memory
```python
# FILELESS MALWARE PAYLOAD
# This script executes entirely in memory
# No files written to disk!

def log(msg):
    print(f"[*] {msg}")

log("=== FILELESS PAYLOAD EXECUTING ===")
log("Stage 1: Reconnaissance")
...
```

### Stolen Credentials
```
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
STRIPE_SECRET_KEY=sk_test_4eC39HqLyjWDarjtT1zdp7dc
DATABASE_PASSWORD=super_secret_db_password_123
```

## Key Takeaways

1. **Fileless malware is invisible to traditional tools** - No files means no file hashes, no `ls`, no artifact to scan

2. **eBPF enables kernel-level detection** - Tetragon sees syscalls before they complete, can block in real-time

3. **CRIU captures volatile evidence** - The in-memory script would be lost if the container was simply killed

4. **Don't kill compromised containers** - Checkpoint them first, then analyze at leisure

## Files Produced

After running the demo, forensic artifacts are saved to:

```
/tmp/k8s-checkpoints/<pod-name>_<timestamp>/
├── checkpoint.tar          # CRIU memory dump
├── container_logs.txt      # Application logs
├── payload_server_logs.txt # C2 server logs
└── criu-output.log        # CRIU execution log
```

A compressed bundle is also created:
```
/tmp/k8s-checkpoints/<pod-name>_<timestamp>_forensics.tar.gz
```