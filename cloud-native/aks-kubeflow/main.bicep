param location string = resourceGroup().location
param clusterName string = 'aks-kubeflow'
param kubernetesVersion string
param nodeCount int = 2
param vmSize string = 'Standard_D4s_v6'
param osSKU string = 'AzureLinux'

resource cluster 'Microsoft.ContainerService/managedClusters@2026-05-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  properties: {
    dnsPrefix: toLower('${clusterName}-${uniqueString(resourceGroup().id)}')
    enableRBAC: true
    kubernetesVersion: kubernetesVersion
    autoUpgradeProfile: {
      upgradeChannel: 'none'
      nodeOSUpgradeChannel: 'NodeImage'
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: nodeCount
        vmSize: vmSize
        mode: 'System'
        osType: 'Linux'
        osSKU: osSKU
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'azure'
      loadBalancerSku: 'standard'
    }
  }
}

var dnsLabel = 'kubeflow-${uniqueString(resourceGroup().id, clusterName, toLower(location))}'

output clusterName string = cluster.name
output kubernetesVersion string = cluster.properties.kubernetesVersion
output location string = cluster.location
output dnsLabel string = dnsLabel
output kubeflowHostname string = '${dnsLabel}.${toLower(location)}.cloudapp.azure.com'
