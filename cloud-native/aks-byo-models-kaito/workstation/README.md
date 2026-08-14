# Ubuntu Workstation (for BYO model on AKS with KAITO and open-source tools)

This Terraform script provisions an Ubuntu Virtual Machine (VM) in Azure, configured as a workstation for development and testing purposes. The VM is set up with essential software tools that facilitate cloud-native AI development workflows, including Azure CLI, Terraform, Docker, kubectl, KitOps CLI, and Cog CLI. The VM is provisioned using cloud-init to automate the installation of these tools at startup.

This particular VM will include the following software:

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [Terraform](https://developer.hashicorp.com/terraform/install)
- [Docker](https://www.docker.com/get-started/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)
- [KitOps CLI](https://kitops.org/docs/cli/installation/)
- [Cog CLI](https://cog.run/getting-started/#install-cog)
- [Python](https://www.python.org/downloads/)

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/get-started), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Terraform](https://www.terraform.io/downloads.html)

## Provisioning resources

Login to Azure using the Azure CLI with the command below and follow the instructions output to the terminal.

```sh
az login
```

Set the subscription ID for Terraform to use.

```sh
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

Initialize the Terraform configuration.

```sh
terraform init
```

> [!note]
> The Azure VM SKU is set in a variable named `vm_size` in the `variables.tf` file. This is defaulted to `Standard_D8s_v4`, which is a general-purpose VM with 8 vCPUs and 32 GiB of memory. You can change this to a different SKU based on your requirements. If you are deploying a N-series VM which are NVIDIA GPU-enabled, you will need to install drivers to make use of the GPU. See the [N-series VM documentation](https://learn.microsoft.com/azure/virtual-machines/linux/n-series-driver-setup) for more information on how to install the NVIDIA drivers. You can also install the NVIDIA drivers using the [NVIDIA GPU Driver Extension for Linux](https://learn.microsoft.com/azure/virtual-machines/extensions/hpccompute-gpu-linux).

Run the following command to create the resources. This will prompt you to confirm the changes. Type `yes` to proceed.

```sh
terraform apply
```

## Connecting to VM

An [Azure Network Security Group (NSG)](https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview) is created to allow [SSH](https://www.man7.org/linux/man-pages/man1/ssh.1.html) access to the VM only from the IP address of the machine running the script. To authenticate, a new public/private key pair is generated and stored in Azure. The private key pem file is stored in the current directory and is meant to be ephemeral and will be deleted when as resources get deleted but should still be kept secure.

To SSH into the VM, use the following command:

```bash
ssh -i $(terraform output -raw ssh_private_key) $(terraform output -raw ssh_username)@$(terraform output -raw public_ip)
```

You could also SSH into the VM from VSCode using the [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension. To do this, add the following to your SSH config file:

```text
# ~/.ssh/config
Host <replace_this_with_public_ip>
    HostName <replace_this_with_public_ip>
    User <replace_this_with_ssh_username>
    IdentityFile <replace_this_with_path_to_private_key>
```

See this [documentation](https://code.visualstudio.com/docs/remote/ssh) for more information on Remote Development using SSH.
