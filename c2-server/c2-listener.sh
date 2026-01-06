#!/bin/bash
# Mock C2 (Command & Control) Server
# For demo purposes - logs all incoming connections

echo "========================================="
echo "C2 Server Started"
echo "Listening for compromised pods..."
echo "========================================="

# Start netcat listener on port 4444 (reverse shell port)
# Log all connections
mkdir -p /var/log/c2

handle_connection() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="/var/log/c2/connection_${timestamp//[:\ ]/_}.log"

    echo "[$timestamp] New connection received" | tee -a /var/log/c2/activity.log

    # Read and log whatever comes in
    while IFS= read -r line; do
        echo "[$timestamp] $line" | tee -a "$log_file"
    done
}

# HTTP listener for exfiltration attempts
python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from datetime import datetime

class C2Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Custom logging
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f'[{timestamp}] {format%args}')

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')

        timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
        log_file = f'/var/log/c2/exfil_{timestamp}.log'

        with open(log_file, 'w') as f:
            f.write('=== EXFILTRATION ATTEMPT ===\\n')
            f.write(f'Timestamp: {timestamp}\\n')
            f.write(f'Client: {self.client_address[0]}\\n')
            f.write(f'Path: {self.path}\\n')
            f.write('\\n=== DATA ===\\n')
            f.write(body)

        print(f'[EXFIL] Data received from {self.client_address[0]} -> {log_file}')

        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'OK')

    def do_GET(self):
        # Serve fake stage2 payload
        if 'stage2' in self.path:
            print(f'[DOWNLOAD] Stage2 payload requested by {self.client_address[0]}')
            self.send_response(200)
            self.send_header('Content-type', 'application/octet-stream')
            self.end_headers()
            self.wfile.write(b'#!/bin/sh\\necho STAGE2_PAYLOAD\\n')
        else:
            self.send_response(404)
            self.end_headers()

server = HTTPServer(('0.0.0.0', 8080), C2Handler)
print('[C2-HTTP] Listening on port 8080...')
server.serve_forever()
" &

# Also listen on raw socket for reverse shells
nc -lvnp 4444 -k 2>&1 | while IFS= read -r line; do
    echo "[C2-SHELL] $line" | tee -a /var/log/c2/shells.log
done &

# Keep container running
wait
