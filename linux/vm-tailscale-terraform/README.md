# Deploy an Azure Linux Virtual Machine using Terraform and connect with Tailscale

In this lab, you will explore how to deploy an Azure Linux Virtual Machine with Tailscale installed, configured, and ready for secure SSH connections.

## Get ready

To complete this lab you will need to following:

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/quickstart), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Just](https://just.systems/) (`brew install just`, or see the [install guide](https://just.systems/man/en/packages.html))
- The [Terraform CLI](https://developer.hashicorp.com/terraform/downloads)
- A [Tailscale account](https://login.tailscale.com/start)
  - Your [Tailscale API key](https://login.tailscale.com/admin/settings/keys) to automatically generate authentication keys for your machines to be able to join your Tailnet (see [Tailscale API](https://tailscale.com/kb/1101/api/?q=api%20key) for more information)
  - Your unique [Tailnet organization name](https://tailscale.com/kb/1217/tailnet-name/#organization-name) (optional)

## How to do it

The Terraform configuration has been parameterized so that you can pass in user specific values at runtime. The variables are defined in the [`variables.tf`](./variables.tf) file. Open the file and take a look at some of the values you can pass in.

All of the variables except for `tailnet_name` and `tailscale_api_key` have a default value. Since the Tailscale variables are unique and sensitive to your deployment, you can pass values in at runtime using a `terraform.tfvars` file.

Create a new `terraform.tfvars` file in the same location as the [`main.tf`](./main.tf) file and add the following entries.

```terraform
tailnet_name      = "-"
tailscale_api_key = "<YOUR_TAILSCALE_API_KEY>"
```

The `tailnet_name` value is populated with your `Organization` from the [General](https://login.tailscale.com/admin/settings/general) (e.g. `example.com`). However, you can leave this as `-` to target your default Tailnet. Note the [Tailnet organization name](https://tailscale.com/kb/1217/tailnet-name/#organization-name) is different to your Tailnet name which is in the form `example-name.ts.net`.

Also note the `tailscale_api_key` is populated with the Tailscale `API key` from the [Keys](https://login.tailscale.com/admin/settings/keys) page, and not an `Auth key`. You can also set this key to expire in as little as 1 day.

If you'd like to further customize the deployment, you can add additional values for the variables defined in `variables.tf`.

Here is an example:

```terraform
# example terraform.tfvars file
tailnet_name            = "-"
tailscale_api_key       = "<YOUR_TAILSCALE_API_KEY>"
location                = "westus3"
vnet_address_space      = "10.21.0.0/28"
snet_address_space      = "10.21.0.0/28"
vm_sku                  = "Standard_D2s_v5"
vm_username             = "paul"
vm_os_disk_storage_type = "Premium_LRS"
```

For example, here we are using a `Standard_D2s_v5` [Dsv5](https://learn.microsoft.com/azure/virtual-machines/dv5-dsv5-series) series SKU for the Virtual Machine, rather than the `Standard_B2s` [B-series burstable](https://learn.microsoft.com/azure/virtual-machines/sizes-b-series-burstable) VM we use by default in [variables.tf](./variables.tf).

The `terraform.tfvars` file is a special file within Terraform. When the Terraform CLI detects a file with the name of `terraform.tfvars` or `*.auto.tfvars`, it will automatically map the values to variables at runtime without needing to pass in the *.tfvars file to the command.

To run the Terraform, open a terminal and make sure you are logged into the Azure CLI.

```bash
az login
```

Make sure you are in the right directory, run the following command if needed.

```bash
cd linux/vm-tailscale-terraform 
```

Run the `init` command.

```bash
terraform init
```

Run the `apply` command.

```bash
terraform apply
```

The `terraform apply` command will issue a `terraform plan` and output the list of changes to the console. Review the output then type the word `yes` and "enter" to continue.

Once the Terraform command is completed, you should see output on the console which displays an SSH command that you can use to connect to the VM.

You can connect to the using the following command.

```bash
eval $(terraform output -raw ssh_command)
```

## How it works

The [`main.tf`](./main.tf) file uses the following providers:

- [`hashicorp/azurerm`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) for deploying Azure resources.
- [`hashicorp/cloudinit`](https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs) for configuring your machine to install and configure Tailscale.
- [`hashicorp/tls`](https://registry.terraform.io/providers/hashicorp/tls/latest/docs) for generating a SSH key to satisfy Azure VM requirements
- [`hashicorp/random`](https://registry.terraform.io/providers/hashicorp/random/latest/docs) to generate random resource names
- [`tailscale/tailscale`](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs) for generating Tailscale authentication keys to onboard your machine to your Tailnet

The deployment will first generate a [`random_pet`](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/pet) name which will be used to name your Azure resources. This is good for lab environments that will be thrown away.

Then a new [resource group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) will be provisioned and resources that support an [virtual machine](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine) will be created including a [virtual network](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network), a [subnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet), and a [network security group assigned](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) to the subnet. As part of the network security group configuration, an inbound [network security rule](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group#security_rule) will be added to allow Tailscale to communicate with your machine using UDP on port 41641.

A new [SSH key pair](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) will be generated and the public key will be assigned to the [`azurerm_ssh_public_key`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/ssh_public_key) resource and the private key will be assigned to the Linux virtual machine; however, this key pair is not actually used since Tailscale will provide authentication for SSH access.

A new one-time, pre-authorized [Tailscale authorization key](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/tailnet_key) will be generated and passed into the [`cloud-init`](https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs/data-sources/cloudinit_config) configuration which will be passed in as [custom data](https://learn.microsoft.com/azure/virtual-machines/custom-data) on the virtual machine. The cloud-init config combines two resources as a multipart MIME archive. By default this archive is Gzip compressed and base64 encoded.

> NOTE: Azure requires custom data be base64 encoded and cannot exceed 64KB in size.

Two pieces of configuration is passed to the virtual machine's custom data to demonstrate the usage of [cloud-config data](https://cloudinit.readthedocs.io/en/latest/topics/format.html#cloud-config-data) and [user-data script](https://cloudinit.readthedocs.io/en/latest/topics/format.html#user-data-script).

The **cloud-config data** is a simple [`tailscale.yml`](./tailscale.yml) YAML file which instructs the VM to create a file named `/var/tmp/hello-world.txt` which contains the text "Hello, World!".

To install and configure Tailscale, **user-data script** executes the [`tailscale.sh`](./tailscale.sh) script. This particular data types uses a [`part`](https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs/data-sources/cloudinit_config#part) to load the bash script as template file. If you notice in the script, there is a placeholder for `${tailscale_auth_key}`. This is passed into the script at runtime with the value that was generated by the `tailscale_tailnet_key` resource.

The multipart archive cloud-init configuration is then passed into the [`custom_data`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine#custom_data) property of the [Linux virtual machine resource](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine).

## Final steps

You can view the Azure Resources that were created as part of this lab by opening the [Azure Portal](https://portal.azure.com) and looking for Resource Group with an `rg-` prefix (e.g. `rg-factualworm`).

When you are done exploring, run the `destroy` command to delete all your resources.

```bash
terraform destroy
```

## What's next?

Using this approach, you can add as many user-data types needed for your virtual machine's cloud-init configuration.

To further secure your Tailscale API key, you could look to storing it in Azure Key Vault and using the [key vault secret](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault_secret) data type securely inject the API key at runtime.

If you thought this was helpful, please give the repo a ⭐️ or let us know of any questions of feedback by filing a [new issue](https://github.com/Azure-Samples/azure-opensource-labs/issues/new).

Cheers!
