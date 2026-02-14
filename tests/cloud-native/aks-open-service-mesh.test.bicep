targetScope = 'subscription'


module main '../../cloud-native/aks-open-service-mesh/main.bicep' = {
  name: 'aks-open-service-mesh'
  params: {
    name: 'testing'
    userObjectId: '00000000-0000-0000-0000-000000000000'
    location: 'westus'
  }
}
