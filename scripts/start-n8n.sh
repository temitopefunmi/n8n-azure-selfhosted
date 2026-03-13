#!/bin/bash
set -euxo pipefail

LOG_FILE="/var/log/n8n-start.log"
exec >> "$LOG_FILE" 2>&1

echo "===== $(date) Starting n8n via docker-compose ====="

# Wait for Docker
while ! docker info > /dev/null 2>&1; do
  echo "Waiting for Docker..."
  sleep 2
done

cd /opt/n8n

# Stop any existing containers
docker-compose down || true

# Start n8n
exec docker-compose up 

