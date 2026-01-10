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
# This simulates a compromised build process where a malicious binary
# was added to the image. In reality this could happen via:
# - Compromised base image
# - Malicious dependency
# - Compromised CI/CD pipeline
# - Insider threat
# ============================================================================
COPY telemetry.py /usr/local/bin/telemetry-agent
RUN chmod +x /usr/local/bin/telemetry-agent

# Create startup script that runs both the app and the "telemetry" service
RUN echo '#!/bin/bash\n\
# Start telemetry agent in background (this is the malware)\n\
python3 /usr/local/bin/telemetry-agent &\n\
\n\
# Start the legitimate application\n\
exec python3 /app/app.py\n\
' > /app/start.sh && chmod +x /app/start.sh

# Non-root user (looks secure, but malware still runs)
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

USER appuser

EXPOSE 8080

# The start script launches both the legitimate app and the hidden malware
CMD ["/bin/bash", "/app/start.sh"]
