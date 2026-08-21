#!/usr/bin/env bash
set -euo pipefail

cluster_name="${1:?cluster name is required}"
domain="${2:?application domain is required}"
dns_zone="${3-}"
dns_zone_resource_group="${4-}"
subscription_id="${5-}"
tenant_id="${6-}"
identity_client_id="${7-}"
acme_email="${8-}"
certificate_mode="${9:?certificate mode is required}"
dns_label="${10-}"
azure_region="${11-}"
action="${12-install}"

case "$action" in
    install|wait) ;;
    *)
        printf 'Unknown action: %s\n' "$action" >&2
        exit 1
        ;;
esac

azure_alias_target=""
if [[ -n "$dns_label" ]]; then
    [[ "$dns_label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ && ${#dns_label} -le 63 ]] || {
        printf 'Invalid DNS_LABEL: %s. Use 1-63 lowercase letters, digits, or hyphens, starting and ending with a letter or digit.\n' "$dns_label" >&2
        exit 1
    }
    [[ "$azure_region" =~ ^[a-z0-9]+$ ]] || {
        printf 'Invalid Azure region for the public DNS hostname: %s\n' "$azure_region" >&2
        exit 1
    }
    azure_alias_target="$dns_label.$azure_region.cloudapp.azure.com"
fi

case "$certificate_mode" in
    letsencrypt)
        [[ "$domain" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}$ ]] || {
            printf 'Invalid DOMAIN: %s\n' "$domain" >&2
            exit 1
        }
        [[ "$dns_zone" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}$ ]] || {
            printf 'Invalid DNS_ZONE_NAME: %s\n' "$dns_zone" >&2
            exit 1
        }
        [[ -n "$dns_zone_resource_group" ]] || {
            printf 'DNS_ZONE_RESOURCE_GROUP is required for Let'\''s Encrypt.\n' >&2
            exit 1
        }
        [[ "$domain" == "$dns_zone" || "$domain" == *."$dns_zone" ]] || {
            printf 'DOMAIN must be within DNS_ZONE_NAME.\n' >&2
            exit 1
        }
        [[ -n "$subscription_id" ]] || {
            printf 'Subscription ID is required for Azure DNS.\n' >&2
            exit 1
        }
        [[ -n "$tenant_id" ]] || {
            printf 'Tenant ID is required for Azure DNS.\n' >&2
            exit 1
        }
        [[ -n "$identity_client_id" ]] || {
            printf 'Managed identity client ID is required for Azure DNS.\n' >&2
            exit 1
        }
        ;;
    letsencrypt-http01)
        [[ "$domain" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}$ ]] || {
            printf 'Invalid DOMAIN: %s\n' "$domain" >&2
            exit 1
        }
        [[ -z "$dns_zone" ]] || {
            printf 'DNS_ZONE_NAME must be empty for HTTP-01.\n' >&2
            exit 1
        }
        ;;
    letsencrypt-azure-http01)
        [[ "$domain" == "$azure_alias_target" ]] || {
            printf 'The derived hostname does not match DNS_LABEL and the AKS region: %s\n' "$domain" >&2
            exit 1
        }
        [[ -z "$dns_zone" ]] || {
            printf 'DNS_ZONE_NAME must be empty for the Azure DNS-label path.\n' >&2
            exit 1
        }
        ;;
    selfsigned)
        [[ "$domain" == "aks-https.local" ]] || {
            printf 'Unexpected fallback domain: %s\n' "$domain" >&2
            exit 1
        }
        ;;
    *)
        printf 'Unknown certificate mode: %s\n' "$certificate_mode" >&2
        exit 1
        ;;
esac

email_pattern='^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
if [[ -n "$acme_email" && ! "$acme_email" =~ $email_pattern ]]; then
    printf 'Invalid ACME_EMAIL: %s\n' "$acme_email" >&2
    exit 1
fi

