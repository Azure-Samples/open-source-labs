# Serve an AKS application over automatic HTTPS with Gateway API

This lab deploys an Azure Kubernetes Service (AKS) cluster and serves a maintained HTTP echo application through [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/). It replaces the old three-part Application Gateway Ingress Controller walkthrough with one Bicep deployment and one in-cluster installation command.

The traffic layer is [Envoy Gateway](https://gateway.envoyproxy.io/) 1.9.0. Envoy Gateway is a current, maintained Gateway API implementation and its `ClientTrafficPolicy` provides a supported TLS minimum-version setting, which this lab fixes at TLS 1.3. HTTP requests receive a permanent redirect to HTTPS.

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-students))
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) 2.86.0 or later
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/get-started), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Just](https://just.systems/) (`brew install just`, or see the [install guide](https://just.systems/man/en/packages.html))
- The `diff` utility
- An existing resource group
- For publicly trusted TLS only: a domain delegated to an existing public Azure DNS zone in the same subscription, plus permission to deploy and create role assignments in the zone's resource group

Local `kubectl`, Helm, cluster credentials, and network access to the Kubernetes API aren't required. [`az aks command invoke`](https://learn.microsoft.com/cli/azure/aks/command#az-aks-command-invoke) supplies `kubectl` and Helm inside the cluster.

## Instructions

Login to Azure and change to this directory.

```bash
az login
cd cloud-native/aks-https-gateway
```

Set the only required variable. The resource group must already exist.

```bash
export RESOURCE_GROUP='my-existing-resource-group'
```

Running `just` lists the available recipes.

```console
$ just
Available recipes:
    default
    deploy      # Deploy AKS, then install the complete HTTPS application stack in one run-command.
    group-empty # Empty the resource group while preserving the group and its scoped access.
    validate    # Check generated ARM and preview the deployment without changing resources.
```

### Choose a certificate path

The path is selected from optional environment variables:

| Path | Configuration | Result |
| --- | --- | --- |
| Self-signed fallback | Leave `DOMAIN` and `DNS_ZONE_NAME` empty | The lab completes with HTTPS at `aks-https.local`. The certificate is **not publicly trusted**; use the printed `curl --insecure --resolve ...` command. |
| Let's Encrypt | Set `DOMAIN` to the application hostname and `DNS_ZONE_NAME` to its authoritative public Azure DNS zone | ExternalDNS creates the application record. cert-manager completes a DNS-01 challenge and renews the publicly trusted certificate automatically. |

For example, if Azure DNS hosts `example.com`:

```bash
export DOMAIN='echo.example.com'
export DNS_ZONE_NAME='example.com'

# Only needed when the zone is in another resource group.
export DNS_ZONE_RESOURCE_GROUP='dns-resource-group'

# Optional ACME account contact.
export ACME_EMAIL='you@example.com'
```

The domain must already be delegated to the Azure DNS name servers. The lab uses the supplied zone; it doesn't register a domain or change registrar delegation.

### Preview

`validate` builds fresh ARM JSON from [main.bicep](./main.bicep) and [dns-rbac.bicep](./dns-rbac.bicep), requires empty diffs from the committed JSON files, and then requests a resource-group-scoped Azure what-if preview.

```bash
just validate
```

### Deploy

```bash
just deploy
```

This is one ARM deployment followed by one `az aks command invoke`. The deployment creates AKS, the managed identity, federated credentials, and conditional Azure DNS RBAC. The run-command installs Envoy Gateway 1.9.0, cert-manager 1.21.1, optional ExternalDNS 0.21.0, the issuer, the application, the Gateway, and both routes. It waits for the certificate and Gateway, then prints the endpoint and test commands.

A Bicep `deploymentScripts` resource is deliberately not used. It would add a script identity, storage resources, and log-retention lifecycle to the ARM deployment while still depending on the new cluster becoming ready and having outbound registry access. A single explicit AKS run-command keeps those Kubernetes concerns in-cluster, needs no local credentials, is retryable, and remains the only follow-up command.

## What gets deployed

- AKS with Azure Linux 3, OIDC issuer, and workload identity enabled
- Envoy Gateway 1.9.0 and Gateway API resources
- cert-manager 1.21.1 with automatic renewal
- `mendhak/http-https-echo:41`, a maintained, non-root HTTP echo image published in June 2026, replacing the retired Azure Vote and Redis images
- An HTTP listener and `RequestRedirect` route that send clients to HTTPS
- An HTTPS listener whose certificate Secret is generated by cert-manager and referenced by the Gateway
- An Envoy `ClientTrafficPolicy` that permits TLS 1.3 only

The Let's Encrypt path creates one user-assigned identity with `DNS Zone Contributor` on the supplied zone. Its federated credential trusts only `system:serviceaccount:cert-manager:cert-manager`; cert-manager's controller pod is labeled for workload identity and its service account is annotated with the identity client ID. No client secret is created or stored in Kubernetes. A second federated credential for `system:serviceaccount:external-dns:external-dns` lets ExternalDNS publish the Gateway address using the same narrowly scoped identity.

Both certificate paths request an ECDSA P-256 private key with rotation enabled. The Let's Encrypt `ClusterIssuer` uses Azure DNS DNS-01 and the production ACME directory. The fallback uses a self-signed `ClusterIssuer`. In both cases, Gateway annotations make cert-manager create and renew the `Certificate`; the lab never hand-creates a TLS Secret.

## Why not the AKS application-routing Istio Gateway

`az aks approuting gateway istio enable` is available as a GA **core** command in stock Azure CLI 2.86.0 and later; the `aks-preview` extension is not required. This was checked with Azure CLI 2.89.0 in a clean `AZURE_CONFIG_DIR` while `AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no`. The same command was also checked with `aks-preview` 21.0.0b15 installed: that extension overrides the core command and adds a custom header for a separate preview feature, but the base command remains in core.

The managed Istio implementation wasn't selected because it can't enforce this lab's TLS 1.3 minimum through a supported API. Its Gateway listener conversion supports certificate references and cipher suites, but no minimum protocol version; the ingress-only add-on also doesn't support Istio CRDs such as `EnvoyFilter`. Managed NGINX wasn't used as a fallback because upstream maintenance ended in March 2026 and Azure support ends in November 2026. Envoy Gateway retains Gateway API while providing the required listener policy on a current stack.

## Empty the resource group

Never delete a resource group when your Azure access is assigned at resource-group scope. Empty it instead so the group and its role assignments remain.

```bash
just group-empty
```
