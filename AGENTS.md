# Working on a lab

This file contains the repository-level operational rules for changing a lab.

## Generated ARM and validation

- Bicep is the source of truth. Never hand-edit generated ARM JSON. Change the
  `.bicep`, run `az bicep build --file <file>.bicep`, and commit the source and
  generated output together.
- Generated JSON must end with a trailing newline. `az bicep build` emits one,
  and `validate` compares bytes; losing it can make every ARM comparison fail
  even when a multi-command recipe ultimately exits zero.
- Compare every source/output pair with a fresh build. Use strict shell mode in
  multi-file recipes so an early failed `diff` cannot be hidden by a later
  success. `linux/vm/empty.json` has no Bicep source; do not invent a pairing.
- `validate` must not mutate Azure. Require an existing `RESOURCE_GROUP` and use
  `az deployment group what-if`; never fall back to subscription scope. This
  also works under least privilege: contributors often have credentials scoped
  to one resource group, for which a subscription-scope preview fails with an
  authorization error.
- Read command output rather than trusting only the exit code. For example,
  `go test ./...` succeeds when a module has no tests. Retain `go vet ./...` so
  the package must compile, and claim `go-test` only when at least one test ran.

## Documentation contract

- Generated ARM comparisons and Azure previews verify templates, not the prose
  beside them. Re-read a lab's README whenever its Justfile, template, or
  variables change; treat a stale claim as a defect, not untidiness.
- Run `just --list` in the lab and make its README recipe listing match the
  output. When a recipe, file, or lab is removed or renamed, remove or update
  every reference to it.
- Match image publisher, offer, SKU, versions, sizes, and API versions quoted in
  prose to the template values actually deployed.
- From the repository root, run
  `lychee --include-fragments '**/*.md'` and fix every relative link, including
  anchors into headings in other documents.

## Azure safety

- Export `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` before any `az` command that
  touches Bicep. Lab Justfiles must export it too.
- Validate against an existing resource group that you are authorized to use.
- Never delete a resource group to clean up a lab. Empty its resources while
  preserving the group and its role assignments, so a group provisioned by
  someone else and access granted at group scope both survive. Use
  `just group-empty` in labs that provide it; otherwise use an equivalent
  resource cleanup mechanism that leaves the group itself intact.

## Justfile contract

- Keep `default:` as the first recipe and make it run `@just --list`. Indent
  recipe bodies with four spaces and declare configurable values with
  `env_var_or_default`.
- `RESOURCE_GROUP` is the only standard setting a reader should need for
  validation. Credential-specific labs may expose explicit credential
  variables, but must reject incomplete combinations rather than silently
  weakening validation.
- Keep `validate` non-mutating and meaningful. Put daemon-dependent work such as
  container builds in a separate recipe when it is not part of the validation
  bar.

## Terraform

- Use pessimistic provider constraints such as `~> 5.0` in Terraform source.
  Exact versions belong in `.terraform.lock.hcl`; never use an exact `=`
  constraint or edit the lock by hand.
- After any provider change, update the lock for every supported platform so it
  does not narrow to whichever architecture last ran:

  ```bash
  terraform init -upgrade
  terraform providers lock \
      -platform=linux_amd64 \
      -platform=linux_arm64 \
      -platform=darwin_amd64 \
      -platform=darwin_arm64
  ```

- Do not weaken `validate`: retain `init -lockfile=readonly`, `fmt -check`,
  `terraform validate`, and the non-mutating plan.

## Container images

- Pin static base and workload images as a readable tag plus immutable digest.
  Prefer the OCI image-index digest, not a single-platform manifest digest, so
  the same reference resolves on both amd64 and arm64.
- Treat architecture as functional behavior. Some labs use arm64 node pools;
  an amd64-only image remains pending because it cannot schedule.

## Freshness ledger

- [`labs.json`](labs.json) records evidence that actually ran. `method` is
  successful tokens joined by `+`; `required` is the minimum bar. The accepted
  vocabulary and ranking are enforced by
  [`scripts/lab-freshness.sh`](scripts/lab-freshness.sh).
- Record a method only after running its command and reading successful output.
  Never infer evidence from a recipe or copy another lab's method.
- Record evidence from the repository root with the positional
  [`Justfile`](Justfile) recipe:

  ```bash
  just validated '<lab-path>' '<method>' '<validator>'
  ```

  Do not pass `by=<name>`; that records the literal string `by=<name>`.
- A `blocked` entry explains a gap but does not satisfy it. Blocked,
  insufficient, inferred, changed, and ageing labs still fail
  `just index-check`.
