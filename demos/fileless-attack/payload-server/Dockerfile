FROM python:3.11-slim

WORKDIR /app

# Copy server script
COPY server.py .

# Create log directory
RUN mkdir -p /var/log/payload

EXPOSE 8080

CMD ["python", "server.py"]
