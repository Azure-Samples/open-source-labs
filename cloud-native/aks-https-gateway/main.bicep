@description('Azure region for the AKS cluster.')
param location string = resourceGroup().location

@description('Name of the AKS cluster.')
param clusterName string = 'aks-https-routing'

@description('VM size for the single-node learning cluster.')
param vmSize string = 'Standard_D2s_v5'

@description('Public application hostname. Set without dnsZoneName to use manual HTTP-01, or leave empty to use an Azure-provided DNS label.')
param domainName string = ''

@description('Existing public Azure DNS zone. Leave empty to use HTTP-01 when domainName is set.')
param dnsZoneName string = ''

@description('Optional Azure-managed public IP DNS label override. Leave empty to derive a stable unique label.')
param dnsLabel string = ''

@description('Use a self-signed certificate instead of the default Azure DNS-label and Let\'s Encrypt path.')
param selfSigned bool = false

@description('Resource group containing the existing public Azure DNS zone.')
param dnsZoneResourceGroup string = resourceGroup().name

@description('Optional email address for the Let\'s Encrypt ACME account.')
param acmeEmail string = ''

var useLetsEncrypt = domainName != '' && dnsZoneName != ''
var useSelfSigned = domainName == '' && selfSigned
var useAzureDnsLabel = domainName == '' && !useSelfSigned
var useHttp01 = (domainName != '' && dnsZoneName == '') || useAzureDnsLabel
var suffix = substring(uniqueString(resourceGroup().id), 0, 6)
var generatedDnsLabel = 'aks-https-${uniqueString(resourceGroup().id, clusterName, toLower(location))}'
var effectiveDnsLabel = dnsLabel != '' ? dnsLabel : generatedDnsLabel
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

resource dnsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = if (useLetsEncrypt) {
  name: dnsIdentityName
  location: location
}

resource certManagerFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = if (useLetsEncrypt) {
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
    identityPrincipalId: dnsIdentity!.properties.principalId
    identityResourceId: dnsIdentity.id
    readerRoleId: readerRoleId
  }
}

output clusterName string = cluster.name
output domainName string = domainName != ''
  ? domainName
  : (useAzureDnsLabel ? '${effectiveDnsLabel}.${toLower(location)}.cloudapp.azure.com' : 'aks-https.local')
output dnsZoneName string = dnsZoneName
output dnsLabel string = useAzureDnsLabel ? effectiveDnsLabel : ''
output clusterLocation string = toLower(location)
output dnsZoneResourceGroup string = dnsZoneResourceGroup
output subscriptionId string = subscription().subscriptionId
output tenantId string = tenant().tenantId
output dnsIdentityClientId string = useLetsEncrypt ? dnsIdentity!.properties.clientId : ''
output acmeEmail string = acmeEmail
output certificateMode string = useLetsEncrypt
  ? 'letsencrypt'
  : (useAzureDnsLabel ? 'letsencrypt-azure-http01' : (useHttp01 ? 'letsencrypt-http01' : 'selfsigned'))
