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
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor \
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
# Fetch secrets for .env
# ------------------------
log "Fetching secrets from Key Vault..."
POSTGRES_PASSWORD=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name postgres-password --query value -o tsv)
N8N_ENCRYPTION_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name n8n-encryption-key --query value -o tsv)
DB_POSTGRESDB_HOST=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name db-host --query value -o tsv)

[ -n "$POSTGRES_PASSWORD" ] && [ -n "$N8N_ENCRYPTION_KEY" ] && [ -n "$DB_POSTGRESDB_HOST" ] || fail "Secrets missing"

mkdir -p "$TARGET_DIR"
cat > "$TARGET_DIR/.env" <<EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
DB_POSTGRESDB_HOST=$DB_POSTGRESDB_HOST
DB_POSTGRESDB_USER=n8nadmin
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=postgres
EOF

# ------------------------
# SSL / Nginx
# ------------------------
log "Fetching and installing certificate..."
mkdir -p "$SSL_DIR"

for i in $(seq 1 $RETRY_COUNT); do
  SECRET_VALUE=$(az keyvault secret show \
    --vault-name "$KEYVAULT_NAME" \
    --name "n8n-cert" \
    --query value -o tsv) || true

  [ -n "$SECRET_VALUE" ] && echo "$SECRET_VALUE" | base64 -d > "$SSL_DIR/n8n.pfx"

  [ -s "$SSL_DIR/n8n.pfx" ] && break
  log "Retry cert $i"
  sleep $RETRY_DELAY
done

[ -f "$SSL_DIR/n8n.pfx" ] || fail "No certificate found"

# Extract cert/key
openssl pkcs12 -in "$SSL_DIR/n8n.pfx" -clcerts -nokeys -nodes -passin pass: -out "$SSL_DIR/n8n.crt"
openssl pkcs12 -in "$SSL_DIR/n8n.pfx" -nocerts -nodes -passin pass: -out "$SSL_DIR/n8n.key"

chmod 600 "$SSL_DIR/n8n.key"
chmod 644 "$SSL_DIR/n8n.crt"

log "Creating loading page..."
mkdir -p /var/www

cat > /var/www/n8n-loading.html <<EOF
<html>
<head>
    <meta http-equiv="refresh" content="5">
    <title>Starting n8n...</title>
</head>
<body style="font-family:sans-serif;text-align:center;margin-top:100px;">
    <h1>n8n is starting</h1>
    <p>Please wait 10 to 30 seconds...</p>
    <p style="color: gray; font-size: 0.8em;">This page will refresh automatically.</p>
</body>
</html>
EOF


log "Configuring Nginx..."
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

        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;

        error_page 502 503 504 = /n8n-loading.html;
    }

    location = /n8n-loading.html {
        root /var/www;
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
# Move scripts
# ------------------------
log "Moving start script and docker-compose.yml..."
mv "$DOWNLOAD_DIR/start-n8n.sh" "$TARGET_DIR/"
mv "$DOWNLOAD_DIR/docker-compose.yml" "$TARGET_DIR/"
chmod +x "$TARGET_DIR/start-n8n.sh"

# ------------------------
# systemd service
# ------------------------
log "Creating systemd service..."
cat > /etc/systemd/system/n8n.service <<EOF
[Unit]
Description=n8n
After=docker.service
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=$TARGET_DIR
ExecStart=$TARGET_DIR/start-n8n.sh
Restart=always
RestartSec=5
EnvironmentFile=$TARGET_DIR/.env

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable n8n
systemctl restart n8n

log "INSTALL COMPLETE"