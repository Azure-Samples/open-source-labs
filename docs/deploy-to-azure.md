# Deploy to Azure buttons

Several labs offer a `Deploy to Azure` button that opens their ARM template in
the Azure portal, ready to deploy. The button is an ordinary link: the portal's
custom deployment page, followed by the percent-encoded URL of a template.

```
https://portal.azure.com/#create/Microsoft.Template/uri/<encoded template URL>
```

Decoded, the template URL is always the raw file on GitHub:

```
https://raw.githubusercontent.com/Azure-Samples/open-source-labs/main/<path>
```

## The buttons always deploy this repository, on `main`

The portal fetches the template from the URL as written. It has no idea which
page the button was clicked from, and the URL has no way to say "wherever this
file lives". Every button in this repository therefore names
`Azure-Samples/open-source-labs` and the `main` branch, and that is what it
deploys, wherever the page carrying it is being read.

* **In a fork**, the buttons deploy the canonical templates, not the fork's.
  GitHub renders a fork's README exactly like the original, so a button can look
  local while deploying somebody else's template. Editing a template in a fork
  does not change what the button beside it deploys.
* **On a branch, or in a pull request**, the same holds. A button that names a
  template only added on that branch resolves to a path that does not exist on
  `main` yet, and the portal reports that it cannot fetch the template. A
  button, unlike the template it points at, cannot be exercised before merge.
* **On a snapshot branch**, the same again, which is why deploying what a
  snapshot holds takes a substitution. See [Lab snapshots](snapshot.md).
* **In a private fork**, no button can work. The portal fetches anonymously, and
  raw URLs into a private repository are not served anonymously.

The same applies to the `az deployment group create --template-uri` commands in
the labs, which take the raw URL unencoded and fetch it the same way.

## Building a button for a fork, a branch, or a snapshot

Swap the owner, repository, and branch in the raw URL, then encode it. This is
the snippet the labs' own `PORTAL.md` files use, for example
[`linux/vm/PORTAL.md`](../linux/vm/PORTAL.md):

```bash
TEMPLATE_URL='https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<path>'
OUTPUT_URL='https://portal.azure.com/#create/Microsoft.Template/uri/'$(printf "$TEMPLATE_URL" | jq -s -R -r @uri )
echo $OUTPUT_URL
```

Open `$TEMPLATE_URL` first, or `curl -sI` it. If the raw URL does not return the
template, neither will the portal, and the error the portal gives is further
from the cause.

Encoding only affects `:` and `/`, as `%3A` and `%2F`, so an existing button URL
can be read without decoding it: `%2Fmain%2F` is the branch segment.

## Changing a button

Generated ARM is what a button deploys, so a template change is only live once
its regenerated JSON is on `main`. See [AGENTS.md](../AGENTS.md) for the rule
that Bicep and its generated JSON are committed together.

When a pull request adds a lab and a button together, expect the button to fail
until it merges. That is the mechanism above rather than a defect, and it is not
a reason to point the button anywhere other than `main`.
