# GitOps - ArgoCD Managed Applications

This directory will contain all Kubernetes applications managed via ArgoCD in a GitOps fashion.

## Planned Structure

```
gitops/
├── bootstrap/          # ArgoCD bootstrap configuration
├── apps/              # Application manifests
│   ├── base/          # Base Kustomize configurations
│   └── overlays/      # Environment-specific overlays
├── infrastructure/    # Infrastructure services (cert-manager, metallb, etc.)
└── platform/          # Platform services (monitoring, logging, etc.)
```

## GitOps Workflow

1. All cluster state declared in Git
2. ArgoCD monitors this directory for changes
3. Automatic synchronization with SyncWaves for dependency ordering
4. Secrets managed via SOPS + Age encryption

## Security

- SOPS-encrypted secrets (no plaintext credentials)
- Age keys for decryption (external to cluster)
- Network policies via Cilium
- Service mesh mTLS via Istio Ambient
- Admission control via Kyverno
- Runtime security via Falco

---

**Status**: Directory structure pending - will be populated during GitOps migration
