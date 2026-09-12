---
name: argocd-oidc-setup
description: ArgoCD SSO via Dex → Kanidm, protected by Caddy + oauth2-proxy forward_auth — working state as of 2026-09-12
metadata:
  type: project
---

## Architecture Overview

ArgoCD login uses two auth layers stacked on top of each other:

```
Browser → Caddy (OPNsense)
           ├── Layer 1: oauth2-proxy forward_auth (Kanidm client: oauth2-proxy)
           │            sets cookie _oauth2_proxy_homelab on .opnsense.internal
           └── Layer 2: ArgoCD Dex OIDC (Kanidm client: argocd)
                        issues ArgoCD session token
```

**Layer 1 — Network gate**: Caddy blocks unauthenticated requests to `argocd.opnsense.internal` using oauth2-proxy as a forward-auth sidecar. The browser must hold a valid `_oauth2_proxy_homelab` cookie (domain `.opnsense.internal`) before any request reaches ArgoCD.

**Layer 2 — Application auth**: Once past Caddy, ArgoCD's own login UI uses Dex as OIDC intermediary. Dex talks to Kanidm directly (cluster-internal URL). After Dex callback, ArgoCD issues its own session token.

Both layers authenticate against Kanidm but use separate OAuth2 client registrations.

---

## Component Reference

| Component | Where | Endpoint |
|---|---|---|
| Caddy | OPNsense (caddy-os + manual .conf) | `argocd.opnsense.internal` |
| oauth2-proxy | `oauth2-proxy` namespace, LB `192.168.30.203` | `:4180` |
| ArgoCD | `argocd` namespace, LB `192.168.30.202` | `:80` (insecure, TLS by Istio) |
| Dex | `argocd` namespace, sidecar to argocd-server | `:5556` (internal) |
| Kanidm | `kanidm` namespace, LB `192.168.30.201` | `:8443` |

---

## Layer 1: Caddy + oauth2-proxy

### Caddy config (`/usr/local/etc/caddy/caddy.d/argocd.conf` on OPNsense)

```caddy
argocd.opnsense.internal {
    @private {
        not client_ip 192.168.0.0/16
    }
    handle @private {
        abort
    }

    # No auth cookie → redirect to sign-in immediately
    # NOTE: handle_errors 401 does NOT work with forward_auth —
    # Caddy writes the upstream 401 directly to the client, bypassing handle_errors.
    @unauth {
        not header_regexp Cookie _oauth2_proxy_homelab=
    }
    handle @unauth {
        redir https://oauth2proxy.opnsense.internal/oauth2/sign_in?rd={scheme}://{host}{uri} 302
    }

    # Cookie present → validate with forward_auth
    handle {
        forward_auth http://192.168.30.203:4180 {
            uri /oauth2/auth
            copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
        }
        reverse_proxy 192.168.30.202:80
    }
}
```

**CRITICAL**: argocd was removed from the caddy-os GUI (config.xml UUID `346edae3-5d30-4d72-ad2b-6238c7ad4da8`). It is managed ONLY via `argocd.conf`. If caddy-os is reconfigured via GUI and argocd is re-added, there will be a duplicate site error. Remove via `python3` edit of config.xml using the UUID approach.

**Known limitation**: If the cookie exists but is expired, forward_auth returns 401 → user sees "Unauthorized" instead of being redirected to login.

### oauth2-proxy (Kanidm client: `oauth2-proxy`)

Files: `infra/k8s/oauth2-proxy/deployment.yaml`, `service.yaml`, `secrets.sops.yaml`

Key configuration decisions:
- `--oidc-issuer-url=https://kanidm.kanidm.svc.cluster.local:8443/oauth2/openid/oauth2-proxy`
  Use cluster-internal URL — pods cannot resolve `kanidm.opnsense.internal` (AdGuard DNS is on host network, not reachable from pods)
- `--insecure-oidc-skip-issuer-verification=true`
  Kanidm's configured origin is `kanidm.opnsense.internal` so the issuer in OIDC discovery won't match the cluster-internal URL
- `--ssl-insecure-skip-verify=true`
  Kanidm's cert is signed by homelab-ca (istio-ca intermediate) — not in the oauth2-proxy container trust store
- `--code-challenge-method=S256`
  Required by Kanidm. Without PKCE, Kanidm returns `InvalidState` error
- `--upstream=static://202`
  forward_auth mode — oauth2-proxy returns 200/401 without proxying any upstream itself
- `--cookie-name=_oauth2_proxy_homelab`, `--cookie-domain=.opnsense.internal`
  Cookie is shared across all `.opnsense.internal` subdomains
- `--redirect-url=https://oauth2proxy.opnsense.internal/oauth2/callback`
  Must match the Kanidm client registration exactly (including no trailing slash)

LoadBalancer: `192.168.30.203:4180` via Cilium IPAM annotation `lbipam.cilium.io/ips`

Kanidm client registration (in Kanidm admin UI):
- Client ID: `oauth2-proxy`
- Redirect URL: `https://oauth2proxy.opnsense.internal/oauth2/callback`
- PKCE: enabled
- Scopes: `openid email profile`

---

## Layer 2: ArgoCD Dex + Kanidm (Kanidm client: `argocd`)

### How Dex fits in

ArgoCD's native OIDC does not support PKCE, but Kanidm requires it. Dex acts as an OIDC intermediary:
- Browser authenticates with Dex (ArgoCD trusts Dex)
- Dex authenticates with Kanidm using PKCE (`enablePKCE: true`)
- Dex issues a token to ArgoCD after Kanidm confirms identity

