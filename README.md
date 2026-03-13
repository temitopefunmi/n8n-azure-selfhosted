### Secure, Self-Hosted Automation with VNet Isolation & Managed PostgreSQL

This repository deploys an n8n instance on Azure using a **healthcare-style secure architecture**. It moves beyond simple "demo" setups by implementing enterprise security patterns: private networking, identity-based access, and decoupled managed data persistence.

> **The Goal:** Run `terraform apply` and immediately access production-ready automation platform, over HTTPS, where the database is invisible to the internet, secrets are never stored on disk, and reboots are handled with a professional, automated UX.

---

# 🏗️ Architecture Overview

The infrastructure is designed for **defensible security** and **high reliability**.

* **Compute:** Ubuntu Linux VM running n8n via Docker Compose in "Attached Mode" for direct systemd monitoring.
* **Database:** Azure Database for PostgreSQL (Flexible Server) — decoupled from the VM for 99.9% availability.
* **Networking:**
* **VNet Integration**: The database has **zero public exposure**. It resides in a delegated subnet reachable only by the VM via a private IP.
* **Private DNS**: Internal name resolution via Azure Private DNS Zones ensures secure, private communication.


* **Reverse Proxy:** Host-level NGINX handling TLS termination and WebSockets.
* **Security:** System-Assigned Managed Identity for passwordless Key Vault access.

---

# 🛡️ Security & Compliance Features

### 1. Network Isolation (The "Healthcare" Standard)

Unlike standard tutorials, this setup uses **Virtual Network (VNet) Integration**.

* The database is strictly private and has no public IP.
* Traffic between n8n and PostgreSQL never touches the public internet.
* External access to the VM is restricted to ports 80 (redirected) and 443 (TLS).

### 2. Identity-Based Secret Management

We eliminate the risk of "secrets in code".

* **Zero-Knowledge VM**: The VM does not store Azure credentials or database passwords on its disk.
* **Managed Identity**: At boot, the VM uses its **System-Assigned Managed Identity** to "handshake" with Azure Key Vault and retrieve secrets at runtime.
* **Automated Secrets**: Terraform generates 32-character random passwords for the database and n8n encryption, storing them directly in Key Vault.

### 3. Professional UX (The Boot Experience)

We’ve solved the "502 Bad Gateway" issue common during container initialization.

* **Custom Loading Page**: NGINX serves a professional "n8n is starting" page while containers initialize.
* **Auto-Refresh**: The loading page automatically refreshes every 5 seconds until n8n is ready, providing a seamless hand-off to the setup screen.
* **Attached Mode Monitoring**: The startup script uses `exec docker-compose up`, allowing `systemd` to maintain a direct heartbeat on the n8n process.

---

# 💾 Data Persistence Model

* **Decoupled Storage**: Workflows and execution data are stored in **Azure Database for PostgreSQL**, ensuring your data survives VM reboots or even total VM destruction.
* **Managed Reliability**: Since the DB is a managed service, it benefits from Azure's automated backups and point-in-time recovery.

---

# 🚀 Getting Started

### 1. Prerequisites

* Azure CLI logged in (`az login`).
* Terraform (v1.5+).
* SSH Keypair (ssh-keygen -t rsa -b 4096).

### 2. Configuration

Create a `terraform.tfvars` file based on the example:

```hcl
resource_prefix      = "n8n"
location             = "eastus"
vm_admin_username    = "azureuser"
ssh_key_path         = "~/.ssh/id_rsa.pub"
ssh_private_key_path = "~/.ssh/id_rsa"
address_space        = ["10.0.0.0/16"]
address_prefixes     = ["10.0.1.0/24"]
db_subnet_prefixes   = ["10.0.2.0/24"]

```

### 3. Deployment

```bash
# Initialize and deploy
terraform init
terraform apply

```

---

# 🌐 Accessing n8n

**Option A: By IP**
```bash
https://<VM_PUBLIC_IP>
```

