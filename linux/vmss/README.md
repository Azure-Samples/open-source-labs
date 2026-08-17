# Linux on Azure with Bicep/ARM and Virtual Machine Scale Sets (VMSS)

This lab deploys a Virtual Machine Scale Set with Flexible orchestration, the
recommended mode for new scale sets. Flexible replaces the legacy Uniform mode
so each instance is a standard Azure VM with normal VM lifecycle, networking,
RBAC, backup, and recovery APIs.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure-Samples%2Fopen-source-labs%2Fmain%2Flinux%2Fvmss%2Fvmss.json)

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

| `OS_IMAGE` | Publisher | Offer | SKU | Architecture | VM size |
| --- | --- | --- | --- | --- | --- |
| `Azure Linux 4` (default) | microsoftazurelinux | azurelinux-4 | 4 | x64 | Standard_D2s_v6 |
| `Azure Linux 4 (arm64)` | microsoftazurelinux | azurelinux-4 | 4-arm64 | Arm64 | Standard_D2ps_v6 |
| `Ubuntu 26.04-LTS` | Canonical | ubuntu-26_04-lts | server | x64 | Standard_D2s_v6 |
| `Ubuntu 26.04-LTS (arm64)` | Canonical | ubuntu-26_04-lts | server-arm64 | Arm64 | Standard_D2ps_v6 |
| `Ubuntu 24.04-LTS` | Canonical | ubuntu-24_04-lts | server | x64 | Standard_D2s_v6 |

The Arm64 images automatically use the Arm64-capable `Standard_D2ps_v6` size.
The other images default to `Standard_D2s_v6`.

## Scale set capabilities

- **Flexible orchestration:** uses standard VM resources and supports modern
  VM lifecycle and management APIs; automatically created instance names use
  the configured prefix plus a unique suffix.
- **Maximum fault-domain spreading:** `platformFaultDomainCount` is `1`, letting
  Azure spread instances as widely as possible while supporting up to 1,000 VMs;
  `singlePlacementGroup` is omitted so the Flexible platform selects its value.
- **Trusted Launch:** Secure Boot and vTPM protect the boot chain for every
  selectable Generation 2 image.
- **Application health and repairs:** the health extension checks SSH locally,
  and Azure replaces an unhealthy instance after a 30-minute grace period.
- **Inbound NAT rule v2:** maps a frontend port range to the load balancer
  backend pool because Flexible instances do not support VMSS NAT pools.
- **No automatic OS image upgrades:** Flexible support remains a preview, so
  this teaching lab omits the legacy automatic image-upgrade policy.
- **No availability zones:** the regional layout keeps this teaching lab
  portable and lets Azure provide maximum fault-domain spreading.
- **No encryption at host:** it is subscription-feature dependent and adds
  portability friction without improving the orchestration lesson.

## Cloud-init

The optional bootstrap is a single readable
[`cloud-init/cloud-init.yaml`](cloud-init/cloud-init.yaml) file loaded directly
by Bicep. It writes the `ENV` object to the instance user's `env.json` and
records completion in `cloud-init-complete.txt`; it deliberately avoids
Ubuntu-specific `apt` commands and package names, so it also works on Azure
Linux 4.

Enable it with `CUSTOM_DATA=cloud-init`. The default is `none`.

The default location is `canadacentral`. Override `RESOURCE_GROUP`, `LOCATION`,
`VMSS_NAME`, `VMSS_SIZE`, `VMSS_INSTANCE_COUNT`, `VMSS_OS_DISK_SIZE`,
`OS_IMAGE`, `CUSTOM_DATA`, `ENV`, `IP_ALLOW`, or `SSH_KEY` through environment
variables.

## Usage

```bash
# (optional) define the resource group name
# export RESOURCE_GROUP='2026-08-vmss'

# create the group and deploy the vmss
just group-create deploy-vmss

# deploy the Arm64 image
OS_IMAGE='Ubuntu 26.04-LTS (arm64)' just deploy-vmss

# deploy with the cloud-init bootstrap
CUSTOM_DATA=cloud-init ENV='{"HELLO":"world"}' just deploy-vmss

# empty the group while preserving it and its scoped role assignments
just group-empty

# or delete the group and everything in it
just group-delete
```
