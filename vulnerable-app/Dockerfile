FROM python:3.11-slim

WORKDIR /app

# Install curl and Flask
RUN apt-get update && apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/* && \
    pip install --no-cache-dir flask==3.0.0

# Copy application
COPY app.py .

# Non-root user (looks secure, but backdoor remains)
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

USER appuser

EXPOSE 8080

CMD ["python", "app.py"]
