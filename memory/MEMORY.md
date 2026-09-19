# Memory Index

- [Cilium + Istio Ambient pitfalls](project_cilium_istio_pitfalls.md) — 5 non-obvious issues that silently broke Istio Ambient for 27h: Kyverno admission blocking cert-manager, istiod Certificate wrong issuer kind, bpf.masquerade breaking ztunnel health checks
- [ArgoCD self-managed, DragonflyDB, Longhorn, CNPG, Reloader fixes](project_argocd_dragonfly_longhorn.md) — ArgoCD self-managed pitfalls, DragonflyDB as Redis, Longhorn split-namespace on all nodes, istiod cert renewal, CNPG large CRDs, Reloader Kyverno exclusion
- [Caddy + Kanidm + oauth2-proxy SSO setup](project_caddy_sso_setup.md) — Caddy on OPNsense reverse proxy, TinyCA ACME (port 8443), Kanidm IdP, oauth2-proxy forward-auth, Cilium LB IPAM, pending OPNsense config steps
- [Always use Kubernetes FQDNs](feedback_fqdn.md) — Use full `<svc>.<ns>.svc.cluster.local` form everywhere, never bare short service names
- [ExternalDNS AdGuard integration TODO](project_externaldns_todo.md) — ArgoCD app deployed (chart 1.22.0, webhook provider), 5 remaining steps before it's functional
- [Homelab TODO — Future Sessions](project_homelab_todo.md) — 14 items: SSO/OIDC for all UIs, Caddy/TinyCA PKI, ExternalDNS AdGuard, HA, docs/scripts, OpenChoreo eval
- [Kanidm full recovery 2026-09-14](kanidm-oauth2-recovery-2026-09.md) — kaniop bootstrap fix, group conflict fix, all 7 OAuth2 clients + logos restored, ArgoCD OIDC + RBAC fixed
- [Longhorn NVMe fix 2026-09-14](project_longhorn_nvme_fix-2026-09-14.md) — disk-mount DaemonSet was wiping NVMe on every restart (wrong path + mkfs.xfs -f); deleted it, Talos UserVolumeConfig now handles NVMe; 750GB across 3 nodes healthy
- [Ghost pod cascade + Kanidm 502 fix 2026-09-15](project_ghost_pod_cascade.md) — 212 ContainerStatusUnknown ghosts caused turingpi-3 crash loop → ingress gateway never ready → Cilium endpoint maintenance → Kanidm 502; also fixed Kyverno ambient policy labeling istio-ingress
