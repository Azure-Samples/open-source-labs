# Linux VM in Azure with Tailscale SSH

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure-Samples%2Fopen-source-labs%2Fmain%2Flinux%2Fvm-tailscale%2Fvm.json)

Deploy an Azure Linux VM with [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh/) — no public SSH ports, no SSH keys to manage. Connect securely over your [Tailscale tailnet](https://tailscale.com/kb/1136/tailnet/).

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- A [Tailscale](https://tailscale.com/) account
- A Tailscale [Auth key](https://login.tailscale.com/admin/settings/keys) (one-off recommended)

## Quick Start

Create a resource group:

```bash
RESOURCE_GROUP='260200-linux-ts'
LOCATION='eastus'

az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION
```

Deploy directly from URL (no local files needed):

```bash
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-uri https://raw.githubusercontent.com/Azure-Samples/open-source-labs/main/linux/vm-tailscale/vm.json \
    --parameters \
        cloudInit='tailscale' \
        env='{"tskey":"<YOUR_TAILSCALE_AUTH_KEY>"}'
```

Or deploy using a local file:

```bash
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file vm.bicep \
    --parameters \
        cloudInit='tailscale' \
        env='{"tskey":"<YOUR_TAILSCALE_AUTH_KEY>"}'
```

Once deployed, SSH via Tailscale (with [MagicDNS](https://tailscale.com/kb/1081/magicdns/)):

```bash
ssh azureuser@vm1
```

Or by Tailscale IP:

```bash
ssh azureuser@<tailscale-ip>
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `vmName` | `vm1` | VM name (also the Tailscale hostname) |
| `vmSize` | `Standard_B2s_v2` | VM size (see VM Sizes below) |
| `osImage` | `Ubuntu 24.04-LTS` | OS image (`Ubuntu 24.04-LTS (arm64)` for Arm) |
| `osDiskSize` | `64` | OS disk size in GB |
| `cloudInit` | `none` | `tailscale` or `none` |
| `env` | `{}` | JSON object with `tskey` for Tailscale auth key |
| `adminUsername` | `azureuser` | VM admin username |
| `adminPasswordOrKey` | _(placeholder)_ | SSH public key (not needed with Tailscale SSH) |

## VM Sizes

| Size | vCPUs | RAM | Arch | Notes |
|------|-------|-----|------|-------|
| `Standard_B2ts_v2` | 2 | 1 GiB | x64 | Free tier eligible |
| `Standard_B2ls_v2` | 2 | 4 GiB | x64 | |
| `Standard_B2s_v2` | 2 | 8 GiB | x64 | Default |
| `Standard_B4ls_v2` | 4 | 8 GiB | x64 | |
| `Standard_B4s_v2` | 4 | 16 GiB | x64 | |
| `Standard_D2s_v5` | 2 | 8 GiB | x64 | |
| `Standard_D4s_v5` | 4 | 16 GiB | x64 | |
| `Standard_D2ps_v5` | 2 | 8 GiB | arm64 | Ampere Altra |
| `Standard_D4ps_v5` | 4 | 16 GiB | arm64 | Ampere Altra |

## Arm64 VMs

To deploy on [Ampere Altra Arm64-based VMs](https://azure.microsoft.com/blog/azure-virtual-machines-with-ampere-altra-arm-based-processors-generally-available/):

```bash
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-uri https://raw.githubusercontent.com/Azure-Samples/open-source-labs/main/linux/vm-tailscale/vm.json \
    --parameters \
        vmName='arm1' \
        cloudInit='tailscale' \
        env='{"tskey":"<YOUR_TAILSCALE_AUTH_KEY>"}' \
        vmSize='Standard_D2ps_v5' \
        osImage='Ubuntu 24.04-LTS (arm64)'
```

## Cleanup

Empty the resource group (keeps the group, removes all resources):

```bash
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-uri https://raw.githubusercontent.com/Azure-Samples/open-source-labs/main/linux/vm-tailscale/empty.json \
    --mode Complete
```
