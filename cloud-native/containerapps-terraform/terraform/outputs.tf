output "helloworld_ingress_url" {
  value = format("%s%s", "https://", azapi_resource.helloworld.output.properties.configuration.ingress.fqdn)
}

output "servicebus_connection_string" {
  value     = azurerm_servicebus_namespace.aca.default_primary_connection_string
  sensitive = true
}

output "servicebus_receiver_revision_suffix" {
  value = random_string.aca.result
}