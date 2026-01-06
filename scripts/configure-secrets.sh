#!/bin/bash
set -e   # Exit immediately if any command fails

# Target directory where n8n runtime files will live
TARGET_DIR="/opt/n8n"

echo "Installation begins..."

# -----------------------------
# Install required dependencies
# -----------------------------
export DEBIAN_FRONTEND=noninteractive   # Prevent interactive prompts during apt installs
apt update
apt install -y \
  docker.io \        # Docker engine
  docker-compose \   # Docker Compose for multi-container setup
  nginx \            # Reverse proxy
  jq                 # Lightweight JSON processor (used in scripts)

# Enable and start Docker service so containers can run
systemctl enable docker
systemctl start docker

# -----------------------------
# Configure NGINX reverse proxy
# -----------------------------
echo "Configuring NGINX..."
cat <<EOF >/etc/nginx/sites-available/n8n
server {
  listen 80;                         # Listen on port 80 (HTTP)
  location / {
    proxy_pass http://localhost:5678; # Forward traffic to n8n container
    proxy_http_version 1.1;           # Ensure HTTP/1.1 for WebSocket support
    proxy_set_header Upgrade \$http_upgrade;   # Handle WebSocket upgrade requests
    proxy_set_header Connection "upgrade";     # Maintain WebSocket connection
    proxy_set_header Host \$host;              # Preserve original host header
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; # Forward client IP
    proxy_set_header X-Forwarded-Proto \$scheme;                  # Forward protocol (http/https)
  }
}
EOF

# Enable the new site config and disable the default
ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
rm -f /etc/nginx/sites-enabled/default

# Reload NGINX to apply changes (restart if reload fails)
systemctl reload nginx || systemctl restart nginx

echo "Installation complete."

# -----------------------------
# Prepare n8n runtime directory
# -----------------------------
mkdir -p $TARGET_DIR

# Move runtime files (downloaded by Custom Script Extension) into /opt/n8n
# Since the script runs from the download directory, we can use relative paths
mv ./start-n8n.sh $TARGET_DIR/
mv ./docker-compose.yml $TARGET_DIR/

# Make the startup script executable
chmod +x $TARGET_DIR/start-n8n.sh

echo "✔ n8n runtime prepared at /opt/n8n"
