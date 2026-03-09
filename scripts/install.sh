#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
export OPENSSL_CONF=/dev/null

DOWNLOAD_DIR="/var/lib/waagent/custom-script/download/0"
TARGET_DIR="/opt/n8n"
SSL_DIR="/etc/nginx/ssl"

RETRY_COUNT=10
RETRY_DELAY=10

log() { echo "[INSTALL] $1"; }
fail() { echo "[ERROR] $1"; exit 1; }

log "Starting install script..."

sleep 15

# ------------------------
# Update + packages
# ------------------------

log "Updating apt..."
apt-get update -y

log "Installing packages..."
apt-get install -y \
  ca-certificates \
  curl \
  apt-transport-https \
  lsb-release \
  gnupg \
  docker.io \
  docker-compose \
  nginx \
  jq \
  openssl

systemctl enable docker
systemctl start docker

# ------------------------
# Azure CLI
# ------------------------

log "Installing Azure CLI..."

curl -sL https://packages.microsoft.com/keys/microsoft.asc \
 | gpg --dearmor \
 | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null

AZ_REPO=$(lsb_release -cs)

echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" \
 > /etc/apt/sources.list.d/azure-cli.list

apt-get update -y
apt-get install -y azure-cli

command -v az || fail "Azure CLI missing"

# ------------------------
# Managed identity login
# ------------------------

log "Waiting for managed identity..."

for i in $(seq 1 $RETRY_COUNT); do
  az login --identity --allow-no-subscriptions --output none && break
  log "Retry login $i"
  sleep $RETRY_DELAY
done

az account show || fail "Managed identity failed"

# ------------------------
# Fetch certificate
# ------------------------

log "Fetching certificate from KeyVault..."

mkdir -p "$SSL_DIR"

for i in $(seq 1 $RETRY_COUNT); do

  SECRET_VALUE=$(az keyvault secret show \
    --vault-name "$KEYVAULT_NAME" \
    --name "n8n-cert" \
    --query value -o tsv) || true

  if [ -n "$SECRET_VALUE" ]; then
    echo "$SECRET_VALUE" | base64 -d > "$SSL_DIR/n8n.pfx"
  fi

  if [ -s "$SSL_DIR/n8n.pfx" ]; then
    break
  fi

  log "Retry cert $i"
  sleep $RETRY_DELAY

done

[ -f "$SSL_DIR/n8n.pfx" ] || fail "No cert"

# ------------------------
# Extract cert
# ------------------------

log "Extracting cert..."

openssl pkcs12 \
 -in "$SSL_DIR/n8n.pfx" \
 -clcerts \
 -nokeys \
 -nodes \
 -passin pass: \
 -out "$SSL_DIR/n8n.crt"

openssl pkcs12 \
 -in "$SSL_DIR/n8n.pfx" \
 -nocerts \
 -nodes \
 -passin pass: \
 -out "$SSL_DIR/n8n.key"

chmod 600 "$SSL_DIR/n8n.key"
chmod 644 "$SSL_DIR/n8n.crt"

# ------------------------
# NGINX
# ------------------------

log "Config nginx..."

cat > /etc/nginx/sites-available/n8n <<EOF
server {

    listen 443 ssl;
    server_name _;

    ssl_certificate $SSL_DIR/n8n.crt;
    ssl_certificate_key $SSL_DIR/n8n.key;

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 90s;
        proxy_connect_timeout 90s;
    }
}

server {
    listen 80;
    return 301 https://\$host\$request_uri;
}
EOF

ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl enable nginx
systemctl restart nginx

# ------------------------
# Move files
# ------------------------

log "Prepare n8n dir..."

mkdir -p "$TARGET_DIR"

mv "$DOWNLOAD_DIR/start-n8n.sh" "$TARGET_DIR/"
mv "$DOWNLOAD_DIR/docker-compose.yml" "$TARGET_DIR/"

chmod +x "$TARGET_DIR/start-n8n.sh"

# ------------------------
# systemd service
# ------------------------

log "Creating service..."

cat > /etc/systemd/system/n8n.service <<EOF
[Unit]
Description=n8n
After=docker.service
Requires=docker.service

[Service]
Type=simple
Environment=KEYVAULT_NAME=$KEYVAULT_NAME
WorkingDirectory=$TARGET_DIR
ExecStart=$TARGET_DIR/start-n8n.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable n8n
systemctl restart n8n

log "DONE"