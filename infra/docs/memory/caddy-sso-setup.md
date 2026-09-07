---
name: project-caddy-sso-setup
description: Caddy reverse proxy on OPNsense with TinyCA mTLS + Kanidm SSO + oauth2-proxy — current state and next steps
metadata:
  type: project
---

## Architecture
- Caddy on OPNsense (caddy-os plugin) — reverse proxy for `*.opnsense.internal`
- TinyCA (Step-CA) at `192.168.10.37:8443` — ACME CA + mTLS client cert issuer
- Kanidm at `192.168.30.201:8443` (LoadBalancer) — OIDC IdP
- oauth2-proxy at `192.168.30.203:4180` (LoadBalancer) — forward_auth bridge
- ArgoCD at `192.168.30.202:80` (LoadBalancer) — GitOps

## IP Assignments (Cilium LB IPAM 192.168.30.200/28)
- `192.168.30.201` — Kanidm (ports 8443, 3636)
- `192.168.30.202` — ArgoCD server
- `192.168.30.203` — oauth2-proxy

## OPNsense Access
- IP: `192.168.10.1` (VLAN 10 Management)
- API: `https://192.168.10.1:8443/api/`
- SSH: `zMynx@192.168.1.1` with vault key

## Caddy Status (COMPLETE)
- Running on port 443 (disabled HTTP redirect — port 80 was occupied)
- Virtual hosts configured via caddy-os API:
  - `firewall.opnsense.internal` → `192.168.1.1:8443` (OPNsense GUI)
  - `argocd.opnsense.internal` → `192.168.30.202:80` (HTTP)
  - `kanidm.opnsense.internal` → `192.168.30.201:8443` (HTTPS, **TODO: fix transport**)
  - `oauth2proxy.opnsense.internal` → `192.168.30.203:4180` (HTTP)
- mTLS enabled on ALL virtual hosts: `ClientAuthMode=require_and_verify`, `ClientAuthTrustPool=TinyCA Homelab Root CA`
- TinyCA root imported into OPNsense trust store (UUID: `8d570851-7915-40fc-9a84-685792519267`, refid: `6a9f14342b28d`)
- ACME CA configured: `/usr/local/etc/caddy/caddy.d/homelab.global` contains `acme_ca` + `acme_ca_root` pointing to TinyCA
- Auth Provider: `authelia` (oauth2-proxy compatible) → `http://192.168.30.203:4180/oauth2/auth`
- ArgoCD handle has `ForwardAuth=1` (SSO-protected)

**TODO (Caddy):**
- Fix Kanidm handle backend TLS: in OPNsense web UI → Services → Caddy → Reverse Proxy → Handles → Kanidm handle → set Upstream Transport to `https://`, Trusted CA to `TinyCA Homelab Root CA`. (API rejects `HttpTls` field due to caddy-os validation bug with `://` in values)

## DNS (AdGuard — already configured)
All `*.opnsense.internal` domains → `192.168.10.1`, plus:
- `tinyca.opnsense.internal` → `192.168.10.37` (also in Unbound host overrides)

## Unbound Host Override (COMPLETE)
- `tinyca.opnsense.internal` → `192.168.10.37` (UUID: `4fff06a3-5296-426c-a17e-3618550c13a1`)

## mTLS Client Cert (TODO — BLOCKED: can't SSH into TinyCA Pi)
TinyCA only has ACME provisioner — need to add JWK provisioner first:
```sh
# SSH into TinyCA Pi
ssh <user>@192.168.10.37
step ca provisioner add admin --type JWK --create
sudo systemctl restart step-ca
exit
```
Then on Mac:
```sh
step ca bootstrap \
  --ca-url https://tinyca.opnsense.internal:8443 \
  --fingerprint ded8941c2c3260a6d65a40147a7fe8af9034f24c927cc782ad8ac7d234bd7736 \
  --install

step ca certificate "$(hostname)" \
  "$(hostname)".crt "$(hostname)".key \
  --not-after=8760h \
  --ca-url https://tinyca.opnsense.internal:8443 \
  --provisioner admin

step certificate p12 "$(hostname)".p12 \
  "$(hostname)".crt "$(hostname)".key \
  --ca ~/.step/certs/root_ca.crt

open "$(hostname)".p12  # install into macOS Keychain
```
TinyCA fingerprint: `ded8941c2c3260a6d65a40147a7fe8af9034f24c927cc782ad8ac7d234bd7736`

## K8s Deployments
- **Kanidm**: Pod running (`kanidm-6f75fd85f5-tlj6f`), config at `/data/server.toml`, db at `/data/kanidm.db`
  - idm_admin password recovered: `CqxZezXFZESt8Y21GdK1dsBrZvH3GPKzCQHfZQGJWhdBKteG` (**STORE SECURELY, ROTATE AFTER USE**)
- **oauth2-proxy**: Deployed (namespace + deployment + service + secret), but pods in CrashLoopBackOff — needs real Kanidm client secret
- **ArgoCD**: LB service at `192.168.30.202` confirmed active

## Kanidm oauth2-proxy Registration (TODO — NEXT STEP)
Need to run while `kubectl port-forward svc/kanidm -n kanidm 9443:8443` is active:
```sh
brew install kanidm  # if not installed

kanidm login --name idm_admin \
  --url https://localhost:9443 --skip-hostname-verification

kanidm system oauth2 create oauth2-proxy "oauth2-proxy" \
  "https://oauth2proxy.opnsense.internal/oauth2/callback" \
  --url https://localhost:9443 --skip-hostname-verification

kanidm system oauth2 update-scope-map oauth2-proxy \
  idm_all_persons openid email profile \
  --url https://localhost:9443 --skip-hostname-verification

kanidm system oauth2 show-basic-secret oauth2-proxy \
  --url https://localhost:9443 --skip-hostname-verification
```
Then update the SOPS secret with the real client secret:
```sh
SOPS_AGE_KEY_FILE=key.txt.secret sops -d infra/k8s/oauth2-proxy/secrets.sops.yaml > /tmp/s.yaml
# edit OAUTH2_PROXY_CLIENT_SECRET in /tmp/s.yaml
SOPS_AGE_KEY_FILE=key.txt.secret sops -e /tmp/s.yaml > infra/k8s/oauth2-proxy/secrets.sops.yaml
rm /tmp/s.yaml
kubectl apply -f infra/k8s/oauth2-proxy/secrets.sops.yaml  # after decrypting
kubectl rollout restart deploy/oauth2-proxy -n oauth2-proxy
git add -A && git commit -m "fix(oauth2-proxy): set real Kanidm client secret" && git push
```

## ArgoCD Sync Issue
All apps show "Unknown" sync status. Root cause: not yet fully diagnosed.
- GitHub is reachable from cluster (`git ls-remote` works)
- Repo is public (HTTP 200)
- `argocd-self` uses multi-source (Helm chart + git values) — Helm chart source may be causing TLS issues
- Git-only apps (kanidm, oauth2-proxy) were deployed manually via `kubectl apply`

## Security Notes
- OPNsense API key shared in chat — REVOKE AND REGENERATE
- idm_admin password above — store in password manager and rotate
