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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.29"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

locals {
  tailscale_key_enabled = var.tailnet_name != "" && var.tailscale_api_key != ""
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    virtual_machine {
      delete_os_disk_on_deletion     = true
      skip_shutdown_and_force_delete = true
    }
  }
}

provider "tailscale" {
  # Terraform configures this provider even when the resource count is zero,
  # and the provider rejects empty values before planning any resources.
  tailnet = local.tailscale_key_enabled ? var.tailnet_name : "-"
  api_key = local.tailscale_key_enabled ? var.tailscale_api_key : "unused"
}

resource "random_pet" "ts" {
  length    = 2
  separator = ""
}

data "azurerm_resource_group" "ts" {
  count = var.resource_group_name == "" ? 0 : 1
  name  = var.resource_group_name
}

resource "azurerm_resource_group" "ts" {
  count    = var.resource_group_name == "" ? 1 : 0
  name     = "rg-${random_pet.ts.id}"
  location = var.location
  tags     = var.tags
}

locals {
  resource_group_name = var.resource_group_name == "" ? azurerm_resource_group.ts[0].name : data.azurerm_resource_group.ts[0].name
  location            = var.resource_group_name == "" ? var.location : data.azurerm_resource_group.ts[0].location
}

resource "azurerm_virtual_network" "ts" {
  name                = "vnet-${random_pet.ts.id}"
  address_space       = [var.vnet_address_space]
  location            = local.location
  resource_group_name = local.resource_group_name
}

resource "azurerm_subnet" "ts" {
  name                 = "snet-${random_pet.ts.id}"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.ts.name
  address_prefixes     = [var.snet_address_space]
}

resource "azurerm_network_security_group" "ts" {
  name                = "nsg-${random_pet.ts.id}"
  location            = local.location
  resource_group_name = local.resource_group_name

  security_rule {
    name                       = "AllowTailscaleInbound"
    priority                   = 150
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "41641"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "ts" {
  subnet_id                 = azurerm_subnet.ts.id
  network_security_group_id = azurerm_network_security_group.ts.id
}

resource "tls_private_key" "ts" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_ssh_public_key" "ts" {
  name                = "ssh-${random_pet.ts.id}"
  resource_group_name = local.resource_group_name
  location            = local.location
  public_key          = tls_private_key.ts.public_key_openssh
}

resource "tailscale_tailnet_key" "ts" {
  count         = local.tailscale_key_enabled ? 1 : 0
  reusable      = false
  ephemeral     = true
  preauthorized = true
}

data "cloudinit_config" "ts" {
  base64_encode = true
  gzip          = true

  part {
    content_type = "text/cloud-config"
    content      = file("./tailscale.yml")
  }

  part {
    content_type = "text/x-shellscript"
    content = templatefile("./tailscale.sh", {
      tailscale_auth_key = local.tailscale_key_enabled ? tailscale_tailnet_key.ts[0].key : ""
    })
  }

  lifecycle {
    precondition {
      condition     = (var.tailnet_name == "") == (var.tailscale_api_key == "")
      error_message = "tailnet_name and tailscale_api_key must either both be set or both be empty."
    }
  }
}

resource "azurerm_network_interface" "ts" {
  name                = "${random_pet.ts.id}-nic"
  location            = local.location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.ts.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "ts" {
  name                = random_pet.ts.id
  resource_group_name = local.resource_group_name
  location            = local.location
  size                = var.vm_sku
  admin_username      = var.vm_username

  network_interface_ids = [
    azurerm_network_interface.ts.id,
  ]

  admin_ssh_key {
    username   = var.vm_username
    public_key = tls_private_key.ts.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_os_disk_storage_type
  }

  source_image_reference {
    publisher = var.vm_source_image.publisher
    offer     = var.vm_source_image.offer
    sku       = var.vm_source_image.sku
    version   = var.vm_source_image.version
  }

  custom_data = data.cloudinit_config.ts.rendered
}

resource "azurerm_virtual_machine_run_command" "tailscale_auth_url" {
  count              = local.tailscale_key_enabled ? 0 : 1
  name               = "fetch-tailscale-auth-url"
  location           = local.location
  virtual_machine_id = azurerm_linux_virtual_machine.ts.id

  source {
    script = <<-EOT
      #!/usr/bin/env bash
      set -euo pipefail

      timeout_seconds=300
      poll_interval_seconds=5
      deadline=$(( $(date +%s) + timeout_seconds ))

      while [ "$(date +%s)" -lt "$deadline" ]; do
        if command -v tailscale-authurl >/dev/null 2>&1; then
          remaining_seconds=$(( deadline - $(date +%s) ))
          if [ "$remaining_seconds" -le 0 ]; then
            break
          fi

          if url=$(timeout "$remaining_seconds"s tailscale-authurl 2>/dev/null) && [ -n "$url" ]; then
            printf '%s\n' "$url"
            exit 0
          fi
        fi

        remaining_seconds=$(( deadline - $(date +%s) ))
        if [ "$remaining_seconds" -le 0 ]; then
          break
        elif [ "$remaining_seconds" -lt "$poll_interval_seconds" ]; then
          sleep "$remaining_seconds"
        else
          sleep "$poll_interval_seconds"
        fi
      done

      echo "Tailscale login URL was not available within $timeout_seconds seconds" >&2
      exit 1
    EOT
  }
}
