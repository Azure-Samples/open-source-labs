param location string = resourceGroup().location
param clusterName string = 'aks1'
param nodeCount int = 1
param vmSize string = 'standard_d2s_v5'
param gpu1VmSize string = 'Standard_NC4as_T4_v3'
param gpu2VmSize string = 'Standard_NC24ads_A100_v4'

// GPU pools are opt-in, because they need quota that a subscription does not
// have by default. Checked on 2026-08-11 in canadacentral: every current GPU
// family — NCASv3_T4, NCADS_A100_v4, NCadsH100v5, NCADSA10v4 — had a vCPU limit
// of 0, and the older NCSv3 family that did have quota is no longer offered to
// AKS in the region at all. With both pools on and no quota, the cluster fails
// to deploy and takes the whole lab with it. Request quota first, then:
//   az deployment group create ... --parameters deployGpuPools=true
param deployGpuPools bool = false

@description('The node OS. This lab is about Azure Linux, so it defaults to Azure Linux 3.')
@allowed([
  'AzureLinux3'
  'AzureLinux'
  'Ubuntu'
])
param osSKU string = 'AzureLinux3'

// No kubernetesVersion is set: AKS picks the current default for the region.
// Pinning it here is what broke this template — '1.29' fell below the oldest
// version canadacentral still offers, so the deployment failed outright rather
// than deploying something old. Pass one explicitly at deploy time if a lab
// step needs a specific version.

var rand = substring(uniqueString(resourceGroup().id), 0, 6)

var systemPool = [
  {
    name: 'nodepool1'
    count: nodeCount
    vmSize: vmSize
    mode: 'System'
    osType: 'Linux'
    osSKU: osSKU
  }
]

var gpuPools = [
  {
    name: 'gpu1'
    count: 1
    vmSize: gpu1VmSize
    mode: 'User'
    osType: 'Linux'
    osSKU: osSKU
    nodeTaints: [
      'sku=gpu:NoSchedule'
    ]
    enableAutoScaling: true
    minCount: 0
    maxCount: 1
  }
  {
    name: 'gpu2'
    count: 1
    vmSize: gpu2VmSize
    mode: 'User'
    osType: 'Linux'
    osSKU: osSKU
    nodeTaints: [
      'sku=gpu:NoSchedule'
    ]
    enableAutoScaling: true
    minCount: 0
    maxCount: 1
  }
]

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: '${resourceGroup().name}-identity'
  location: location
}

resource aks 'Microsoft.ContainerService/managedClusters@2026-05-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    dnsPrefix: clusterName
    enableRBAC: true
    agentPoolProfiles: concat(systemPool, deployGpuPools ? gpuPools : [])
  }
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2019-05-01' = {
  name: 'acr${rand}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: false
  }
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

// via: https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-resource#subscriptionresourceid-example
var roleDefinitionId = {
  Owner: '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
  Contributor: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
  Reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  AcrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  StorageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  KubernetesServiceClusterUserRole: '4abbcc35-e782-43d8-92c5-2d3f1bd2253f'
}

// https://github.com/Azure/bicep/discussions/3181
var roleAssignmentAcrDefinition = 'AcrPull'
resource roleAssignmentAcr 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, roleAssignmentAcrDefinition)
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId[roleAssignmentAcrDefinition])
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
  }
}

var roleAssignmentStorageAccountDefinition = 'StorageBlobDataContributor'
resource roleAssignmentStorageAccount 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, roleAssignmentStorageAccountDefinition)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId[roleAssignmentStorageAccountDefinition])
    principalId: managedIdentity.properties.principalId
  }
  dependsOn: [
    aks
  ]
}
