@description('Location for the AKS cluster.')
param location string = resourceGroup().location

@description('Name of the AKS cluster.')
param clusterName string = 'aks-azure-container-linux'

@description('Generation 2 node size. Use Standard_D2pds_v6 for Arm64.')
@allowed([
  'Standard_D2s_v5'
  'Standard_D2pds_v6'
])
param vmSize string = 'Standard_D2s_v5'

resource aks 'Microsoft.ContainerService/managedClusters@2026-04-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: toLower('${clusterName}-${uniqueString(resourceGroup().id)}')
    enableRBAC: true
    kubernetesVersion: '1.34'
    autoUpgradeProfile: {
      nodeOSUpgradeChannel: 'NodeImage'
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: 1
        vmSize: vmSize
        mode: 'System'
        osType: 'Linux'
        osSKU: 'AzureContainerLinux'
        securityProfile: {
          enableSecureBoot: true
          enableVTPM: true
        }
      }
    ]
  }
}

output clusterName string = aks.name
output kubernetesVersion string = aks.properties.kubernetesVersion
output nodeOSSKU string = 'AzureContainerLinux'
output nodeVMSize string = vmSize
