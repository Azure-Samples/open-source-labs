# PORTAL

```bash
TEMPLATE_URL='https://raw.githubusercontent.com/Azure-Samples/open-source-labs/main/linux/vm/vm.json'
OUTPUT_URL='https://portal.azure.com/#create/Microsoft.Template/uri/'$(printf "$TEMPLATE_URL" | jq -s -R -r @uri )
echo $OUTPUT_URL

# https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure-Samples%2Fopen-source-labs%2Fmain%2Flinux%2Fvm%2Fvm.json
```
