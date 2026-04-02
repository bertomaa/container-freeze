# Container Freeze

```
·  ❄  ·     ·  ❄  ·     ·  ❄  ·     ·  ❄  ·     ·  ❄  ·

  ██████╗███████╗██████╗ ███████╗███████╗███████╗███████╗
 ██╔════╝██╔════╝██╔══██╗██╔════╝██╔════╝╚══███╔╝██╔════╝
 ██║     █████╗  ██████╔╝█████╗  █████╗    ███╔╝ █████╗
 ██║     ██╔══╝  ██╔══██╗██╔══╝  ██╔══╝   ███╔╝  ██╔══╝
 ╚██████╗██║     ██║  ██║███████╗███████╗███████╗███████╗
  ╚═════╝╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚══════╝

·  ❄  ·     ·  ❄  ·     ·  ❄  ·     ·  ❄  ·     ·  ❄  ·

                     They're Inside. Now What?
```

**Kubernetes Forensics & Live Containment POC**

A proof-of-concept toolkit demonstrating advanced attack scenarios in Kubernetes environments and how to detect, block, and forensically capture malicious activity using modern eBPF-based security (Tetragon) and memory forensics (CRIU).

---

## 🎯 Available Demos

| Demo | Description |
|------|-------------|
| [**`fileless-attack`**](demos/fileless-attack/README.md) | Supply-chain backdoor that executes malicious code entirely in memory. Demonstrates Tetragon blocking and CRIU memory capture. |

---

## Overview

Container Freeze simulates supply-chain attacks against containerized applications and demonstrates incident response workflows:

- **Detection**: Tetragon eBPF policies detect suspicious syscalls in real-time
- **Blocking**: SIGSTOP signals freeze malicious processes before damage is done
- **Forensics**: CRIU checkpointing captures in-memory malware for analysis
- **Containment**: NetworkPolicy quarantine isolates compromised pods

## Quick Start

### macOS

```bash
# Install dependencies
brew install lima gum

# Start the interactive CLI
./cfreeze
```

Lima creates a QEMU/Ubuntu VM automatically — no KVM or libvirt required.

> **Apple Silicon (M1/M2/M3):** The VM runs natively on arm64 at full speed. Intel Macs use the amd64 image.

### Linux (Arch)

```bash
# Install dependencies
sudo pacman -S gum libvirt qemu-desktop

# Start the interactive CLI
./cfreeze
```

The interactive menu will guide you through:
1. **Setup** - Create VM with K3s, Tetragon, and CRIU
2. **Demo** - Deploy and run attack scenarios
3. **SSH** - Access the VM directly

## Requirements

| | macOS | Linux |
|---|---|---|
| Virtualisation | [Lima](https://lima-vm.io/) (`brew install lima`) | libvirt + QEMU (`libvirt qemu-desktop`) |
| UI | [gum](https://github.com/charmbracelet/gum) (`brew install gum`) | [gum](https://github.com/charmbracelet/gum) |
| RAM | ~4GB | ~4GB |
| Disk | ~20GB | ~20GB |

> **Linux KVM:** Linux hosts require KVM support (`lsmod | grep kvm`). macOS hosts do not — Lima handles virtualisation transparently.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST MACHINE                            │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    cfreeze CLI                            │  │
│  │  - Interactive menu (gum)                                 │  │
│  │  - Demo discovery & deployment                            │  │
│  │  - VM lifecycle management                                │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │ SSH                              │
│                              ▼                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   LIBVIRT VM (Ubuntu 22.04)               │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │                   K3s Cluster                       │  │  │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │  │  │
│  │  │  │  Tetragon   │  │    CRIU     │  │   Demo      │  │  │  │
│  │  │  │   (eBPF)    │  │ checkpoint  │  │   Pods      │  │  │  │
│  │  │  └─────────────┘  └─────────────┘  └─────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## CLI Usage

### Interactive Mode (Recommended)

```bash
./cfreeze
```

## Key Technologies

### Tetragon (eBPF Security)

[Tetragon](https://tetragon.io/) provides kernel-level observability and enforcement:
- Monitors syscalls (`openat`, `connect`, etc.) without performance overhead
- Can send SIGSTOP/SIGKILL to block malicious processes
- Uses TracingPolicies to define detection rules

### CRIU (Checkpoint/Restore)

[CRIU](https://criu.org/) enables process memory capture:
- Freezes a running container and dumps its entire memory state
- Captures in-memory malware that leaves no disk artifacts
- Enables forensic analysis of volatile data

### K3s

Lightweight Kubernetes distribution with containerd runtime and built-in CRIU support (v1.32+).


## Troubleshooting

### VM won't start
```bash
# Check libvirt status
sudo systemctl status libvirtd

# Verify KVM support
lsmod | grep kvm
```

### K3s not responding
```bash
# SSH into VM and check K3s
./cfreeze ssh
sudo systemctl status k3s
kubectl get nodes
```

### Tetragon not detecting
```bash
# Check Tetragon pod
kubectl get pods -n kube-system -l app.kubernetes.io/name=tetragon

# View Tetragon logs
kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon -c export-stdout
```

### CRIU checkpoint fails
```bash
# Check CRIU is installed
criu --version

# Verify containerd supports checkpoint
crictl info | grep checkpoint
```

## License

MIT

## Credits

Built with:
- [Tetragon](https://tetragon.io/) - eBPF-based Security Observability
- [CRIU](https://criu.org/) - Checkpoint/Restore In Userspace
- [K3s](https://k3s.io/) - Lightweight Kubernetes
- [gum](https://github.com/charmbracelet/gum) - Shell script UI toolkit
