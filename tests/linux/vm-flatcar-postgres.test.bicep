targetScope = 'subscription'


module main '../../linux/vm-flatcar-postgres/main.bicep' = {
  name: 'vm-flatcar-postgres'
  params: {
    location: 'westus'
    sshKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD'
  }
}
