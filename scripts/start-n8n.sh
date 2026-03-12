#!/bin/bash
set -euo pipefail

mkdir -p /opt/n8n

cp /var/lib/waagent/custom-script/download/0/* /opt/n8n/
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
DB_POSTGRESDB_HOST=$(/usr/bin/az keyvault secret show --vault-name "$KEYVAULT_NAME" --name db-host --query value -o tsv)

if [[ -z "$POSTGRES_PASSWORD" || -z "$N8N_ENCRYPTION_KEY" || -z "$DB_POSTGRESDB_HOST" ]]; then
  echo "ERROR: Failed to retrieve required secrets from Key Vault"
  exit 1
fi

export POSTGRES_PASSWORD
export N8N_ENCRYPTION_KEY
export DB_POSTGRESDB_HOST
export DB_POSTGRESDB_USER="n8nadmin"
export DB_POSTGRESDB_PORT="5432"
export DB_POSTGRESDB_DATABASE="postgres"

echo "Secrets loaded successfully"

echo "Waiting for Docker to be ready..."
while ! docker info > /dev/null 2>&1; do
  sleep 2
done
echo "Docker is ready"

cd /opt/n8n

cat > /opt/n8n/.env <<EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
DB_POSTGRESDB_HOST=$DB_POSTGRESDB_HOST
EOF

# Clean up any old containers
docker-compose down || true
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

echo "===== $(date) Startup script finished. n8n should be running via HTTPS. ====="
