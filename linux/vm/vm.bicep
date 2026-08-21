@description('The name of your Virtual Machine.')
param vmName string = 'vm1'

@description('The Virtual Machine size.')
@allowed([
  'Standard_B1ls'
  'Standard_B1s'
  'Standard_B2s'
  'Standard_B1ms'
  'Standard_B2ms'
  'Standard_B4ms'
  'Standard_D2s_v5'
  'Standard_D4s_v5'
  'Standard_D2ps_v5'
  'Standard_D4ps_v5'
])
param vmSize string = 'Standard_B2s'

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
])
param osImage string = 'Ubuntu 26.04-LTS'

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
param adminPasswordOrKey string = ''

@description('Deploy with cloud-init.')
@allowed([
  'none'
  'docker'
  'tailscale'
  'tailscale-private'
  'tailscale-postgres'
  'url'
])
param cloudInit string = 'none'

@description('Environment variables as JSON object.')
@secure()
param env object = {}

var rand = substring(uniqueString(resourceGroup().id), 0, 6)
var virtualNetworkName_var = virtualNetworkName != '' ? virtualNetworkName : '${resourceGroup().name}-vnet'
var subnetName = 'default'
var keyData_var = adminPasswordOrKey != '' ? adminPasswordOrKey : 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3gkRpKwprN00sT7yekr0xO0F+uTllDua02puhu1v0zGu3aENvUsygBHJiTy+flgrO2q3mY9F5/D67+WHDeSpr5s71UtnbzMxTams89qmo+raTm+IqjzdNujaWf0/pbT6JUkQq0fR0BfIvg3/7NTXhlzjmCOP2EpD91LzN6b5jAm/5hXr0V5mcpERo8kk2GWxjKmwmDOV+huH1DIFDpMxT3WzR2qvZp1DZbNSYmKkrite3FHlPGLXA1I3bRQT+iTj8vRGpxOPSiMdPK4RNMEZVXSGQ3OZbSl2FBCbd/tdJ1idKo8/ZCkHxdh9/em28/yfPUK0D164shgiEdIkdOQJv'
var publicIPAddressName = '${vmName}-ip'
var networkInterfaceName = '${vmName}-nic'
var ipConfigName = '${vmName}-ipconfig'
var subnetAddressPrefix = '10.1.0.0/24'
var addressPrefix = '10.1.0.0/16'

var cloudInitDocker = '''
#cloud-config
# vim: syntax=yaml

packages:
- docker.io
- jq

# create the docker group
groups:
- docker

# Add default auto created user to docker group
system_info:
  default_user:
    groups: [docker]
'''

var cloudInitTailscale = '''
#cloud-config
# vim: syntax=yaml

packages:
- docker.io
- jq

# create the docker group
groups:
- docker

# Add default auto created user to docker group
system_info:
  default_user:
    groups: [docker]

write_files:
- path: /home/azureuser/env.json
  content: {0}
  encoding: b64
- path: /home/azureuser/tailscale.sh
  content: |
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/focal.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/focal.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
    
    sudo apt-get update
    sudo apt-get install -y tailscale
    
    sudo tailscale up --advertise-routes=10.1.0.0/24,168.63.129.16/32 --accept-dns=false --ssh --authkey "$1"

runcmd:
- cd /home/azureuser/
- bash tailscale.sh "$(jq -r '.tskey' env.json)"
- echo $(date) > hello.txt
- chown -R azureuser:azureuser /home/azureuser/
'''

var cloudInitTailscaleFormat = format(cloudInitTailscale, base64(string(env)))

