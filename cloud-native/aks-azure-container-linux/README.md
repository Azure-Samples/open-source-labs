# Azure Container Linux on Azure Kubernetes Service

Deploy an Azure Kubernetes Service (AKS) cluster whose system node pool runs
[Azure Container Linux (ACL)](https://learn.microsoft.com/azure/azure-linux/azure-container-linux-overview).
This lab focuses only on ACL. For the mutable Azure Linux Container Host on AKS,
use [`../aks-azure-linux`](../aks-azure-linux); for a general-purpose Azure Linux
4 virtual machine, use
[`../../linux/vm-azure-linux`](../../linux/vm-azure-linux).

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure-Samples%2Fopen-source-labs%2Fmain%2Fcloud-native%2Faks-azure-container-linux%2Fmain.json)

## What Azure Container Linux is

ACL is an immutable, container-optimized AKS operating system derived from
Flatcar Container Linux. It layers Azure Linux packages, servicing, and Azure
platform integration onto Flatcar's container-first design. ACL is the
generally available release of what was Flatcar Container Linux for AKS and is
GA beginning with AKS 1.34.

Its security boundary is enforced by the OS rather than by a convention:

- `/usr` is read-only and protected by dm-verity. The kernel checks a signed
  root hash at boot and runtime to detect and block tampering.
- SELinux runs in enforcing mode by default.
- Trusted Launch is mandatory. Every ACL node must use Secure Boot and vTPM;
  there is no non-Trusted-Launch ACL image.
- The image contains only the components needed to run containers, reducing
  packages, services, and host entry points.
- AKS publishes a complete, tested ACL node image weekly. The `NodeImage`
  channel rolls nodes to the new image rather than maintaining the host through
  independent package updates.

Choose ACL when workloads fit a minimal container-only host and kernel-enforced
immutability, mandatory access control, measured boot, and whole-image servicing
are useful security properties. Workload software and configuration belong in
container images and Kubernetes resources, not as mutable node customization.

ACL retains its Flatcar lineage, but it is an Azure-integrated AKS node image.
For a lab that provisions upstream Flatcar directly on an Azure VM, see
[`../../linux/vm-flatcar-postgres`](../../linux/vm-flatcar-postgres).

## Adoption constraints

These constraints can determine whether ACL fits a cluster:

- `SecurityPatch` and `Unmanaged` node OS upgrade channels aren't supported.
  This lab selects `NodeImage`.
- Generation 1 VM sizes aren't supported.
- Pod Sandboxing isn't supported.
- A non-Trusted-Launch variant isn't available; Secure Boot and vTPM are
  required.
- AMD64 and Arm64 are supported, but ACL on Arm64 requires a Cobalt-based v6
  size for Trusted Launch. GPU node pools are AMD64 only.

Node auto-provisioning supports ACL. Existing Ubuntu or Azure Linux node pools
can also migrate in place by changing their OS SKU to `AzureContainerLinux`,
provided the pool is made compatible with ACL's Trusted Launch and VM-size
requirements.

Sources:

- [Azure Container Linux overview](https://learn.microsoft.com/azure/azure-linux/azure-container-linux-overview)
  - lineage, GA version, security design, architecture support, weekly images,
    node auto-provisioning, and unsupported features
- [Migrate nodes to Azure Container Linux](https://learn.microsoft.com/azure/azure-linux/tutorial-migrate-azure-container-linux-aks)
  - in-place OS SKU migration and the Cobalt v6 requirement for Arm64
- [Trusted Launch with AKS](https://learn.microsoft.com/azure/aks/use-trusted-launch)
  - Bicep property names for Secure Boot and vTPM
- [AKS node OS auto-upgrade channels](https://learn.microsoft.com/azure/aks/auto-upgrade-node-os-image)
  - `NodeImage` whole-VHD servicing behavior
- [AKS `2026-04-01` API schema](https://github.com/Azure/azure-rest-api-specs/blob/main/specification/containerservice/resource-manager/Microsoft.ContainerService/aks/stable/2026-04-01/managedClusters.json)
  - `AzureContainerLinux`, agent-pool security properties, and upgrade profile

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

## Architecture and defaults

The resource-group-scoped [`main.bicep`](./main.bicep) creates one
system-assigned-identity AKS 1.34 cluster with a single system-pool node. The
pool sets:

- `osSKU` to `AzureContainerLinux`;
- `securityProfile.enableSecureBoot` and `securityProfile.enableVTPM` to
  `true`;
- the node OS upgrade channel to `NodeImage`; and
- the VM size to Generation 2-capable `Standard_D2s_v5` by default.

The stable `Microsoft.ContainerService/managedClusters@2026-04-01` schema
defines these exact fields. `Standard_D2s_v5` is AMD64. To exercise ACL's Arm64
support, select the Cobalt `Standard_D2pds_v6` option.

Canada Central is the default location; both offered VM sizes have been used
successfully there.

## Requirements

- An Azure subscription and an existing resource group
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell
- [Just](https://just.systems/)
- The `diff` utility

Set the only required environment variable:

```bash
export RESOURCE_GROUP='<resource-group-name>'
cd cloud-native/aks-azure-container-linux
```

Running `just` with no arguments lists the recipes:

```console
$ just
Available recipes:
    aks-credentials # Get credentials for the AKS cluster.
    default
    deploy          # Deploy the Azure Container Linux AKS cluster at resource-group scope.
    node-images     # Show each node pool's running ACL image version.
    validate        # Check generated ARM and preview the deployment without changing Azure resources.
```

Preview the resource-group-scoped deployment without changing Azure:

```bash
just validate
```

Deploy the AMD64 default:

```bash
just deploy
```

Deploy an Arm64 system pool instead:

```bash
VM_SIZE=Standard_D2pds_v6 just deploy
```

## Observe weekly node images

After deployment, display the image actually running in each pool:

```bash
just node-images
```

The recipe runs:

```bash
az aks nodepool list \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-name "$AKS_NAME" \
  --query '[].{name:name,nodeImageVersion:nodeImageVersion}'
```

ACL image versions follow the AKS date-based format, for example:

```json
[
  {
    "name": "systempool",
    "nodeImageVersion": "AKSAzureContainerLinux-202606.01.0"
  }
]
```

Never delete a resource group when access is granted at resource-group scope,
because deleting it also destroys that scoped role assignment.
