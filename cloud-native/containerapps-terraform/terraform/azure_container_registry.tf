resource "azurerm_container_registry" "aca" {
  name                = "aca${local.resource_name_unique}"
  resource_group_name = azurerm_resource_group.aca.name
  location            = azurerm_resource_group.aca.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_user_assigned_identity" "aca" {
  resource_group_name = azurerm_resource_group.aca.name
  location            = azurerm_resource_group.aca.location

  name = "id-${local.resource_name}"
}

resource "azurerm_role_assignment" "aca" {
  scope                = azurerm_container_registry.aca.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.aca.principal_id
}

resource "null_resource" "sender" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "az acr build -t go-servicebus-sender:${random_string.aca.result} -r ${azurerm_container_registry.aca.login_server} --no-wait ../go-servicebus-sender"
  }
}

resource "null_resource" "receiver" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "az acr build -t go-servicebus-receiver:${random_string.aca.result} -r ${azurerm_container_registry.aca.login_server} --no-wait ../go-servicebus-receiver"
  }
}

resource "time_sleep" "wait" {
  triggers = {
    always_run = "${timestamp()}"
  }

  create_duration = "60s"

  depends_on = [
    null_resource.receiver,
    null_resource.sender
  ]
}