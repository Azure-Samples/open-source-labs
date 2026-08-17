# Run Azure Linux nodes on Azure Kubernetes Service (AKS)

This lab deploys an AKS cluster whose Linux node pools use the Azure Linux node
OS. The Bicep template also creates a container registry, managed identity, and
storage account. Two GPU pools are available as an opt-in deployment when the
subscription has the required quota.

## What Azure Linux is

[Azure Linux](https://github.com/microsoft/azurelinux/tree/3.0) is Microsoft's
open-source, Fedora-derived, RPM-based Linux distribution. The
[Azure Linux Container Host for AKS](https://learn.microsoft.com/azure/azure-linux/azure-linux-aks-overview)
is a curated image of that distribution, optimized for container workloads on
Azure. It includes `containerd`, an Azure-optimized kernel, and only the host
packages needed to run containers, and it is compatible with Azure agents.
Microsoft documents roughly 400 packages and a disk footprint up to 5 GB
smaller than the other AKS Linux images.

Choose Azure Linux when workloads are packaged in containers and you want a
small host package set, reduced attack surface, Azure-tuned kernel, and
Microsoft's integrated build and validation pipeline. Microsoft builds, signs,
and tests the packages, releases security patches monthly and critical fixes
within days when needed, and favors backports over disruptive version changes
within a major release.

This is a managed but conventional Linux node OS: it uses the RPM package
ecosystem, and AKS servicing documentation describes package updates through
`dnf-automatic` as one supported update path. It is **not** the
[immutable Azure Container Linux product](https://learn.microsoft.com/azure/aks/concepts-security#container-and-security-optimized-os-options).
At the AKS layer, Linux node images are
[published weekly](https://learn.microsoft.com/azure/aks/upgrade-node-image);
the configured
[node OS upgrade channel](https://learn.microsoft.com/azure/aks/auto-upgrade-node-os-image)
controls how those images or security fixes reach running nodes.

## Choose an OS SKU

The template accepts both AKS Azure Linux OS SKU values:

| `OS_SKU` | Selection |
| --- | --- |
| `AzureLinux3` | Explicitly selects Azure Linux 3.0. This versioned SKU is the lab default. |
| `AzureLinux` | Selects the Azure Linux major version associated with the Kubernetes version. AKS selects Azure Linux 3.0 for Kubernetes 1.32 and later. |

The current AKS
[OS version documentation](https://learn.microsoft.com/azure/aks/upgrade-os-version)
lists `AzureLinux3` for Kubernetes 1.28 through 1.36. A versioned SKU must be
changed before moving to a Kubernetes version that no longer supports it. The
unversioned `AzureLinux` SKU follows the AKS default and is the better choice
when that automatic major-version selection is wanted. There is no
`AzureLinux4` AKS node OS SKU.

Use the default or select the unversioned SKU when previewing or deploying:

```bash
just validate
OS_SKU=AzureLinux just validate
OS_SKU=AzureLinux just deploy-aks
```

## Azure Linux and Azure Container Linux side by side

Two different node operating systems, not two versions of one. This table is
repeated in both labs so the comparison is visible from either side.

| | Azure Linux (`AzureLinux`, `AzureLinux3`) | Azure Container Linux (`AzureContainerLinux`) |
| --- | --- | --- |
| Lineage | RPM-based Azure Linux | Flatcar Container Linux, with Azure Linux packages and servicing layered on |
| Root filesystem | Conventional and mutable | `/usr` mounted read-only and protected by dm-verity; the kernel validates a signed root hash at boot and at runtime |
| Mandatory access control | Not enforcing by default | SELinux enforcing by default |
| Boot integrity | Optional | Requires Trusted Launch with Secure Boot and vTPM; there is no variant without it |
| Servicing | Node image updates | Weekly whole node images, versioned like `AKSAzureContainerLinux-202606.01.0` |
| Node OS upgrade channels | `NodeImage`, `SecurityPatch`, `Unmanaged` | `NodeImage` only |
| Availability on AKS | `AzureLinux` selects Azure Linux 3.0 from Kubernetes 1.32 | GA from Kubernetes 1.34 |
| Architectures | AMD64 and ARM64 | AMD64 and ARM64; GPU node pools are AMD64 only |
| Constraints specific to it | — | No Generation 1 VM sizes, and no Pod Sandboxing |

There is no `AzureLinux4` node SKU. The node OS does not track the version of
the [Azure Linux 4 virtual machine image](../../linux/vm-azure-linux/), which
is a separate product with its own release line.

Sources: [Azure Container Linux overview](https://learn.microsoft.com/azure/azure-linux/azure-container-linux-overview),
and `az aks nodepool add --help` for the accepted OS SKU values.

## Related labs

- [Azure Linux 4 on a virtual machine](../../linux/vm-azure-linux/) uses the
  general-purpose Azure Linux 4 VM image rather than an AKS-optimized Azure
  Linux 3 node image.
- [Azure Container Linux on AKS](../aks-azure-container-linux/) uses the
  immutable Azure Container Linux node OS rather than the conventional
  RPM-managed Azure Linux host used here.

## Requirements

- An [Azure subscription](https://azure.microsoft.com/free/)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell, such as Linux, macOS, WSL, Azure Cloud Shell, or GitHub
  Codespaces
- [Git](https://git-scm.com/)
- [Just](https://just.systems/) (`brew install just`, or see the
  [installation guide](https://just.systems/man/en/packages.html))

## Instructions

Sign in to Azure:

```bash
az login
```

Clone this repository and change to the lab directory:

```bash
git clone https://github.com/Azure-Samples/open-source-labs.git
cd open-source-labs/cloud-native/aks-azure-linux
```

The [Justfile](./Justfile) wraps the Azure CLI and [Bicep](./aks.bicep)
commands. Running `just` with no arguments lists the available recipes:

```text
$ just
Available recipes:
    aks-credentials    # Get credentials for the AKS cluster.
    default
    deploy-aks         # Deploy aks.bicep at resource group scope.
    empty-namespace    # Delete all resources in the configured Kubernetes namespace.
    group-create       # Create the Azure resource group.
    group-empty        # Empty the resource group, leaving the group itself in place.
    install-kubectl    # Install kubectl through the Azure CLI.
    node-image-version # Show the node image version running in each AKS node pool.
    validate           # Preview the AKS deployment without changing Azure resources.
```

Preview the resource-group-scoped deployment without changing Azure:

```bash
RESOURCE_GROUP=<resource-group> LOCATION=<location> just validate
```

Create a resource group and deploy the lab:

```bash
RESOURCE_GROUP=<resource-group> LOCATION=<location> just group-create deploy-aks
```

The template leaves the Kubernetes version unset so AKS selects the supported
regional default. GPU node pools remain disabled unless `deployGpuPools=true`
is passed directly to the Bicep deployment after confirming regional VM
availability and quota.

## Observe node image servicing

List the image version currently running in every node pool:

```bash
RESOURCE_GROUP=<resource-group> AKS_NAME=<cluster-name> just node-image-version
```

The recipe runs:

```bash
az aks nodepool list \
    --resource-group <resource-group> \
    --cluster-name <cluster-name> \
    --query '[].{name:name,nodeImageVersion:nodeImageVersion}'
```

## Empty the resource group

Never delete a resource group when access is granted at resource-group scope:
deleting it also destroys the scoped role assignment. Empty it with a
Complete-mode deployment instead:

```bash
RESOURCE_GROUP=<resource-group> just group-empty
```
