@description('Existing public Azure DNS zone.')
param dnsZoneName string

@description('Principal ID of the workload identity.')
param identityPrincipalId string

@description('Resource ID of the workload identity.')
param identityResourceId string

@description('DNS Zone Contributor role definition resource ID.')
param dnsZoneContributorRoleId string

@description('Reader role definition resource ID.')
param readerRoleId string

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: dnsZoneName
}

resource dnsZoneContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dnsZone.id, identityResourceId, dnsZoneContributorRoleId)
  scope: dnsZone
  properties: {
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: dnsZoneContributorRoleId
  }
}

resource dnsResourceGroupReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, identityResourceId, readerRoleId)
  properties: {
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: readerRoleId
  }
}
