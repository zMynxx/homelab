---
name: project-externaldns-todo
description: ExternalDNS AdGuard Home integration — pending tasks to finish the setup
metadata:
  type: project
---

ExternalDNS is deployed as an ArgoCD app (chart 1.22.0, webhook provider for AdGuard Home). App and values are in git but the integration is not yet functional.

**Why:** User wants ExternalDNS to manage DNS records in AdGuard Home automatically.

**How to apply:** When user returns to ExternalDNS work, pick up from this checklist.

## TODO — Finish ExternalDNS Integration

1. **Create the `externaldns-adguard` Secret** in `external-dns` namespace:
   ```bash
   kubectl create secret generic externaldns-adguard \
     --namespace external-dns \
     --from-literal=username=<user> \
     --from-literal=password=<pass>
   ```
   Consider SOPS-encrypting this and committing it to `infra/k8s/externaldns/`.

2. **Set `ADGUARD_URL`** in `infra/k8s/externaldns/values.yaml` — current placeholder assumes in-cluster AdGuard at `adguard-home.adguard-home.svc.cluster.local`; update to actual LAN IP/service if AdGuard runs outside the cluster.

3. **Add `domainFilters`** (e.g. `["home.arpa"]`) to `values.yaml` to prevent ExternalDNS from touching unintended zones.

4. **Add `external-dns` to Kyverno baseline exclusions** in `infra/k8s/kyverno/policies/baseline.yaml` — same `exclude.any` pattern used for cert-manager, istio-system, etc. The AdGuard webhook sidecar may trip `require-non-root` or `require-resource-limits`.

5. **Verify ArgoCD sync** after all above: check `kubectl get pods -n external-dns` and ExternalDNS logs for successful provider handshake.

## Files
- `infra/k8s/argocd/apps/externaldns.yaml` — ArgoCD Application
- `infra/k8s/externaldns/values.yaml` — Helm values (webhook provider wired, URL/secret placeholders)
