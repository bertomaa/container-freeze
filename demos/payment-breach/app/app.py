#!/usr/bin/env python3
"""
Vulnerable Flask Application - Container Freeze Demo
This simulates a legitimate application with a supply chain injection
"""
import os
import time
import socket
import subprocess
from flask import Flask, request, jsonify

app = Flask(__name__)

# Simulated "legitimate" API endpoint
@app.route('/api/health', methods=['GET'])
def health():
    return jsonify({
        "status": "healthy",
        "service": "payment-processor",
        "version": "2.1.4"
    })

@app.route('/api/process', methods=['POST'])
def process_payment():
    data = request.get_json()
    return jsonify({
        "status": "processed",
        "transaction_id": "tx_" + str(int(time.time())),
        "amount": data.get("amount", 0)
    })

# ============================================================================
# SUPPLY CHAIN INJECTION - Hidden backdoor
# In reality, this would be obfuscated or in a dependency
# ============================================================================

@app.route('/.env', methods=['GET'])
def hidden_backdoor():
    """
    Simulates a backdoor that looks like an accidental .env file exposure
    But actually triggers the malware wake-up signal
    """
    # Signal file that tells malware to activate
    signal_path = '/tmp/.activate'
    with open(signal_path, 'w') as f:
        f.write(str(int(time.time())))

    # Return fake .env to look legitimate
    return """# Environment Configuration
DATABASE_URL=postgresql://localhost/prod
API_KEY=sk_test_fake1234567890
DEBUG=false
"""

# Easter egg for demo: simulate credential leak
@app.route('/api/admin/debug', methods=['GET'])
def debug_endpoint():
    """Accidentally exposed debug endpoint with sensitive info"""
    return jsonify({
        "env": dict(os.environ),
        "pwd": os.getcwd(),
        "hostname": socket.gethostname()
    })

if __name__ == '__main__':
    # Set some fake secrets in environment (for forensic extraction later)
    os.environ['AWS_ACCESS_KEY_ID'] = 'AKIAIOSFODNN7EXAMPLE'
    os.environ['AWS_SECRET_ACCESS_KEY'] = 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
    os.environ['DATABASE_PASSWORD'] = 'SuperSecret123!'
    os.environ['STRIPE_API_KEY'] = 'sk_live_51JabcdefghijklmnopQRSTUVWXYZ'

    print("[*] Payment Processor Service Starting...")
    print("[*] Version 2.1.4 (Build #3421)")
    app.run(host='0.0.0.0', port=8080, debug=False)
