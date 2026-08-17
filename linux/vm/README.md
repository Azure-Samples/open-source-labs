# Linux on Azure with Bicep/ARM and Virtual Machines (VM)

## Azure Portal

Use the following link to deploy the template in this repo using the Azure Portal:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure-Samples%2Fopen-source-labs%2Fmain%2Flinux%2Fvm%2Fvm.json)

The "Deploy to Azure" button above can be the fastest way to get up and running with no local dependencies.

You can see how this link is generated in [PORTAL.md](PORTAL.md). It uses the [vm.json](vm.json) ARM (Azure Resource Manager) template, generated from the [vm.bicep](vm.bicep) Bicep template using the `az bicep build -f vm.bicep` command.

Deploying via the command line, which deploys the Bicep template directly, enables you to easily customize it to your requirements, install the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) and follow the steps below. These examples require a Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/get-started), or [GitHub Codespaces](https://github.com/features/codespaces)).

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/get-started), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Just](https://just.systems/) (`brew install just`, or see the [install guide](https://just.systems/man/en/packages.html))
- The `diff` utility
- [jq](https://jqlang.github.io/jq/download/)
- The `dig` DNS lookup utility

## Cloud-init

This template uses [cloud-init](https://cloudinit.readthedocs.io/en/latest/), _the industry standard multi-distribution method for cross-platform cloud instance initialization_.

There are multiple pre-defined cloud-init templates included in `vm.bicep` which can be selected via the `cloudInit` parameter. These can help you create your own `cloud-init` scripts. We also include an `env` parameter that enables you to pass data to your `cloud-init` scripts in JSON format (default: `{}`).

The current pre-defined cloud-init options are:

### `none`

Do not run any cloud-init script (default).

### `docker`

Installs [docker](https://docs.docker.com/engine/install/ubuntu/) for containers and [jq](https://stedolan.github.io/jq/) for working with JSON such as our `env` parameter. This is defined in the `packages` module of our cloud-init. We use `groups` and `system_info` to add the default user to the docker group. See variable `cloudInitDocker` in [vm.bicep](vm.bicep).

This template is used as the foundation for other templates such as `tailscale` and is an excellent starting point for your own cloud-init scripts.

### `tailscale`

This package uses the `write_files` and `run_cmd` modules to write the `env` parameter (`{"tskey":"..."}`) to `/home/azureuser/env.json` function), and our setup script to `/home/azureuser/tailscale.sh`. The `env` variable is embedded in the template using Bicep's [format](https://learn.microsoft.com/azure/azure-resource-manager/bicep/bicep-functions-string#format) function. The `tskey` value is extracted using `jq` and the script completes by echoing the current date to `/home/azureuser/hello.txt`. See variable `cloudInitTailscale` in [vm.bicep](vm.bicep).

You must generate a Tailscale [Auth key](https://tailscale.com/kb/1085/auth-keys/) via <https://login.tailscale.com/admin/settings/keys> prior to running this script. We recommend using a **one-off** key for this purpose, especially if you are not using [device authorization](https://tailscale.com/kb/1099/device-authorization/).

Tailscale is deployed with [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh/) enabled using the `--ssh` flag. This enables you to SSH into the VM seamlessly, without ever opening up SSH to the public internet or handling SSH keys, via `ssh azureuser@vm1` (if you have [MagicDNS](https://tailscale.com/kb/1081/magicdns/) enabled), or by its [stable IP address](https://tailscale.com/kb/1033/ip-and-dns-addresses/) on the tailnet using `ssh azureuser@<ip address>` (if MagicDNS is not enabled). You can learn more about [Tailscale on Azure VMs](https://tailscale.com/kb/1142/cloud-azure-linux/) in the Tailscale docs.

### `tailscale-private`

This template deployment is nearly identical to the tailscale deployment above, but the VM has no public IP address. The network security group retains the UDP port 41641 rule used by Tailscale. It is advisable that you configure MagicDNS so that you can ssh in to the server using just the VM name.

### `tailscale-postgres`

tailscale-postgres deploys docker, tailscale, and postgres using its [official docker image](https://hub.docker.com/_/postgres/), as a final step, using the following command:

```bash
docker run \
    --name postgres \
    --restart always \
    -e POSTGRES_HOST_AUTH_METHOD=trust \
    -v /home/azureuser/postgresql/data:/var/lib/postgresql/data \
    -p 5432:5432 \
    -d postgres:14
```

This command mounts the postgres data directory to `/home/azureuser/postgresql/data` for persistence. The `POSTGRES_HOST_AUTH_METHOD=trust` will let you login to the server using the `postgres` user and no password (for test/dev and non-prod deployments **only**). Do not open port `5432` to the public internet under any circumstances.

Postgres will be available on port `5432` to any machine on your Tailscale tailnet, via the following command:

```bash
psql --host=vm1 --username=postgres
```

### url

This is an example of running a simple bash script by its URL using `#include`. It is currently hard-coded to [cloud-init/cloud-init.sh](cloud-init/cloud-init.sh), but could easily be parameterized. See variable `cloudInitUrl` in [vm.bicep](vm.bicep).

## Create Resource Group

```bash
RESOURCE_GROUP='220700-azure-linux'
LOCATION='eastus'

az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION
```

## Create Virtual Machine (VM)

### Option 1: Basic

Deploy the template with default values.

```bash
RESOURCE_GROUP='220700-azure-linux'

az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file vm.bicep
```

This template includes defaults for all values including `allowIpPort22`, set to `127.0.0.1`, and a temporary default public SSH key for `adminPasswordOrKey`, which should be set to your own value in production. This allows the template to be deployed in a single click or CLI command.

### Option 2: Advanced

Set an SSH key using `adminPasswordOrKey` and open Port 22 (SSH) to your current IP using `allowIpPort22`.

```bash
RESOURCE_GROUP='220700-azure-linux'
PASSWORD_OR_KEY="$(cat ~/.ssh/id_rsa.pub)"
IP_ALLOW=$(dig @1.1.1.1 ch txt whoami.cloudflare +short | tr -d '"')

OUTPUT=$(az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file vm.bicep \
    --parameters \
        adminPasswordOrKey="$PASSWORD_OR_KEY" \
        allowIpPort22="$IP_ALLOW")

echo $OUTPUT | jq -r '.properties.outputs.sshCommand.value'
```

[Azure Bastion](https://learn.microsoft.com/azure/bastion/tutorial-create-host-portal#createhost) is an alternative to allowing access to Port 22 (SSH) on a single IP address. You can find the command to connect using the [native client](https://learn.microsoft.com/azure/bastion/connect-native-client-windows) via the `az network bastion ssh` command in [BASTION.md](BASTION.md).

### Option 3: Advanced with tailscale

Create a VM with a custom name (e.g. `vm1` vs `vm2`) using `vmName`, which enables it to be deployed in the same Resource Group as a previous VM, select `tailscale` as the `cloudInit` option and pass in the `tskey` using `env`.

```bash
# first create a file env.json using heredoc syntax
# make sure to replace <YOUR_TAILSCALE_AUTH_KEY> with your actual auth key
cat << EOF > env.json
{"tskey":"<YOUR_TAILSCALE_AUTH_KEY>"}
EOF

RESOURCE_GROUP='220700-azure-linux'
VM_NAME='tailscale-vm1'
ENV=$(cat env.json)

OUTPUT=$(az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file vm.bicep \
    --parameters \
        vmName="$VM_NAME" \
        cloudInit='tailscale' \
        env="$ENV")

echo $OUTPUT | jq -r '.properties.outputs.sshCommand.value'
```

### Option 4: Advanced with tailscale (no exposure to the internet)

Create a VM with a custom name (e.g. `vm1` vs `vm2`) using `vmName`, which enables it to be deployed in the same Resource Group as a previous VM, select `tailscale-private` as the `cloudInit` option and pass in the `tskey` using `env`.

```bash
# first create a file env.json using heredoc syntax
# make sure to replace <YOUR_TAILSCALE_AUTH_KEY> with your actual auth key
cat << EOF > env.json
{"tskey":"<YOUR_TAILSCALE_AUTH_KEY>"}
EOF

RESOURCE_GROUP='220700-azure-linux'
VM_NAME='tailscale-vm2'
ENV=$(cat env.json)

OUTPUT=$(az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file vm.bicep \
    --parameters \
        vmName="$VM_NAME" \
        cloudInit='tailscale-private' \
        env="$ENV")

echo $OUTPUT | jq -r '.properties.outputs.sshCommand.value'
```

### Option 5: Ampere Altra Arm–based VM SKUs

If you want to try any of the above deployment options using the new [Ampere Altra Arm64-based VM SKUs](https://azure.microsoft.com/en-us/blog/azure-virtual-machines-with-ampere-altra-arm-based-processors-generally-available/), pass in the necessary `osImage` and `vmSize` parameters below.

```bash
cat << EOF > env.json
{"tskey":"<YOUR_TAILSCALE_AUTH_KEY>"}
EOF

RESOURCE_GROUP='220900-azure-linux'
VM_NAME='arm1'
VM_SIZE='Standard_D2ps_v5'
ENV=$(cat env.json)

az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file vm.bicep \
    --parameters \
        vmName="$VM_NAME" \
        cloudInit='tailscale-private' \
        env="$ENV" \
        vmSize="$VM_SIZE" \
        osImage='Ubuntu 26.04-LTS (arm64)'
```

The `vmSize` parameter in the [vm.bicep](./vm.bicep) template accepts either `Standard_D2ps_v5` or `Standard_D4ps_v5` for Arm64 deployments.

When using either Arm64 SKU, you must make sure the `osImage` is set to `Ubuntu 26.04-LTS (arm64)` as this value selects the matching Arm64 OS image.

## Delete Resources

When you are finished you may wish to empty the entire Resource Group, which can be done quickly be deploying an empty ARM template, [empty.json](empty.json). This leaves the Resource Group in place and ready for another deployment.

```bash
# empty resource group
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file empty.json \
    --mode Complete
```

Alternatively, you may wish to simply re-deploy a specific VM in the Resource Group when performing a task such as testing a cloud-init configuration. In this case you can delete the specific virtual machine and its disk (leaving other resources in place), and re-deploy the original template.

```bash
# delete single vm and disk for re-deployment
VM_NAME='vm2'
az vm delete --yes --resource-group $RESOURCE_GROUP --name $VM_NAME
az disk delete --yes --resource-group $RESOURCE_GROUP --name "${VM_NAME}-osdisk1"
```
