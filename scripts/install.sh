#!/bin/bash
set -e

DOWNLOAD_DIR="/var/lib/waagent/custom-script/download/0"
TARGET_DIR="/opt/n8n"

echo "Installation begins..."
apt update
apt install -y \
  docker.io \
  docker-compose \
  nginx \
  jq

systemctl enable docker
systemctl start docker


echo "Configuring NGINX..."
cat <<EOF >/etc/nginx/sites-available/n8n
server {
  listen 80;
  location / {
    proxy_pass http://localhost:5678;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
  }
}
EOF

ln -s /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default
systemctl restart nginx

echo "Installation complete."

mkdir -p $TARGET_DIR

# Move runtime files into place
mv $DOWNLOAD_DIR/start-n8n.sh $TARGET_DIR/
mv $DOWNLOAD_DIR/docker-compose.yml $TARGET_DIR/

chmod +x $TARGET_DIR/start-n8n.sh

echo "✔ n8n runtime prepared at /opt/n8n"
