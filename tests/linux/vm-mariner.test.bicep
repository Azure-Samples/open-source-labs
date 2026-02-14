targetScope = 'resourceGroup'


module main '../../linux/vm-mariner/vm.bicep' = {
  name: 'vm-mariner'
  params: {
    location: 'westus'
    sshKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD'
  }
}
