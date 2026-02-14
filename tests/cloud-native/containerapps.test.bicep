targetScope = 'subscription'


module main '../../cloud-native/containerapps-bicep/main.bicep' = {
  name: 'containerapps-bicep'
  params: {
    location: 'westus'
  }
}
