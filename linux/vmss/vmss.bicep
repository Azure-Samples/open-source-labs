@description('The name of your Virtual Machine.')
param vmssName string = 'vmss1'

@description('The Virtual Machine size.')
@allowed([
  'Standard_D2s_v6'
])
param vmSize string = 'Standard_D2s_v6'

@description('The Storage Account Type for OS and Data disks.')
@allowed([
  'Standard_LRS'
  'Premium_LRS'
  'UltraSSD_LRS'
])
param diskAccountType string = 'Premium_LRS'

@description('The OS Disk size.')
@allowed([
  1024
  512
  256
  128
  64
  32
])
param osDiskSize int = 256

@description('The OS image for the VM.')
@allowed([
  'Ubuntu 26.04-LTS'
  'Ubuntu 26.04-LTS (arm64)'
  'Ubuntu 24.04-LTS'
  'Azure Linux 4'
  'Azure Linux 4 (arm64)'
])
param osImage string = 'Azure Linux 4'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Name of the VNET.')
param virtualNetworkName string = ''

@description('Default IP to allow Port 22 (SSH). Set to your own IP Address')
param allowIpPort22 string = '127.0.0.1'

@description('Username for the Virtual Machine.')
param adminUsername string = 'azureuser'

@secure()
@description('SSH Key for the Virtual Machine.')
param sshKey string = ''

@description('Deploy with cloud-init.')
@allowed([
  'cloud-init'
  'none'
])
param customData string = 'none'

@description('Environment variables as JSON object.')
@secure()
param env object = {}

// vmss specific
@description('Number of VM instances (1000 or less).')
@maxValue(1000)
param instanceCount int = 1

@description('Tier')
@allowed([
  'Standard'
  'Basic'
])
param vmssTier string = 'Standard'

@description('Priority')
@allowed([
  'Regular'
  'Low'
  'Spot'
])
param vmssPriority string = 'Regular'

@description('Eviction Policy')
@allowed([
  'Deallocate'
  'Delete'
])
param vmssEvictionPolicy string = 'Deallocate'

var rand = substring(uniqueString(resourceGroup().id), 0, 6)
var keyData = sshKey != '' ? sshKey : 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3gkRpKwprN00sT7yekr0xO0F+uTllDua02puhu1v0zGu3aENvUsygBHJiTy+flgrO2q3mY9F5/D67+WHDeSpr5s71UtnbzMxTams89qmo+raTm+IqjzdNujaWf0/pbT6JUkQq0fR0BfIvg3/7NTXhlzjmCOP2EpD91LzN6b5jAm/5hXr0V5mcpERo8kk2GWxjKmwmDOV+huH1DIFDpMxT3WzR2qvZp1DZbNSYmKkrite3FHlPGLXA1I3bRQT+iTj8vRGpxOPSiMdPK4RNMEZVXSGQ3OZbSl2FBCbd/tdJ1idKo8/ZCkHxdh9/em28/yfPUK0D164shgiEdIkdOQJv'
var resourceGroupName = resourceGroup().name
var bePoolName = '${vmssName}-bepool'
var frontEndIPConfigID = resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations', loadBalancerName, 'LoadBalancerFrontEnd')
var ipConfigName = '${vmssName}-ipconfig'
var loadBalancerName = '${vmssName}-lb'
var natRuleName = '${vmssName}-natrule'
var natBackendPort = 22
var natStartPort = 50000
var natEndPort = 50119
var nicName = '${vmssName}-nic'
var publicIPAddressName = '${vmssName}-ip'
var publicIPAddressType = 'Static'
var subnetName = 'default'
var addressPrefix = '10.1.0.0/16'
var subnetAddressPrefix = '10.1.0.0/24'
var vnetName = virtualNetworkName != '' ? virtualNetworkName : '${resourceGroupName}-vnet'
var nsgName = '${resourceGroupName}-nsg'

var customDataCloudInit = format(loadTextContent('cloud-init/cloud-init.yaml'), adminUsername, base64(string(env)))

