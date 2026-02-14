targetScope = 'subscription'


module main '../../cloud-native/aks-arm64/main.bicep' = {
  name: 'aks-arm64'
  params: {
    name: 'test-aks-arm64'
    location: 'westus'
  }
}
