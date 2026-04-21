# PKI & Certificates — step-ca on Raspberry Pi

> Trigger: certificate, cert, ca, pki, step-ca, stepca, tinyca, smallstep, mtls, tls, trust, root ca, intermediate, acme, rpi, raspberry, keycloak, sso, oidc

## Architecture

- **Root CA**: Private root CA running [step-ca](https://smallstep.com/docs/step-ca/) (Smallstep) on a dedicated Raspberry Pi.
- **Purpose**: Issue **every certificate** in the homelab — Kubernetes control plane PKI, kubelet certs, etcd peer/client certs, Istio mesh mTLS, ingress TLS, internal services, device certificates.
- **Trust model**: The RPi CA is the **single root of trust**. Nothing in this homelab uses self-signed or auto-generated certificates. Every TLS certificate chains to the step-ca root.

## HARD RULE: All Cluster Certificates From step-ca

**No component generates its own CA or self-signed certificates.** This includes:

| Certificate | Default Behavior | Homelab Override |
|-------------|-----------------|------------------|
| Kubernetes API server | Talos auto-generates at bootstrap | Provide via `cluster.secrets` in machine config |
| Kubernetes CA | Talos auto-generates | Pre-generate from step-ca, inject via `secrets.yaml` bundle |
| etcd CA + peer/client certs | Talos auto-generates | Pre-generate from step-ca, inject via `secrets.yaml` bundle |
| Front-proxy CA | Talos auto-generates | Pre-generate from step-ca, inject via `secrets.yaml` bundle |
| Service account signing key | Talos auto-generates | Pre-generate, inject via `secrets.yaml` bundle |
| Kubelet serving certs | Kubelet self-signs, then cert-approver approves | Approved certs should chain to cluster CA (which is step-ca) |
| Istio workload certs | Istio citadel auto-generates CA | Plug step-ca root via `cacerts` secret |
| cert-manager issued certs | Depends on issuer | `ClusterIssuer` points to step-ca ACME |
| Caddy TLS | Auto from Let's Encrypt or self-signed | step-ca issued certs |
| Keycloak TLS | Self-signed by default | step-ca issued cert |

### Talos Secrets Bundle

Instead of letting `talosctl gen config` auto-generate PKI material, pre-generate a secrets bundle with CAs issued by step-ca:

```bash
# 1. Generate intermediates from step-ca for each Kubernetes CA role
step ca certificate "kubernetes" k8s-ca.crt k8s-ca.key --ca-url https://<rpi-ip>:8443 --not-after=87600h
step ca certificate "etcd" etcd-ca.crt etcd-ca.key --ca-url https://<rpi-ip>:8443 --not-after=87600h
step ca certificate "front-proxy" front-proxy-ca.crt front-proxy-ca.key --ca-url https://<rpi-ip>:8443 --not-after=87600h

# 2. Build a Talos secrets bundle (secrets.yaml) with these CAs
#    This replaces the auto-generated PKI in talosctl gen config

# 3. Generate machine configs using the pre-built secrets
talosctl gen config <cluster-name> https://192.168.1.100:6443 \
  --with-secrets secrets.yaml \
  --config-patch-control-plane @talos/_out/cp.patch.yaml
```

The `secrets.yaml` bundle structure:
```yaml
cluster:
  id: <cluster-id>
  secret: <cluster-secret>
certs:
  etcd:
    cert: <etcd-ca-cert-from-step-ca>
    key: <etcd-ca-key>
  k8s:
    cert: <k8s-ca-cert-from-step-ca>
    key: <k8s-ca-key>
  k8s-aggregator:
    cert: <front-proxy-ca-cert-from-step-ca>
    key: <front-proxy-ca-key>
  k8s-serviceaccount:
    key: <sa-signing-key>
```

### Root CA Trust Distribution

The step-ca root certificate must be trusted by every node. In Talos, inject it via machine config:

```yaml
machine:
  files:
    - content: |
        -----BEGIN CERTIFICATE-----
        <step-ca-root-cert-PEM>
        -----END CERTIFICATE-----
      permissions: 0644
      path: /etc/ssl/certs/homelab-root-ca.crt
      op: create
  env:
    SSL_CERT_DIR: /etc/ssl/certs
```

### Verification Checklist

When setting up or rotating certificates, verify the full chain:
```bash
# Verify API server cert chains to step-ca root
talosctl get certificates --nodes 192.168.1.34
openssl s_client -connect 192.168.1.100:6443 -showcerts 2>/dev/null | openssl x509 -noout -issuer -subject

# Verify etcd certs
talosctl -n 192.168.1.34 get etcdmembers

# Verify kubelet serving certs
kubectl get csr -o wide

# Verify Istio workload certs chain to step-ca
istioctl proxy-config secret <pod> -n <ns> -o json | jq '.dynamicActiveSecrets[0].secret.tlsCertificate.certificateChain'
```

## Components

| Component | Role | Location |
|-----------|------|----------|
| **step-ca** | ACME + X.509 certificate authority | Raspberry Pi (dedicated, not in cluster) |
| **cert-manager** | Kubernetes certificate lifecycle | In-cluster (ArgoCD managed) |
| **Istio CA** | Service mesh mTLS certificates | In-cluster (plugged into step-ca root) |
| **Keycloak** | SSO / OIDC identity provider | Protectli Vault (alongside OPNsense) |
| **Caddy** | Internal reverse proxy + TLS termination | Protectli Vault (alongside OPNsense) |
| **Pangolin** | Public access tunnel (planned) | VPS (future) |

## step-ca Configuration

- **Provisioners**: ACME (for cert-manager), JWK (for manual issuance), SSHPOP (optional for SSH certs).
- **ACME endpoint**: `https://<rpi-ip>:8443/acme/acme/directory`
- **Root cert distribution**: Root CA certificate must be distributed to:
  1. Talos machine config (`machine.files[]` or `machine.env`)
  2. cert-manager `ClusterIssuer` CA bundle
  3. Istio's `cacerts` secret in `istio-system`
  4. Any client that needs to verify TLS (browsers, CLI tools)

## cert-manager Integration

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: step-ca-issuer
spec:
  acme:
    server: https://<rpi-ip>:8443/acme/acme/directory
    privateKeySecretRef:
      name: step-ca-account-key
    caBundle: <base64-encoded-root-ca-cert>
    solvers:
      - http01:
          ingress:
            class: istio
```

## Istio mTLS Integration

Istio must trust the homelab root CA for mesh-wide mTLS:

1. Create a `cacerts` secret in `istio-system` with the root cert + intermediate.
2. Istio uses this to sign workload certificates.
3. All pod-to-pod mTLS certificates chain up to the homelab root CA.

```bash
# Create the Istio CA secret
kubectl create secret generic cacerts -n istio-system \
  --from-file=ca-cert.pem=<intermediate-cert> \
  --from-file=ca-key.pem=<intermediate-key> \
  --from-file=root-cert.pem=<root-cert> \
  --from-file=cert-chain.pem=<cert-chain>
```

## Certificate Lifecycle Rules

1. **Never commit private keys to Git** — not even encrypted ones unless using SOPS/SealedSecrets with proper KMS.
2. **Short-lived certs** — default 24h for workload certs, 90 days for ingress certs, 10 years for root CA.
3. **Auto-renewal** — cert-manager handles renewal. Set `renewBefore` to 2/3 of cert lifetime.
4. **Root CA rotation** — planned manually. Document the procedure; it affects every trust anchor.
5. **Wildcard certs** — acceptable for `*.homelab.<domain>` on the ingress gateway. Not for individual services.

## Troubleshooting

```bash
# Check cert-manager certificate status
kubectl get certificates -A
kubectl describe certificate <name> -n <ns>

# Check cert-manager issuer readiness
kubectl get clusterissuers
kubectl describe clusterissuer step-ca-issuer

# Verify a certificate chain
openssl verify -CAfile root-ca.crt -untrusted intermediate.crt server.crt

# Check step-ca health
step ca health --ca-url https://<rpi-ip>:8443

# Inspect a certificate
step certificate inspect <cert.pem>
```

## When Generating Certificate Manifests

- Always use `cert-manager.io/v1` API version.
- Use `ClusterIssuer` (not namespace-scoped `Issuer`) since the CA is shared.
- Set `dnsNames` explicitly — no wildcard unless for the ingress gateway.
- Include `issuerRef` pointing to `step-ca-issuer`.
- Store generated cert secrets with annotation `cert-manager.io/issuer-name` for traceability.

## Keycloak SSO Integration

Keycloak runs on the Protectli Vault (OPNsense box) and provides OIDC/SAML SSO for all homelab services.

### Certificate Trust
- Keycloak's HTTPS endpoint should use a certificate issued by step-ca.
- Cluster services authenticating via OIDC must trust the homelab root CA to validate Keycloak's TLS cert.
- Keycloak realm JWKS endpoint must be reachable from within the cluster (via OPNsense firewall rules).

### Auth Flow (Current — Caddy on Protectli Vault)
```
Client (LAN) → Caddy (Protectli Vault, step-ca TLS) → Keycloak (OIDC) → upstream service
```
- **Internal TLS**: Caddy uses step-ca issued certs for all internal HTTPS.
- **SSO**: Caddy validates OIDC tokens from Keycloak before proxying to services.

### Auth Flow (Future — with Pangolin on VPS)
```
Client (Internet) → Pangolin (VPS) → tunnel → Caddy (Protectli Vault) → Keycloak (OIDC) → upstream
```
- Public TLS termination strategy TBD when Pangolin is implemented.

### Rules
- Keycloak's TLS certificate should be issued by step-ca with a SAN matching its FQDN.
- OIDC client secrets for services are managed outside Git (Keycloak admin + sealed secrets in cluster).
- When adding a new service behind SSO: create OIDC client in Keycloak, add `oauth2-proxy` sidecar or use Istio `RequestAuthentication` with Keycloak's JWKS URI.
