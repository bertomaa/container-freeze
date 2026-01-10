#!/usr/bin/env python3
"""
Payment Backend Service - Container Freeze Demo
Legitimate payment processing API
"""
import os
import time
import socket
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/api/health', methods=['GET'])
def health():
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
    # Set credentials in environment (will be stolen by malware)
    os.environ['AWS_ACCESS_KEY_ID'] = 'AKIAIOSFODNN7EXAMPLE'
    os.environ['AWS_SECRET_ACCESS_KEY'] = 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
    os.environ['DATABASE_PASSWORD'] = 'SuperSecret123!'
    os.environ['STRIPE_API_KEY'] = 'sk_live_51JabcdefghijklmnopQRSTUVWXYZ'
    os.environ['PAYMENT_GATEWAY_TOKEN'] = 'pgw_live_abc123xyz789'

    print("[*] Payment Backend Service Starting...")
    print("[*] Version 3.2.1 (Build #8842)")
    app.run(host='0.0.0.0', port=8080, debug=False)