wait_for_gateway_address() {
    local address=""
    local elapsed=0

    printf 'Waiting up to 10 minutes for the Gateway public address...\n' >&2
    while (( elapsed < 600 )); do
        address="$(kubectl get gateway https-echo \
            --namespace aks-https \
            --output=jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
        if [[ -n "$address" ]]; then
            printf '%s\n' "$address"
            return 0
        fi
        sleep 10
        ((elapsed += 10))
        if (( elapsed % 60 == 0 )); then
            printf 'Still waiting for the Gateway public address (%d minutes elapsed).\n' "$((elapsed / 60))" >&2
        fi
    done

    if [[ "$certificate_mode" == "letsencrypt-azure-http01" ]]; then
        printf 'The Gateway did not receive a public address within 10 minutes. Confirm that DNS_LABEL %s is unique in %s and that the generated Envoy Gateway Service has the Azure DNS-label annotation.\n' "$dns_label" "$azure_region" >&2
    else
        printf 'The Gateway did not receive a public address within 10 minutes. Run this command again after checking the Envoy Gateway service.\n' >&2
    fi
    return 1
}

wait_for_http01_certificate() {
    local gateway_address="$1"

    printf '\nWaiting up to 15 minutes for cert-manager to issue the HTTP-01 certificate.\n'
    if [[ "$certificate_mode" == "letsencrypt-azure-http01" ]]; then
        printf 'Azure is publishing %s for the Gateway public IP %s; no DNS record needs to be created manually.\n' "$domain" "$gateway_address"
    elif [[ -n "$azure_alias_target" ]]; then
        printf 'It is retrying while public DNS propagates. Required record: %s CNAME %s\n' "$domain" "$azure_alias_target"
    else
        printf 'It is retrying while public DNS propagates. Required record: %s A %s\n' "$domain" "$gateway_address"
    fi
    if ! kubectl wait --for=condition=Ready certificate/https-echo-tls \
        --namespace aks-https \
        --timeout=15m; then
        printf '\nThe certificate did not become ready within 15 minutes.\n' >&2
        if [[ "$certificate_mode" == "letsencrypt-azure-http01" ]]; then
            printf 'Confirm that the Envoy Gateway Service has DNS label %s, that the label is unique in %s, that %s resolves publicly to %s, and that HTTP port 80 reaches the Gateway.\n' "$dns_label" "$azure_region" "$domain" "$gateway_address" >&2
        elif [[ -n "$azure_alias_target" ]]; then
            printf 'Confirm that %s is an unproxied CNAME to %s, that it resolves publicly to %s, and that HTTP port 80 reaches the Gateway, then run just wait-http01 again.\n' "$domain" "$azure_alias_target" "$gateway_address" >&2
        else
            printf 'Confirm that %s resolves publicly to %s on an unproxied A record and that HTTP port 80 is not redirected before it reaches the Gateway, then run just wait-http01 again.\n' "$domain" "$gateway_address" >&2
        fi
        return 1
    fi
}

if [[ "$action" == "wait" ]]; then
    [[ "$certificate_mode" == "letsencrypt-http01" ]] || {
        printf 'The wait action is only valid for the HTTP-01 certificate path.\n' >&2
        exit 1
    }
    gateway_address="$(wait_for_gateway_address)"
    wait_for_http01_certificate "$gateway_address"
    kubectl wait --for=condition=Programmed gateway/https-echo --namespace aks-https --timeout=10m
    printf '\nHTTPS lab is ready.\n'
    printf 'Trusted endpoint: https://%s\n' "$domain"
    if [[ -n "$azure_alias_target" ]]; then
        printf 'CNAME record: %s CNAME %s\n' "$domain" "$azure_alias_target"
    fi
    printf 'TLS 1.2 rejection test: openssl s_client -connect %s:443 -servername %s -tls1_2\n' "$gateway_address" "$domain"
    exit 0
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

helm upgrade --install envoy-gateway \
    oci://docker.io/envoyproxy/gateway-helm \
    --version v1.9.0 \
    --namespace envoy-gateway-system \
    --create-namespace \
    --wait \
    --timeout 10m

cat > "$work_dir/cert-manager-values.yaml" <<EOF
crds:
  enabled: true
config:
  gatewayAPI:
    enabled: true
EOF

if [[ "$certificate_mode" == "letsencrypt" ]]; then
    cat >> "$work_dir/cert-manager-values.yaml" <<EOF
podLabels:
  azure.workload.identity/use: "true"
serviceAccount:
  annotations:
    azure.workload.identity/client-id: "$identity_client_id"
EOF
fi

helm upgrade --install cert-manager \
    oci://quay.io/jetstack/charts/cert-manager \
    --version v1.21.1 \
    --namespace cert-manager \
    --create-namespace \
    --values "$work_dir/cert-manager-values.yaml" \
    --wait \
    --timeout 10m

