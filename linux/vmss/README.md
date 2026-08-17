# Linux on Azure with Bicep/ARM and Virtual Machine Scale Sets (VMSS)

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/get-started), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Just](https://just.systems/) (`brew install just`, or see the [install guide](https://just.systems/man/en/packages.html))
- [curl](https://curl.se/)
- The `diff` utility

## Commands

```
$ just
Available recipes:
    default
    deploy-vmss  # Deploy vmss.bicep at resource group scope.
    group-create # Create the Azure resource group.
    group-delete # Delete the Azure resource group and everything in it.
    group-empty  # Empty the resource group, leaving the group itself in place.
    who-am-i     # Print the caller's public IP address.
```

`group-empty` deploys an empty template in Complete mode, removing the contents
but leaving the group itself. Prefer it over `group-delete` where your access is
granted at the resource-group scope, since deleting the group destroys any role
assignment scoped to it.

## OS images

| `OS_IMAGE` | Publisher | Offer | SKU | Architecture |
| --- | --- | --- | --- | --- |
| `Ubuntu 26.04-LTS` (default) | Canonical | ubuntu-26_04-lts | server | x64 |
| `Ubuntu 26.04-LTS (arm64)` | Canonical | ubuntu-26_04-lts | server-arm64 | Arm64 |
| `Ubuntu 24.04-LTS` | Canonical | ubuntu-24_04-lts | server | x64 |
| `Azure Linux 4` | microsoftazurelinux | azurelinux-4 | 4 | x64 |

The Arm64 image automatically uses the Arm64-capable `Standard_D2ps_v6` size.
The other images default to `Standard_D2s_v6`.

## Usage

```bash
# (optional) define the resource group name
# export RESOURCE_GROUP='2026-08-vmss'

# create the group and deploy the vmss
just group-create deploy-vmss

# deploy the Arm64 image
OS_IMAGE='Ubuntu 26.04-LTS (arm64)' just deploy-vmss

# empty the group while preserving it and its scoped role assignments
just group-empty

# or delete the group and everything in it
just group-delete
```
