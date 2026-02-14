targetScope = 'subscription'


module main '../../cloud-native/aks-webapp-routing/main.bicep' = {
  name: 'aks-webapp-routing'
  params: {
    name: 'testing'
    userObjectId: '00000000-0000-0000-0000-000000000000'
    location: 'westus'
    dnsName: 'testing.com'
  }
}
