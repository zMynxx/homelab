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

## ArgoCD Consolidation: argocd-self → argocd (completed 2026-09-12)

The bootstrap `argocd-self` instance has been removed. ArgoCD is now a single self-managed helm release (`argocd`, revision 12). `argocd-server` holds `192.168.30.202`.

**Pitfall 1 — Name-pattern bulk delete wipes non-self SAs**
`kubectl get all,sa,... | awk '/argocd-self/' | xargs kubectl delete` matched non-prefixed argocd-* ServiceAccounts (application-controller, server, etc.) that appeared adjacent in the list output. Always use label selectors: `-l app.kubernetes.io/instance=argocd-self`. Never use name-pattern grep for bulk delete in the argocd namespace.

**Pitfall 2 — Helm upgrade SSA field manager conflict**
After SA deletion, `helm upgrade` fails with "conflict with argocd-controller" on ConfigMaps/Secrets (ArgoCD owns those fields via SSA). Fix:
```bash
helm template argocd argo/argo-cd --version 10.4.2 -n argocd \
  -f infra/k8s/argocd/values.yaml \
  | kubectl apply --server-side --force-conflicts -n argocd -f -
```

**Pitfall 3 — SSA restore wipes argocd-secret data**
The `helm template | kubectl apply --server-side --force-conflicts` approach recreates `argocd-secret` with empty data (chart template has no values). Dex crashes with `server.secretkey is missing`. Fix: patch after restore:
```bash
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
kubectl patch secret argocd-secret -n argocd \
  --type=json \
  -p="[{\"op\":\"add\",\"path\":\"/data\",\"value\":{\"server.secretkey\":\"$(echo -n $SECRET_KEY | base64)\"}}]"
```
Then restart Dex and argocd-server.

**Pitfall 4 — root recreates argocd-self after controller restart**
`root` has `selfHeal: true`. When the controller restarted after our cleanup, it had a cached git state that still included `argocd-self.yaml` and recreated the Application. After the controller reconciled against the latest git commit (which removed the file), it stopped. Patch out the finalizer and delete twice if needed:
```bash
kubectl patch application argocd-self -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete application argocd-self -n argocd
```

**Pitfall 5 — Dex crashes if Kanidm is not yet ready at startup**
Dex fetches Kanidm's OIDC discovery document at startup. If Kanidm is still coming up (502), Dex crashes with `failed to open all connectors (1/1)` and never starts its gRPC server. This causes 502 on the ArgoCD OIDC callback. Fix: restart Dex after Kanidm is healthy:
```bash
kubectl rollout restart deployment/argocd-dex-server -n argocd
```

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

## ArgoCD repo-server HBONE stale TPROXY rules

**What**: After many pod restarts, ztunnel's TPROXY iptables rules for a pod IP become stale — ztunnel knows about the workload (shows identity in logs) but "Connection refused" on port 15008. The connection hits the pod directly instead of being intercepted.

**Symptom**: ztunnel logs show `error="io error: Connection refused (os error 111)"` on port 15008 for a specific pod IP that ztunnel knows about.

**Fix**: `kubectl rollout restart deployment <name>` — fresh network namespace forces ztunnel to re-enroll the pod cleanly.

**Why**: 249+ restarts on argocd-self-repo-server caused stale TPROXY state. After rollout restart, HBONE connections went from error to `info` immediately.

## ArgoCD talosctl certificate expiry

**What**: The talosctl client certificate (in `~/.talos/config`) expires annually. After expiry, all `talosctl` commands fail with i/o timeout even though nodes are reachable.

**Fix**: Regenerate from `infra/talos/` directory:
```bash
cd infra/talos && SOPS_AGE_KEY_FILE=../../key.txt.secret talhelper genconfig --secret-file talsecret.sops.yaml --out-dir clusterconfig
cp clusterconfig/talosconfig ~/.talos/config
talosctl config endpoint 192.168.30.103 192.168.30.104 192.168.30.105
```
**Note**: Must run from `infra/talos/` (patches use relative paths). Expired 2026-08-23, regenerated 2026-09-02.

## CiliumLoadBalancerIPPool v2 API migration

**What**: `cilium.io/v2alpha1` uses `spec.cidrs`; `cilium.io/v2` uses `spec.blocks`. The Cilium controller silently strips `spec.cidrs` from v2 resources, leaving only `spec.disabled: false` in the spec. ArgoCD enters a sync loop trying to re-apply `spec.cidrs`.