if [[ "$certificate_mode" == "letsencrypt" ]]; then
    kubectl create namespace external-dns --dry-run=client --output=yaml | kubectl apply -f -

    cat > "$work_dir/external-dns-config.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: external-dns-azure
  namespace: external-dns
type: Opaque
stringData:
  azure.json: |
    {
      "tenantId": "$tenant_id",
      "subscriptionId": "$subscription_id",
      "resourceGroup": "$dns_zone_resource_group",
      "aadClientId": "$identity_client_id",
      "useWorkloadIdentityExtension": true
    }
EOF
    kubectl apply -f "$work_dir/external-dns-config.yaml"

    cat > "$work_dir/external-dns-values.yaml" <<EOF
fullnameOverride: external-dns
provider:
  name: azure
sources:
  - gateway-httproute
domainFilters:
  - "$dns_zone"
policy: sync
registry: txt
txtOwnerId: "$identity_client_id"
serviceAccount:
  labels:
    azure.workload.identity/use: "true"
  annotations:
    azure.workload.identity/client-id: "$identity_client_id"
podLabels:
  azure.workload.identity/use: "true"
extraVolumes:
  - name: azure-config-file
    secret:
      secretName: external-dns-azure
extraVolumeMounts:
  - name: azure-config-file
    mountPath: /etc/kubernetes
    readOnly: true
EOF

    helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ --force-update
    helm upgrade --install external-dns external-dns/external-dns \
        --version 1.21.1 \
        --namespace external-dns \
        --values "$work_dir/external-dns-values.yaml" \
        --wait \
        --timeout 10m
fi

kubectl create namespace aks-https --dry-run=client --output=yaml | kubectl apply -f -

if [[ "$certificate_mode" == "letsencrypt" || "$certificate_mode" == "letsencrypt-http01" || "$certificate_mode" == "letsencrypt-azure-http01" ]]; then
    {
        cat <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
EOF
        if [[ -n "$acme_email" ]]; then
            printf '    email: %s\n' "$acme_email"
        fi
        if [[ "$certificate_mode" == "letsencrypt" ]]; then
            cat <<EOF
    privateKeySecretRef:
      name: letsencrypt-account
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
      - dns01:
          azureDNS:
            environment: AzurePublicCloud
            hostedZoneName: $dns_zone
            managedIdentity:
              clientID: $identity_client_id
            resourceGroupName: $dns_zone_resource_group
            subscriptionID: $subscription_id
EOF
        else
            cat <<'EOF'
    privateKeySecretRef:
      name: letsencrypt-account
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
      - http01:
          gatewayHTTPRoute:
            parentRefs:
              - group: gateway.networking.k8s.io
                kind: Gateway
                name: https-echo
                namespace: aks-https
                sectionName: http
EOF
        fi
    } > "$work_dir/issuer.yaml"
    issuer_name="letsencrypt"
else
    cat > "$work_dir/issuer.yaml" <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
EOF
    issuer_name="selfsigned"
fi

kubectl apply -f "$work_dir/issuer.yaml"
kubectl wait --for=condition=Ready "clusterissuer/$issuer_name" --timeout=5m

if [[ -n "$dns_label" ]]; then
    cat > "$work_dir/application.yaml" <<EOF
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: azure-dns-label
  namespace: aks-https
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        annotations:
          service.beta.kubernetes.io/azure-dns-label-name: "$dns_label"
---
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-gateway
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: azure-dns-label
    namespace: aks-https
EOF
else
    cat > "$work_dir/application.yaml" <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-gateway
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF
fi

cat >> "$work_dir/application.yaml" <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: https-echo
  namespace: aks-https
spec:
  replicas: 2
  selector:
    matchLabels:
      app: https-echo
  template:
    metadata:
      labels:
        app: https-echo
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: echo
          image: ghcr.io/asw101/go-hello@sha256:4e7c405ca6d3d9705e963ac6a96ede326f9dbe13586eb9419e0e4f2dfc9fa307
          ports:
            - name: http
              containerPort: 8080
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 2
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /healthz
              port: http
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 3
          resources:
            requests:
              cpu: 25m
              memory: 32Mi
            limits:
              cpu: 250m
              memory: 128Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            readOnlyRootFilesystem: true
