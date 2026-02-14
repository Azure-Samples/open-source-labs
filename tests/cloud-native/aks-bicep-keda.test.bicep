targetScope = 'subscription'


module main01 '../../cloud-native/aks-bicep-keda/01-aks/main.bicep' = {
  name: 'aks-01-bicep'
  params: {
    location: 'westus'
  }
}
