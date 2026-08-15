#!/usr/bin/env bash
# Install Tailscale, then either join with an auth key or publish a login URL.
set -eo pipefail

cat >/usr/local/bin/tailscale-authurl <<'EOF'
#!/usr/bin/env bash
# Print this node's Tailscale interactive login URL.
# Pass --refresh to discard an expired URL and mint a fresh one.
set -eo pipefail

if [ "$#" -gt 0 ] && [ "$1" = "--refresh" ]; then
    tailscale logout >/dev/null 2>&1 || true
    setsid tailscale up --ssh --timeout=1s >/dev/null 2>&1 || true
fi

for i in $(seq 1 30); do
    url=$(tailscale status --json 2>/dev/null | jq -r '.AuthURL // empty')
    if [ -n "$url" ]; then
        echo "$url"
        exit 0
    fi
    state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // empty')
    if [ "$state" = "Running" ]; then
        echo "already onboarded; re-run with --refresh to re-authenticate" >&2
        exit 0
    fi
    sleep 2
done

echo "no auth URL available" >&2
exit 1
EOF
chmod 0755 /usr/local/bin/tailscale-authurl

curl -fsSL https://tailscale.com/install.sh | sh

key="${tailscale_auth_key}"
if [ -n "$key" ] && [ "$key" != "null" ]; then
    sudo tailscale up --advertise-routes=10.1.0.0/24,168.63.129.16/32 --accept-dns=false --ssh --authkey "$key"
    echo "tailscale: joined tailnet with auth key" >/dev/console 2>/dev/null || true
    exit 0
fi

# No auth key. 'tailscale up' blocks until the node is authorized, so run it
# detached and poll the daemon for the login URL it generates.
setsid tailscale up --ssh >/var/log/tailscale-up.log 2>&1 &

url=""
for i in $(seq 1 60); do
    url=$(tailscale status --json 2>/dev/null | jq -r '.AuthURL // empty')
    if [ -n "$url" ]; then
        break
    fi
    sleep 2
done

if [ -z "$url" ]; then
    echo "tailscale: FAILED to obtain a login URL" >/dev/console 2>/dev/null || true
    echo "tailscale: FAILED to obtain a login URL" >&2
    exit 1
fi

echo "$url" >/var/lib/tailscale-authurl.txt
chmod 0644 /var/lib/tailscale-authurl.txt

# Publish to the serial console so it reaches Azure boot diagnostics.
# Best-effort: the file above is the authoritative copy.
printf '\n===== TAILSCALE LOGIN URL =====\n%s\n===============================\n\n' \
    "$url" >/dev/console 2>/dev/null || true
