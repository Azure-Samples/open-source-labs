# Deploy a Scalable and Secure Azure Kubernetes Service cluster using the Azure CLI

Azure Kubernetes Service provides a powerful way to manage Kubernetes applications which are Portable, extensibile, and when combined with Azure infrastructure highly scalable. Part 1 of this tutorial covers steps in creating a basic web voting application. Parts 2 and 3 will show how to scale the application and add a custom domain which is secured via https.

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/quickstart), or [GitHub Codespaces](https://github.com/features/codespaces))
- [Helm](https://helm.sh/docs/intro/install/)
- envsubst (`pip3 install envsubst`)

## Setup

This tutorial will use bash variables. Set the following variables. 

```bash
RESOURCE_GROUP="my-aks"
LOCATION="eastus"
AKS_NAME="aks1"
```

Run the `login` command.

```bash
az login
```

After signing in, CLI commands are run against your default subscription. If you have multiple subscriptions, you can [change your default subscription](https://docs.microsoft.com/en-us/cli/azure/manage-azure-subscriptions-azure-cli).

## Create a Resource Group

An Azure resource group is a logical group in which Azure resources are deployed and managed. When you create a resource group, you are prompted to specify a location. This location is the storage location of your resource group metadata and where your resources will run in Azure if you don't specify another region during resource creation.

Validate resource group does not already exist. If it does, select a new resource group name by running the following:

```bash
if [ "$(az group exists --name $RESOURCE_GROUP)" = 'true' ]; then export RAND=$RANDOM; export RESOURCE_GROUP="$RESOURCE_GROUP$RAND"; echo "Your new Resource Group Name is $RESOURCE_GROUP"; fi
```

Create a resource group.

```bash
az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION
```

The following is output for successful resource group creation.

Results:

```expected_similarity=0.5
{
  "id": "/subscriptions/bb318642-28fd-482d-8d07-79182df07999/resourceGroups/testResourceGroup24763",
  "location": "eastus",
  "managedBy": null,
  "name": "testResourceGroup",
  "properties": {
    "provisioningState": "Succeeded"
  },
  "tags": null,
  "type": "Microsoft.Resources/resourceGroups"
}
```

## Create an AKS Cluster

Create an AKS cluster using the az aks create command with the --enable-addons monitoring parameter to enable Container insights. The following example creates a cluster named myAKSCluster with one node:

```bash
az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_NAME \
    --node-count 1 \
    --enable-addons monitoring \
    --generate-ssh-keys
```

## Connect to the cluster

To manage a Kubernetes cluster, use the Kubernetes command-line client, kubectl. kubectl is already installed if you use Azure Cloud Shell.

Install kubectl CLI locally using the az aks install-cli command.

```bash
az aks install-cli
```

> **Note** depending on your platform, you may need to run `sudo az aks install-cli` instead.

Configure kubectl to connect to your Kubernetes cluster using the `az aks get-credentials` command. 

```bash
az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_NAME \
    --overwrite-existing
```

This command downloads credentials and configures the Kubernetes CLI to use them. It uses ~/.kube/config, the default location for the Kubernetes configuration file. You can specify a different location for your Kubernetes configuration file using --file argument. 

> **Warning**
> This will overwrite any existing credentials with the same entry

Verify the connection to your cluster using the kubectl get command. This command returns a list of the cluster nodes.

```bash
kubectl get nodes
```

The following output example shows the single node created in the previous steps. Make sure the node status is Ready.

```
NAME                                STATUS   ROLES   AGE     VERSION
aks-nodepool1-26003523-vmss000000   Ready    agent   8m54s   v1.23.8
```

## Deploy the Application

A [Kubernetes manifest file](https://docs.microsoft.com/en-us/azure/aks/concepts-clusters-workloads#deployments-and-yaml-manifests) defines a cluster's desired state, such as which container images to run.

In this quickstart, you will use a manifest to create all objects needed to run the [Azure Vote application](https://github.com/Azure-Samples/azure-voting-app-redis). This manifest includes two Kubernetes deployments:

- The sample Azure Vote Python applications.
- A Redis instance.

Two [Kubernetes Services](https://docs.microsoft.com/en-us/azure/aks/concepts-network#services) are also created:

- An internal service for the Redis instance.
- An external service to access the Azure Vote application from the internet.

Create a file named `azure-vote-start.yaml` and copy in the following manifest.

If you use the Azure Cloud Shell, this file can be created using `code`, `vi`, or `nano` as if working on a virtual or physical system.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: azure-vote-back
spec:
  replicas: 1
  selector:
    matchLabels:
      app: azure-vote-back
  template:
    metadata:
      labels:
        app: azure-vote-back
    spec:
      nodeSelector:
        "kubernetes.io/os": linux
      containers:
        - name: azure-vote-back
          image: mcr.microsoft.com/oss/bitnami/redis:6.0.8
          env:
            - name: ALLOW_EMPTY_PASSWORD
              value: "yes"
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 250m
              memory: 256Mi
          ports:
            - containerPort: 6379
              name: redis
---
apiVersion: v1
kind: Service
metadata:
  name: azure-vote-back
spec:
  ports:
    - port: 6379
  selector:
    app: azure-vote-back
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: azure-vote-front
spec:
  replicas: 1
  selector:
    matchLabels:
      app: azure-vote-front
  template:
    metadata:
      labels:
        app: azure-vote-front
    spec:
      nodeSelector:
        "kubernetes.io/os": linux
      containers:
        - name: azure-vote-front
          image: mcr.microsoft.com/azuredocs/azure-vote-front:v1
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 250m
              memory: 256Mi
          ports:
            - containerPort: 80
          env:
            - name: REDIS
              value: "azure-vote-back"
---
apiVersion: v1
kind: Service
metadata:
  name: azure-vote-front
spec:
  type: LoadBalancer
  ports:
    - port: 80
  selector:
    app: azure-vote-front
```

Deploy the application using the [kubectl apply](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#apply) command and specify the name of your YAML manifest:

```bash
kubectl apply -f azure-vote-start.yml
```

## Test the Application

When the application runs, a Kubernetes service exposes the application front end to the internet. This process can take a few minutes to complete.

Check progress using the kubectl get service command.

```bash
kubectl get service
```

Store the public IP Address as an environment variable for later use.

```bash
IP_ADDRESS=$(kubectl get service azure-vote-front --output jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

Run the following command to obtain the URL.

```bash
echo "http://${IP_ADDRESS}"
```

Open the URL in a web browser and can see the Azure Vote app in action.

## Next steps

Learn how to scale an AKS Application with part 2 of the tutorial, see [Deploy a Scalable and Secure Azure Kubernetes Service cluster using the Azure CLI (Part 2)](./02-scale-your-application).