var cloudInitTailscalePostgres = '''
#cloud-config
# vim: syntax=yaml

packages:
- docker.io
- jq

# create the docker group
groups:
- docker

# Add default auto created user to docker group
system_info:
  default_user:
    groups: [docker]

write_files:
- path: /home/azureuser/env.json
  content: {0}
  encoding: b64
- path: /home/azureuser/tailscale.sh
  content: |
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/focal.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/focal.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
    
    sudo apt-get update
    sudo apt-get install -y tailscale
    
    sudo tailscale up --advertise-routes=10.1.0.0/24,168.63.129.16/32 --accept-dns=false --ssh --authkey "$1"

runcmd:
- cd /home/azureuser/
- bash tailscale.sh "$(jq -r '.tskey' env.json)"
- docker run --name postgres --restart always -e POSTGRES_HOST_AUTH_METHOD=trust -v /home/azureuser/postgresql/data:/var/lib/postgresql/data -p 5432:5432 -d postgres:14
- echo $(date) > hello.txt
- chown -R azureuser:azureuser /home/azureuser/
'''

var cloudInitTailscalePostgresFormat = format(cloudInitTailscalePostgres, base64(string(env)))

var cloudInitUrl = '''
#include
https://raw.githubusercontent.com/Azure-Samples/open-source-labs/main/linux/vm/cloud-init/cloud-init.sh
'''

var kvCloudInit = {
  none: null
  docker: base64(cloudInitDocker)
  tailscale: base64(cloudInitTailscaleFormat)
  'tailscale-private': base64(cloudInitTailscaleFormat)
  'tailscale-postgres': base64(cloudInitTailscalePostgresFormat)
  url: base64(cloudInitUrl)
}

var kvImageReference = {
  'Ubuntu 26.04-LTS': {
    publisher: 'Canonical'
    offer: 'ubuntu-26_04-lts'
    sku: 'server'
    version: 'latest'
  }
  'Ubuntu 24.04-LTS': {
    publisher: 'Canonical'
    offer: 'ubuntu-24_04-lts'
    sku: 'server'
    version: 'latest'
  }
  'Ubuntu 26.04-LTS (arm64)': {
    publisher: 'Canonical'
    offer: 'ubuntu-26_04-lts'
    sku: 'server-arm64'
    version: 'latest'
  }
}

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

// If the cloudInit option is set to 'tailscale-private', then only use the 'Port_41641' rule which is the last rule in the base array
var nsgSecurityRules = (cloudInit == 'tailscale-private' ? [ last(nsgSecurityRulesBase) ] : nsgSecurityRulesBase)

resource identityName 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: '${resourceGroup().name}-identity'
  location: location
}

resource nic 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: networkInterfaceName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: ipConfigName
        properties: {
          subnet: {
            id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Network/virtualNetworks/${virtualNetworkName_var}/subnets/${subnetName}'
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: (cloudInit != 'tailscale-private' ? { id: publicIP.id } : null)
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: '${resourceGroup().name}-nsg'
  location: location
  properties: {
    securityRules: nsgSecurityRules
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = if (virtualNetworkName == '') {
  name: virtualNetworkName_var
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

resource publicIP 'Microsoft.Network/publicIPAddresses@2021-05-01' = if (cloudInit != 'tailscale-private') {
  name: publicIPAddressName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: toLower('${vmName}-${rand}')
    }
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: vmName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityName.id}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        managedDisk: {
          storageAccountType: diskAccountType
        }
        name: '${vmName}-osdisk1'
        diskSizeGB: osDiskSize
        createOption: 'FromImage'
      }
      imageReference: kvImageReference[osImage]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    osProfile: {
      computerName: vmName
      customData: kvCloudInit[cloudInit]
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              keyData: keyData_var
              path: '/home/${adminUsername}/.ssh/authorized_keys'
            }
          ]
        }
      }
    }
  }
}

output adminUsername string = adminUsername
output hostname string = (cloudInit != 'tailscale-private' ? publicIP.properties.dnsSettings.fqdn : vmName)
output sshCommand string = 'ssh ${adminUsername}@${(cloudInit != 'tailscale-private' ? publicIP.properties.dnsSettings.fqdn : vmName)}'
