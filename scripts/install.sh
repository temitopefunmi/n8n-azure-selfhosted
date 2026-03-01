#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

DOWNLOAD_DIR="/var/lib/waagent/custom-script/download/0"
TARGET_DIR="/opt/n8n"

log() { echo "[INSTALL] $1"; }
fail() { echo "[ERROR] $1"; exit 1; }

# ---- Install prerequisites ----
log "Updating apt..."
sudo apt-get update -y

log "Installing required packages..."
sudo apt-get install -y --no-install-recommends \
  ca-certificates curl apt-transport-https lsb-release gnupg \
  docker.io docker-compose nginx jq openssl

# ---- Install Azure CLI ----
log "Installing Azure CLI..."
curl -sL https://packages.microsoft.com/keys/microsoft.asc | \
  gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null

AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
  sudo tee /etc/apt/sources.list.d/azure-cli.list

sudo apt-get update -y
sudo apt-get install -y azure-cli

# verify installation
command -v az >/dev/null 2>&1 || fail "Azure CLI installation failed"
log "Azure CLI installed at $(which az)"

# Authenticate with the VM's managed identity
az logout --output none || true
az login --identity --allow-no-subscriptions --output none || fail "Managed identity login failed"
log "Logged in with VM's managed identity"

sudo systemctl enable docker
sudo systemctl start docker

# ---- SSL certificate ----
log "Fetching SSL certificate and password from Key Vault..."
sudo mkdir -p /etc/nginx/ssl

# Get the PFX as a secret (base64-encoded)
CERT_PFX=$(az keyvault secret show \
  --vault-name "${KEYVAULT_NAME}" \
  --name "n8n-cert" \
  --query value -o tsv)

# Decode the base64 string into a .pfx file
echo "$CERT_PFX" | base64 --decode > /etc/nginx/ssl/n8n.pfx

# Get the password secret
CERT_PASSWORD=$(az keyvault secret show \
  --vault-name "${KEYVAULT_NAME}" \
  --name "n8n-cert-password" \
  --query value -o tsv)

# Extract PEM files
log "Extracting PEM files from PFX..."
sudo openssl pkcs12 -in /etc/nginx/ssl/n8n.pfx \
  -clcerts -nokeys \
  -out /etc/nginx/ssl/n8n.crt \
  -password pass:${CERT_PASSWORD}

sudo openssl pkcs12 -in /etc/nginx/ssl/n8n.pfx \
  -nocerts -nodes \
  -out /etc/nginx/ssl/n8n.key \
  -password pass:${CERT_PASSWORD}

sudo chmod 640 /etc/nginx/ssl/n8n.key
sudo chmod 644 /etc/nginx/ssl/n8n.crt
sudo chown root:www-data /etc/nginx/ssl/n8n.key


# ---- NGINX config ----
log "Configuring NGINX..."
sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

sudo tee /etc/nginx/sites-available/n8n > /dev/null <<EOF
server {
    listen 443 ssl;
    server_name _;

    ssl_certificate /etc/nginx/ssl/n8n.crt;
    ssl_certificate_key /etc/nginx/ssl/n8n.key;

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