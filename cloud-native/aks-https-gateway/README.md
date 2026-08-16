# Serve an AKS application over automatic HTTPS with Gateway API

This lab deploys an Azure Kubernetes Service (AKS) cluster and serves a maintained HTTP echo application through [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/). It replaces the old three-part Application Gateway Ingress Controller walkthrough with one Bicep deployment and in-cluster installation commands.

The traffic layer is [Envoy Gateway](https://gateway.envoyproxy.io/) 1.9.0. Envoy Gateway is a current, maintained Gateway API implementation and its `ClientTrafficPolicy` provides a supported TLS minimum-version setting, which this lab fixes at TLS 1.3. HTTP requests receive a permanent redirect to HTTPS, except that cert-manager's temporary HTTP-01 challenge route takes precedence when that certificate path is used.

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-students))
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) 2.86.0 or later
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/get-started), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Just](https://just.systems/) (`brew install just`, or see the [install guide](https://just.systems/man/en/packages.html))
- The `diff` utility
- An existing resource group
- For publicly trusted TLS: a domain you control. The preferred path uses an existing public Azure DNS zone in the same subscription and permission to deploy and create role assignments in its resource group. Other DNS providers can use the manual HTTP-01 path.

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
    deploy      # Deploy AKS, then install the HTTPS application stack.
    group-empty # Empty the resource group while preserving the group and its scoped access.
    validate    # Check generated ARM and preview the deployment without changing resources.
    wait-http01 # Wait for HTTP-01 certificate issuance after creating the printed public DNS record.
```

### Choose a certificate path

The path is selected from optional environment variables:

| Path | Configuration | Result |
| --- | --- | --- |
| Let's Encrypt with Azure DNS (preferred) | Set `DOMAIN` to the application hostname and `DNS_ZONE_NAME` to its authoritative public Azure DNS zone | ExternalDNS creates the application record. cert-manager completes a DNS-01 challenge with workload identity and renews the publicly trusted certificate automatically. |
| Let's Encrypt with other DNS hosting | Set `DOMAIN` and leave `DNS_ZONE_NAME` empty | The lab prints the Gateway address. You create one public A record, then run the bounded certificate wait while cert-manager completes an HTTP-01 challenge. No DNS provider credentials are created or configured. |
| Self-signed fallback | Leave `DOMAIN` and `DNS_ZONE_NAME` empty | The lab completes with HTTPS at `aks-https.local`. The certificate is **not publicly trusted**; use the printed `curl --insecure --resolve ...` command. |

For example, if Azure DNS hosts `example.com`, use the preferred DNS-01 path:

```bash
export DOMAIN='echo.example.com'
export DNS_ZONE_NAME='example.com'

# Only needed when the zone is in another resource group.
export DNS_ZONE_RESOURCE_GROUP='dns-resource-group'

# Optional ACME account contact.
export ACME_EMAIL='you@example.com'
```

The domain must already be delegated to the Azure DNS name servers. The lab uses the supplied zone; it doesn't register a domain or change registrar delegation.

If another provider hosts the zone, set only the application hostname:

```bash
export DOMAIN='echo.example.com'
unset DNS_ZONE_NAME

# Optional ACME account contact.
export ACME_EMAIL='you@example.com'
```

Do not create the A record yet: the target address doesn't exist until the Gateway is deployed. Run `just deploy`, copy the prominently printed `DOMAIN A ADDRESS` record into your DNS provider, wait for it to resolve publicly, and then run `just wait-http01`. cert-manager starts retrying as soon as the Gateway is created. The follow-up command states what record it is waiting on and waits at most 15 minutes for issuance; if it times out, it prints the checks to make before retrying instead of appearing to hang.

For Cloudflare, the A record must be **DNS only** (grey cloud), not proxied. A proxied record lets Cloudflare terminate the connection at its edge and can intercept the challenge. Disable Cloudflare's **Always Use HTTPS** for this hostname because it can redirect `/.well-known/acme-challenge/` before the request reaches the cluster. This configuration must remain compatible with HTTP-01: Let's Encrypt normally renews roughly every 60 days, so changing the record to proxied later can cause a silent renewal failure. If you need Cloudflare proxying, HTTP-01 is the wrong certificate path; configure a Cloudflare DNS-01 solver with provider credentials instead. This lab deliberately does not build that provider-specific path.

### Preview

`validate` builds fresh ARM JSON from [main.bicep](./main.bicep) and [dns-rbac.bicep](./dns-rbac.bicep), requires empty diffs from the committed JSON files, and then requests a resource-group-scoped Azure what-if preview.

```bash
just validate
```

### Deploy

```bash
just deploy
```

The Azure DNS and self-signed paths use one ARM deployment followed by one `az aks command invoke`. The deployment creates AKS and preserves the existing identity behavior for these paths; Azure DNS also receives its conditional federated credential and RBAC resources. The run-command installs Envoy Gateway 1.9.0, cert-manager 1.21.1, optional ExternalDNS 0.21.0, the issuer, the application, the Gateway, and both permanent routes. It waits for the certificate and Gateway, then prints the endpoint and test commands.

The external-DNS HTTP-01 path must be ordered differently. Its first run-command returns after the Gateway receives an address because `az aks command invoke` does not stream remote logs while a command is running; waiting inside that command would hide the address needed for the A record. After you create the printed record, `just wait-http01` starts a second run-command with a bounded certificate wait. cert-manager's temporary solver route is already present or retrying by then.

A Bicep `deploymentScripts` resource is deliberately not used. It would add a script identity, storage resources, and log-retention lifecycle to the ARM deployment while still depending on the new cluster becoming ready and having outbound registry access. Explicit AKS run-commands keep those Kubernetes concerns in-cluster, need no local credentials, and are retryable.

## What gets deployed

- AKS with Azure Linux 3, OIDC issuer, and workload identity enabled
- Envoy Gateway 1.9.0 and Gateway API resources
- cert-manager 1.21.1 with automatic renewal
- `mendhak/http-https-echo:41`, a maintained, non-root HTTP echo image published in June 2026, replacing the retired Azure Vote and Redis images
- An HTTP listener and `RequestRedirect` route that send clients to HTTPS
- An HTTPS listener whose certificate Secret is generated by cert-manager and referenced by the Gateway
- An Envoy `ClientTrafficPolicy` that permits TLS 1.3 only

The Azure DNS Let's Encrypt path creates one user-assigned identity with `DNS Zone Contributor` on the supplied zone. Its federated credential trusts only `system:serviceaccount:cert-manager:cert-manager`; cert-manager's controller pod is labeled for workload identity and its service account is annotated with the identity client ID. No client secret is created or stored in Kubernetes. A second federated credential for `system:serviceaccount:external-dns:external-dns` lets ExternalDNS publish the Gateway address using the same narrowly scoped identity. The HTTP-01 path creates none of these DNS identity resources and does not configure workload identity on cert-manager.

All three certificate paths request an ECDSA P-256 private key with rotation enabled. The preferred Let's Encrypt `ClusterIssuer` uses Azure DNS DNS-01 and the production ACME directory. The external-DNS issuer uses cert-manager 1.21.1's Gateway API schema `solvers[].http01.gatewayHTTPRoute.parentRefs` to attach its temporary `HTTPRoute` to the Gateway's port 80 listener. cert-manager generates an `Exact` match for `/.well-known/acme-challenge/<token>`; Gateway API gives that match precedence over the permanent redirect's explicit `PathPrefix: /`, so issuance and later renewal do not get redirected to HTTPS. The fallback uses a self-signed `ClusterIssuer`. In every case, Gateway annotations make cert-manager create and renew the `Certificate`; the lab never hand-creates a TLS Secret.

## Why not the AKS application-routing Istio Gateway

`az aks approuting gateway istio enable` is available as a GA **core** command in stock Azure CLI 2.86.0 and later; the `aks-preview` extension is not required. This was checked with Azure CLI 2.89.0 in a clean `AZURE_CONFIG_DIR` while `AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no`. The same command was also checked with `aks-preview` 21.0.0b15 installed: that extension overrides the core command and adds a custom header for a separate preview feature, but the base command remains in core.

The managed Istio implementation wasn't selected because it can't enforce this lab's TLS 1.3 minimum through a supported API. Its Gateway listener conversion supports certificate references and cipher suites, but no minimum protocol version; the ingress-only add-on also doesn't support Istio CRDs such as `EnvoyFilter`. Managed NGINX wasn't used as a fallback because upstream maintenance ended in March 2026 and Azure support ends in November 2026. Envoy Gateway retains Gateway API while providing the required listener policy on a current stack.

## Empty the resource group

Never delete a resource group when your Azure access is assigned at resource-group scope. Empty it instead so the group and its role assignments remain.

```bash
just group-empty
```
