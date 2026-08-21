param location string = resourceGroup().location

var rand = substring(uniqueString(resourceGroup().id), 0, 6)

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: '${resourceGroup().name}-identity'
  location: location
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-02-01' = {
  name: 'storage${rand}'
  location: location
  kind: 'BlockBlobStorage'
  sku: {
    name: 'Premium_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
    }
    minimumTlsVersion: 'TLS1_2'
  }
}

var roleDefinitionId = {
  Owner: '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
  Contributor: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
  Reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  AcrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  StorageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  ServiceBusDataOwner: '090c5cfd-751d-490a-894a-3ce6f1109419'
  KubernetesServiceClusterUserRole: '4abbcc35-e782-43d8-92c5-2d3f1bd2253f'
}

var roleAssignmentStorageAccountDefinition = 'StorageBlobDataContributor'
resource roleAssignmentStorageAccount 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, roleAssignmentStorageAccountDefinition)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId[roleAssignmentStorageAccountDefinition])
    principalId: managedIdentity.properties.principalId
  }
}