**Fix**: Update `infra/k8s/cilium/lb-ipam-pool.yaml` to use `apiVersion: cilium.io/v2` + `spec.blocks`. Add `ignoreDifferences` for `/spec/disabled` and `/status` in `infra/k8s/argocd/apps/cilium-lb-ipam.yaml`.

## Cilium non-idempotent TLS secrets

**What**: `cilium-ca`, `hubble-relay-client-certs`, `hubble-server-certs` are labeled `cilium.io/helm-template-non-idempotent` — Cilium generates them at runtime with random cert data. ArgoCD sees them OutOfSync on every Helm render.

**Fix**: Add `ignoreDifferences` for `/data` on each secret in `infra/k8s/argocd/apps/cilium.yaml`. Requires `argocd.argoproj.io/refresh=hard` annotation to take effect after adding.

## databases app missing git path

**What**: The `databases` ArgoCD Application points to `infra/k8s/databases/` which didn't exist. Result: persistent EOF from repo-server when trying to generate manifests.

**Fix**: Created `infra/k8s/databases/kustomization.yaml` as placeholder, and added `infra/k8s/argocd/apps/databases.yaml` to git (it existed live but not in git, causing root OutOfSync).

## Nodes stay cordoned after Talos upgrade drain failure

**What**: `talosctl upgrade --wait` drains the node (cordons it in Kubernetes). If drain fails (e.g. Longhorn instance-manager rate limiter), the upgrade still installs and the node reboots — but it stays **cordoned** in Kubernetes. Longhorn mirrors the cordon and marks the node `SCHEDULABLE: False`, preventing instance-managers from starting and all replicas on that node from coming up.

**Symptom**: After upgrade, volumes fail to attach with `DeadlineExceeded`; Longhorn instance-managers for that node are `stopped` with no pod; `kubectl get nodes` shows `UNSCHEDULABLE: true` with `node.kubernetes.io/unschedulable` taint.

**Fix**: `kubectl uncordon turingpi-1 turingpi-4` — Longhorn picks up the change within ~20s and transitions nodes to `SCHEDULABLE: True`.

**After every upgrade**: verify all nodes are uncordoned: `kubectl get nodes -o custom-columns=NAME:.metadata.name,UNSCHEDULABLE:.spec.unschedulable`

## Engine binary missing on NVMe after node reboot

**What**: After a node reboots, the `longhorn-engine-binary-sync` DaemonSet init container may write the engine binary to the **SD card** view of `/var/lib/longhorn` (kubelet namespace) instead of the **NVMe** (HOST namespace), even with `Bidirectional` mountPropagation. This happens when the init container starts before the `longhorn-disk-mount` pod has established the NVMe mount in the HOST namespace.

**Symptom**: `kubectl get engineimage -n longhorn-system` shows `STATE: deployed` but Longhorn volume controller logs show "instance manager is unable to launch the replica"; disk-mount pod shows empty engine-binaries directory on NVMe.

**Reliable fix**: Pipe the binary directly from the engine-image pod through the disk-mount pod (which definitively mounts NVMe at `/host/longhorn`):
```bash
TARGET_DIR="/host/longhorn/engine-binaries/docker.io-longhornio-longhorn-engine-v1.12.1"
ENGINE_POD=$(kubectl get pod -n longhorn-system -l longhorn.io/component=engine-image --field-selector spec.nodeName=<node> -o jsonpath='{.items[0].metadata.name}')
MOUNT_POD=$(kubectl get pod -n longhorn-mount --field-selector spec.nodeName=<node> -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n longhorn-mount $MOUNT_POD -- mkdir -p "$TARGET_DIR"
kubectl exec -n longhorn-system $ENGINE_POD -- cat /usr/local/bin/longhorn | \
  kubectl exec -i -n longhorn-mount $MOUNT_POD -- sh -c "cat > $TARGET_DIR/longhorn && chmod +x $TARGET_DIR/longhorn && ls -lh $TARGET_DIR/longhorn"
```
Expected: `42M` binary. Then delete errored instance-managers so Longhorn recreates them.

**After every node reboot**: check binary on ALL nodes via disk-mount pods, not just the rebooted one.
