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
Upstream's Istio ingress Gateway retains port 80 for temporary ACME HTTP-01
challenge Ingresses. The overlay excludes only
`/.well-known/acme-challenge/*` from Kubeflow's OAuth2 and JWT authorization
policies; all other unauthenticated HTTP requests remain denied, and no
dashboard route is served over HTTP.

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
- Bash, [just](https://just.systems/), `curl`, `tar`, `sha256sum`, `openssl`,
  `jq`, and [lychee](https://github.com/lycheeverse/lychee).
- Python 3 with the `venv` module. `just e2e` creates `.cache/e2e-venv` and
  installs the pinned `tests/requirements.txt` into it; nothing is installed
  system-wide.
- Bicep CLI `0.46.1`, kubectl `v1.35.x` through `v1.37.x`, Kustomize `v5.8.1`,
  and Go with the `go1.26.6` toolchain available.
- Permission to preview and deploy resources in the existing resource group.

`RESOURCE_GROUP` is the only required setting. `LOCATION` defaults to `eastus`
and `AKS_NAME` defaults to `aks-kubeflow`. `DOMAIN` and `DNS_LABEL` are optional
and default to empty. The Dex issuer, login URL, OAuth2 redirect URI, and
Kubeflow hostname are derived values, not independent settings.

## Recipes

```console
Available recipes:
    clean-cache     # Remove the downloaded and extracted Kubeflow release.
    configure-dex   # Generate and apply runtime Dex credentials, then restart authentication.
    credentials     # Get administrator credentials for the AKS cluster.
    default
    deploy-aks      # Deploy the AKS cluster at resource-group scope.
    deploy-kubeflow # Install pinned Kubeflow and configure its runtime Dex credentials.
    e2e             # Run the authenticated end-to-end release gate against the live deployment.
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
a bounded retry loop, then calls `configure-dex`. The independently runnable
`configure-dex` recipe generates a 32-character password and cost-12 bcrypt
hash, replaces the unusable rendered Dex sentinel through
`Secret/dex-passwords`, rejects incomplete or malformed hashes before updating
the Secret, restarts Dex, forces Istio to fetch the recovered Dex signing keys,
waits for oauth2-proxy readiness, and prints the generated values once.
`deploy-kubeflow` obtains the default DNS label, hostname, and
location from the completed Bicep deployment and waits for the Istio ingress
address. Neither recipe writes credentials to a file. Save the printed password
in an appropriate secret manager if the deployment must outlive the terminal
session.

Azure CLI versions have emitted deployment-output TSV as either one
tab-delimited record or one value per line. The recipe normalizes both forms
before validating the three required outputs.

Rendering the release produces one manifest stream, so applying it creates
application workloads in the same pass that creates the Istio control plane.
Deployments can therefore be created before `istiod` is serving and before the
sidecar injector webhook exists, which produces no admission error because at
that moment there is no webhook to fail. Those pods never receive a sidecar,
and nothing restarts them. After the apply loop succeeds, `deploy-kubeflow`
waits for `istiod` and restarts any workload in an injection-enabled namespace
whose pods have no `istio-proxy` and did not opt out.

`wait-ready` performs bounded pod readiness checks and then asserts that every
pod in an Istio-injection-enabled namespace either carries an `istio-proxy`
sidecar or explicitly opts out with `sidecar.istio.io/inject: "false"`. That
second check exists because readiness cannot detect a missed injection, and a
pod that missed one is Ready while every route to it through an `ISTIO_MUTUAL`
DestinationRule returns 503.

`e2e` is the release gate, described below. Pod readiness alone does not
establish that the lab works.

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

Run through `just deploy-kubeflow`, then create the unproxied DNS record it
prints before continuing with `just wait-ready`.
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
Only that path bypasses OAuth2 and JWT checks; all other unauthenticated HTTP
traffic is denied. The certificate contains only `DOMAIN`, never the Azure
alias target.

## The release gate

`just e2e` is the check that decides whether a deployment is good. It reads the
selected hostname from `Certificate/kubeflow-tls`, so the endpoint is derived
from the cluster rather than supplied. Setting `KUBEFLOW_ENDPOINT` is allowed
only as an assertion that you agree with the certificate: a value that
disagrees is rejected rather than used, so a stale shell cannot silently test
another host. `DEX_USERNAME` defaults to `user@example.com`. When `DEX_PASSWORD`
is unset the recipe prompts for it with terminal echo disabled.

`tests/e2e.py` is derived from upstream `tests/dex_login_test.py`, parameterized
by those three variables. Upstream runs against a port-forwarded Kind cluster
over plain HTTP; this gate always verifies TLS against the system CA bundle and
offers no way to turn that off. It authenticates through oauth2-proxy to Dex,
requires an `oauth2_proxy` session cookie and a final HTTPS response from the
same host, then proves the platform with one real user workload: it applies
`tests/notebook.yaml`, waits up to ten minutes for
`.status.readyReplicas == 1`, calls the notebooks API and the JupyterLab route
with the authenticated session, and deletes the Notebook in a `finally` block.
It prints exactly six markers:

```text
PASS trusted-tls
PASS dex-login
PASS dashboard
PASS notebook-controller
PASS notebook-api
PASS jupyterlab
```

The password and the session cookies are registered as secrets and scrubbed
from everything the test writes, on success and on every failure path.
`validate-static` enforces that: it rejects any bypass of TLS verification, and
requires that the only unscrubbed `print` calls are the two inside the scrubbing
helpers themselves.

`tests/notebook.yaml` is upstream's
`tests/notebook.test.kubeflow-user-example.com.yaml` with a workspace volume
added. Upstream's fixture declares no `volumeMounts`, and the Jupyter Web App's
list endpoint subscripts that field instead of treating it as optional, so
listing the Notebook it creates returns HTTP 500 and the gate cannot reach
`PASS notebook-api`. A workspace volume is also what the Jupyter interface
creates for a real notebook, so this exercises a more representative object.

`tests/e2e_selftest.py` covers the scrubbing, endpoint-identity, and marker
logic offline with the standard library alone, and runs as part of
`validate-static`. It needs no cluster, so a mistake in the parts that are
invisible in a passing run is caught before any deployment exists.

After the functional half, `e2e` forces certificate reissuance: it records the
serial on the wire, deletes `secret/kubeflow-tls`, waits for the Certificate to
go Ready, and requires a different serial plus a successful request. This is the
only way to establish that ACME HTTP-01 renewal traverses Istio under a given
network configuration; rendering the manifests cannot show it. Let's Encrypt
allows five [duplicate certificates](https://letsencrypt.org/docs/rate-limits/)
per week, which caps forced reissuance at five runs per week. Set
`E2E_SKIP_REISSUANCE=1` to run only the functional half.

This gate cannot run unattended in continuous integration when `DOMAIN` is set,
because that path has a manual DNS step in the middle of the deployment.

## Cleanup

`just group-empty` removes resources with a Complete-mode empty deployment but
preserves the resource group and role assignments scoped to it. It waits ten
seconds before acting. Review `RESOURCE_GROUP` carefully; never delete the
resource group.
