# Explore Azure Container Apps, Terraform, KEDA, and Grafana

In this lab you will deploy Azure Container Apps, Azure Container Registry, Azure Service Bus, Azure Managed Grafana, and potentially other Azure Services (i.e., Azure Virtual Network) using [Terraform](https://learn.hashicorp.com/tutorials/terraform/infrastructure-as-code?in=terraform/azure-get-started). At the time of this writing some services are not available in Hashicorp's `azurerm` [provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest) so we will deploy container apps and the managed Grafana service using the [AzAPI](https://learn.microsoft.com/azure/developer/terraform/overview-azapi-provider) provider.

You will deploy two types of container apps to demonstrate Azure Container Apps autoscaling features. The `helloworld` container app is a simple app found in the Azure Container Apps [quickstart guide](https://learn.microsoft.com/azure/container-apps/get-started?tabs=bash). This container app will be configured for **HTTP scaling**. Upon creation of the resources, a `k6_scripts.js` file will appear in your directory. You can use to load test the application.

The other set of container apps will demonstrate autoscaling using event-driven scalers. In this case, we will be using the [`azure-servicebus` KEDA scaler](https://keda.sh/docs/scalers/azure-service-bus/) to scale our replica counts up and down based on the number of messages in the queue. This solution includes a project called `go-servicebus-sender`. This app will produce messages and add them to the queue. The other app called `go-servicebus-receiver` will receive messages off the queue. Autoscaling will be applied to the message receiver app.

For both container app types, you can view the replica counts using the metrics blade within the Azure portal. You can also import a curated Azure Container Apps dashboard into your Azure Managed Grafana instance and view the metrics from there.

To import dashboards, navigate to your Azure Managed Grafana site, click on the **Dashboards** menu item and click the **+Import** button. In the **Import via grafana.com** textbox, enter `16592` to import the [Azure / Container Apps / Container App View](https://grafana.com/grafana/dashboards/16592-azure-container-apps-container-app-view/) dashboard. You can explore and import other dashboards curated by the [`azuremonitorteam`](https://grafana.com/orgs/azuremonitorteam). 

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/quickstart), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Just](https://just.systems/) (`brew install just`, or see the [install guide](https://just.systems/man/en/packages.html))
- The [Terraform CLI](https://www.terraform.io/downloads)
- [Go](https://go.dev/doc/install)
- [Docker](https://docs.docker.com/get-docker/)
- The [k6 CLI](https://k6.io/docs/getting-started/installation/)

Export the selected Azure subscription ID for the AzureRM provider:

```bash
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

## Clone this repository

Before you begin, clone this repository to your location of choice.

```bash
git clone https://github.com/Azure-Samples/azure-opensource-labs.git
```

## Deploy via Terraform CLI

Terraform will use your Azure CLI login context to deploy the resources into your subscription. Login to the Azure CLI and ensure you have selected the proper subscription.

```bash
az login
```

Optionally set the correct subscription if you have more than one.

```bash
az account set -s '<YOUR_SUBSCRIPTION_NAME>'
```

Change to the `cloud-native/containerapps-terraform/terraform` subdirectory of this repo and run the Terraform deployment script.

```bash
cd cloud-native/containerapps-terraform/terraform
terraform init
terraform apply
```

> NOTE: [Terraform state](https://www.terraform.io/language/state) files will be stored locally within your directory

Review the items that will be deployed by Terraform, then type `yes` in the console to confirm the deployment.

For a more in depth guide on how the Terraform is put together using the AzAPI provider, go check out this [blog post](https://dev.to/azure/monitoring-azure-container-apps-with-azure-managed-grafana-148j).

## Explore Container Apps and its scaling features

The container apps will already have autoscaling fully configured and enabled. 

Open the [Azure portal](https://portal.azure.com).

Navigate to the `rg-fittingshiner` resource group to explore the deployment and its configuration.

Next, use [k6](https://k6.io/) load testing tool to send load to the application URL.

This will use the [k6_scripts.js](./k6_scripts.js) file that was created by [k6_load_test_script.tf](./k6_load_test_script.tf) based on the [k6_scripts.tpl](./k6_scripts.tpl) template, when we ran the `terraform apply` command. It will output the `const res = http.get('${INGRESS_FQDN}');` with the correct application URL for your `helloworld` app.

Run the below command to send some load to your application.

```bash
k6 run --vus 200 --duration 10s k6_scripts.js
```

If you are feeling adventurous, try implementing another container app with one of these [KEDA scalers](https://keda.sh/docs/scalers/) 🚀

## Clean up resources

Once you have finished exploring, you should delete the deployment to avoid any further charges.

```bash
terraform destroy
```
