# Kanidm Setup Guide

## Environment
- Domain: `kanidm.opnsense.internal`
- Origin: `https://kanidm.opnsense.internal`
- Replication: 3-node (kanidm-0, kanidm-1, kanidm-2)
- Access via Caddy + oauth2-proxy at `https://kanidm.opnsense.internal`

## Logos Available
- ✅ Grafana (2249x2500, 116K)
- ✅ Longhorn (1556x767, 25K)
- ✅ Zot (420x420, 1.5K)
- ⚠️ Cilium/Hubble (needs manual logo)
- ⚠️ Kiali (needs manual logo)

Logos stored in `/infra/k8s/kanidm/logos/`

## Setup Steps

### 1. Initial Admin Recovery
If Kanidm is not yet initialized, recover the admin account:

```bash
kubectl exec -n kanidm deploy/kanidm -- kanidmd recover-account admin -c /etc/kanidm/server.toml
```

### 2. Log In to Kanidm Admin UI
Access https://kanidm.opnsense.internal (must be on 192.168.0.0/16 network)

### 3. Create Groups
Navigate to **Groups** and create:

| Group | Description |
|-------|-------------|
| `grafana-admins` | Grafana administrators |
| `longhorn-admins` | Longhorn storage admins |
| `zot-users` | Container registry users |
| `hubble-viewers` | Cilium observability viewers |
| `kiali-viewers` | Istio service mesh viewers |
| `homelab-users` | General homelab access (optional parent) |

### 4. Create User `lior`
1. Navigate to **Users** → **+ Create User**
2. Fill in:
   - **Username:** `lior`
   - **Display Name:** Your display name
   - **Email:** lior.dux@develeap.com
   - **Password:** Set secure password (or let user reset after first login)
3. Click **Create**
4. Go to user's profile → **Member Of** → add to desired groups:
   - `grafana-admins`
   - `longhorn-admins`
   - `zot-users`
   - `hubble-viewers`
   - `kiali-viewers`

### 5. Register OAuth2 Applications

For each service, go to **Applications** → **OAuth2** → **+ Create Application**

#### Grafana
- **Name:** Grafana
- **Redirect URI:** `https://grafana.opnsense.internal/oauth2/callback`
- **Logo:** Upload `/infra/k8s/kanidm/logos/grafana.png`
- After creation, note the **Client ID** and **Client Secret**

#### Longhorn
- **Name:** Longhorn
- **Redirect URI:** `https://longhorn.opnsense.internal/oauth2/callback`
- **Logo:** Upload `/infra/k8s/kanidm/logos/longhorn.png`

#### Zot
- **Name:** Zot
- **Redirect URI:** `https://zot.opnsense.internal/oauth2/callback`
- **Logo:** Upload `/infra/k8s/kanidm/logos/zot.png`

#### Cilium Hubble
- **Name:** Hubble
- **Redirect URI:** `https://hubble.opnsense.internal/oauth2/callback`
- **Logo:** Add manually (SVG or PNG)

#### Kiali
- **Name:** Kiali
- **Redirect URI:** `https://kiali.opnsense.internal/oauth2/callback`
- **Logo:** Add manually (SVG or PNG)

### 6. Update oauth2-proxy Secrets
Once all OAuth2 apps are created, update the secrets file with client credentials.

For now, oauth2-proxy uses a single client (`oauth2-proxy`) that's already registered. If you want per-service clients, that would require additional oauth2-proxy configuration.

## Verification

1. **Test Kanidm Admin UI:**
   ```bash
   curl -k https://kanidm.opnsense.internal/
   ```

2. **Test oauth2-proxy Forward Auth:**
   ```bash
   curl -k -b "_oauth2_proxy_homelab=test" http://192.168.30.203:4180/oauth2/auth
   ```

3. **Test OIDC Discovery:**
   ```bash
   curl -k https://kanidm.opnsense.internal/oauth2/openid/oauth2-proxy/.well-known/openid-configuration
   ```

## Troubleshooting

### Admin account locked
```bash
kubectl exec -n kanidm deploy/kanidm -- kanidmd recover-account admin -c /etc/kanidm/server.toml
```

### Check Kanidm logs
```bash
kubectl logs -n kanidm -f deploy/kanidm
```

### Verify replication
```bash
kubectl exec -n kanidm kanidm-0 -- kanidm status
kubectl exec -n kanidm kanidm-1 -- kanidm status
kubectl exec -n kanidm kanidm-2 -- kanidm status
```

## Next Steps

1. ✅ Download logos (done - grafana, longhorn, zot available)
2. ⏳ Create groups in Kanidm admin UI
3. ⏳ Add `lior` user and assign to groups
4. ⏳ Register OAuth2 applications with logos
5. ⏳ Test OIDC flow for each UI service
6. ⏳ Configure per-service OAuth2 clients if needed
