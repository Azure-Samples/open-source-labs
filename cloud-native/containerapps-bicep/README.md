# Explore Azure Container Apps, Bicep, and PostgreSQL

In this lab you will deploy Azure Container Apps, Azure Database for PostgreSQL, and other Azure Services (Key Vault, Storage and Managed Identity) with [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) and [Bicep](https://docs.microsoft.com/azure/azure-resource-manager/bicep/overview).

You will deploy containers from GitHub [Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) and built with GitHub [Actions](https://docs.github.com/en/actions/publishing-packages/publishing-docker-images#publishing-images-to-github-packages).

You will also import and have the opportunity to explore data from the [Cassini](https://en.wikipedia.org/wiki/Cassini%E2%80%93Huygens) mission to Saturn, thanks to Rob Conery ([@robconery](https://twitter.com/robconery))'s [A curious moon](https://bigmachine.io/products/a-curious-moon/)/[SQL in Orbit](https://bigmachine.io/product/sql-in-orbit/).

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/quickstart), or [GitHub Codespaces](https://github.com/features/codespaces))
- A [GitHub Account](https://github.com)

## Deploy via Azure Portal

The link below will deploy Azure Container Apps, Azure Database for Postgres and Key Vault via a single ARM template, generated from [main.bicep](main.bicep). This template will also create a Resource Group for you.

[Deploy to Azure](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure-Samples%2Fazure-opensource-labs%2Fmain%2Fcloud-native%2Fcontainerapps-bicep%2Fmain.json)

## Deploy via Azure CLI

Use the [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) and [Bicep](https://docs.microsoft.com/azure/azure-resource-manager/bicep/overview) templates to deploy the infrastructure for your application.

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

## Explore Postgres

See [POSTGRES.md](POSTGRES.md) for instructions on how to login to your Postgres server from your local machine.

## Clean up resources

Once you have finished exploring, you should delete the resource group to avoid any further charges.

```bash
az group delete \
  --name $RESOURCE_GROUP
```