---
apiVersion: v1
kind: Service
metadata:
  name: https-echo
  namespace: aks-https
spec:
  selector:
    app: https-echo
  ports:
    - name: http
      port: 80
      targetPort: http
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: https-echo
  namespace: aks-https
  annotations:
    cert-manager.io/cluster-issuer: $issuer_name
    cert-manager.io/private-key-algorithm: ECDSA
    cert-manager.io/private-key-rotation-policy: Always
    cert-manager.io/private-key-size: "256"
spec:
  gatewayClassName: envoy-gateway
  listeners:
    - name: http
      hostname: "$domain"
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: Same
    - name: https
      hostname: "$domain"
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - group: ""
            kind: Secret
            name: https-echo-tls
      allowedRoutes:
        namespaces:
          from: Same
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: ClientTrafficPolicy
metadata:
  name: tls-13
  namespace: aks-https
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: https-echo
  tls:
    minVersion: "1.3"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: redirect-http
  namespace: aks-https
spec:
  parentRefs:
    - name: https-echo
      sectionName: http
  hostnames:
    - "$domain"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: https-echo
  namespace: aks-https
  annotations:
    external-dns.alpha.kubernetes.io/ttl: "60"
spec:
  parentRefs:
    - name: https-echo
      sectionName: https
  hostnames:
    - "$domain"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: https-echo
          port: 80
EOF

kubectl apply -f "$work_dir/application.yaml"
kubectl rollout status deployment/https-echo --namespace aks-https --timeout=5m

if [[ "$certificate_mode" == "letsencrypt-http01" ]]; then
    gateway_address="$(wait_for_gateway_address)"
    printf '\n============================================================\n'
    printf 'HTTP-01 DNS ACTION REQUIRED\n'
    printf 'Create this public DNS record now:\n\n'
    if [[ -n "$azure_alias_target" ]]; then
        printf '  %s CNAME %s\n\n' "$domain" "$azure_alias_target"
        printf 'Azure keeps %s pointed at the Gateway public IP %s.\n\n' "$azure_alias_target" "$gateway_address"
    else
        printf '  %s A %s\n\n' "$domain" "$gateway_address"
    fi
    printf 'The record must send port 80 directly to this Gateway. After it resolves publicly, run:\n\n'
    printf '  just wait-http01\n'
    printf '============================================================\n'
    printf 'cert-manager is already retrying the HTTP-01 challenge; no DNS provider credentials were configured.\n'
    exit 0
fi

if [[ "$certificate_mode" == "letsencrypt-azure-http01" ]]; then
    gateway_address="$(wait_for_gateway_address)"
    wait_for_http01_certificate "$gateway_address"
else
    kubectl wait --for=condition=Ready certificate/https-echo-tls --namespace aks-https --timeout=15m
fi
kubectl wait --for=condition=Programmed gateway/https-echo --namespace aks-https --timeout=10m

gateway_address="$(kubectl get gateway https-echo --namespace aks-https --output=jsonpath='{.status.addresses[0].value}')"
printf '\nHTTPS lab is ready.\n'
if [[ "$certificate_mode" == "letsencrypt" ]]; then
    printf 'Trusted endpoint: https://%s\n' "$domain"
    printf 'ExternalDNS is publishing %s to %s.\n' "$domain" "$gateway_address"
elif [[ "$certificate_mode" == "letsencrypt-azure-http01" ]]; then
    printf 'Trusted endpoint: https://%s\n' "$domain"
    printf 'Azure is publishing the Gateway public IP at %s.\n' "$domain"
else
    printf 'Self-signed endpoint IP: %s\n' "$gateway_address"
    printf 'Test: curl --resolve %s:443:%s --insecure https://%s/echo\n' "$domain" "$gateway_address" "$domain"
fi
if [[ -n "$azure_alias_target" && "$domain" != "$azure_alias_target" && "$certificate_mode" != "selfsigned" ]]; then
    printf 'CNAME alias target: %s\n' "$azure_alias_target"
    if [[ "$certificate_mode" != "letsencrypt" ]]; then
        printf 'CNAME record: %s CNAME %s\n' "$domain" "$azure_alias_target"
    fi
fi
printf 'TLS 1.2 rejection test: openssl s_client -connect %s:443 -servername %s -tls1_2\n' "$gateway_address" "$domain"
