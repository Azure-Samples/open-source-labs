resource "azurerm_log_analytics_workspace" "aca" {
  name                = "law-${local.resource_name_unique}"
  resource_group_name = azurerm_resource_group.aca.name
  location            = azurerm_resource_group.aca.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# https://registry.terraform.io/providers/Azure/azapi/latest/docs
# https://learn.microsoft.com/azure/templates/microsoft.app/2022-03-01/managedenvironments?tabs=bicep&pivots=deployment-language-terraform
resource "azapi_resource" "env" {
  type      = "Microsoft.App/managedEnvironments@2022-03-01"
  name      = "env-${local.resource_name}"
  parent_id = azurerm_resource_group.aca.id
  location  = azurerm_resource_group.aca.location

  body = jsonencode({
    properties = {
      appLogsConfiguration = {
        destination = "log-analytics"
        logAnalyticsConfiguration = {
          customerId = azurerm_log_analytics_workspace.aca.workspace_id
          sharedKey  = azurerm_log_analytics_workspace.aca.primary_shared_key
        }
      }
      # if you want to use a custom VNET, set the vnetConfiguration property
      vnetConfiguration = var.environment_virtual_network.use_custom_vnet ? {
        infrastructureSubnetId = element(azurerm_virtual_network.aca[0].subnet.*.id, index(azurerm_virtual_network.aca[0].subnet.*.name, "Environment"))
        internal               = var.environment_virtual_network.is_internal
      } : null
    }
  })
}

# https://learn.microsoft.com/azure/templates/microsoft.app/2022-03-01/containerapps?tabs=bicep&pivots=deployment-language-terraform
resource "azapi_resource" "helloworld" {
  type      = "Microsoft.App/containerApps@2022-03-01"
  name      = "helloworld"
  parent_id = azurerm_resource_group.aca.id
  location  = azurerm_resource_group.aca.location

  body = jsonencode({
    properties = {
      managedEnvironmentId = azapi_resource.env.id
      configuration = {
        ingress = {
          allowInsecure = false
          external      = true
          targetPort    = 80
          traffic = [
            {
              label          = "dev"
              latestRevision = true
              weight         = 100
            }
          ]
        }
      }
      template = {
        containers = [
          {
            name  = "helloworld"
            image = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
            resources = {
              cpu    = 0.5
              memory = "1.0Gi"
            }
          }
        ]
        revisionSuffix = random_string.aca.result
        scale = {
          minReplicas = 0
          maxReplicas = 30
          rules = [
            {
              name = "http-rule"
              http = {
                metadata = {
                  concurrentRequests = "100"
                }
              }
            }
          ]
        }
      }
    }
  })

  # this tells azapi to pull out properties and stuff into the output attribute for the object
  response_export_values = ["properties.configuration.ingress.fqdn"]
}

resource "azapi_resource" "sender" {
  type      = "Microsoft.App/containerApps@2022-03-01"
  name      = "go-servicebus-sender"
  parent_id = azurerm_resource_group.aca.id
  location  = azurerm_resource_group.aca.location
  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.aca.id
    ]
  }

  body = jsonencode({
    properties = {
      managedEnvironmentId = azapi_resource.env.id
      configuration = {
        registries = [
          {
            identity = azurerm_user_assigned_identity.aca.id
            server   = azurerm_container_registry.aca.login_server
          }
        ]
        secrets = [
          {
            name  = "azure-servicebus-connection-string"
            value = azurerm_servicebus_namespace.aca.default_primary_connection_string
          }
        ]
      }
      template = {
        containers = [
          {
            name  = "go-servicebus-sender"
            image = "${azurerm_container_registry.aca.login_server}/go-servicebus-sender:${random_string.aca.result}"
            resources = {
              cpu    = 0.5
              memory = "1.0Gi"
            }
            env = [
              {
                name  = "AZURE_SERVICEBUS_QUEUE_NAME"
                value = azurerm_servicebus_queue.aca.name
              },
              {
                name      = "AZURE_SERVICEBUS_CONNECTION_STRING"
                secretRef = "azure-servicebus-connection-string"
              },
              {
                name  = "BATCH_SIZE"
                value = "1"
              }
            ]
          }
        ]
        revisionSuffix = random_string.aca.result
        scale = {
          minReplicas = 1
          maxReplicas = 1
        }
      }
    }
  })

  depends_on = [
    azurerm_role_assignment.aca,
    time_sleep.wait
  ]
}

resource "azapi_resource" "receiver" {
  type      = "Microsoft.App/containerApps@2022-03-01"
  name      = "go-servicebus-receiver"
  parent_id = azurerm_resource_group.aca.id
  location  = azurerm_resource_group.aca.location
  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.aca.id
    ]
  }

  body = jsonencode({
    properties = {
      managedEnvironmentId = azapi_resource.env.id
      configuration = {
        registries = [
          {
            identity = azurerm_user_assigned_identity.aca.id
            server   = azurerm_container_registry.aca.login_server
          }
        ]
        secrets = [
          {
            name  = "azure-servicebus-connection-string"
            value = azurerm_servicebus_namespace.aca.default_primary_connection_string
          }
        ]
      }
      template = {
        containers = [
          {
            name  = "go-servicebus-receiver"
            image = "${azurerm_container_registry.aca.login_server}/go-servicebus-receiver:${random_string.aca.result}"
            resources = {
              cpu    = 0.5
              memory = "1.0Gi"
            }
            env = [
              {
                name  = "AZURE_SERVICEBUS_QUEUE_NAME"
                value = azurerm_servicebus_queue.aca.name
              },
              {
                name      = "AZURE_SERVICEBUS_CONNECTION_STRING"
                secretRef = "azure-servicebus-connection-string"
              },
              {
                name  = "BATCH_SIZE"
                value = "1"
              }
            ]
          }
        ]
        revisionSuffix = random_string.aca.result
        scale = {
          minReplicas = 0
          maxReplicas = 30
          rules = [
            {
              name = "servicebus-rule"
              custom = {
                type = "azure-servicebus"
                metadata = {
                  queueName    = azurerm_servicebus_queue.aca.name
                  namespace    = azurerm_servicebus_namespace.aca.name
                  messageCount = "5"
                }
                auth = [
                  {
                    secretRef        = "azure-servicebus-connection-string"
                    triggerParameter = "connection"
                  }
                ]
              }
            }
          ]
        }
      }
    }
  })

  depends_on = [
    azurerm_role_assignment.aca,
    time_sleep.wait
  ]
}