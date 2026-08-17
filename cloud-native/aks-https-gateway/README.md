# Serve an AKS application over automatic HTTPS with Gateway API

This lab deploys an Azure Kubernetes Service (AKS) cluster and produces a publicly trusted HTTPS endpoint through [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/) with no domain, DNS records, or credentials to configure. Azure publishes a stable, deployment-specific `cloudapp.azure.com` hostname for the Gateway public IP, and cert-manager obtains and automatically renews a 90-day Let's Encrypt certificate.

The traffic layer is [Envoy Gateway](https://gateway.envoyproxy.io/) 1.9.0. Envoy Gateway is a current, maintained Gateway API implementation and its `ClientTrafficPolicy` provides a supported TLS minimum-version setting, which this lab fixes at TLS 1.3. HTTP requests receive a permanent redirect to HTTPS, except that cert-manager's temporary HTTP-01 challenge route takes precedence when that certificate path is used.

The workload is this repository's own `go-hello` Go server, pinned by OCI image-index digest and run on both published platforms, `linux/amd64` and `linux/arm64`. Append `/echo` to the HTTPS endpoint to inspect the method, path, headers, forwarded headers, and whether the connection from the Gateway to the origin used TLS:

```bash
curl https://<printed-hostname>/echo
```

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure-Samples%2Fopen-source-labs%2Fmain%2Fcloud-native%2Faks-https-gateway%2Fmain.json)

