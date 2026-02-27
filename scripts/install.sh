echo "Generating self-signed SSL certificate..."
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/n8n.key \
  -out /etc/nginx/ssl/n8n.crt \
  -subj "/CN=$(hostname -I | awk '{print $1}')"

# Fix permissions so NGINX can read the key
chmod 640 /etc/nginx/ssl/n8n.key
chmod 644 /etc/nginx/ssl/n8n.crt
chown root:www-data /etc/nginx/ssl/n8n.key

echo "Configuring NGINX with SSL..."
cat <<EOF >/etc/nginx/sites-available/n8n
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
    }
}

server {
    listen 80;
    server_name _;
    return 301 https://\$host\$request_uri;
}
EOF

ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
rm -f /etc/nginx/sites-enabled/default

# Validate and restart
nginx -t
systemctl restart nginx
