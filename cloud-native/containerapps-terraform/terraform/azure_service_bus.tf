resource "azurerm_servicebus_namespace" "aca" {
  name                = "sb-${local.resource_name_unique}"
  location            = local.location
  resource_group_name = local.resource_group_name
  sku                 = "Standard"
}

resource "azurerm_servicebus_queue" "aca" {
  name         = "myqueue"
  namespace_id = azurerm_servicebus_namespace.aca.id
}
