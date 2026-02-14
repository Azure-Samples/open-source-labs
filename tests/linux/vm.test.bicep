targetScope = 'resourceGroup'


module main '../../linux/vm/vm.bicep' = {
  name: 'linux-vm'
  params: {
    location: 'westus'
  }
}
