# Troubleshooting Guide

This document collects the most useful commands for diagnosing issues with the n8n Azure deployment.

---

## 🔐 Key Vault Verification (Local)

Check that secrets and certificates exist in Key Vault:

```bash
# List all secrets
az keyvault secret list --vault-name <kv-name>

# Show the certificate secret (PKCS#12 content)
az keyvault secret show --vault-name <kv-name> --name n8n-cert

# Show the generated password secret (if used)
az keyvault secret show --vault-name <kv-name> --name n8n-cert-password
```

Validate the `.pfx` locally:

```bash
openssl pkcs12 -in cert.pfx -info
```

---

## 🖥️ On the VM

### Extension Logs
Custom Script Extension logs are stored here:

```bash
# Linux
/var/log/azure/Microsoft.Azure.Extensions.CustomScript/2.1/extension.log
```

View logs live:

```bash
sudo tail -f /var/log/azure/Microsoft.Azure.Extensions.CustomScript/2.1/extension.log
```

---

### Service Status
Check if the n8n systemd service is running:

```bash
sudo systemctl status n8n
```

Follow logs in real time:

```bash
sudo journalctl -u n8n -f
```

View logs since boot:

```bash
sudo journalctl -u n8n --since "today"
```

---

### NGINX
Verify NGINX configuration:

```bash
sudo nginx -t
sudo systemctl status nginx
```

---

### Certificate Files
Confirm certificate files exist and are valid:

```bash
ls -l /etc/nginx/ssl/
openssl x509 -in /etc/nginx/ssl/n8n.crt -text -noout
```

---

### Quick Connectivity Test
From the VM:

```bash
curl -vk https://localhost/
```

From your local machine:

```bash
curl -vk https://<VM_PUBLIC_IP>/
curl -vk https://demo.local/
```

---

## Common Failure Modes

### VMExtensionProvisioningError
- Check `/var/log/azure/Microsoft.Azure.Extensions.CustomScript/2.1/extension.log`
- Verify Key Vault secret retrieval (`az keyvault secret show`)
- Ensure Managed Identity has **secret Get/List** permissions

### ASN.1 Errors (PKCS#12)
- Caused by fetching certificate metadata instead of the secret
- Fix: use `az keyvault secret show` with `base64 --decode` to reconstruct `.pfx`

---

## Cleanup
If troubleshooting fails, destroy and redeploy:

```bash
terraform destroy
terraform apply
```
```

