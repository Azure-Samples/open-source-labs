module managedCluster 'br/public:avm/res/container-service/managed-cluster:0.14.0' = {
  name: 'managedClusterDeployment'
  params: {
    // Required parameters
    name: 'aks-avm'
    primaryAgentPoolProfiles: [
      {
        count: 1
        mode: 'System'
        name: 'systempool'
        vmSize: 'Standard_D2s_v5'
        osSKU: 'AzureLinux3'
      }
    ]
    // Non-required parameters
    aadProfile: {
      enableAzureRBAC: true
      managed: true
    }
    managedIdentities: {
      systemAssigned: true
    }
  }
}