var kvCustomData = {
  none: null
  'cloud-init': base64(customDataCloudInit)
}

var kvImages = {
  'Ubuntu 26.04-LTS': {
    architecture: 'x64'
    reference: {
      publisher: 'Canonical'
      offer: 'ubuntu-26_04-lts'
      sku: 'server'
      version: 'latest'
    }
  }
  'Ubuntu 26.04-LTS (arm64)': {
    architecture: 'arm64'
    reference: {
      publisher: 'Canonical'
      offer: 'ubuntu-26_04-lts'
      sku: 'server-arm64'
      version: 'latest'
    }
  }
  'Ubuntu 24.04-LTS': {
    architecture: 'x64'
    reference: {
      publisher: 'Canonical'
      offer: 'ubuntu-24_04-lts'
      sku: 'server'
      version: 'latest'
    }
  }
  'Azure Linux 4': {
    architecture: 'x64'
    reference: {
      publisher: 'microsoftazurelinux'
      offer: 'azurelinux-4'
      sku: '4'
      version: 'latest'
    }
  }
  'Azure Linux 4 (arm64)': {
    architecture: 'arm64'
    reference: {
      publisher: 'microsoftazurelinux'
      offer: 'azurelinux-4'
      sku: '4-arm64'
      version: 'latest'
    }
  }
}

var vmSizeByArchitecture = {
  x64: vmSize
  arm64: 'Standard_D2ps_v6'
}
var selectedImage = kvImages[osImage]
var resolvedVmSize = vmSizeByArchitecture[selectedImage.architecture]

// Base network security group rules
var nsgSecurityRulesBase = [
  {
    name: 'Port_22'
    properties: {
      priority: 100
      protocol: 'Tcp'
      access: 'Allow'
      direction: 'Inbound'
      sourceAddressPrefix: allowIpPort22
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '22'
    }
  }
  {
    name: 'Port_80'
    properties: {
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '80'
      sourceAddressPrefix: 'Internet'
      destinationAddressPrefix: '*'
      access: 'Allow'
      priority: 110
      direction: 'Inbound'
    }
  }
  {
    name: 'Port_443'
    properties: {
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '443'
      sourceAddressPrefix: 'Internet'
      destinationAddressPrefix: '*'
      access: 'Allow'
      priority: 120
      direction: 'Inbound'
    }
  }
  {
    name: 'Port_8080'
    properties: {
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '8080'
      sourceAddressPrefix: 'Internet'
      destinationAddressPrefix: '*'
      access: 'Allow'
      priority: 130
      direction: 'Inbound'
    }
  }
  {
    name: 'Port_41641'
    properties: {
      protocol: 'Udp'
      sourcePortRange: '*'
      destinationPortRange: '41641'
      sourceAddressPrefix: 'Internet'
      destinationAddressPrefix: '*'
      access: 'Allow'
      priority: 140
      direction: 'Inbound'
    }
  }
]

var nsgSecurityRules = nsgSecurityRulesBase

resource identityName 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: '${resourceGroup().name}-identity'
  location: location
}

resource publicIP 'Microsoft.Network/publicIPAddresses@2026-01-01' = {
  name: publicIPAddressName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: publicIPAddressType
    dnsSettings: {
      domainNameLabel: toLower('${vmssName}-${rand}')
    }
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2026-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.1.1.0/26'
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2026-01-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: nsgSecurityRules
  }
}

