@description('Azure region for the AKS cluster.')
param location string = resourceGroup().location

@description('Name of the AKS cluster.')
param clusterName string = 'aks-https-routing'

@description('VM size for the single-node learning cluster.')
param vmSize string = 'Standard_D2s_v5'

@description('Public application hostname. Leave empty to use the self-signed fallback.')
param domainName string = ''

@description('Existing public Azure DNS zone. Leave empty to use the self-signed fallback.')
param dnsZoneName string = ''

@description('Resource group containing the existing public Azure DNS zone.')
param dnsZoneResourceGroup string = resourceGroup().name

@description('Optional email address for the Let\'s Encrypt ACME account.')
param acmeEmail string = ''

var useLetsEncrypt = domainName != '' && dnsZoneName != ''
var suffix = substring(uniqueString(resourceGroup().id), 0, 6)
var dnsIdentityName = 'cert-manager-dns-${suffix}'
var dnsZoneContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'befefa01-2a29-4197-83a8-272ff33ce314'
)
var readerRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'acdd72a7-3385-48ef-bd42-f606fba81ae7'
)

resource cluster 'Microsoft.ContainerService/managedClusters@2026-01-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  properties: {
    dnsPrefix: '${clusterName}-${suffix}'
    enableRBAC: true
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: 1
        vmSize: vmSize
        mode: 'System'
        osType: 'Linux'
        osSKU: 'AzureLinux3'
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'azure'
      loadBalancerSku: 'standard'
    }
  }
}

resource dnsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: dnsIdentityName
  location: location
}

resource certManagerFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: dnsIdentity
  name: 'cert-manager'
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: cluster.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:cert-manager:cert-manager'
  }
}

resource externalDnsFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = if (useLetsEncrypt) {
  parent: dnsIdentity
  name: 'external-dns'
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: cluster.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:external-dns:external-dns'
  }
}

module dnsRbac './dns-rbac.bicep' = if (useLetsEncrypt) {
  name: 'dns-rbac'
  scope: resourceGroup(dnsZoneResourceGroup)
  params: {
    dnsZoneContributorRoleId: dnsZoneContributorRoleId
    dnsZoneName: dnsZoneName
    identityPrincipalId: dnsIdentity.properties.principalId
    identityResourceId: dnsIdentity.id
    readerRoleId: readerRoleId
  }
}

output clusterName string = cluster.name
output domainName string = useLetsEncrypt ? domainName : 'aks-https.local'
output dnsZoneName string = dnsZoneName
output dnsZoneResourceGroup string = dnsZoneResourceGroup
output subscriptionId string = subscription().subscriptionId
output tenantId string = tenant().tenantId
output dnsIdentityClientId string = dnsIdentity.properties.clientId
output acmeEmail string = acmeEmail
output certificateMode string = useLetsEncrypt ? 'letsencrypt' : 'selfsigned'
