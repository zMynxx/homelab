---
name: project-caddy-sso-setup
description: Caddy reverse proxy on OPNsense with TinyCA ACME certs + Kanidm SSO + oauth2-proxy — current working state
metadata:
  type: project
---

## Architecture (WORKING as of 2026-09-09)
- Caddy on OPNsense (caddy-os plugin) — reverse proxy for `*.opnsense.internal`
- TinyCA (Step-CA) at `192.168.10.37:8443` — ACME CA
- Kanidm at `192.168.30.201:8443` (LoadBalancer) — OIDC IdP (v1.11.1)
- oauth2-proxy at `192.168.30.203:4180` (LoadBalancer) — forward_auth bridge
- ArgoCD at `192.168.30.202:80` (argocd-self-server LoadBalancer)

## IP Assignments (Cilium LB IPAM 192.168.30.200/28)
- `192.168.30.201` — Kanidm (ports 8443, 3636)
- `192.168.30.202` — ArgoCD (argocd-self-server, ports 80/443)
- `192.168.30.203` — oauth2-proxy (port 4180)

## OPNsense Access
- VLAN10 MGMT: `192.168.10.1`
- API: `https://127.0.0.1:8443/api/` (from OPNsense SSH session — NOT reachable from VLAN30)
- Web UI: not reachable from VLAN30 (192.168.30.0/24)
- SSH: requires key from Bitwarden agent

## Caddy Config Status (WORKING)
Auto-generated Caddyfile via caddy-os handles:
- `firewall.opnsense.internal` → `192.168.1.1:8443` (OPNsense GUI, restricted to 192.168.1.0/24)
- `kanidm.opnsense.internal` → `192.168.30.201:8443` (HTTPS passthrough, tls_insecure_skip_verify)
- `oauth2proxy.opnsense.internal` → `192.168.30.203:4180`

Manual `.conf` files in `/usr/local/etc/caddy/caddy.d/` (NOT managed by caddy-os GUI):
- `homelab.global` — ACME CA config pointing to TinyCA at `https://192.168.10.37:8443/acme/acme/directory`
- `argocd.conf` — ArgoCD with SSO (cookie pre-check + forward_auth)

**CRITICAL**: argocd was REMOVED from caddy-os GUI (deleted from config.xml, UUID `346edae3-5d30-4d72-ad2b-6238c7ad4da8`). It is managed ONLY via `/usr/local/etc/caddy/caddy.d/argocd.conf`. If caddy-os is reconfigured via GUI and argocd is re-added, there will be a duplicate site error — remove it via `python3` edit of config.xml using the UUID approach.

## argocd.conf (cookie pre-check SSO pattern)
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

**Known limitation**: If the cookie exists but is expired, forward_auth returns 401 → user sees "Unauthorized" instead of being redirected to login. Not yet fixed.

## oauth2-proxy Config (infra/k8s/oauth2-proxy/deployment.yaml)
Key args:
- `--oidc-issuer-url=https://kanidm.kanidm.svc.cluster.local:8443/oauth2/openid/oauth2-proxy` (cluster-internal — CoreDNS resolves it; external kanidm.opnsense.internal doesn't resolve from pods)
- `--insecure-oidc-skip-issuer-verification=true` (Kanidm's origin is kanidm.opnsense.internal, not the cluster URL)
- `--redirect-url=https://oauth2proxy.opnsense.internal/oauth2/callback` (NO hyphen — must match Kanidm client registration exactly)
- `--upstream=static://202` (forward-auth mode)
- `--cookie-name=_oauth2_proxy_homelab`
- `--cookie-domain=.opnsense.internal`
- `--code-challenge-method=S256` (PKCE — required by Kanidm, causes InvalidState error if omitted)
- `--skip-provider-button=true`
- `--ssl-insecure-skip-verify=true` (Kanidm cert signed by homelab-ca/istio-ca)

## DNS (AdGuard)
All `*.opnsense.internal` → `192.168.30.1` (VLAN30 gateway, reachable from client at 192.168.30.101)
**NOT 192.168.10.1** (MGMT VLAN, unreachable from VLAN30 clients)

## ArgoCD Native OIDC with Kanidm (CONFIGURED — pending sync)
Configured in `infra/k8s/argocd/values.yaml` (`configs.cm.oidc.config`):
- Issuer: `https://kanidm.opnsense.internal/oauth2/openid/argocd`
- ClientID: `argocd`
- Client secret: in SOPS-encrypted `infra/k8s/argocd/oidc/argocd-oidc-kanidm.sops.yaml` (Secret `argocd-oidc-kanidm`, key `clientSecret`)
- Referenced in oidc.config as `$argocd-oidc-kanidm:clientSecret` (ArgoCD external secret syntax)
- ArgoCD callback URL registered in Kanidm: `https://argocd.opnsense.internal/auth/callback`
- Scopes: openid, email, profile, groups
- `insecureSkipVerify: true` (Kanidm cert signed by homelab CA)
- `policy.default: role:admin` (all authenticated users get admin — homelab only)
- Managed by ArgoCD Application `argocd-oidc` (`infra/k8s/argocd/apps/argocd-oidc.yaml`)
- **Requires ArgoCD sync to be fixed before this takes effect** (see below)
- If ArgoCD sync is broken: manually apply with `kubectl apply -f infra/k8s/argocd/oidc/argocd-oidc-kanidm.sops.yaml` (after decrypting) and `helm upgrade argocd argo/argo-cd -f infra/k8s/argocd/values.yaml -n argocd`

## ArgoCD Sync Issue (UNRESOLVED)
All apps show "Unknown" sync status. Error: `failed to list refs: EOF`
- GitHub reachable from cluster (HTTP 200 confirmed)
- Repo: `https://github.com/zmynxx/homelab.git` (public, HTTPS)
- No GitHub repo secret registered in ArgoCD (only OCI Helm repos for dragonfly + spegel)
- argocd-application-controller StatefulSet logs timed out — couldn't read
- **TODO**: Investigate. May need to register the git repo even if public, or check argocd-application-controller logs

## OPNsense API (from OPNsense SSH session only)
Use `https://127.0.0.1:8443/api/` — external interfaces don't accept API from VLAN30.
caddy-os config structure in API response: `caddy.reverseproxy.reverse.<uuid>.*`
To find a UUID: `curl ... /api/caddy/ReverseProxy/get | python3 -c "import json,sys; d=json.load(sys.stdin); [print(k,v.get('FromDomain')) for k,v in d['caddy']['reverseproxy']['reverse'].items()]"`

## mTLS Client Certs (DEFERRED — needs physical Pi access)
TinyCA SSH is disabled (smallstep security hardening). To enable mTLS:
1. Physical access to TinyCA Pi → add JWK provisioner → `step ca provisioner add admin --type JWK --create && sudo systemctl restart step-ca`
2. On Mac: bootstrap + issue client cert + import into macOS Keychain
3. Re-enable `ClientAuthMode=require_and_verify` on Caddy vhosts

TinyCA fingerprint: `ded8941c2c3260a6d65a40147a7fe8af9034f24c927cc782ad8ac7d234bd7736`

## Security Notes
- Credentials (OPNsense API key, Kanidm passwords, oauth2-proxy secrets) stored in `infra/docs/memory/credentials.sops.yaml`
- OPNsense API keys are single-use — if shared in chat, regenerate via GUI
