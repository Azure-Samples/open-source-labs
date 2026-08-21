# Explore Azure Container Apps, Bicep, and PostgreSQL

In this lab you will deploy Azure Container Apps, Azure Database for PostgreSQL, and other Azure Services (Key Vault, Storage and Managed Identity) with [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) and [Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview).

By default, the Container App runs Microsoft's Container Apps hello-world image from Microsoft Container Registry.

You will also import and have the opportunity to explore data from the [Cassini](https://en.wikipedia.org/wiki/Cassini%E2%80%93Huygens) mission to Saturn, thanks to Rob Conery ([@robconery](https://twitter.com/robconery))'s [A curious moon](https://bigmachine.io/products/a-curious-moon/)/[SQL in Orbit](https://bigmachine.io/products/sql-in-orbit/).

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/get-started), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Just](https://just.systems/) (`brew install just`, or see the [install guide](https://just.systems/man/en/packages.html))
- The `diff` utility
- An existing resource group for validation

## Deploy via Azure Portal

The full-lab template deploys Azure Container Apps, Azure Database for Postgres, and Key Vault, and creates a resource group:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure-Samples%2Fopen-source-labs%2Fmain%2Fcloud-native%2Fcontainerapps-bicep%2Fmain.json)

The self-contained Container Apps template deploys into an existing resource group:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure-Samples%2Fopen-source-labs%2Fmain%2Fcloud-native%2Fcontainerapps-bicep%2Fcontainerapp.json)

## Deploy via Azure CLI

Use the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) and [Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview) templates to deploy the infrastructure for your application.

This allows you to deploy the Bicep templates of your choice step-by-step.

Login to the Azure CLI.

```bash
az login
```

Set environment variables and create a Resource Group.

```bash
RESOURCE_GROUP="my-container-apps"
LOCATION="canadacentral"

az group create \
  --name $RESOURCE_GROUP \
  --location "$LOCATION"
```

Change directory to this directory, `cloud-native/containerapps-bicep`.

```bash
cd cloud-native/containerapps-bicep
```

Deploy the bicep templates of your choice with the following `az deployment` commands.

## Deploy to Resource Group

```bash
# containerapp
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file ./containerapp.bicep \
  --parameters \
      location="$LOCATION"

# storage
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file ./storage.bicep

# postgres + keyvault (combined)
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file ./postgres-keyvault.bicep

# key vault (stand-alone)
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file ./keyvault.bicep

# postgres (stand-alone)
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file ./postgres.bicep

# empty
az deployment group create \
  --mode Complete \
  --resource-group "$RESOURCE_GROUP" \
  --template-file ./empty.bicep
```

## Deploy to Subscription

The template used in the Deploy via Azure Portal section above can also be deployed via the CLI. Note this is a subscription-scoped deployment and it will create the Resource Group for you.

```bash
# subscription (containerapp + postgres-keyvault)
LOCATION='canadacentral'
az deployment sub create \
    --name='220600-containerapps' \
    --location $LOCATION \
    --template-file ./main.bicep \
    --parameters \
      resourceGroup='220600-containerapps'
```

## Validate

Set `RESOURCE_GROUP` to an existing resource group. Validation compiles every template, checks the generated ARM JSON, uses the group's location, and runs resource-group-scoped previews of `containerapp.bicep` and `postgres-keyvault.bicep`, the two modules deployed by `main.bicep`:

```bash
export RESOURCE_GROUP='<EXISTING_RESOURCE_GROUP_NAME>'
just validate
```

## Explore Postgres

See [POSTGRES.md](POSTGRES.md) for instructions on how to login to your Postgres server from your local machine.

## Clean up resources

Never delete a resource group when access is granted at resource-group scope:
deleting it also destroys the scoped role assignment. Empty it with the
Complete-mode deployment of [empty.bicep](./empty.bicep) shown in
[Deploy to Resource Group](#deploy-to-resource-group) instead, which removes
every resource while leaving the group and its role assignments in place:

```bash
az deployment group create \
  --mode Complete \
  --resource-group "$RESOURCE_GROUP" \
  --template-file ./empty.bicep
```
