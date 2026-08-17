# Kubeflow on Azure Kubernetes Service

This lab deploys the Kubeflow community distribution on Azure Kubernetes
Service (AKS) from a pinned, checksummed release. Bicep is the cluster source of
truth, a small Kustomize overlay configures public HTTPS on Kubeflow's existing
Istio gateway, and Dex credentials are generated only at deployment time.

## Architecture and versions

`main.bicep` creates one Free-tier AKS cluster with a system-assigned identity,
Kubernetes RBAC, Azure CNI Overlay, Azure network policy, and a Standard load
balancer. Its system pool has two AMD64 `Standard_D4s_v6` nodes running Azure
Linux 3 through the unversioned `AzureLinux` OS SKU. Kubernetes upgrades are
disabled while node-image upgrades remain enabled.

The Kubeflow `26.03.1` `example` installation is downloaded from
[`kubeflow/community-distribution`](https://github.com/kubeflow/community-distribution/releases/tag/26.03.1),
verified with SHA-256, and rendered with the lab's `overlay/`. The overlay keeps
Kubeflow's Istio ingress and Dex authentication, uses cert-manager for a
publicly trusted ECDSA certificate, and exposes only HTTPS dashboard traffic.
Port 80 is reserved for temporary ACME HTTP-01 challenge Ingresses and otherwise
returns 404.

| Component | Version or requirement |
| --- | --- |
| AKS Kubernetes | `1.36` |
| Kubeflow community distribution | `26.03.1` |
| cert-manager | `1.20.2` |
| Istio | `1.30.1` |
| Bicep CLI | `0.46.1` |
| kubectl | `v1.35.x` through `v1.37.x` |
| Kustomize | `v5.8.1` |
| Go language / toolchain | `1.26.0` / `go1.26.6` |

The kubectl range follows the Kubernetes
[version-skew policy](https://kubernetes.io/releases/version-skew-policy/#kubectl):
the client may be one minor version older or newer than the `1.36` API server,
and its patch version does not need to match.

The two nodes provide 8 vCPU and 32 GiB total. The recorded East US Linux
consumption price is US$0.202 per node-hour, or US$0.404 per hour for compute.
Allow approximately US$0.50 per hour after managed disks and the Standard load
balancer; verify current regional pricing before deployment.

## Prerequisites

- An Azure subscription, an existing resource group, and an authenticated
  [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli).
- Bash, [just](https://just.systems/), `curl`, `tar`, `sha256sum`, and
  [lychee](https://github.com/lycheeverse/lychee).
- Bicep CLI `0.46.1`, kubectl `v1.35.x` through `v1.37.x`, Kustomize `v5.8.1`,
  and Go with the `go1.26.6` toolchain available.
- Permission to preview and deploy resources in the existing resource group.

`RESOURCE_GROUP` is the only required setting. `LOCATION` defaults to `eastus`
and `AKS_NAME` defaults to `aks-kubeflow`. `DOMAIN` and `DNS_LABEL` are optional
and default to empty. The Dex issuer, login URL, OAuth2 redirect URI, and
Kubeflow hostname are derived values, not independent settings.

> **Phase 4 checkpoint:** This phase establishes the final recipe and
> documentation contract but does not implement Phase 6's deployment-output
> lookup or custom-domain DNS instruction output. Do not run the deployment
> sequence from this checkpoint. Phase 5 adds only a non-mutating Azure
> what-if; Phase 6 makes the documented deployment paths operational.

## Recipes

```console
Available recipes:
    clean-cache     # Remove the downloaded and extracted Kubeflow release.
    credentials     # Get administrator credentials for the AKS cluster.
    default
    deploy-aks      # Deploy the AKS cluster at resource-group scope.
    deploy-kubeflow # Install pinned Kubeflow and configure runtime Dex credentials.
    e2e             # Check the public HTTPS endpoint with trusted TLS.
    fetch-kubeflow  # Download, verify, and prepare the pinned Kubeflow release.
    group-empty     # Empty the resource group while preserving it and its scoped access.
    password        # Generate a 32-character password and its cost-12 bcrypt hash.
    validate        # Run static validation and preview the AKS deployment.
    validate-static # Run local version, source, manifest, test, and link checks.
    wait-ready      # Wait for every Kubeflow pod to become ready.
```

`just validate-static` needs no Azure account or cluster. It checks exact
versions for reproducibility-sensitive tools, kubectl's supported client/server
skew, generated ARM bytes, the Go module and tests, the upstream checksum,
rendered version, credential, TLS, and hostname invariants, README links, and
the public recipe contract. `just validate` runs those checks first and then
requires `RESOURCE_GROUP` for a non-mutating resource-group-scope Bicep what-if.

## Deploy

The default sequence is:

```bash
export RESOURCE_GROUP='<existing-resource-group>'
just validate
just deploy-aks
just credentials
just deploy-kubeflow
just wait-ready
just e2e
just group-empty
```

`deploy-kubeflow` applies the pinned upstream release with server-side apply and
a bounded retry loop. It generates a 32-character password and cost-12 bcrypt
hash, replaces the unusable rendered Dex sentinel through
`Secret/dex-passwords`, restarts Dex, and prints the username, password, and
HTTPS URL once. It does not write credentials to a file. Save the printed
password in an appropriate secret manager if the deployment must outlive the
terminal session.

`wait-ready` performs bounded pod readiness checks. `e2e` reads the selected
hostname from `Certificate/kubeflow-tls` and requires the public endpoint to
respond over HTTPS with normal CA verification.

## Select the HTTPS endpoint

With both optional variables empty, the deployment uses the deterministic
Bicep output:

```bash
unset DOMAIN DNS_LABEL
```

To choose the Azure public-IP label, set `DNS_LABEL` to 1-63 lower-case letters,
digits, or hyphens. The endpoint becomes
`<label>.<region>.cloudapp.azure.com`:

```bash
export DNS_LABEL='my-kubeflow'
```

To use a reader-owned lower-case FQDN, set `DOMAIN`. `DNS_LABEL` may also select
its Azure CNAME target:

```bash
export DOMAIN='kubeflow.example.com'
export DNS_LABEL='my-kubeflow'
```

In the Phase 6 implementation, run through `just deploy-kubeflow`, then create
the unproxied DNS record it prints before continuing with `just wait-ready`.
Prefer:

```text
kubeflow.example.com CNAME my-kubeflow.eastus.cloudapp.azure.com
```

An A record to the printed ingress IP is supported, but it can become stale if
Azure replaces that IP. At that phase boundary, `deploy-kubeflow` returns while
certificate issuance is pending so the DNS record can be created and allowed
to resolve publicly.

The record must send `/.well-known/acme-challenge/` on port 80 directly to the
Istio ingress. Do not put it behind a proxy or provider-side forced HTTPS:
Let's Encrypt normally renews a 90-day certificate after roughly 60 days, and
an interception added later can leave a working deployment unable to renew.
The certificate contains only `DOMAIN`, never the Azure alias target.

## Cleanup

`just group-empty` removes resources with a Complete-mode empty deployment but
preserves the resource group and role assignments scoped to it. It waits ten
seconds before acting. Review `RESOURCE_GROUP` carefully; never delete the
resource group.
