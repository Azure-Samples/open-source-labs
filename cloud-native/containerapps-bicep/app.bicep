param env_name string = 'my-environment'
param app_name string = 'my-container-app'

param registry_server string = 'example.azurecr.io'
param app_image string = 'containerapps-helloworld:latest'

param location string = resourceGroup().location

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: '${resourceGroup().name}-identity'
}

resource environment 'Microsoft.App/managedEnvironments@2026-01-01' existing = {
  name: env_name
}

resource app 'Microsoft.App/containerApps@2026-01-01' = {
  name: app_name
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
      }
      registries: [
        {
          server: registry_server
          identity: managedIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          image: app_image
          name: app_name
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}
