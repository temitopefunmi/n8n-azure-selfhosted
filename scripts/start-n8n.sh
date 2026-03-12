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

# Start in detached mode
docker-compose up -d

# -----------------------------
# Wait until n8n is fully ready
# -----------------------------
echo "Waiting for n8n to be ready (this may take 20-30s)..."
MAX_WAIT=60
WAITED=0

until curl -s http://127.0.0.1:5678/healthz > /dev/null 2>&1 || [ $WAITED -ge $MAX_WAIT ]; do
  sleep 2
  WAITED=$((WAITED+2))
done

if [ $WAITED -ge $MAX_WAIT ]; then
  echo "[WARNING] n8n may not be fully ready yet."
else
  echo "n8n is ready and accessible!"
fi

echo "===== $(date) Startup script finished ====="