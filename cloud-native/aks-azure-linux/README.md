# Explore Azure Linux Container Host for Azure Kubernetes Service (AKS) and GPU workloads

In this lab you will deploy an Azure Kubernetes Service (AKS) cluster with Azure Linux Container Host nodes, a GPU node pool, and other Azure services (Container Registry, Managed Identity, Storage Account), with the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) and [Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview).

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/quickstart), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Just](https://just.systems/) (`brew install just`, or see the [install guide](https://just.systems/man/en/packages.html))

## Instructions

Use the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) and [Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview) templates to deploy the infrastructure for your application.

Login to the Azure CLI.

```bash
az login
```

Clone this repository.

```bash
git clone https://github.com/Azure-Samples/azure-opensource-labs.git
```

Change to this directory.

```
cd azure-opensource-labs/cloud-native/aks-azure-linux
```

While you can deploy the Bicep templates ([aks.bicep](./aks.bicep)) via the Azure CLI or Azure Portal, we have included a [Justfile](./Justfile) with recipes that make deployment easier.

Running `just` with no arguments lists them:

```
$ just
Available recipes:
    aks-credentials # Get credentials for the AKS cluster.
    default
    deploy-aks      # Deploy aks.bicep at resource group scope.
    empty-namespace # Delete all resources in the configured Kubernetes namespace.
    group-create    # Create the Azure resource group.
    group-delete    # Delete the Azure resource group and everything in it.
    group-empty     # Empty the resource group, leaving the group itself in place.
    install-kubectl # Install kubectl through the Azure CLI.
```

`group-empty` deploys an empty template in Complete mode, removing the contents
but leaving the group itself. Prefer it over `group-delete` where your access is
granted at the resource-group scope, since deleting the group destroys any role
assignment scoped to it.

### Deployment

```
just group-create deploy-aks
```

### Empty the resource group

Never delete the resource group: doing so removes the service principal's scoped Owner grant. Emptying it with a Complete-mode deployment reclaims its resources while preserving access.

```
just group-empty
```
