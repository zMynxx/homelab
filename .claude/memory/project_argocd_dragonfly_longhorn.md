---
name: argocd-dragonfly-longhorn-fixes
description: ArgoCD self-managed pattern pitfalls, DragonflyDB as Redis replacement, Longhorn engine binary split-namespace on all nodes, istiod cert renewal fix
metadata:
  type: project
---

## ArgoCD self-managed (argocd-self Helm release) pitfalls

**What**: Several non-obvious issues when running ArgoCD managing itself via a Helm release named `argocd-self`.

**Pitfalls**:
1. `argocd-self` Helm overwrites `argocd-cmd-params-cm` — controllers get redirected to `argocd-self-redis:6379` and `argocd-self-repo-server:8081`. Fix: lock via `configs.params` in values.yaml.
2. Duplicate `redis:` keys in values.yaml — second block silently overrides first (including `enabled: false`). Always merge into single block.
3. Auto-created NetworkPolicies use `instance=argocd` selector — blocks `argocd-self-*` pods (instance=argocd-self) from accessing `argocd-redis` and `argocd-repo-server`. Patch both NPs to add ingress from `argocd-self-*`.
4. `argocd-redis` secret: bootstrap controller reads `auth` key; self-managed controller reads `redis-password` key. Must add `redis-password` key to secret.

**Files**: `infra/k8s/argocd/values.yaml`

## DragonflyDB as ArgoCD Redis replacement

**What**: ArgoCD uses DragonflyDB (Redis-compatible) cluster instead of built-in Redis.

**Setup**:
- `dragonfly-operator` app: git source at `github.com/dragonflydb/dragonfly-operator` → `charts/dragonfly-operator` tag `v1.6.1` (OCI path `ghcr.io/dragonflydb/dragonfly-operator/helm` is private/inaccessible)
- `dragonfly-argocd-cache` app: deploys `Dragonfly` CR creating 3-replica cluster, service `argocd-cache:6379` in argocd namespace
- ArgoCD values: `redis.enabled: false`, `configs.params.redis.server: argocd-cache:6379`

**Files**: `infra/k8s/argocd/apps/dragonfly-operator.yaml`, `infra/k8s/argocd/apps/dragonfly-argocd-cache.yaml`, `infra/k8s/argocd/values.yaml`

## Longhorn engine binary split-namespace — ALL nodes

**What**: ALL TuringPi nodes (not just turingpi-4) have `/dev/nvme0n1` at `/var/lib/longhorn` on HOST. Engine-image DaemonSet (no mountPropagation) writes binary to kubelet namespace (SD card view); instance-manager (HostToContainer) reads HOST namespace (NVMe) → binary missing → volumes fault.

**Fix**: `infra/k8s/longhorn/engine-binary-sync-tp4.yaml` — DaemonSet with `privileged: true` + `Bidirectional` mountPropagation runs on ALL nodes (no nodeSelector). Idempotent.

**Important**: ArgoCD auto-sync will revert live `kubectl patch` — always commit file changes first, then refresh ArgoCD app.

**Why**: kubectl apply doesn't remove map keys (nodeSelector) — must use `kubectl patch --type=json` with `op:remove`, but even then ArgoCD reverts it. Commit first.

## istiod Certificate renewal failure

**What**: cert-manager-istio-csr chart defaults `app.certmanager.issuer.kind: Issuer`, but only a `ClusterIssuer` named `istio-ca` exists. Certificate renewals fail silently with "Referenced Issuer not found".

**Fix**: Add to `infra/k8s/cert-manager/istio-csr-values.yaml`:
```yaml
app:
  certmanager:
    issuer:
      kind: ClusterIssuer
      name: istio-ca
      group: cert-manager.io
```

Note: `runtimeConfiguration.issuer` controls CSR signing for workloads; `certmanager.issuer` controls the `istiod` Certificate resource itself — both must be set.

## CNPG large CRDs

**What**: `clusters.postgresql.cnpg.io` and `poolers.postgresql.cnpg.io` exceed 262kb annotation limit.

**Fix**: Apply CRDs with `kubectl apply --server-side`, and add `ServerSideApply=true` to the ArgoCD Application's syncOptions.

## Reloader

**What**: Stakater Reloader v2.2.16 installed via ArgoCD app `infra/k8s/argocd/apps/reloader.yaml`, namespace `reloader`.

**Kyverno**: `reloader` namespace must be in exclusion list in `infra/k8s/kyverno/policies/baseline.yaml` for all three policies (require-non-root, disallow-privileged, require-resource-limits).
