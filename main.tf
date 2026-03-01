provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_prefix}-rg"
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.resource_prefix}-vnet"
  address_space       = var.address_space
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.resource_prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.address_prefixes
}

resource "azurerm_public_ip" "public_ip" {
  name                = "${var.resource_prefix}-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "nic" {
  name                = "${var.resource_prefix}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${var.resource_prefix}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_association" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "random_id" "rand" {
  byte_length = 3
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "${var.resource_prefix}-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.vm_admin_username
  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = file(var.ssh_public_key_path)
  }

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  tags = {
    Environment = "n8n-selfhosted"
  }
}

resource "azurerm_key_vault" "kv" {
  name                        = "${var.resource_prefix}kv${random_id.rand.hex}"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  purge_protection_enabled    = false
  soft_delete_retention_days  = 7

  # VM identity (read-only)
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_linux_virtual_machine.vm.identity[0].principal_id

    secret_permissions = [
      "Get",
      "List"
    ]
    certificate_permissions = [
      "Get"
    ]
  }

  # Your user/service principal (read + write)
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Set",
      "Get",
      "List"
    ]
  }
  depends_on = [ azurerm_linux_virtual_machine.vm ]
}

resource "azurerm_key_vault_certificate" "n8n_cert" {
  name         = "n8n-cert"
  key_vault_id = azurerm_key_vault.kv.id

  certificate {
    contents = filebase64("${path.module}/cert.pfx")
    password = var.cert_password
  }
}

resource "azurerm_key_vault_secret" "cert_password" {
  name         = "n8n-cert-password"
  value        = var.cert_password
  key_vault_id = azurerm_key_vault.kv.id
}

resource "random_password" "postgres_password" {
  length  = 32
  special = true
}

resource "random_password" "n8n_encryption_key" {
  length  = 32
  special = true
}

resource "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgres-password"
  value        = random_password.postgres_password.result
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "n8n_encryption_key" {
  name         = "n8n-encryption-key"
  value        = random_password.n8n_encryption_key.result
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_virtual_machine_extension" "startup" {
  name                 = "n8n-setup"
  virtual_machine_id   = azurerm_linux_virtual_machine.vm.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"
  depends_on           = [azurerm_linux_virtual_machine.vm, azurerm_key_vault.kv]

  settings = <<SETTINGS
    {
        "fileUris": [
            "${var.install_sh_url}",
            "${var.start_n8n_sh_url}",
            "${var.docker_compose_url}"
        ],
        "commandToExecute": "KEYVAULT_NAME=${azurerm_key_vault.kv.name} bash install.sh"
    }
  SETTINGS
}
