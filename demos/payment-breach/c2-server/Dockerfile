FROM python:3.11-slim

RUN apt-get update && apt-get install -y netcat-traditional && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY c2-listener.sh /app/c2.sh
RUN chmod +x /app/c2.sh

RUN mkdir -p /var/log/c2

EXPOSE 4444 8080

CMD ["/app/c2.sh"]
