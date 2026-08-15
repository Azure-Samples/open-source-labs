param administratorLogin string = 'username'
@secure()
param administratorLoginPassword string = newGuid()
param firewallRuleIp string = '127.0.0.1'
param storageSizeGb int = 256
param location string = resourceGroup().location

var rand = substring(uniqueString(resourceGroup().id), 0, 6)
var postgresName = 'postgres-${rand}'

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: '${resourceGroup().name}-identity'
  location: location
}

resource keyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: 'keyvault${rand}'
  location: location
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    tenantId: subscription().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    accessPolicies: [
      {
        objectId: managedIdentity.properties.principalId
        permissions: {
          secrets: [
            'all'
          ]
        }
        tenantId: subscription().tenantId
      }
    ]
  }
}

var secretName = 'postgres-${rand}-password'
var secretValue = administratorLoginPassword

resource keyVaultSecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: keyVault
  name: secretName
  properties: {
    value: secretValue
  }
}

module postgres './postgres.bicep' = {
  name: postgresName
  params: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    firewallRuleIp: firewallRuleIp
    storageSizeGb: storageSizeGb
    location: location
  }
}

output postgresName string = postgresName
output postgresUrl string = 'postgres://${administratorLogin}:$PGPASSWORD@${postgresName}.postgres.database.azure.com/postgres?sslmode=require'
