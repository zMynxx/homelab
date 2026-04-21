# GitOps — ArgoCD + Kustomize

> Trigger: argocd, argo, gitops, kustomize, kustomization, application, applicationset, deploy, manifest, overlay, sync

## Architecture

- **GitOps Engine**: ArgoCD — single source of truth for cluster state
- **Templating**: Kustomize (NOT Helm as primary — Helm charts are consumed via Kustomize when needed)
- **Repository**: This repo (`homelab`) is the GitOps repo. ArgoCD watches it.
- **Cluster**: Talos Linux on TuringPi2 (see `talos-cluster` skill)

## Directory Convention

All Kubernetes manifests follow the Kustomize directory layout:

```
k8s/                              # Root for all Kubernetes manifests
├── argocd/                       # ArgoCD self-management
│   ├── base/
│   │   ├── kustomization.yaml
│   │   └── namespace.yaml
│   └── overlays/
│       └── prod/
│           ├── kustomization.yaml
│           └── patches/
├── apps/                         # Application workloads
│   ├── <app-name>/
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   └── ...
│   │   └── overlays/
│   │       └── prod/
│   │           ├── kustomization.yaml
│   │           └── patches/
├── infrastructure/               # Cluster infrastructure (CNI, mesh, storage, etc.)
│   ├── cilium/
│   ├── istio/
│   ├── kyverno/
│   ├── falco/
│   ├── cert-manager/
│   ├── metallb/
│   ├── longhorn/
│   └── ...
└── platform/                     # Platform services (monitoring, logging, etc.)
    ├── prometheus/
    ├── grafana/
    ├── loki/
    └── ...
```

## Kustomize Rules

1. **Every directory with manifests MUST have a `kustomization.yaml`**.
2. **Base** contains the canonical resource definitions — no environment-specific values.
3. **Overlays** apply environment-specific patches (currently only `prod` — this is a homelab).
4. **Patches** go in `overlays/<env>/patches/` as strategic merge patches or JSON patches.
5. **Never use `kubectl apply` directly** — all changes go through Git → ArgoCD sync.
6. **Namespace** is declared in `kustomization.yaml` via `namespace:` field, not in individual resources.
7. **Common labels** are applied via `kustomization.yaml` `commonLabels:` — not duplicated per resource.
8. **Image tags** are managed via `kustomization.yaml` `images:` section — never hardcode in deployments.
9. When consuming Helm charts, use `helmCharts` in kustomization.yaml or an ArgoCD Application with `source.helm`.

## ArgoCD Patterns

### Application Definition
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app-name>
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: <this-repo-url>
    targetRevision: main
    path: k8s/apps/<app-name>/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: <target-namespace>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### App of Apps / ApplicationSet
- Use **ApplicationSet** with Git directory generator to auto-discover apps.
- Place ApplicationSet definitions in `k8s/argocd/overlays/prod/`.
- ApplicationSets should target directory structures, not enumerate apps manually.

## Hard Rules

- **No `kubectl apply`** for anything managed by ArgoCD. Git is the only interface.
- **No secrets in Git** — use SealedSecrets, SOPS, or ExternalSecrets. Never commit plaintext secrets.
- **Sync waves** for ordering: infrastructure (wave 0) → platform (wave 1) → apps (wave 2).
- **Prune enabled** — resources removed from Git get removed from cluster.
- **Self-heal enabled** — manual cluster changes get reverted to Git state.
- All ArgoCD Applications live in the `argocd` namespace.
