---
name: longhorn-nvme-fix-2026-09-14
description: Root cause and full fix for Longhorn instability — disk-mount DaemonSet was wiping NVMe on every restart; replaced with Talos UserVolumeConfig
metadata:
  type: project
---

# Longhorn NVMe Fix — 2026-09-14

**What:** Full teardown and clean reinstall of Longhorn to fix chronic storage instability.

**Why:** `infra/k8s/longhorn/disk-mount.yaml` (a DaemonSet) was the root cause — it mounted NVMe at `/var/lib/longhorn` (wrong path vs values.yaml's `/var/mnt/longhorn`) and ran `mkfs.xfs -f /dev/nvme0n1` unconditionally on every pod restart, wiping all data ~320 times. Longhorn was actually writing to the SD card (rootfs), not the NVMe.

## Root cause chain

1. `disk-mount.yaml` mounted NVMe at `/var/lib/longhorn` via bidirectional DaemonSet mount
2. `values.yaml` set `defaultDataPath: /var/mnt/longhorn` — path mismatch meant NVMe was never used
3. DaemonSet script ran `mount || mkfs.xfs -f` — wiped drive on every restart
4. Bidirectional mount propagation meant the mount persisted on host after pod deletion → "Resource busy" during cleanup
5. 16MB dd wipe was insufficient — XFS backup superblocks at AG boundaries (~every 8GB) survived; needed to wipe start + every 8GB + end

## What was deleted

- `infra/k8s/longhorn/disk-mount.yaml` — the DaemonSet (root cause, gone)
- `infra/talos/patches/longhorn-uservolume.yaml` — dead file with pre-v1.10 incompatible schema (`provisioner: disk`)
- `infra/k8s/argocd/apps/longhorn-manifests.yaml` — ArgoCD app that only existed to deploy disk-mount.yaml

## Correct setup (post-fix)

**NVMe provisioning** is handled entirely by Talos `UserVolumeConfig` in `infra/talos/patches/nvme-storage.yaml`:
- Creates GPT partition + XFS on any NVMe disk ≥ 10GB
- Mounts at `/var/mnt/longhorn`
- Shows as `u-longhorn` in `VolumeConfig`/`VolumeStatus`
- `kubelet.extraMounts` propagates `/var/mnt/longhorn` into kubelet's mount namespace

**Longhorn** (`infra/k8s/longhorn/values.yaml`) stability settings added:
```yaml
defaultDataPath: /var/mnt/longhorn
defaultReplicaCount: 2
storageOverProvisioningPercentage: 100
storageMinimalAvailablePercentage: 10
nodeDrainPolicy: block-if-contains-last-replica
autoSalvage: true
autoDeletePodWhenVolumeDetachedUnexpectedly: true
allowVolumeCreationWithDegradedAvailability: true
replicaSoftAntiAffinity: true
orphanAutoDeletion: true
concurrentReplicaRebuildPerNodeLimit: 1
v2DataEngine: false
```

## Known gotchas

- **`snapshots.longhorn.io` CRD** was missing after Helm install even though ArgoCD reported it Synced. Applied manually with `helm template | python3 extract | kubectl apply`. Root cause unclear — likely ArgoCD stale sync state.
- **Longhorn pre-upgrade Job** (Helm pre-install hook) requires `longhorn-service-account` SA which doesn't exist on fresh install → circular dependency. Fix: create SA manually before ArgoCD sync.
- **`longhorn-system` namespace** created by ArgoCD's `CreateNamespace=true` lacks privileged PSA labels → privileged pods blocked. Fix: `kubectl label namespace longhorn-system pod-security.kubernetes.io/enforce=privileged pod-security.kubernetes.io/audit=privileged pod-security.kubernetes.io/warn=privileged`.
- **Stuck Terminating namespace**: delete `ValidatingWebhookConfiguration` + `MutatingWebhookConfiguration` for longhorn, then patch namespace finalizers via `/api/v1/namespaces/longhorn-system/finalize`.
- **NVMe full wipe**: `dd if=/dev/zero of=/dev/nvme0n1 bs=1M count=64` + wipe every 8GB boundary + last 64MB. 16MB was not enough (XFS AG backup superblocks survived).

## Final state (2026-09-14)

All 3 nodes (turingpi-1, turingpi-3, turingpi-4):
- Disk: `default-disk-1030100000000` at `/var/mnt/longhorn`, XFS, ~250 GB each
- Status: `Ready` and `Schedulable`
- Total: ~750 GB NVMe available to Longhorn
- All pods healthy: managers 2/2, CSI layer, engine-images, instance-managers all running
