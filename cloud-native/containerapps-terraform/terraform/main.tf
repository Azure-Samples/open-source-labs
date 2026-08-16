terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }

    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

resource "random_pet" "aca" {
  length    = 2
  separator = ""
}

resource "random_integer" "aca" {
  min = 000
  max = 999
}

resource "random_string" "aca" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false

  keepers = {
    # Generate a new random_string on every run to avoid a conflict with the previous revision
    none = timestamp()
  }
}

locals {
  resource_name        = format("%s", random_pet.aca.id)
  resource_name_unique = format("%s%s", random_pet.aca.id, random_integer.aca.result)
  location             = var.location
}

resource "azurerm_resource_group" "aca" {
  name     = "rg-${local.resource_name}"
  location = local.location

  tags = {
    repo = "git@github.com:Azure-Samples/azure-opensource-labs.git"
  }
}

# // todo: https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/service_principal