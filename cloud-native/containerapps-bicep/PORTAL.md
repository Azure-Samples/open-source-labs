# PORTAL

This snippet below generates a link to an ARM template in GitHub that will allow you to deploy it via the Azure Portal.

```bash
TEMPLATE_URL='https://raw.githubusercontent.com/Azure-Samples/open-source-labs/main/cloud-native/containerapps-bicep/main.json'
OUTPUT_URL='https://portal.azure.com/#create/Microsoft.Template/uri/'$(printf "$TEMPLATE_URL" | jq -s -R -r @uri )
echo $OUTPUT_URL

# https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure-Samples%2Fopen-source-labs%2Fmain%2Fcloud-native%2Fcontainerapps-bicep%2Fmain.json
```