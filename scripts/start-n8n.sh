#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/n8n-start.log"
exec >> "$LOG_FILE" 2>&1

echo "===== $(date) Starting n8n startup script ====="

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

docker-compose down -v || true

echo "Starting Postgres and n8n containers..."

# This keeps the service alive permanently
exec docker-compose up

echo "Startup script finished. n8n is now running in the background."