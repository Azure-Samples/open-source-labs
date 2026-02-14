targetScope = 'resourceGroup'


module main '../../cloud-native/aks-azure-linux/aks.bicep' = {
  name: 'aks-azure-linux'
  params: {
    location: 'westus'
  }
}
