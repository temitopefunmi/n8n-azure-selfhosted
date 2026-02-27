variable "resource_prefix" {
  description = "Prefix for naming"
  type = string
}

variable "location" {
  description = "Location of resources"
  type = string
}

variable "vm_admin_username" {
  description = "Admin username for the VM"
  type = string
}


variable "ssh_public_key_path" {
  description = "Path to your SSH public key"
  type = string
}

variable "address_space" {
  description = "Address space for the virtual network"
  type = list(string)
}

variable "address_prefixes" {
  description = "Address prefixes for the subnet"
  type = list(string)
}

variable "vm_size" {
  description = "Size of the VM"
  type = string
}

variable "install_sh_url" {
  description = "Raw GitHub URL for install.sh"
  type        = string
}

variable "start_n8n_sh_url" {
  description = "Raw GitHub URL for start-n8n.sh"
  type        = string
}

variable "docker_compose_url" {
  description = "Raw GitHub URL for docker-compose.yml"
  type        = string
}

variable "postgres_password" {
  type      = string
  sensitive = true
}

variable "n8n_encryption_key" {
  type      = string
  sensitive = true
}
