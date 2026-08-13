# Azure Kubernetes Service with ARM64 node pools and Terraform

This directory holds Terraform configuration files for deploying an AKS cluster with ARM64 node pools. It is an alternative to [deploying with Azure Bicep](../aks-arm64#deploy-azure-resources-using-azure-bicep)

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/quickstart), or [GitHub Codespaces](https://github.com/features/codespaces))
- The [Terraform CLI](https://www.terraform.io/downloads)

## Deploy Azure Resources using Terraform

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
cd cloud-native/aks-arm64-terraform
terraform init
terraform apply
```

> [Terraform state](https://www.terraform.io/language/state) files will be stored locally within your current directory; however, best practice is to store your Terraform state files in [Azure Storage](https://learn.microsoft.com/azure/developer/terraform/store-state-in-azure-storage?tabs=azure-cli) or [Terraform Cloud](https://cloud.hashicorp.com/products/terraform).

## Validate the deployment

Once you've completed the deployment of Azure infrastructure, run the following command to set the random deployment name to an environment variable.

```bash
export name=$(terraform output -raw random_pet_name)
```

You can pull down the `kube_config` file with the following command.

```bash
az aks get-credentials --resource-group "rg-${name}" --name "aks-${name}"
```

Validate access to your AKS cluster using `kubectl`.

```bash
kubectl get nodes -o wide
```

## Next steps

Continue on to the [Deploying `ARM64` workloads to Kubernetes](../aks-arm64#deploying-arm64-workloads-to-kubernetes) portion of the [Azure Kubernetes Service with ARM64 node pools](../aks-arm64/) lab to deploy workloads to your cluster.

## Clean up resources

Once you have finished exploring AKS with ARM64 node pools, you should delete the deployment to avoid any further charges.

Run the `destroy` command to delete all your resources.

```bash
terraform destroy
```