**Option B: By hostname (`demo.local`)**
On macOS, edit `/etc/hosts`:
```bash
sudo nano /etc/hosts
```
Add:
```
<VM_PUBLIC_IP> demo.local
```
Flush DNS cache:
```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```
Test:
```bash
ping demo.local
```
Then browse:
```bash
https://demo.local
```
---

**Compliance Note:** For production, replace `demo.local` with a real DNS name and issue a certificate from a trusted CA (e.g., Let’s Encrypt, DigiCert).

---

# 📂 Repository Structure

├── main.tf
├── outputs.tf
├── terraform.tfvars
├── scripts/
│   ├── install.sh
│   ├── start-n8n.sh
│   └── docker-compose.yml
├── .gitignore
└── README.md

* `main.tf`: Core logic for VNet Integration, Managed DB, and Identity.
* `variables.tf`: Configuration variables for your environment.
* `scripts/install.sh`: Host-level hardening, NGINX configuration, and loading page setup.
* `scripts/start-n8n.sh`: Secure runtime secret fetching and process management.
* `scripts/docker-compose.yml`: Simplified n8n container stack.

---

# 🔎 Troubleshooting & Logs

**View real-time application logs:**

```bash
sudo journalctl -u n8n -f

```

**Verify Key Vault connectivity:**

```bash
az login --identity
az keyvault secret show --vault-name <KV_NAME> --name db-host

```

---

### 🔎 Checking Service Status
Run:
```bash
sudo systemctl status n8n
```

---

### ✅ Quick Health Check
```bash
curl -vk https://demo.local/
```


# Important Implementation Details

### Azure CLI on the VM

The VM installs Azure CLI during provisioning because the runtime script depends on:

```
/usr/bin/az login --identity
```

Without Azure CLI installed, secret retrieval would fail.

---

### systemd Service

A systemd service (`/etc/systemd/system/n8n.service`) ensures:

* n8n starts on boot
* Docker is required before startup
* If containers crash, systemd restarts the service
* Logs are written to:

  * `/var/log/n8n-start.log`
  * `journalctl -u n8n`

This prevents restart loops and 502 errors caused by detached Docker processes.

---

### Docker Compose Behavior

The service runs:

```
docker-compose up
```

(not `-d`)

This is intentional.

Why?

* systemd must own the foreground process
* Avoids container restart loops
* Ensures clean service lifecycle management

---

# Cleanup

```bash
terraform destroy
```

---

# 📈 Roadmap (Phase 4 Improvements)

* [ ] **CI/CD with OIDC**
  Use GitHub Actions with OpenID Connect to deploy without storing credentials.

* [ ] **WAF Integration**
  Add Azure Application Gateway with Web Application Firewall (WAF) for Layer-7 protection.

* [ ] **Secret Rotation**
  Automate rotation of PostgreSQL, n8n encryption key, and TLS certificates via Azure Automation / Key Vault.

* [ ] **Azure Monitor + Log Analytics**
  Enable centralized logging, audit trails, and alerting for VM, PostgreSQL, and Key Vault.

* [ ] **Backup & Recovery Policy**
  Configure automated backups and point-in-time restore validation for PostgreSQL.

* [ ] **Disk Encryption & Secure Boot**
  Enable Azure Disk Encryption and Trusted Launch for the VM.

* [ ] **RBAC Hardening**
  Restrict Key Vault and resource access using least-privilege role assignments.

* [ ] **Patch Management**
  Enable automatic OS patching for the VM using Azure Update Manager.

* [ ] **Private DNS + Custom Domain**
  Replace demo.local with real DNS + trusted CA certificate.

* [ ] **High Availability**
  Add VM Scale Set or zone-redundant PostgreSQL for higher uptime.

---

**Author:** Temitope Olayinka.
*Demonstrating secure, reproducible automation infrastructure on Microsoft Azure.*