resource loadBalancer 'Microsoft.Network/loadBalancers@2026-01-01' = {
  name: loadBalancerName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'LoadBalancerFrontEnd'
        properties: {
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: bePoolName
      }
    ]
    loadBalancingRules: [
      {
        name: 'Rule_80'
        properties: {
          loadDistribution: 'Default'
          frontendIPConfiguration: {
            id: frontEndIPConfigID
          }
          backendAddressPool: {
            #disable-next-line use-resource-id-functions
            id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Network/loadBalancers/${loadBalancerName}/backendAddressPools/${bePoolName}'
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 5
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'Probe_80')
          }
        }
      }
      {
        name: 'Rule_443'
        properties: {
          loadDistribution: 'Default'
          frontendIPConfiguration: {
            id: frontEndIPConfigID
          }
          backendAddressPool: {
            #disable-next-line use-resource-id-functions
            id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Network/loadBalancers/${loadBalancerName}/backendAddressPools/${bePoolName}'
          }
          protocol: 'Tcp'
          frontendPort: 443
          backendPort: 443
          enableFloatingIP: false
          idleTimeoutInMinutes: 5
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'Probe_443')
          }
        }
      }
    ]
    probes: [
      {
        name: 'Probe_80'
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
      {
        name: 'Probe_443'
        properties: {
          protocol: 'Tcp'
          port: 443
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
  }
}

resource inboundNatRule 'Microsoft.Network/loadBalancers/inboundNatRules@2026-01-01' = {
  parent: loadBalancer
  name: natRuleName
  properties: {
    frontendIPConfiguration: {
      id: frontEndIPConfigID
    }
    backendAddressPool: {
      #disable-next-line use-resource-id-functions
      id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Network/loadBalancers/${loadBalancerName}/backendAddressPools/${bePoolName}'
    }
    protocol: 'Tcp'
    frontendPortRangeStart: natStartPort
    frontendPortRangeEnd: natEndPort
    backendPort: natBackendPort
    idleTimeoutInMinutes: 15
    enableTcpReset: true
  }
}

resource vmssName_resource 'Microsoft.Compute/virtualMachineScaleSets@2026-04-01' = {
  name: vmssName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityName.id}': {}
    }
  }
  sku: {
    name: resolvedVmSize
    capacity: instanceCount
    tier: vmssTier
  }
  properties: {
    orchestrationMode: 'Flexible'
    platformFaultDomainCount: 1
    automaticRepairsPolicy: {
      enabled: true
      gracePeriod: 'PT30M'
      repairAction: 'Replace'
    }
    virtualMachineProfile: {
      priority: vmssPriority
      evictionPolicy: ((vmssPriority == 'Regular') ? null : vmssEvictionPolicy)
      storageProfile: {
        osDisk: {
          managedDisk: {
            storageAccountType: diskAccountType
          }
          diskSizeGB: osDiskSize
          createOption: 'FromImage'
          caching: 'ReadWrite'
          deleteOption: 'Delete'
        }
        imageReference: selectedImage.reference
      }
      securityProfile: {
        securityType: 'TrustedLaunch'
        uefiSettings: {
          secureBootEnabled: true
          vTpmEnabled: true
        }
      }
      osProfile: {
        computerNamePrefix: vmssName
        customData: kvCustomData[customData]
        adminUsername: adminUsername
        linuxConfiguration: {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                keyData: keyData
                path: '/home/${adminUsername}/.ssh/authorized_keys'
              }
            ]
          }
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: nicName
            properties: {
              primary: true
              deleteOption: 'Delete'
              ipConfigurations: [
                {
                  name: ipConfigName
                  properties: {
                    subnet: {
                      #disable-next-line use-resource-id-functions
                      id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Network/virtualNetworks/${vnetName}/subnets/${subnetName}'
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        #disable-next-line use-resource-id-functions
                        id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Network/loadBalancers/${loadBalancerName}/backendAddressPools/${bePoolName}'
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
      extensionProfile: {
        extensions: [
          {
            name: 'ApplicationHealthLinux'
            properties: {
              publisher: 'Microsoft.ManagedServices'
              type: 'ApplicationHealthLinux'
              typeHandlerVersion: '2.0'
              autoUpgradeMinorVersion: true
              settings: {
                protocol: 'tcp'
                port: 22
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    loadBalancer
    vnet
  ]
}

output adminUsername string = adminUsername
output fqdn string = publicIP.properties.dnsSettings.fqdn
