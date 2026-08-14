# Serverless Containers with Go, Azure Container Apps, and GitHub Container Registry

In this lab you will create a sample Go app from a template repository in GitHub. You will then use the included GitHub Actions workflow which will build a container image you can then make public. You will then deploy the public container image to Azure Container Apps.

Azure Container Apps enables you to run microservices and containerized applications on a serverless platform. With Container Apps, you enjoy the benefits of running containers while leaving behind the concerns of manually configuring cloud infrastructure and complex container orchestrators.

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli?view=azure-cli-latest)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/get-started), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Just](https://just.systems/) (`brew install just`, or see the [install guide](https://just.systems/man/en/packages.html))
- [Lychee](https://github.com/lycheeverse/lychee)
- A [GitHub Account](https://github.com)

## 1. Build and Containerize asw101/go-hello

1. Visit <https://github.com/asw101/go-hello>
1. Click "Use this template".
1. Name your repo "serverless-gopher".
1. Create a new branch called release.
1. Click on the Actions tab.
1. View the output of the action.
1. Return to the main repo (Code tab).
1. Click on "serverless-gopher" under "Packages" on the right hand size.
1. Copy the `docker pull` command which will include the image name.
1. Update the `GITHUB_USER_OR_ORG` environment variable below with your GitHub username or organization name.
1. Note: If you chose to make your GitHub repository Private rather than Public in step 3, you will need to click on "Package settings" on the right hand side, scroll down and click "Change visibility" button to make your package public.

## 2. Install Azure CLI Extension and Register Resource Providers

If this is the first time you have used Azure Container Apps from the Azure CLI, or with your Azure Account, you will need to install the `containerapp` extension, and register the providers for `Microsoft.App` and `Microsoft.OperationalInsights` using the following commands.

```bash
az extension add --name containerapp

az provider register --namespace Microsoft.App --wait

az provider register --namespace Microsoft.OperationalInsights --wait
```

## 3. Set Environment Variables

```bash
RESOURCE_GROUP="my-container-apps"
LOCATION="canadacentral"
CONTAINERAPPS_ENVIRONMENT="my-environment"

GITHUB_USER_OR_ORG="asw101"
CONTAINER_IMAGE="ghcr.io/${GITHUB_USER_OR_ORG}/serverless-gopher:release"
```

## 4. Create Resource Group

```bash
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION
```

## 5. Create Azure Container Apps Environment

[Quickstart (learn.microsoft.com)](https://learn.microsoft.com/azure/container-apps/get-started-existing-container-image?tabs=bash&pivots=container-apps-private-registry)

```bash
az containerapp env create \
  --name $CONTAINERAPPS_ENVIRONMENT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION
```

## 6. Create Container App with a Public Image

```bash
az containerapp create \
  --name my-container-app \
  --resource-group $RESOURCE_GROUP \
  --environment $CONTAINERAPPS_ENVIRONMENT \
  --image "$CONTAINER_IMAGE" \
  --target-port 80 \
  --ingress 'external'
```

## 7. Test Container App with curl

```bash
CONTAINERAPP_FQDN=$(az containerapp show --resource-group $RESOURCE_GROUP \
  --name my-container-app \
  --query properties.configuration.ingress.fqdn \
  --out tsv)

echo "https://${CONTAINERAPP_FQDN}"

curl "https://${CONTAINERAPP_FQDN}"
```

## 8. Delete Resource Group

```bash
az group delete \
  --name $RESOURCE_GROUP
```
