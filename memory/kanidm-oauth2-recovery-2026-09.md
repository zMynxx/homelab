---
name: kanidm-oauth2-recovery-2026-09
description: Kanidm + kaniop + oauth2-proxy full recovery after Kanidm rebuild — root causes and fixes
metadata:
  type: project
---

## Kanidm & oauth2-proxy recovery after database rebuild (2026-09-13/14)

**What**: Full recovery of Kanidm auth stack after Longhorn storage migration caused pod restarts and secret loss.

**Why**: Longhorn moved from `/var/lib/longhorn` (SD card in kubelet namespace) to `/var/mnt/longhorn` (NVMe via UserVolumeConfig). Kanidm PVCs were rebuilt, erasing the database. The `kanidm-admin-passwords` secret was also manually deleted during troubleshooting.

**How to apply**: Reference this when Kanidm needs recovery or kaniop isn't bootstrapping.

---

### Root Causes & Fixes

**1. kaniop not bootstrapping admin secret**
- Symptom: `Initialized: False`, `AdminSecretNotExists` in Kanidm CR; all sub-reconcilers failing 404
- Fix: `kubectl rollout restart deployment/kaniop -n kaniop` — the Kanidm CR reconciler (top-level) only ran after restart
- Result: `kanidm-admin-passwords` secret created with `ADMIN_PASSWORD` and `IDM_ADMIN_PASSWORD`

**2. Groups not being reconciled (lior not in any groups)**
- Symptom: kaniop reconciling groups without errors but no members in Kanidm
- Root cause: `groups.yaml` (no members) and `group-memberships.yaml` (with members) defined the SAME KanidmGroup CRs. ArgoCD applies alphabetically: `group-memberships.yaml` first, `groups.yaml` second → overwrites members with empty
- Fix: Merged members into `groups.yaml`, deleted `group-memberships.yaml`

**3. oauth2-proxy crash-looping (OIDC discovery 404 "nomatchingentries")**
- Symptom: `failed to discover OIDC configuration: unexpected status "404": "nomatchingentries"`
- Root cause: The generic `oauth2-proxy` OAuth2 client was manually created in Kanidm before the rebuild and was lost
- Fix: Added `KanidmOAuth2Client` named `oauth2-proxy` to `infra/k8s/kanidm/oauth2-clients.yaml`; after kaniop created it, decoded `CLIENT_SECRET` from `oauth2-proxy-kanidm-oauth2-credentials` secret in `kanidm` namespace; updated `infra/k8s/oauth2-proxy/secrets.sops.yaml` with new secret via `sops --set`

**4. oauth2-proxy-adguard removal**
- Removed: `adguard-deployment.yaml`, `adguard-secrets.sops.yaml`, `adguard-service.yaml` from `infra/k8s/oauth2-proxy/`
- Had to delete cluster resources manually (ArgoCD `prune: false` won't auto-delete)
- ArgoCD `selfHeal: true` was recreating the DaemonSet until the git removal was pushed

---

### Credential Reset for lior
- Use: `kanidm person credential create-reset-token -H https://kanidm.opnsense.internal -D idm_admin lior`
- Must be logged in as `idm_admin` (not `admin` — admin is not authorized for person credential resets)
- Admin login: credentials in `kanidm/kanidm-admin-passwords` secret

### kaniop-generated OAuth2 secrets format
- Location: `kanidm` namespace, named `<client-name>-kanidm-oauth2-credentials`
- Keys: `CLIENT_ID` (base64) and `CLIENT_SECRET` (base64)
- These are NOT automatically synced to other namespaces; SOPS secrets must be manually updated when clients are recreated
