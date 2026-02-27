#!/bin/bash
set -euo pipefail

# -----------------------------
# Production-ready n8n startup
# -----------------------------
LOG_FILE="/var/log/n8n-start.log"
exec >> "$LOG_FILE" 2>&1

echo "===== $(date) Starting n8n startup script ====="

KEYVAULT_NAME="${KEYVAULT_NAME:?KEYVAULT_NAME is not set}"

# ---- Login using Managed Identity ----
echo "Authenticating to Azure..."
/usr/bin/az login --identity --allow-no-subscriptions --output none

# ---- Fetch Secrets ----
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

# ---- Wait for Docker daemon ----
echo "Waiting for Docker to be ready..."
while ! sudo docker info > /dev/null 2>&1; do
  sleep 2
done
echo "Docker is ready"

cd /opt/n8n

# ---- Clean old containers and volumes ----
sudo -E docker-compose down -v || true

# ---- Start containers ----
echo "Starting Postgres and n8n containers..."
sudo -E docker-compose up -d

# ---- Wait for Postgres to be healthy ----
POSTGRES_CONTAINER="n8n_postgres_1"
echo "Waiting for Postgres to initialize..."
until sudo docker exec "$POSTGRES_CONTAINER" pg_isready -U postgres > /dev/null 2>&1; do
  sleep 2
done
echo "Postgres is ready"

echo "n8n containers should now be running"
echo "===== $(date) Finished n8n startup script ====="