### Dex config (in `infra/k8s/argocd/values.yaml`)

```yaml
configs:
  cm:
    dex.config: |
      connectors:
      - type: oidc
        id: kanidm
        name: Kanidm
        config:
          issuer: https://kanidm.opnsense.internal/oauth2/openid/argocd
          clientID: argocd
          clientSecret: $argocd-oidc-kanidm:clientSecret
          redirectURI: https://argocd.opnsense.internal/api/dex/callback
          scopes:
            - openid
            - email
            - profile
            - groups
          rootCAs:
            - /etc/ssl/caddy-ca/ca.crt
          enablePKCE: true
```

Key decisions:
- `issuer` uses the EXTERNAL URL (`kanidm.opnsense.internal`) because Dex runs in OPNsense's network context (cluster pod → Caddy → Kanidm), and `rootCAs` is required since Kanidm's cert is signed by the homelab CA
- The homelab CA cert is mounted from ConfigMap `argocd-caddy-local-ca` into Dex at `/etc/ssl/caddy-ca/ca.crt`
- `$argocd-oidc-kanidm:clientSecret` is ArgoCD's external secret syntax — reads from Secret `argocd-oidc-kanidm`, key `clientSecret`
- `enablePKCE: true` handles the Kanidm PKCE requirement at the Dex→Kanidm leg

### argocd-caddy-local-ca ConfigMap

File: `infra/k8s/argocd/caddy-local-ca-cm.yaml`

Contains the homelab-ca certificate (TinyCA root). Mounted into Dex pod at `/etc/ssl/caddy-ca`. Without this, Dex cannot verify Kanidm's TLS cert and authentication fails with a TLS error.

### Client secret Secret

File: `infra/k8s/argocd/oidc/argocd-oidc-kanidm.sops.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-oidc-kanidm
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd  # required — ArgoCD only reads Secrets with this label
type: Opaque
stringData:
  clientSecret: <encrypted>
```

The `app.kubernetes.io/part-of: argocd` label is mandatory. Without it, ArgoCD's repo-server refuses to read the Secret and `$argocd-oidc-kanidm:clientSecret` resolves to empty string.

Managed by ArgoCD Application `argocd-oidc` (`infra/k8s/argocd/apps/argocd-oidc.yaml`), decrypted by the SOPS CMP plugin.

### RBAC

```yaml
configs:
  rbac:
    policy.default: role:admin
```

All authenticated users get admin. Appropriate for a single-user homelab.

### Kanidm client registration (in Kanidm admin UI)

- Client ID: `argocd`
- Redirect URL: `https://argocd.opnsense.internal/api/dex/callback`
- PKCE: enabled
- Scopes: `openid email profile groups`

---

## Login Flow (end-to-end)

1. Browser → `https://argocd.opnsense.internal`
2. Caddy: no `_oauth2_proxy_homelab` cookie → redirect to `https://oauth2proxy.opnsense.internal/oauth2/sign_in?rd=...`
3. oauth2-proxy → redirects browser to Kanidm (`oauth2-proxy` client) for login
4. User authenticates with Kanidm → Kanidm redirects to `oauth2proxy.opnsense.internal/oauth2/callback`
5. oauth2-proxy sets `_oauth2_proxy_homelab` cookie → redirects browser back to `argocd.opnsense.internal`
6. Caddy: cookie present → forward_auth validates with oauth2-proxy → 200 → proxies to `192.168.30.202:80`
7. ArgoCD UI loads → user clicks "Log in via Dex"
8. Browser → Dex at `argocd.opnsense.internal/api/dex/auth`
9. Dex → redirects to Kanidm (`argocd` client) with PKCE
10. User is already authenticated in Kanidm (session cookie) → Kanidm auto-approves → redirects to `argocd.opnsense.internal/api/dex/callback`
11. Dex validates, issues token → ArgoCD grants session
12. User is logged in to ArgoCD

Step 10 usually requires no second login since Kanidm holds the session from step 4.

---

## Troubleshooting

### "Invalid client" or "InvalidState" from Kanidm
- Check PKCE is enabled on the Kanidm client
- Verify `--code-challenge-method=S256` is set on oauth2-proxy
- Verify `enablePKCE: true` is set in Dex connector config

### Dex TLS error connecting to Kanidm
- Verify `argocd-caddy-local-ca` ConfigMap exists in `argocd` namespace
- Verify Dex pod has the ConfigMap mounted at `/etc/ssl/caddy-ca`
- Verify the CA cert in the ConfigMap matches the one that signed Kanidm's cert

### `$argocd-oidc-kanidm:clientSecret` resolves to empty
- Verify Secret `argocd-oidc-kanidm` exists in `argocd` namespace
- Verify it has label `app.kubernetes.io/part-of: argocd`
- Verify the SOPS CMP plugin decrypted it (check repo-server logs for SOPS errors)

### oauth2-proxy "oauth2 error: could not verify token"
- The cluster-internal Kanidm URL must be used for `--oidc-issuer-url`
- `--insecure-oidc-skip-issuer-verification=true` must be set

### Dex pod crashlooping (OOMKill)
- Dex copies binaries at startup — needs at least 256Mi memory limit
- See `infra/k8s/argocd/values.yaml` `dex.resources`

### Cookie present but user gets 401 ("Unauthorized") instead of login redirect
- Cookie is expired — Caddy's `@unauth` check only looks for cookie presence, not validity
- User must manually visit `https://oauth2proxy.opnsense.internal/oauth2/sign_in` to re-authenticate
- This is a known limitation of the cookie pre-check pattern
