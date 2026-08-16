terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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

resource "random_pet" "arm64" {
  separator = ""
  length    = 2
}

resource "azurerm_resource_group" "arm64" {
  name     = "rg-${random_pet.arm64.id}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_container_registry" "arm64" {
  name                = "acr${random_pet.arm64.id}"
  resource_group_name = azurerm_resource_group.arm64.name
  location            = azurerm_resource_group.arm64.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_log_analytics_workspace" "arm64" {
  name                = "law-${random_pet.arm64.id}"
  resource_group_name = azurerm_resource_group.arm64.name
  location            = azurerm_resource_group.arm64.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_kubernetes_cluster" "arm64" {
  name                = "aks-${random_pet.arm64.id}"
  resource_group_name = azurerm_resource_group.arm64.name
  location            = azurerm_resource_group.arm64.location
  dns_prefix          = "aks-${random_pet.arm64.id}"

  default_node_pool {
    name                         = "default"
    node_count                   = 2
    vm_size                      = "Standard_D2s_v5"
    only_critical_addons_enabled = true
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.arm64.id
  }

  identity {
    type = "SystemAssigned"
  }

  node_provisioning_profile {
    mode = "Manual"
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "arm64" {
  name                  = "arm64"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.arm64.id
  vm_size               = "Standard_D4pds_v5"
  node_count            = 2
}

resource "azurerm_role_assignment" "arm64" {
  principal_id                     = azurerm_kubernetes_cluster.arm64.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.arm64.id
  skip_service_principal_aad_check = true
}