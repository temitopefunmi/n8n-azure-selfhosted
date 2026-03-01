#!/bin/bash
set -euo pipefail

# -------------------------------
# Variables
# -------------------------------
CERT_NAME="n8n-cert"              # Logical name for the cert
DOMAIN="app.demo.local"           # Demo CN; in production, use your real domain
# ------------------------------- 
# Prompt user for password securely with confirmation 
# ------------------------------- 
while true; do 
  read -s -p "Enter certificate password: " CERT_PASSWORD
  echo
  read -s -p "Confirm certificate password: " CONFIRM_PASSWORD
  echo
  if [[ "$CERT_PASSWORD" == "$CONFIRM_PASSWORD" ]]; then 
    break
  else 
    echo "Passwords do not match. Please try again."
  fi
done

# -------------------------------
# Step 1: Generate PEM files
# -------------------------------
# DEMO: self-signed cert generated locally
# PRODUCTION: you’d skip this step, because your CA gives you privkey.pem + fullchain.pem
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout privkey.pem \
  -out fullchain.pem \
  -subj "/CN=${DOMAIN}"\
  -addext "subjectAltName = DNS:${DOMAIN}"
  
echo "[PREGEN] PEM files generated (privkey.pem, fullchain.pem)."

# -------------------------------
# Step 2: Convert to PFX
# -------------------------------
# DEMO: convert self-signed PEMs to PFX
# PRODUCTION: convert CA-issued PEMs to PFX (same command)
openssl pkcs12 -export \
  -out cert.pfx \
  -inkey privkey.pem \
  -in fullchain.pem \
  -password pass:${CERT_PASSWORD}

echo "[PREGEN] Converted PEMs to PFX (cert.pfx)."

echo "[PREGEN] ✔ Done. You now have cert.pfx and its password locally."
echo "          Terraform or your VM install script will later upload/download from Key Vault."
