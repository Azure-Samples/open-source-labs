targetScope = 'subscription'


module main '../../cloud-native/aks-bicep/01-aks/main.bicep' = {
  name: 'aks-bicep'
  params: {
    location: 'westus'
  }
}
