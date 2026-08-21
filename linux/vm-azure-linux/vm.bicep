@description('The name of the Virtual Machine.')
param vmName string = 'vm1'

@description('The Azure Linux 4 image architecture.')
@allowed([
  'Azure Linux 4'
  'Azure Linux 4 (arm64)'
])
param osImage string = 'Azure Linux 4'

@description('The Virtual Machine size for the x64 image. The Arm64 image automatically uses Standard_D2ps_v6.')
@allowed([
  'Standard_D2s_v6'
])
param vmSize string = 'Standard_D2s_v6'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The source IP address or CIDR allowed to connect over SSH.')
param allowIpPort22 string = '127.0.0.1'

@description('Username for the Virtual Machine.')
param adminUsername string = 'azureuser'

@secure()
@description('SSH public key for the Virtual Machine.')
param sshKey string

var imageReferences = {
  'Azure Linux 4': {
    publisher: 'microsoftazurelinux'
    offer: 'azurelinux-4'
    sku: '4'
    version: 'latest'
  }
  'Azure Linux 4 (arm64)': {
    publisher: 'microsoftazurelinux'
    offer: 'azurelinux-4'
    sku: '4-arm64'
    version: 'latest'
  }
}
var resolvedVmSize = osImage == 'Azure Linux 4 (arm64)' ? 'Standard_D2ps_v6' : vmSize
var publicIPAddressName = '${vmName}-ip'
var networkInterfaceName = '${vmName}-nic'
var virtualNetworkName = '${vmName}-vnet'
var networkSecurityGroupName = '${vmName}-nsg'
var subnetName = 'default'

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2026-01-01' = {
  name: networkSecurityGroupName
  location: location
  properties: {
    securityRules: [
      {
        name: 'SSH'
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
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2026-01-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.1.0.0/24'
        }
      }
    ]
  }
}

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2026-01-01' = {
  name: publicIPAddressName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: toLower('${vmName}-${uniqueString(resourceGroup().id)}')
    }
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2026-01-01' = {
  name: networkInterfaceName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddress.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2026-04-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: resolvedVmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
      imageReference: imageReferences[osImage]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshKey
            }
          ]
        }
      }
    }
  }
}

output adminUsername string = adminUsername
output hostname string = publicIPAddress.properties.dnsSettings.fqdn
output sshCommand string = 'ssh ${adminUsername}@${publicIPAddress.properties.dnsSettings.fqdn}'
