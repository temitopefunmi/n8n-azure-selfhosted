#!/bin/bash
set -e

# ===============================================
# 🚀 Start n8n (Secrets pulled from Azure Key Vault)
# ===============================================

# ---- CONFIG ----
KEYVAULT_NAME="${KEYVAULT_NAME:?KEYVAULT_NAME is not set}"

# ---- LOGIN USING MANAGED IDENTITY ----
echo "🔐 Authenticating to Azure using Managed Identity..."
az login --identity --output none

# ---- FETCH SECRETS FROM KEY VAULT ----
echo "🔑 Fetching secrets from Azure Key Vault..."

POSTGRES_PASSWORD=$(az keyvault secret show \
  --vault-name "$KEYVAULT_NAME" \
  --name postgres-password \
  --query value -o tsv)

N8N_ENCRYPTION_KEY=$(az keyvault secret show \
  --vault-name "$KEYVAULT_NAME" \
  --name n8n-encryption-key \
  --query value -o tsv)

# ---- VALIDATE SECRETS ----
if [[ -z "$POSTGRES_PASSWORD" || -z "$N8N_ENCRYPTION_KEY" ]]; then
  echo "❌ Failed to retrieve required secrets from Key Vault"
  exit 1
fi

# ---- EXPORT FOR DOCKER COMPOSE ----
export POSTGRES_PASSWORD
export N8N_ENCRYPTION_KEY

echo "✅ Secrets loaded into environment"

# ---- START N8N ----
cd /opt/n8n

echo "🚀 Starting n8n with docker-compose..."
docker-compose up -d

echo ""
echo "✅ n8n started successfully"
echo "🌐 Access via VM public IP (or domain if configured)"
