---
name: feedback-fqdn
description: Always use full Kubernetes FQDNs in manifests, not short service names
metadata:
  type: feedback
---

Always use fully qualified Kubernetes service names (FQDNs) — never bare short names.

**Why:** User explicitly requires this. Short names rely on search domain resolution which can fail or behave unexpectedly across namespaces and DNS implementations.

**How to apply:** In any Kubernetes manifest, Helm values, or config that references a service, always use the full form: `<service>.<namespace>.svc.cluster.local`. For example:
- `argocd-dex-server.argocd.svc.cluster.local` not `argocd-dex-server`
- `argocd-cache.argocd.svc.cluster.local` not `argocd-cache`
- `argocd-repo-server.argocd.svc.cluster.local` not `argocd-repo-server`
