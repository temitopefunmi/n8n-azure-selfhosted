#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/n8n-start.log"
exec >> "$LOG_FILE" 2>&1

echo "===== $(date) Starting n8n startup script ====="

# Ensure KEYVAULT_NAME is set
KEYVAULT_NAME="${KEYVAULT_NAME:?KEYVAULT_NAME is not set}"

echo "Authenticating to Azure..."
/usr/bin/az login --identity --allow-no-subscriptions --output none

echo "Fetching secrets from Azure Key Vault..."
POSTGRES_PASSWORD=$(/usr/bin/az keyvault secret show --vault-name "$KEYVAULT_NAME" --name postgres-password --query value -o tsv)
N8N_ENCRYPTION_KEY=$(/usr/bin/az keyvault secret show --vault-name "$KEYVAULT_NAME" --name n8n-encryption-key --query value -o tsv)

if [[ -z "$POSTGRES_PASSWORD" || -z "$N8N_ENCRYPTION_KEY" ]]; then
  echo "ERROR: Failed to retrieve required secrets from Key Vault"
  exit 1
fi

export POSTGRES_PASSWORD
export N8N_ENCRYPTION_KEY
echo "Secrets loaded successfully"

echo "Waiting for Docker to be ready..."
while ! docker info > /dev/null 2>&1; do
  sleep 2
done
echo "Docker is ready"

cd /opt/n8n

# Clean up any old containers
docker-compose down -v || true

echo "Starting Postgres and n8n containers..."
docker-compose up -d

echo "Waiting for n8n..."
for i in {1..30}; do
  if curl -s http://127.0.0.1:5678 > /dev/null; then
    echo "n8n ready"
    break
  fi
  sleep 2
done

echo "n8n started. Keeping service alive..."

tail -f /dev/null

echo "===== $(date) Startup script finished. n8n should be running via HTTPS. ====="
