FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    procps \
    net-tools \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir flask==3.0.0

# Copy legitimate application
COPY app.py .

# ============================================================================
# SUPPLY CHAIN INJECTION
# This simulates a compromised build process where a malicious module
# was added to the image. In reality this could happen via:
# - Compromised base image
# - Malicious dependency (pip package)
# - Compromised CI/CD pipeline
# - Insider threat
#
# The telemetry.py module looks legitimate but contains malicious code
# that is triggered via a hidden backdoor in the health endpoint.
# ============================================================================
COPY telemetry.py .

# Non-root user (looks secure, but backdoor still works)
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

USER appuser

EXPOSE 8080

# Just run the Flask app - the backdoor is triggered via API call
CMD ["python", "app.py"]
