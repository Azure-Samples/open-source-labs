# Lab snapshots

`main` carries the current labs. Labs on it are updated, retested, and sometimes
retired, so a lab read six months ago may not be the lab on `main` today, and a
lab that was there may be gone.

A snapshot branch freezes the whole collection at one commit. Workshop material,
a conference handout, or a template URL that pointed at a lab can keep working
against the snapshot after `main` has moved on.

Snapshot branches are named for the date they were cut, and are never rewritten
or force-pushed. `main` is the only branch that receives fixes.

## `2026-05-01`

[`2026-05-01`](https://github.com/Azure-Samples/open-source-labs/tree/2026-05-01)
is the collection as it stood before the update, test, and clean-up pass tracked
in [#63](https://github.com/Azure-Samples/open-source-labs/issues/63) and merged
as [#64](https://github.com/Azure-Samples/open-source-labs/pull/64). It sits at
commit `23003bab`, which is the parent of the merge on `main`, so nothing was
lost in cutting it.

The two differ by 196 files: 64 added, 62 deleted, 68 modified, 2 renamed. Most
labs are on both branches in different states. Four are only on the snapshot:

| Lab on `2026-05-01` only |
| --- |
| `cloud-native/aks-https` |
| `cloud-native/aks-open-service-mesh-terraform` |
| `linux/vm-mariner` |
| `linux/vm-mastodon` |

Four labs are new on `main` and are not on the snapshot: `cloud-native/aks-avm`,
`cloud-native/aks-azure-container-linux`, `cloud-native/aks-https-gateway`, and
`linux/vm-azure-linux`.

## Reading a snapshot

Clone the branch on its own:

```bash
git clone --branch 2026-05-01 https://github.com/Azure-Samples/open-source-labs.git
```

Or switch to it in an existing clone:

```bash
git fetch origin 2026-05-01
git switch 2026-05-01
```

## Deploying from a snapshot

**Template URLs in the labs are pinned to `main`, including the ones on the
snapshot's own pages.** They take the form:

```
https://raw.githubusercontent.com/Azure-Samples/open-source-labs/main/<path>
```

GitHub serves that URL from whatever `main` holds now, so it follows `main`
rather than the branch the page was read on. Following a `Deploy to Azure`
button or an `az deployment group create --template-uri` command from the
snapshot deploys the current template, not the one the snapshot describes. Where
the two have diverged, the deployment will not match the surrounding
instructions. `linux/vm-tailscale/vm.json`, the one lab on `2026-05-01` that
publishes deployment URLs, is one of the templates that changed.

To deploy what the snapshot holds, replace the `main` path segment with the
branch name:

```
https://raw.githubusercontent.com/Azure-Samples/open-source-labs/2026-05-01/linux/vm-tailscale/vm.json
```

A `Deploy to Azure` button is that same URL percent-encoded after
`https://portal.azure.com/#create/Microsoft.Template/uri/`, so the substitution
there is `%2Fmain%2F` to `%2F2026-05-01%2F`:

```
https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure-Samples%2Fopen-source-labs%2F2026-05-01%2Flinux%2Fvm-tailscale%2Fvm.json
```

`linux/vm/PORTAL.md` and `cloud-native/containerapps-bicep/PORTAL.md` show how
the encoded URL is built from a template URL.

For the four labs above that are only on the snapshot, this substitution is not
optional. Their paths under `main` now return 404, so any bookmarked raw URL or
button that still points at `main` is already broken.

## What a snapshot does not get

A snapshot is frozen. It receives no updates, no fixes, and no API version
bumps, and the validation described in [AGENTS.md](../AGENTS.md) is run against
`main`. Use a snapshot to reproduce a lab as it was, and `main` for a lab to
build on.
