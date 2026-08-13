# Deploy a Scalable and Secure Azure Kubernetes Service cluster using the Azure CLI (Part 2)

Azure Kubernetes Service provides a powerful way to manage Kubernetes applications which are Portable, extensibile, and when combined with Azure infrastructure highly scalable. Part 2 of this tutorial covers steps in scaling an AKS application by adding Application Gateway Ingress.

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/quickstart), or [GitHub Codespaces](https://github.com/features/codespaces))
- Completion of [Part 1](../README.md)

## Setup

### Define Default Command Line Variables

This tutorial will use command line variables. Copy and run the following  the following to set default command line variables.

```bash
PUBLIC_IP_NAME="myPublicIp"
VNET_NAME="myVnet"
SUBNET_NAME="mySubnet"
APPLICATION_GATEWAY_NAME="myApplicationGateway"
APPGW_TO_AKS_PEERING_NAME="AppGWtoAKSVnetPeering"
AKS_TO_APPGW_PEERING_NAME="AKStoAppGWVnetPeering"
```

## Add Application Gateway Ingress Controller

The Application Gateway Ingress Controller (AGIC) is a Kubernetes application, which makes it possible for Azure Kubernetes Service (AKS) customers to leverage Azure's native Application Gateway L7 load-balancer to expose cloud software to the Internet. AGIC monitors the Kubernetes cluster it is hosted on and continuously updates an Application Gateway, so that selected services are exposed to the Internet

AGIC helps eliminate the need to have another load balancer/public IP in front of the AKS cluster and avoids multiple hops in your data path before requests reach the AKS cluster. Application Gateway talks to pods using their private IP directly and does not require NodePort or KubeProxy services. This also brings better performance to your deployments.

## Deploy a new Application Gateway

Create a Public IP for Application Gateway.

```bash
az network public-ip create \
    --name $PUBLIC_IP_NAME \
    --resource-group $RESOURCE_GROUP \
    --allocation-method Static \
    --sku Standard
```

Create a Virtual Network (VNet) for Application Gateway.

```bash
az network vnet create \
    --name $VNET_NAME \
    --resource-group $RESOURCE_GROUP \
    --address-prefix 11.0.0.0/8 \
    --subnet-name $SUBNET_NAME \
    --subnet-prefix 11.1.0.0/16 
```

Create Application Gateway.

> **Note** 
> This will take around 5 minutes 

```bash
az network application-gateway create \
    --name $APPLICATION_GATEWAY_NAME \
    --location $RESOURCE_LOCATION \
    --resource-group $RESOURCE_GROUP \
    --sku Standard_v2 \
    --public-ip-address $PUBLIC_IP_NAME \
    --vnet-name $VNET_NAME \
    --subnet $SUBNET_NAME
```

## Enable the AGIC add-on in existing AKS cluster

Store Application Gateway ID.

```bash
APPLICATION_GATEWAY_ID=$(az network application-gateway show \
    --name $APPLICATION_GATEWAY_NAME \
    --resource-group $RESOURCE_GROUP \
    --output tsv \
    --query "id")
```

Enable Application Gateway Ingress Add-on.

> **Note**
> This will take a few minutes

```bash
az aks enable-addons \
    --name $AKS_NAME \
    --resource-group $RESOURCE_GROUP \
    --addon ingress-appgw \
    --appgw-id $APPLICATION_GATEWAY_ID
```

Store the node resource as an environment variable group.

```bash
NODE_RESOURCE_GROUP=$(az aks show \
    --name $AKS_NAME \
    --resource-group $RESOURCE_GROUP \
    --output tsv \
    --query "nodeResourceGroup")
```

Store the VNet name as an environment variable.

```bash
AKS_VNET_NAME=$(az network vnet list \
    --resource-group $NODE_RESOURCE_GROUP \
    --output tsv \
    --query "[0].name")
```

Store the VNet ID as an environment variable.

```bash
AKS_VNET_ID=$(az network vnet show \
    --name $AKS_VNET_NAME \
    --resource-group $NODE_RESOURCE_GROUP \
    --output tsv \
    --query "id")
```
## Peer the two virtual networks together

Since we deployed the AKS cluster in its own virtual network and the Application Gateway in another virtual network, you'll need to peer the two virtual networks together in order for traffic to flow from the Application Gateway to the pods in the cluster. Peering the two virtual networks requires running the Azure CLI command two separate times, to ensure that the connection is bi-directional. The first command will create a peering connection from the Application Gateway virtual network to the AKS virtual network; the second command will create a peering connection in the other direction.

Create the peering from Application Gateway to AKS.

```bash
az network vnet peering create \
    --name $APPGW_TO_AKS_PEERING_NAME \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --remote-vnet $AKS_VNET_ID \
    --allow-vnet-access 
```

Store Id of Application Gateway VNet As environment variable.

```bash
APPLICATION_GATEWAY_VNET_ID=$(az network vnet show \
    --name $VNET_NAME \
    --resource-group $RESOURCE_GROUP \
    --output tsv \
    --query "id")
```

Create VNet Peering from AKS to Application Gateway.

```bash
az network vnet peering create \
    --name $AKS_TO_APPGW_PEERING_NAME \
    --resource-group $NODE_RESOURCE_GROUP \
    --vnet-name $AKS_VNET_NAME \
    --remote-vnet $APPLICATION_GATEWAY_VNET_ID \
    --allow-vnet-access
```

Store New IP address as environment variable.

```bash
runtime="2 minute"; endtime=$(date -ud "$runtime" +%s); while [[ $(date -u +%s) -le $endtime ]]; do export IP_ADDRESS=$(az network public-ip show --resource-group $RESOURCE_GROUP --name $PUBLIC_IP_NAME --query ipAddress --output tsv); if ! [ -z $IP_ADDRESS ]; then break; else sleep 10; fi; done
```

## Apply updated application YAML complete with AGIC

Create a file named azure-vote-agic-yaml and copy in the following manifest.

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
  type:
  ports:
    - port: 80
  selector:
    app: azure-vote-front
---
#Application Gateway Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: azure-vote-front
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
spec:
  rules:
    - http:
        paths:
          - path: /
            backend:
              service:
                name: azure-vote-front
                port:
                  number: 80
            pathType: Exact
```

If you use the Azure Cloud Shell, this file can be created using code, vi, or nano as if working on a virtual or physical system.

Deploy the updated Voting App AGIC YAML file with Application Gateway Ingress added.

```bash
kubectl apply -f azure-vote-agic.yml
```

## Check that the application is reachable

Now that the Application Gateway is set up to serve traffic to the AKS cluster, let's verify that your application is reachable. 

Check that the sample application you created is up and running by either visiting the IP address of the Application Gateway that get from running the following command or check with curl. It may take Application Gateway a minute to get the update, so if the Application Gateway is still in an "Updating" state on Portal, then let it finish before trying to reach the IP address. Run the following to check the status:

```bash
kubectl get ingress
```

Run the following command to obtain the IP Address of Application Gateway.

```bash
echo $IP_ADDRESS
```

To see the Azure Vote app in action, open a web browser to the external IP address of the application.

## Next steps

Learn how to scale an AKS Application with part 2 of the tutorial, see [Deploy a Scalable and Secure Azure Kubernetes Service cluster using the Azure CLI (Part 3)](../03-custom-domain-and-https).
