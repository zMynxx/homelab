---
name: caddy-sso-setup
description: Caddy reverse proxy on OPNsense + Kanidm IdP + oauth2-proxy SSO — architecture, pitfalls, status
metadata:
  type: project
---

## What was built
Full internal reverse proxy + SSO stack for the homelab.

**Why:** User wanted HTTPS internal domains via Caddy on OPNsense, TLS from TinyCA, and SSO via Kanidm for all services.

## Architecture
```
Browser → AdGuard DNS (*.opnsense.internal → 192.168.1.1)
        → Caddy on OPNsense (caddy-os plugin, auto-generates Caddyfile)
            ├── forward_auth → oauth2-proxy (192.168.30.203:4180)
            │       └── OIDC → Kanidm (192.168.30.201:8443)
            └── backend services
```

## Key facts
- TinyCA (Step-CA) at 192.168.10.37:**8443** (NOT 9000 — confirmed from step-issuer.yaml)
- ACME directory: `https://192.168.10.37:8443/acme/acme/directory`
- OPNsense at 192.168.1.1, UI on port 8443
- Caddy config is auto-generated — add custom config in `/usr/local/etc/caddy/caddy.d/`
  - `homelab.global` — ACME CA settings
  - `homelab.conf` — additional virtual hosts
- caddy-os plugin has native forward_auth UI (Auth Provider tab) — no custom binary needed
- Caddy Auth Provider UI → oauth2-proxy at 192.168.30.203:4180, URI `/oauth2/auth`

## LoadBalancer IPs (Cilium IPAM pool 192.168.30.200/28)
- .201 — Kanidm
- .202 — ArgoCD server
- .203 — oauth2-proxy

## k8s manifests committed
- `infra/k8s/cilium/lb-ipam-pool.yaml` — CiliumLoadBalancerIPPool
- `infra/k8s/kanidm/` — namespace, cert (homelab-ca), configmap, pvc, deployment, service
- `infra/k8s/oauth2-proxy/` — namespace, deployment, service, secrets.sops.yaml
- `infra/k8s/argocd/apps/` — cilium-lb-ipam, kanidm (wave 1), oauth2-proxy (wave 2)
- Kyverno: kanidm + oauth2-proxy exempted from baseline; databases excluded from Istio Ambient

## ArgoCD: server exposed via LoadBalancer
Added `server.service.type: LoadBalancer` + `lbipam.cilium.io/ips: 192.168.30.202` to `infra/k8s/argocd/values.yaml`. Requires manual sync (selfHeal: false).

## Pending (not yet done)
1. OPNsense shell: create `homelab.global` and `homelab.conf` in caddy.d/, download tinyca root cert
2. Run OPNsense API script for firewall rules + Unbound host override for tinyca.opnsense.internal
3. AdGuard DNS rewrites for all domains → 192.168.1.1
4. Kanidm first-run: `kubectl exec -n kanidm deploy/kanidm -- kanidmd recover-account admin -c /etc/kanidm/server.toml`
5. Register oauth2-proxy OAuth2 client in Kanidm, update secrets.sops.yaml with real client secret
6. Configure Caddy Auth Provider UI in OPNsense

## Kanidm config detail
- domain: `kanidm.opnsense.internal`
- origin: `https://kanidm.opnsense.internal`
- TLS cert from homelab-ca ClusterIssuer (chains to TinyCA root)
- Data PVC: Longhorn, 5Gi
- Image: kanidm/server:1.4.3

## How to apply: Caddy Auth Provider UI
- Protocol: http://
- Domain: 192.168.30.203
- Port: 4180
- URI: /oauth2/auth
- Copy Headers: X-Auth-Request-User, X-Auth-Request-Email
