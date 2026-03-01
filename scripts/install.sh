#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

DOWNLOAD_DIR="/var/lib/waagent/custom-script/download/0"
TARGET_DIR="/opt/n8n"
SSL_DIR="/etc/nginx/ssl"
RETRY_COUNT=5
RETRY_DELAY=10

log()   { echo "[INSTALL] $1"; }
fail()  { echo "[ERROR] $1"; exit 1; }

# ---- Update and install prerequisites ----
log "Updating apt..."
sudo apt-get update -y

log "Installing required packages..."
sudo apt-get install -y --no-install-recommends \
  ca-certificates curl apt-transport-https lsb-release gnupg \
  docker.io docker-compose nginx jq openssl || fail "Package installation failed"

sudo systemctl enable docker
sudo systemctl start docker

# ---- Install Azure CLI ----
log "Installing Azure CLI..."
curl -sL https://packages.microsoft.com/keys/microsoft.asc | \
  gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null

AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
  sudo tee /etc/apt/sources.list.d/azure-cli.list

sudo apt-get update -y
sudo apt-get install -y azure-cli || fail "Azure CLI installation failed"

command -v az >/dev/null 2>&1 || fail "Azure CLI not found"
log "Azure CLI installed at $(which az)"

# ---- Authenticate VM managed identity ----
log "Logging in with VM managed identity..."
for i in $(seq 1 $RETRY_COUNT); do
    az login --identity --allow-no-subscriptions --output none && break || \
    (log "Retrying managed identity login ($i/$RETRY_COUNT)..." && sleep $RETRY_DELAY)
done

az account show >/dev/null 2>&1 || fail "Managed identity login failed"

# ---- Fetch SSL certificate from Key Vault ----
log "Fetching SSL certificate from Key Vault..."
sudo mkdir -p "$SSL_DIR"

for i in $(seq 1 $RETRY_COUNT); do
    az keyvault certificate download \
      --vault-name "${KEYVAULT_NAME}" \
      --name "n8n-cert" \
      --file "${SSL_DIR}/n8n.pfx" && [ -s "${SSL_DIR}/n8n.pfx" ] && break || \
    (log "Retrying fetch of n8n-cert ($i/$RETRY_COUNT)..." && sleep $RETRY_DELAY)
done

[ -f "${SSL_DIR}/n8n.pfx" ] || fail "Certificate file not found"

# Extract PEM files (no password needed for self-signed cert)
log "Extracting PEM files from PFX..."
sudo openssl pkcs12 -in "${SSL_DIR}/n8n.pfx" -clcerts -nokeys -nodes \
  -out "${SSL_DIR}/n8n.crt" || fail "Failed to extract certificate"

sudo openssl pkcs12 -in "${SSL_DIR}/n8n.pfx" -nocerts -nodes \
  -out "${SSL_DIR}/n8n.key" || fail "Failed to extract private key"

sudo chmod 640 "${SSL_DIR}/n8n.key"
sudo chmod 644 "${SSL_DIR}/n8n.crt"
sudo chown root:www-data "${SSL_DIR}/n8n.key"

# ---- Configure NGINX ----
log "Configuring NGINX..."
sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

sudo tee /etc/nginx/sites-available/n8n > /dev/null <<EOF
server {
    listen 443 ssl;
    server_name _;

    ssl_certificate ${SSL_DIR}/n8n.crt;
    ssl_certificate_key ${SSL_DIR}/n8n.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 80;
    return 301 https://\$host\$request_uri;
}
EOF

sudo ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t || fail "NGINX config test failed"
sudo systemctl enable nginx
sudo systemctl restart nginx

# ---- N8N runtime ----
log "Preparing n8n directory..."
sudo mkdir -p "${TARGET_DIR}"
sudo chown -R root:root "${TARGET_DIR}"

sudo mv "${DOWNLOAD_DIR}/start-n8n.sh" "${TARGET_DIR}/" || fail "start-n8n.sh not found"
sudo chmod +x "${TARGET_DIR}/start-n8n.sh"

sudo mv "${DOWNLOAD_DIR}/docker-compose.yml" "${TARGET_DIR}/" || fail "docker-compose.yml not found"

# ---- SYSTEMD service ----
log "Creating systemd service..."
sudo tee /etc/systemd/system/n8n.service > /dev/null <<EOF
[Unit]
Description=n8n Automation Platform
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
Environment=KEYVAULT_NAME=${KEYVAULT_NAME}
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
WorkingDirectory=${TARGET_DIR}
ExecStart=${TARGET_DIR}/start-n8n.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable n8n
sudo systemctl restart n8n

log "✔ Installation finished. n8n should be running via HTTPS immediately."
