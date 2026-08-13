# Deploy a Scalable and Secure Azure Kubernetes Service cluster using the Azure CLI (Part 3)

Azure Kubernetes Service provides a powerful way to manage Kubernetes applications which are Portable, extensibile, and when combined with Azure infrastructure highly scalable. Part 3 of this tutorial covers steps in adding a custom domain with https to an AKS Application.

## Requirements

- An **Azure Subscription** (e.g. [Free](https://aka.ms/azure-free-account) or [Student](https://aka.ms/azure-student-account) account)
- The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- A Bash shell (macOS, Linux, [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/windows/wsl/about), [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/quickstart), or [GitHub Codespaces](https://github.com/features/codespaces))
- Completion of [Part 1](../README.md) and [Part 2](../02-scale-your-application/README.md)

## Setup

### Define Custom Command Line Variables

Custom values are required for the following inputs.

We will now choose and define the custom domain which your application will use. The application will be reachable at {mycustomdomain}.eastus.cloudapp.azure.com
 
Run the following command with a unique custom domain:

> **Note** Do not add any capitalization or .com. The custom domain must be unique and fit the pattern: ^[a-z][a-z0-9-]{1,61}[a-z0-9]$

```bash
CUSTOM_DOMAIN_NAME="myuniquecustomdomain"
```

You can validate the custom domain works by running the following 

```bash
if [[ ! $CUSTOM_DOMAIN_NAME =~ ^[a-z][a-z0-9-]{1,61}[a-z0-9] ]]; then echo "Invalid Domain, run'CUSTOM_DOMAIN_NAME="customdomainname"' again and choose a new domain"; else echo "Custom Domain Set!"; fi; 
```

In order to obtain an SSL certificate from Lets Encrypt we need to provide a valid email address.

Set a valid email address for SSL validation by running the following:

```bash
export SSL_EMAIL_ADDRESS="myemailadress@gmail.com"
```

## Add custom domain to AGIC

Now that Application Gateway Ingress has been added, the next step is to add a custom domain. This will allow the endpoint to be reached by a human readable URL as well as allow for SSL Termination at the endpoint.

Store Unique ID of the Public IP Address as an environment variable.

```bash
PUBLIC_IP_ID=$(az network public-ip list \
    --query "[?ipAddress!=null]|[?contains(ipAddress, '$IP_ADDRESS')].[id]" \
    --output tsv)
```

Update public IP to respond to custom domain requests.

```bash
az network public-ip update \
    --ids $PUBLIC_IP_ID \
    --dns-name $CUSTOM_DOMAIN_NAME
```

Run the following command to see the fully qualified domain name (FQDN) of your application. 

```bash
az network public-ip show \
    --ids $PUBLIC_IP_ID \
    --query "[dnsSettings.fqdn]" \
    --output tsv
```

Validate the domain works by opening a web browser to the FQDN of the application.

Store the custom domain as an environment variable. This will be used later when setting up https termination.

```bash
export FQDN=$(az network public-ip show \
    --ids $PUBLIC_IP_ID \
    --query "[dnsSettings.fqdn]" \
    --output tsv)
```

## Add HTTPS termination to custom domain

At this point in the tutorial you have an AKS web app with Application Gateway as the Ingress controller and a custom domain you can use to access your application. The next step is to add an SSL certificate to the domain so that users can reach your application securely via https.  

### Set Up Cert Manager

In order to add HTTPS we are going to use Cert Manager. Cert Manager is an open source tool used to obtain and manage SSL certificate for Kubernetes deployments. Cert Manager will obtain certificates from a variety of Issuers, both popular public Issuers as well as private Issuers, and ensure the certificates are valid and up-to-date, and will attempt to renew certificates at a configured time before expiry.

In order to install cert-manager, we must first create a namespace to run it in. This tutorial will install cert-manager into the cert-manager namespace. It is possible to run cert-manager in a different namespace, although you will need to make modifications to the deployment manifests.

```bash
kubectl create namespace cert-manager
```

We can now install cert-manager. All resources are included in a single YAML manifest file. This can be installed by running the following:

```bash
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.7.0/cert-manager.crds.yaml
```

Add the certmanager.k8s.io/disable-validation: "true" label to the cert-manager namespace by running the following. This will allow the system resources that cert-manager requires to bootstrap TLS to be created in its own namespace.

```bash
kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true
```

### Obtain certificate via Helm Charts

Helm is a Kubernetes deployment tool for automating creation, packaging, configuration, and deployment of applications and services to Kubernetes clusters.

Cert-manager provides Helm charts as a first-class method of installation on Kubernetes.

Add the Jetstack Helm repository.

```bash
helm repo add jetstack https://charts.jetstack.io
```

This repository is the only supported source of cert-manager charts. There are some other mirrors and copies across the internet, but those are entirely unofficial and could present a security risk.

Update local Helm Chart repository cache.

```bash
helm repo update
```

Install Cert-Manager add-on via helm.

```bash
helm install cert-manager jetstack/cert-manager --namespace cert-manager --version v1.7.0
```

Deploy Cluster Issuer 

ClusterIssuers are Kubernetes resources that represent certificate authorities (CAs) that are able to generate signed certificates by honoring certificate signing requests. All cert-manager certificates require a referenced issuer that is in a ready condition to attempt to honor the request.

Create a file named cluster-issuer-prod.yaml and copy in the following manifest.


```yaml
#!/bin/bash
#kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
name: letsencrypt-prod
spec:
acme:
    # You must replace this email address with your own.
    # Let's Encrypt will use this to contact you about expiring
    # certificates, and issues related to your account.
    email: $SSL_EMAIL_ADDRESS
    # ACME server URL for Let’s Encrypt’s prod environment.
    # The staging environment will not issue trusted certificates but is
    # used to ensure that the verification process is working properly
    # before moving to production
    server: https://acme-v02.api.letsencrypt.org/directory
    # Secret resource used to store the account's private key.
    privateKeySecretRef:
    name: example-issuer-account-key
    # Enable the HTTP-01 challenge provider
    # you prove ownership of a domain by ensuring that a particular
    # file is present at the domain
    solvers:
    - http01:
        ingress:
            class: azure/application-gateway
#EOF

# References:
# https://docs.microsoft.com/en-us/azure/application-gateway/ingress-controller-letsencrypt-certificate-application-gateway
# https://cert-manager.io/docs/configuration/acme/
```

If you use the Azure Cloud Shell, this file can be created using code, vi, or nano as if working on a virtual or physical system.
        
Deploy the Cluster Issuer YAML file by running the following command:

> **Note** envsubst will replace variables in the YAML file with command line variables previosuly defined.

```bash
envsubst < cluster-issuer-prod.yaml | kubectl apply -f -
```

Create and deploy Updated YAML manifest which includes ssl termination.

Create a file named azure-vote-agic-ssl.yml and copy in the following manifest.

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
# INGRESS WITH SSL PROD
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: azure-vote-ingress-agic-ssl
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
    kubernetes.io/tls-acme: "true"
    appgw.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts:
        - $FQDN
      secretName: azure-vote-agic-secret
  rules:
    - host: $FQDN
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: azure-vote-front
                port:
                  number: 80

```

Deploy the YAML file complete with SSL termination by running the following command: 

**Note** envsubst will replace variables in the YAML file with command line variables previously defined

```
envsubst < azure-vote-agic-ssl.yml | kubectl apply -f -
```
## Validate application is working

Wait for SSL certificate to issue. The following command will query the status of the SSL certificate for 3 minutes.

In rare occasions it may take up to 15 minutes for Lets Encrypt to issue a successful challenge and the ready state to be 'True'.

```bash
runtime="10 minute"; endtime=$(date -ud "$runtime" +%s); while [[ $(date -u +%s) -le $endtime ]]; do STATUS=$(kubectl get certificate --output jsonpath={..status.conditions[0].status}); echo $STATUS; if [ "$STATUS" = 'True' ]; then break; else sleep 10; fi; done
```

Validate SSL certificate is True by running the follow command:

```bash
kubectl get certificate --output jsonpath={..status.conditions[0].status}
```

The following is a successful output.

Results:

```expected_similarity=0.8
True
```

## Browse your AKS Deployment Secured via HTTPS!

Run the following command to get the HTTPS endpoint for your application.

> **Note**
> It often takes 2-3 minutes for the SSL certificate to propagate and the site to be reachable via https 

```
echo "https://${FQDN}"
```

To see the Azure Vote app in action, open a web browser to the HTTPS Endpoint of the Application.
