targetScope = 'resourceGroup'


module main '../../cloud-native/aks-bicep-k8s/main.bicep' = {
  name: 'aks-bicep'
  params: {
    location: 'westus'
  }
}
