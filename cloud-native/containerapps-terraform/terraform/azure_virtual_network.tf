resource "azurerm_virtual_network" "aca" {
  count               = var.environment_virtual_network.use_custom_vnet ? 1 : 0
  name                = "vnet-${local.resource_name}"
  address_space       = ["10.0.0.0/16"]
  resource_group_name = azurerm_resource_group.aca.name
  location            = azurerm_resource_group.aca.location

  subnet {
    name             = "Environment"
    address_prefixes = ["10.0.0.0/23"]
  }

  subnet {
    name             = "Sandbox"
    address_prefixes = ["10.0.2.0/23"]
  }
}

resource "azurerm_network_security_group" "env" {
  count               = var.environment_virtual_network.use_custom_vnet ? 1 : 0
  name                = "nsg-${local.resource_name}-environment"
  location            = azurerm_resource_group.aca.location
  resource_group_name = azurerm_resource_group.aca.name
}

resource "azurerm_subnet_network_security_group_association" "env" {
  count                     = var.environment_virtual_network.use_custom_vnet ? 1 : 0
  subnet_id                 = element(azurerm_virtual_network.aca[0].subnet.*.id, index(azurerm_virtual_network.aca[0].subnet.*.name, "Environment"))
  network_security_group_id = azurerm_network_security_group.env[0].id
}

resource "azurerm_network_security_group" "sb" {
  count               = var.environment_virtual_network.use_custom_vnet ? 1 : 0
  name                = "nsg-${local.resource_name}-sandbox"
  location            = azurerm_resource_group.aca.location
  resource_group_name = azurerm_resource_group.aca.name
}

resource "azurerm_subnet_network_security_group_association" "sb" {
  count                     = var.environment_virtual_network.use_custom_vnet ? 1 : 0
  subnet_id                 = element(azurerm_virtual_network.aca[0].subnet.*.id, index(azurerm_virtual_network.aca[0].subnet.*.name, "Sandbox"))
  network_security_group_id = azurerm_network_security_group.sb[0].id
}