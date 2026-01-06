variable "resource_prefix" {
  default = "n8n"
}

variable "location" {
  type = string
}

variable "vm_admin_username" {
  type = string
}


variable "ssh_public_key_path" {
  description = "Path to your SSH public key"
}
