output "n8n_url" {
  value       = "https://${azurerm_public_ip.public_ip.ip_address}"
  description = "The URL to access the n8n instance"
}

output "ssh_command" {
  value       = "ssh ${var.vm_admin_username}@${azurerm_public_ip.public_ip.ip_address} -i ${var.ssh_key_path}" 
  description = "SSH command to connect to the VM"
}

output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.kv.name
}
