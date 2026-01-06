# Self-hosting n8n on Azure (Terraform, Docker, NGINX, Key Vault)

This repository deploys a **production-ready, self‑hosted n8n instance on Azure** using **Terraform**, **Docker Compose**, **NGINX**, and **Azure Key Vault**.

The goal is simple:

> Run `terraform apply`, SSH once, start n8n, and access it immediately — **without hard‑coding secrets or losing data**.

This setup is suitable for **regulated / healthcare‑adjacent environments** (HIPAA‑aware), and demonstrates real‑world infrastructure practices.

---

## Architecture Overview

* **Azure Linux VM (Ubuntu)**
* **Docker + Docker Compose**
* **n8n (self‑hosted)**
* **PostgreSQL (Dockerized)**
* **NGINX (reverse proxy, HTTP)**
* **Azure Key Vault (secrets at runtime)**
* **Managed Identity (no stored cloud credentials)**

```
Internet
   ↓
NGINX (port 80)
   ↓
Docker → n8n (5678)
          ↓
      PostgreSQL
```

NGINX runs directly on the VM (not in Docker) to ensure stable WebSockets and predictable TLS termination.

Secrets (DB password, n8n encryption key) are **never stored in Git or .env files** — they are fetched securely from **Azure Key Vault at runtime**.

---

## Repository Structure

```
.
├── main.tf               # All Azure resources
├── variables.tf          # Input variables
├── terraform.tfvars      # Your environment values
├── outputs.tf            # Values you need after deployment
├── scripts/
│   ├── install.sh        # Installs Docker, NGINX, tools
│   ├── start-n8n.sh      # Runtime entrypoint fetches secrets + starts n8n
│   └── docker-compose.yml
├── .gitignore
└── README.md
```

---

## Prerequisites (Local Machine)

Before starting, you need:

* Azure subscription
* Azure CLI (`az login` already done)
* Terraform ≥ 1.5
* SSH keypair

Generate an SSH key **once** if you don’t have one:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "n8n-azure"
```

This creates:

* `~/.ssh/id_ed25519` (private key)
* `~/.ssh/id_ed25519.pub` (public key)

---

## Step 1 — Configure Terraform Variables

Edit `terraform.tfvars`:

```hcl
resource_prefix = "n8n"
location        = "eastus"
vm_size         = "Standard_B2s"
admin_username  = "azureuser"
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
```

> 💡 The public key is injected into the VM automatically. No passwords are used.

---

## Step 2 — Deploy Infrastructure

From the repo root:

```bash
terraform init
terraform plan
terraform apply
```

Terraform will:

* Create a resource group
* Create a Linux VM
* Create a Network Security Group
* Allow inbound ports:

  * 22 (SSH)
  * 80 (NGINX / n8n)
* Create Azure Key Vault
* Enable Managed Identity on the VM
* Attach a Custom Script Extension
* Upload scripts into the VM

---

## Step 3 — Capture Terraform Outputs

After apply completes:

```bash
terraform output
```

You will see values like:

```text
vm_public_ip = "20.xxx.xxx.xxx"
key_vault_name = "n8nkv3f9a2c1d"
```

Save them — you will need both.

---

## Step 4 — Create Secrets in Azure Key Vault (One-Time step)

After Terraform completes, secrets must be written to Azure Key Vault.

This step is intentionally not automated by Terraform to avoid storing secrets in state files.

Run the following command from your local machine:

```bash
./scripts/configure-secrets.sh <KEY_VAULT_NAME> 
```

You will be prompted to enter:

- PostgreSQL password

- n8n encryption key

The secrets are securely stored in Azure Key Vault and retrieved at runtime by the VM using Managed Identity.

⚠️ **Never rotate `n8n-encryption-key` after production start** — doing so breaks credentials.

---

## Step 5 — SSH into the VM

```bash
ssh azureuser@<VM_PUBLIC_IP>
```

All runtime files are already placed in:

```bash
/opt/n8n
```

---

## Step 6 — Export Key Vault Name (Runtime Only)

Inside the VM:

```bash
export KEYVAULT_NAME=<KEY_VAULT_NAME>
```
This allows the runtime script to locate the correct Key Vault without persisting the value on disk.

This is not stored anywhere — it exists only in the shell session.

---

## Step 7 — Start n8n

```bash
cd /opt/n8n
./start-n8n.sh
```

What this script does:

1. Logs in using **Managed Identity**
2. Fetches secrets from Key Vault
3. Exports them as environment variables
4. Starts Docker Compose

---

## Step 8 — Access n8n

Open in your browser:

```
http://<VM_PUBLIC_IP>
```

You should see the **n8n setup page**.

Create your admin user and begin building workflows.

---

## Persistence & Safety

* PostgreSQL data is stored in Docker volumes
* Container restarts are safe
* VM reboots do not lose workflows
* Secrets never touch disk
* The n8n encryption key is externalized and survives redeployments

To restart later:

```bash
cd /opt/n8n
docker compose up -d
```

---

## HTTPS & Custom Domain (Optional)

This demo uses **HTTP only**.

⚠️ OAuth providers (Google, Microsoft, Slack, etc.) require HTTPS.

To enable HTTPS:

1. Point a domain to the VM public IP
2. Install certbot
3. Add TLS config to NGINX
4. Set `N8N_PROTOCOL=https`

This is intentionally left out to keep the demo cost‑free.

---

## Why This Setup Matters

This project demonstrates:

* Secure secret handling (Key Vault + Managed Identity)
* Docker volume persistence
* Clean infrastructure automation
* Real production failure prevention
* Recoverable, auditable architecture

This is **not a toy n8n install**.

---

## Clean Up

```bash
terraform destroy
```

---

## Author

Built as a **portfolio‑grade infrastructure project** for production automation platforms.

---

