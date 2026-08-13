@description('The name of your Virtual Machine.')
param vmName string = 'vm1'

@description('The Virtual Machine size.')
@allowed([
  'Standard_B2ts_v2'
  'Standard_B2ls_v2'
  'Standard_B2s_v2'
  'Standard_B4ls_v2'
  'Standard_B4s_v2'
  'Standard_D2s_v5'
  'Standard_D4s_v5'
  'Standard_D2ps_v5'
  'Standard_D4ps_v5'
])
param vmSize string = 'Standard_B2s_v2'

@description('Custom VM size (overrides vmSize if set).')
param vmSizeCustom string = ''

@description('The Storage Account Type for OS and Data disks.')
@allowed([
  'Standard_LRS'
  'Premium_LRS'
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
param osDiskSize int = 64

@description('The OS image for the VM.')
@allowed([
  'Ubuntu 26.04-LTS'
  'Ubuntu 26.04-LTS (arm64)'
])
param osImage string = 'Ubuntu 26.04-LTS'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Username for the Virtual Machine.')
param adminUsername string = 'azureuser'

@secure()
@description('SSH Key for the Virtual Machine.')
param adminPasswordOrKey string = ''

@description('Deploy with Tailscale SSH.')
@allowed([
  'none'
  'tailscale'
])
param cloudInit string = 'none'

@description('Environment variables as JSON object (e.g. {"tskey":"tskey-auth-..."}).')
@secure()
param env object = {}

var rand = substring(uniqueString(resourceGroup().id), 0, 6)
var vnetName = '${resourceGroup().name}-vnet'
var subnetName = 'default'
var keyData_var = adminPasswordOrKey != '' ? adminPasswordOrKey : 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3gkRpKwprN00sT7yekr0xO0F+uTllDua02puhu1v0zGu3aENvUsygBHJiTy+flgrO2q3mY9F5/D67+WHDeSpr5s71UtnbzMxTams89qmo+raTm+IqjzdNujaWf0/pbT6JUkQq0fR0BfIvg3/7NTXhlzjmCOP2EpD91LzN6b5jAm/5hXr0V5mcpERo8kk2GWxjKmwmDOV+huH1DIFDpMxT3WzR2qvZp1DZbNSYmKkrite3FHlPGLXA1I3bRQT+iTj8vRGpxOPSiMdPK4RNMEZVXSGQ3OZbSl2FBCbd/tdJ1idKo8/ZCkHxdh9/em28/yfPUK0D164shgiEdIkdOQJv'
var publicIPAddressName = '${vmName}-ip'
var networkInterfaceName = '${vmName}-nic'
var ipConfigName = '${vmName}-ipconfig'
var subnetAddressPrefix = '10.1.0.0/24'
var addressPrefix = '10.1.0.0/16'


var cloudInitTailscale = '''
#cloud-config
# vim: syntax=yaml

packages:
- jq
- curl

write_files:
- path: /home/azureuser/env.json
  content: __ENV_B64__
  encoding: b64
- path: /usr/local/bin/tailscale-authurl
  permissions: '0755'
  content: |
    #!/usr/bin/env bash
    # Print this node's Tailscale interactive login URL.
    # Pass --refresh to discard an expired URL and mint a fresh one.
    set -eo pipefail

    if [ "$#" -gt 0 ] && [ "$1" = "--refresh" ]; then
        tailscale logout >/dev/null 2>&1 || true
        setsid tailscale up --ssh --timeout=1s >/dev/null 2>&1 || true
    fi

    for i in $(seq 1 30); do
        url=$(tailscale status --json 2>/dev/null | jq -r '.AuthURL // empty')
        if [ -n "$url" ]; then
            echo "$url"
            exit 0
        fi
        state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // empty')
        if [ "$state" = "Running" ]; then
            echo "already onboarded; re-run with --refresh to re-authenticate" >&2
            exit 0
        fi
        sleep 2
    done

    echo "no auth URL available" >&2
    exit 1
- path: /home/azureuser/tailscale.sh
  content: |
    #!/usr/bin/env bash
    # Install Tailscale, then either join with an auth key or publish a login URL.
    set -eo pipefail

    curl -fsSL https://tailscale.com/install.sh | sh

    key="$1"
    if [ -n "$key" ] && [ "$key" != "null" ]; then
        tailscale up --ssh --authkey "$key"
        # Console writes are best-effort: never fail the boot over logging.
        echo "tailscale: joined tailnet with auth key" >/dev/console 2>/dev/null || true
        exit 0
    fi

    # No auth key. 'tailscale up' blocks until the node is authorized, so run it
    # detached and poll the daemon for the login URL it generates.
    setsid tailscale up --ssh >/var/log/tailscale-up.log 2>&1 &

    url=""
    for i in $(seq 1 60); do
        url=$(tailscale status --json 2>/dev/null | jq -r '.AuthURL // empty')
        if [ -n "$url" ]; then
            break
        fi
        sleep 2
    done

    if [ -z "$url" ]; then
        echo "tailscale: FAILED to obtain a login URL" >/dev/console 2>/dev/null || true
        echo "tailscale: FAILED to obtain a login URL" >&2
        exit 1
    fi

    echo "$url" >/var/lib/tailscale-authurl.txt
    chmod 0644 /var/lib/tailscale-authurl.txt

    # Publish to the serial console so it reaches Azure boot diagnostics.
    # Best-effort: the file above is the authoritative copy.
    printf '\n===== TAILSCALE LOGIN URL =====\n%s\n===============================\n\n' \
        "$url" >/dev/console 2>/dev/null || true

runcmd:
- cd /home/azureuser/
- bash tailscale.sh "$(jq -r '.tskey' env.json)"
- echo $(date) > hello.txt
- chown -R azureuser:azureuser /home/azureuser/
'''

var cloudInitTailscaleFormat = replace(cloudInitTailscale, '__ENV_B64__', base64(string(env)))

var kvCloudInit = {
  none: null
  tailscale: base64(cloudInitTailscaleFormat)
}

var kvImageReference = {
  'Ubuntu 26.04-LTS': {
    publisher: 'canonical'
    offer: 'ubuntu-26_04-lts'
    sku: 'server'
    version: 'latest'
  }
  'Ubuntu 26.04-LTS (arm64)': {
    publisher: 'canonical'
    offer: 'ubuntu-26_04-lts'
    sku: 'server-arm64'
    version: 'latest'
  }
}

// Only Tailscale UDP port — SSH access is via Tailscale, not public internet
var nsgSecurityRules = [
  {
    name: 'Port_41641'
    properties: {
      protocol: 'Udp'
      sourcePortRange: '*'
      destinationPortRange: '41641'
      sourceAddressPrefix: 'Internet'
      destinationAddressPrefix: '*'
      access: 'Allow'
      priority: 100
      direction: 'Inbound'
    }
  }
]

resource identityName 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${resourceGroup().name}-identity'
  location: location
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${resourceGroup().name}-nsg'
  location: location
  properties: {
    securityRules: nsgSecurityRules
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
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
        }
      }
    ]
  }
}

resource publicIP 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
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

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: networkInterfaceName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: ipConfigName
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: { id: publicIP.id }
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
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
      vmSize: vmSizeCustom != '' ? vmSizeCustom : vmSize
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
    // Managed boot diagnostics: lets the keyless flow surface the Tailscale
    // login URL via 'az vm boot-diagnostics get-boot-log'.
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
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
output hostname string = publicIP.properties.dnsSettings.fqdn
output sshCommand string = 'ssh ${adminUsername}@${publicIP.properties.dnsSettings.fqdn}'

@description('Fetch the Tailscale login URL when deployed without an auth key.')
output authUrlCommand string = 'az vm run-command invoke --resource-group ${resourceGroup().name} --name ${vmName} --command-id RunShellScript --scripts "tailscale-authurl" --query "value[0].message" -o tsv'

@description('Same URL via the serial console, no in-VM agent required.')
output authUrlBootLogCommand string = 'az vm boot-diagnostics get-boot-log --resource-group ${resourceGroup().name} --name ${vmName} -o tsv | grep -o "https://login.tailscale.com/a/[a-z0-9]*" | tail -1'
