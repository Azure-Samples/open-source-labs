# Azure Linux 4 on an Azure Virtual Machine

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure-Samples%2Fopen-source-labs%2Fmain%2Flinux%2Fvm-azure-linux%2Fvm.json)

Deploy a vanilla Azure Linux 4 virtual machine with Bicep. The template follows
the [Microsoft Learn Linux VM Bicep quickstart](https://learn.microsoft.com/azure/virtual-machines/linux/quick-create-bicep)
and restricts SSH access to the caller's public IP address by default.

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/get-started), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Just](https://just.systems/) (`brew install just`, or see the [install guide](https://just.systems/man/en/packages.html))
- [curl](https://curl.se/)
- The `diff` utility
- The OpenSSH `ssh-keygen` utility
- An SSH public key

## Commands

```console
$ just
Available recipes:
    default
    deploy-vm    # Deploy vm.bicep at resource group scope.
    group-create # Create the Azure resource group.
    group-delete # Delete the Azure resource group and everything in it.
    group-empty  # Empty the resource group, leaving the group itself in place.
    ssh-command  # Print the SSH command from the VM deployment.
    who-am-i     # Print the caller's public IP address.
```

`group-empty` deploys an empty template in Complete mode, removing the contents
but leaving the group itself. Prefer it over `group-delete` where your access is
granted at the resource-group scope, since deleting the group destroys any role
assignment scoped to it.

## OS images

| `OS_IMAGE` | Publisher | Offer | SKU | Architecture | VM size |
| --- | --- | --- | --- | --- | --- |
| `Azure Linux 4` (default) | MicrosoftCBLMariner | azure-linux-3 | azure-linux-3-gen2 | x64 | Standard_D2s_v6 |
| `Azure Linux 4 (arm64)` | MicrosoftCBLMariner | azure-linux-3 | azure-linux-3-arm64 | Arm64 | Standard_D2ps_v6 |

Selecting the Arm64 image automatically uses the Arm64-capable
`Standard_D2ps_v6` size. The x64 image defaults to `Standard_D2s_v6`.

## Usage

```bash
export SSH_KEY=~/.ssh/id_ed25519.pub

# Create the resource group and deploy the default x64 VM.
just group-create deploy-vm

# Deploy the Arm64 VM instead.
OS_IMAGE='Azure Linux 4 (arm64)' just deploy-vm

# Print the SSH command after deployment.
just ssh-command

# Empty the group while preserving it and its scoped role assignments.
just group-empty

# Or delete the group and everything in it.
just group-delete
```

The default location is `canadacentral`. Override `RESOURCE_GROUP`, `LOCATION`,
`VM_NAME`, `OS_IMAGE`, `SSH_KEY`, or `IP_ALLOW` through environment variables.
