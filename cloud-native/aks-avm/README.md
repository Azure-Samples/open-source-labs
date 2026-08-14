# Deploy Azure Kubernetes Service (AKS) with Azure Verified Modules

This deliberately minimal lab follows the AVM managed cluster module's [using only defaults example](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/container-service/managed-cluster#example-2-using-only-defaults). Compare it with the [raw-resource Bicep lab](../aks-arm/).

The module is pinned to `0.14.0`. On 2026-08-11, this was verified as the newest release from the upstream [`version.json`](https://github.com/Azure/bicep-registry-modules/blob/main/avm/res/container-service/managed-cluster/version.json) and changelog, and by confirming that its public Microsoft Container Registry OCI manifest exists.

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/quickstart), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Just](https://just.systems/) (`brew install just`, or see the [install guide](https://just.systems/man/en/packages.html))
- The `diff` utility

Deploy it with:

```bash
az deployment group create \
    --resource-group <resource-group> \
    --template-file cloud-native/aks-avm/aks.bicep
```

One deliberate deviation from "only defaults": `osSKU: 'AzureLinux3'` is set
explicitly. The module otherwise defaults to Ubuntu, and every other AKS lab
here runs Azure Linux — a comparison lab that silently differed on the node OS
would compare the wrong thing.

## First comparison finding

The module's defaults are not region-neutral. Validated against `canadacentral`
on 2026-08-11, the defaults example failed preflight:

```
AvailabilityZoneNotSupported: The zone(s) '1' for resource 'systempool' is not
supported. The supported zones for location 'canadacentral' are ''.
```

AVM spreads the system pool across availability zones by default, and the
example's `Standard_DS4_v2` has no zone support in that region — so "using only
defaults" does not deploy there. Moving to `Standard_D2s_v5` (and one node
rather than three) validates cleanly.

The raw-resource [`aks-arm`](../aks-arm/) lab has no such failure mode: it sets
no zones, so there is nothing to be unsupported. That is the trade the two labs
exist to make visible — AVM supplies production defaults, and production
defaults carry regional assumptions a lab has to know about.
