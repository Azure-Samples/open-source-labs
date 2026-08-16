terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

locals {
  random_name = "lab${random_integer.example.result}"
}

data "cloudinit_config" "example" {
  base64_encode = true
  gzip          = true

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = file("${path.module}/cloud-config.yaml")
  }

  part {
    filename     = "install.sh"
    content_type = "text/x-shellscript"

    content = templatefile("${path.module}/install.sh", {
      current_user = var.vm_username
    })
  }
}

data "http" "current_ip" {
  url = "https://api.ipify.org"
}

resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "random_integer" "example" {
  min = 10
  max = 99
}

resource "azurerm_resource_group" "example" {
  name     = "rg-${local.random_name}"
  location = var.location
}

resource "azurerm_virtual_network" "example" {
  name                = "vnet-${local.random_name}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_subnet" "example" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_security_group" "example" {
  name                = "nsg-${local.random_name}"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  security_rule {
    name                       = "SSH"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${data.http.current_ip.response_body}/32"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "example" {
  subnet_id                 = azurerm_subnet.example.id
  network_security_group_id = azurerm_network_security_group.example.id
}

resource "azurerm_public_ip" "example" {
  name                = "pip-${local.random_name}"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "example" {
  name                = "nic-${local.random_name}"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.example.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.example.id
  }
}

resource "azurerm_ssh_public_key" "example" {
  name                = "ssh-${local.random_name}"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  public_key          = tls_private_key.example.public_key_openssh
}

resource "local_file" "ssh_private_key" {
  filename        = "${path.module}/ssh_private_key"
  content         = tls_private_key.example.private_key_pem
  file_permission = "0600"
}

resource "azurerm_linux_virtual_machine" "example" {
  name                            = "vm-${local.random_name}"
  resource_group_name             = azurerm_resource_group.example.name
  location                        = azurerm_resource_group.example.location
  size                            = var.vm_size
  admin_username                  = var.vm_username
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.example.id,
  ]

  admin_ssh_key {
    username   = var.vm_username
    public_key = tls_private_key.example.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 1000
  }

  source_image_reference {
    publisher = "canonical"
    offer     = var.vm_image_offer
    sku       = "server"
    version   = "latest"
  }

  custom_data = data.cloudinit_config.example.rendered
}

# resource "azurerm_virtual_machine_extension" "example" {
#   count                      = startswith(lower(var.vm_size), "standard_n") ? 1 : 0
#   virtual_machine_id         = azurerm_linux_virtual_machine.example.id
#   name                       = "vm-${local.random_name}-nvidia-gpu-driver-extension"
#   publisher                  = "Microsoft.HpcCompute"
#   type                       = "NvidiaGpuDriverLinux"
#   type_handler_version       = "1.6"
#   auto_upgrade_minor_version = true
# }