# Linux on Azure with Flatcar Linux and Azure Database for PostgreSQL

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure-Samples%2Fopen-source-labs%2Fmain%2Flinux%2Fvm-flatcar-postgres%2Fmain.json)

Before using the portal, accept the Flatcar Marketplace terms; the generated form also requires an SSH public key in `sshKey`.

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/get-started), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Just](https://just.systems/) (`brew install just`, or see the [install guide](https://just.systems/man/en/packages.html))
- [Butane](https://coreos.github.io/butane/) for regenerating `ignition.json`
- The `diff` utility
- The OpenSSH `ssh-keygen` utility

```console
$ just
Available recipes:
    accept-terms       # Accept the Flatcar VM image terms.
    bicep              # Inject ignition.json into vm.bicep.
    butane             # Generate ignition.json from cl.yaml.
    clean              # Remove files created during deployment.
    configure-postgres # Configure the PostgreSQL Entra administrator and firewall rule.
    default
    deploy-main        # Deploy main.bicep at subscription scope.
    deploy-postgres    # Deploy postgres.bicep and write connection settings to env.sh.
    deploy-vm          # Deploy vm.bicep at resource group scope.
    ensure-butane      # Install Butane v0.17.0 on Apple silicon macOS.
    env                # Print sample PostgreSQL environment variables.
    group-create       # Create the Azure resource group.
    group-empty        # Empty the resource group, leaving the group itself in place.
    password           # Print a securely generated password.
    psql-command       # Print the psql command from the PostgreSQL deployment.
    psql-docker        # Connect with psql through the latest PostgreSQL Docker image.
    ssh-command        # Print the SSH command from the VM deployment.
    tailscale-deploy   # Run Tailscale on the VM through Docker.
    tailscale-logs     # Print the Tailscale container logs.
    validate           # Check generated ARM and preview the deployment.
```

## Validate

Run `just validate` with `RESOURCE_GROUP` unset to check the generated ARM JSON and preview the subscription-scoped `main.bicep` deployment, including creation of its default resource group:

```bash
unset RESOURCE_GROUP
just validate
```

If your credentials are scoped to an existing resource group, set `RESOURCE_GROUP` instead. Validation uses that group's location and runs resource-group-scoped previews of `vm.bicep` and `postgres.bicep`, passing the same location, generated SSH key, and loopback firewall address as `main.bicep`. The VM preview uses ARM's `Template` validation level because checking the Flatcar Marketplace agreement requires subscription-scope access; Azure still performs the group-scoped what-if and returns the resource changes.

```bash
export RESOURCE_GROUP='<EXISTING_RESOURCE_GROUP_NAME>'
just validate
```

## Usage

The commands below create a resource group, empty it, deploy the VM and PostgreSQL, and configure PostgreSQL.

```console
export SSH_KEY=~/.ssh/id_rsa.pub
just group-create group-empty deploy-vm deploy-postgres configure-postgres
```
