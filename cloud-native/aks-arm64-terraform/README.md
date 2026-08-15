# Azure Kubernetes Service with ARM64 node pools and Terraform

This directory holds Terraform configuration files for deploying an AKS cluster with ARM64 node pools. It is an alternative to [deploying with Azure Bicep](../aks-arm64#deploy-azure-resources-using-azure-bicep)

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/get-started), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Just](https://just.systems/) (`brew install just`, or see the [install guide](https://just.systems/man/en/packages.html))
- The [Terraform CLI](https://www.terraform.io/downloads)
- The `ARM_SUBSCRIPTION_ID` environment variable set to the ID of the selected Azure subscription

## Deploy Azure Resources using Terraform

Terraform will use your Azure CLI login context to deploy the resources into your subscription. Login to the Azure CLI and ensure you have selected the proper subscription.

```bash
az login
```

Optionally set the correct subscription if you have more than one.

```bash
az account set -s '<YOUR_SUBSCRIPTION_NAME>'
```

Export the selected subscription ID for Terraform.

```bash
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

The `resource_group_name` variable controls where resources are deployed. Leave it empty (the default) to create a resource group in `location`:

```bash
unset RESOURCE_GROUP
just validate
```

To deploy into an existing resource group, set `RESOURCE_GROUP`; the Justfile exports it as `TF_VAR_resource_group_name`, and Terraform uses the existing group's location:

```bash
export RESOURCE_GROUP='<EXISTING_RESOURCE_GROUP_NAME>'
just validate
```

When running Terraform directly instead of using Just, set `TF_VAR_resource_group_name` to the existing resource group name.

Change to the `cloud-native/aks-arm64-terraform` subdirectory of this repo and run the Terraform deployment script.

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