The button deploys the ARM portion of the lab; the manual instructions also install the in-cluster HTTPS application stack.

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-students))
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) 2.86.0 or later
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/get-started), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Just](https://just.systems/) (`brew install just`, or see the [install guide](https://just.systems/man/en/packages.html))
- The `diff` utility
- An existing resource group
- A domain is optional. The default trusted path uses an Azure-provided hostname. To use the Azure DNS DNS-01 path instead, provide a public Azure DNS zone in the same subscription and permission to deploy and create role assignments in its resource group.

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

With no certificate variables set, the lab uses its trusted zero-configuration path. Bicep derives `aks-https-<uniqueString>` from the resource-group ID, cluster name, and region. The 13-character `uniqueString` result makes the label unique across different deployment inputs and deterministic for the same deployment, so redeployments keep the same hostname.

The four paths, in order of preference, are:

| Path | Configuration | Result |
| --- | --- | --- |
| Let's Encrypt with an Azure-provided name (default) | Set no certificate variables. Optionally set `DNS_LABEL` to override the generated label. | Azure assigns `<label>.<region>.cloudapp.azure.com` to the Gateway public IP. cert-manager completes HTTP-01 without a domain, manually created record, or DNS provider credentials. |
| Let's Encrypt with Azure DNS | Set `DOMAIN` to the application hostname and `DNS_ZONE_NAME` to its authoritative public Azure DNS zone. `DNS_LABEL` is optional. | ExternalDNS creates the application record. cert-manager completes DNS-01 with workload identity and renews the publicly trusted certificate automatically. An optional label also gives the load balancer a stable Azure hostname. |
| Let's Encrypt with other DNS hosting | Set `DOMAIN`, leave `DNS_ZONE_NAME` empty, and set a unique `DNS_LABEL`. | The lab prints a stable Azure alias target. You create one public CNAME record, then run the bounded certificate wait while cert-manager completes HTTP-01. No DNS provider credentials are created or configured. |
| Explicit self-signed fallback | Set `SELF_SIGNED=true` and leave `DOMAIN` and `DNS_ZONE_NAME` empty. `DNS_LABEL` is optional. | The lab completes with HTTPS at `aks-https.local`. The certificate is **not publicly trusted**; use the printed `curl --insecure --resolve ...` command. |

`DOMAIN` selects the Gateway listener hostname and the certificate name: adding `DNS_ZONE_NAME` selects Azure DNS DNS-01, while `DOMAIN` alone selects manual-record HTTP-01. `DNS_LABEL` independently adds an Azure-managed name to the load balancer public IP. When both are set, the label never replaces `DOMAIN` in the listener or certificate.

`SELF_SIGNED=true` is exclusive of `DOMAIN` and `DNS_ZONE_NAME`, but may be combined with `DNS_LABEL`. A label is only a Service annotation, so excluding it would not improve certificate safety. The self-signed listener and certificate still use `aks-https.local`; the label merely gives the load balancer IP a stable Azure DNS name.

The default needs only the existing resource group:

```bash
unset DOMAIN DNS_ZONE_NAME DNS_LABEL SELF_SIGNED
just deploy
```

For example, if Azure DNS hosts `example.com`, use the DNS-01 path:

```bash
export DOMAIN='echo.example.com'
export DNS_ZONE_NAME='example.com'

# Only needed when the zone is in another resource group.
export DNS_ZONE_RESOURCE_GROUP='dns-resource-group'

# Optional ACME account contact.
export ACME_EMAIL='you@example.com'
```

The domain must already be delegated to the Azure DNS name servers. The lab uses the supplied zone; it doesn't register a domain or change registrar delegation.

If another provider hosts the zone, set the application hostname and a unique Azure DNS label:

```bash
export DOMAIN='echo.example.com'
unset DNS_ZONE_NAME
export DNS_LABEL='my-unique-aks-https-label'

# Optional ACME account contact.
export ACME_EMAIL='you@example.com'
```

Do not create the record yet: the Azure target doesn't exist until the Gateway is deployed. Run `just deploy`, then create the prominently printed record:

```dns
echo.example.com CNAME my-unique-aks-https-label.canadacentral.cloudapp.azure.com
```

Set `DOMAIN` to the hostname readers will use and `DNS_LABEL` to a unique label; create exactly one CNAME from `DOMAIN` to `<label>.<region>.cloudapp.azure.com`. This is preferable to an A record on the load balancer IP because Azure keeps its `cloudapp.azure.com` name pointed at the current public IP if that address changes. The Gateway listener and cert-manager certificate remain bound to `DOMAIN`, and ACME HTTP-01 follows the CNAME chain.

Wait for the CNAME to resolve publicly, and then run `just wait-http01`. cert-manager starts retrying as soon as the Gateway is created. The follow-up command states what record it is waiting on and waits at most 15 minutes for issuance; if it times out, it prints the checks to make before retrying instead of appearing to hang. Omitting `DNS_LABEL` remains supported, but then the deployment prints a raw Gateway IP for an A record.

For Cloudflare, the CNAME (or the A record when no label is used) must be **DNS only** (grey cloud), not proxied. A proxied record lets Cloudflare terminate the connection at its edge and can intercept the challenge. Disable Cloudflare's **Always Use HTTPS** for this hostname because it can redirect `/.well-known/acme-challenge/` before the request reaches the cluster. This configuration must remain compatible with HTTP-01: Let's Encrypt normally renews roughly every 60 days, so changing the record to proxied later can cause a silent renewal failure. If you need Cloudflare proxying, HTTP-01 is the wrong certificate path; configure a Cloudflare DNS-01 solver with provider credentials instead. This lab deliberately does not build that provider-specific path.

To choose the Azure-provided label instead of using the generated default, provide a value that is unique within the AKS region:

```bash
unset DOMAIN DNS_ZONE_NAME
export DNS_LABEL='my-unique-aks-https-label'
```

`DNS_LABEL` must contain 1-63 lowercase letters, digits, or hyphens and must start and end with a letter or digit. The lab combines it with the cluster's `LOCATION` (default `canadacentral`) to form `my-unique-aks-https-label.canadacentral.cloudapp.azure.com`. Envoy Gateway creates the Gateway's `LoadBalancer` Service, so the lab references a namespaced `EnvoyProxy` from the `GatewayClass` and uses `spec.provider.kubernetes.envoyService.annotations` to put `service.beta.kubernetes.io/azure-dns-label-name` on that generated Service. Azure then creates and hosts the public A record for its public IP. When no `DOMAIN` is set, there is no record to create manually and no `just wait-http01` follow-up; the deployment itself waits at most 15 minutes for the HTTP-01 certificate and reports a timeout clearly.

A real deployment with `DNS_LABEL=aks-https-cmbox-2608` in `canadacentral` observed all of the following:

- Azure automatically published `aks-https-cmbox-2608.canadacentral.cloudapp.azure.com` for the Gateway public IP; no DNS record was created by hand.
- Let's Encrypt issued a 90-day certificate with issuer `C=US, O=Let's Encrypt, CN=YE1` and subject CN `aks-https-cmbox-2608.canadacentral.cloudapp.azure.com`.
- `curl` without `--insecure` returned HTTP 200 with `ssl_verify_result=0`, confirming public trust.
- The connection negotiated TLS 1.3 with `TLS_AES_256_GCM_SHA384`; forcing TLS 1.2 was rejected with alert number 70.
- Plain HTTP returned 301 to the HTTPS URL. The ACME challenge still reached the cluster because cert-manager's `Exact` match on `/.well-known/acme-challenge/` takes precedence over the redirect route's `PathPrefix: /`.

cert-manager renews the 90-day certificate automatically through the same HTTP-01 path.

Use the self-signed fallback only when public DNS or ACME is intentionally unavailable, such as an air-gapped environment, a restricted subscription that cannot provide a public IP or Azure DNS label, or an environment where ACME issuance fails:

```bash
unset DOMAIN DNS_ZONE_NAME
export SELF_SIGNED='true'
```

### Preview

`validate` builds fresh ARM JSON from [main.bicep](./main.bicep) and [dns-rbac.bicep](./dns-rbac.bicep), requires empty diffs from the committed JSON files, and then requests a resource-group-scoped Azure what-if preview.

```bash
just validate
```

### Deploy

```bash
just deploy
```

The Azure DNS, Azure-provided DNS-label, and self-signed paths use one ARM deployment followed by one `az aks command invoke`. The deployment creates AKS; only the Azure DNS path creates the conditional federated credentials, identity, and RBAC resources it needs. The run-command installs Envoy Gateway 1.9.0, cert-manager 1.21.1, optional ExternalDNS 0.21.0, the issuer, the application, the Gateway, and both permanent routes. It waits for the certificate and Gateway, then prints the endpoint and test commands. The DNS-label-only path uses the same HTTP-01 solver as the manual-domain path, but Azure publishes the public-IP record automatically, so its bounded wait stays in the first run-command.

The manual-domain HTTP-01 path must be ordered differently. Its first run-command returns after the Gateway receives an address because `az aks command invoke` does not stream remote logs while a command is running; waiting inside that command would hide the A-record address or confirmation that the Azure CNAME target is active. After you create the printed A or CNAME record, `just wait-http01` starts a second run-command with a bounded certificate wait. cert-manager's temporary solver route is already present or retrying by then.

A Bicep `deploymentScripts` resource is deliberately not used. It would add a script identity, storage resources, and log-retention lifecycle to the ARM deployment while still depending on the new cluster becoming ready and having outbound registry access. Explicit AKS run-commands keep those Kubernetes concerns in-cluster, need no local credentials, and are retryable.

## What gets deployed

- AKS with Azure Linux 3, OIDC issuer, and workload identity enabled
- Envoy Gateway 1.9.0 and Gateway API resources
- cert-manager 1.21.1 with automatic renewal
- This repository's `go-hello` server from `ghcr.io/asw101/go-hello`, pinned by OCI image-index digest and run on both AMD64 and ARM64
- An HTTP listener and `RequestRedirect` route that send clients to HTTPS
- An HTTPS listener whose certificate Secret is generated by cert-manager and referenced by the Gateway
- An Envoy `ClientTrafficPolicy` that permits TLS 1.3 only

The Azure DNS Let's Encrypt path creates one user-assigned identity with `DNS Zone Contributor` on the supplied zone. Its federated credential trusts only `system:serviceaccount:cert-manager:cert-manager`; cert-manager's controller pod is labeled for workload identity and its service account is annotated with the identity client ID. No client secret is created or stored in Kubernetes. A second federated credential for `system:serviceaccount:external-dns:external-dns` lets ExternalDNS publish the Gateway address using the same narrowly scoped identity. The two HTTP-01 paths create none of these DNS identity resources and do not configure workload identity on cert-manager.

All four certificate paths request an ECDSA P-256 private key with rotation enabled. The Azure DNS Let's Encrypt `ClusterIssuer` uses DNS-01 and the production ACME directory. Both HTTP-01 paths use cert-manager 1.21.1's Gateway API schema `solvers[].http01.gatewayHTTPRoute.parentRefs` to attach its temporary `HTTPRoute` to the Gateway's port 80 listener. cert-manager generates an `Exact` match for `/.well-known/acme-challenge/<token>`; Gateway API gives that match precedence over the permanent redirect's explicit `PathPrefix: /`, so issuance and later renewal do not get redirected to HTTPS. The fallback uses a self-signed `ClusterIssuer`. In every case, Gateway annotations make cert-manager create and renew the `Certificate`; cert-manager copies the HTTPS listener hostname into the generated `Certificate.spec.dnsNames`, and the lab never hand-creates a TLS Secret.

## Why not the AKS application-routing Istio Gateway

`az aks approuting gateway istio enable` is available as a GA **core** command in stock Azure CLI 2.86.0 and later; the `aks-preview` extension is not required. This was checked with Azure CLI 2.89.0 in a clean `AZURE_CONFIG_DIR` while `AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no`. The same command was also checked with `aks-preview` 21.0.0b15 installed: that extension overrides the core command and adds a custom header for a separate preview feature, but the base command remains in core.

The managed Istio implementation wasn't selected because it can't enforce this lab's TLS 1.3 minimum through a supported API. Its Gateway listener conversion supports certificate references and cipher suites, but no minimum protocol version; the ingress-only add-on also doesn't support Istio CRDs such as `EnvoyFilter`. Managed NGINX wasn't used as a fallback because upstream maintenance ended in March 2026 and Azure support ends in November 2026. Envoy Gateway retains Gateway API while providing the required listener policy on a current stack.

## Empty the resource group

Never delete a resource group when your Azure access is assigned at resource-group scope. Empty it instead so the group and its role assignments remain.

```bash
just group-empty
```
