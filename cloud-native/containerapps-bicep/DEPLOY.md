# DEPLOY

## Deploy Infrastructure

[[Deploy via Azure Portal](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure-Samples%2Fopen-source-labs%2Fmain%2Fcloud-native%2Fcontainerapps-bicep%2Fcontainerapp.json)]

```bash
RESOURCE_GROUP="221200-container-apps"
LOCATION="eastus"

az group create \
  --name $RESOURCE_GROUP \
  --location "$LOCATION"

az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file ./containerapp.bicep \
  --parameters \
      location="$LOCATION"
```

## Build and Deploy Application

[[Deploy via Azure Portal](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure-Samples%2Fopen-source-labs%2Fmain%2Fcloud-native%2Fcontainerapps-bicep%2Fapp.json)]

```bash
ACR_NAME=$(az acr list \
    --resource-group $RESOURCE_GROUP \
    --query '[0].name' \
    --out tsv)

IDENTITY_ID=$(az identity show \
  --name "${RESOURCE_GROUP}-identity" \
  --resource-group $RESOURCE_GROUP \
  --query id \
  --out tsv)

IMAGE_NAME='asw101/go-hello'

# clone repo
gh repo clone asw101/go-hello
cd go-hello/

# build the container
az acr build -t $IMAGE_NAME -r $ACR_NAME .

# deploy container
az containerapp create \
  --resource-group $RESOURCE_GROUP \
  --name 'my-container-app' \
  --environment 'my-environment' \
  --user-assigned $IDENTITY_ID \
  --registry-identity $IDENTITY_ID \
  --registry-server "$ACR_NAME.azurecr.io" \
  --image "$ACR_NAME.azurecr.io/$IMAGE_NAME:latest"
```
