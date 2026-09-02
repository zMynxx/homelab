# Homelab — Claude Context

## Project Overview
Declarative homelab on TuringPi 2 (3x RK1 ARM64). Talos Linux cluster, Cilium CNI, Istio Ambient mesh, cert-manager PKI backed by offline YubiKey Root CA (TinyCA on Raspberry Pi).

## Key Commands
```bash
just talos-cilium         # Install/upgrade Cilium (reads infra/k8s/cilium/values.yaml)
just talos-kyverno        # Install Kyverno + baseline policies
just talos-generate       # Regenerate Talos machine configs (decrypts SOPS)
just talos-apply          # Apply configs to nodes (maintenance mode only — NOT for upgrades)
just talos-bootstrap      # Bootstrap etcd (once per cluster lifetime)
just talos-kubeconfig     # Fetch and merge kubeconfig
just talos-spegel         # Install Spegel P2P image mirror
just talos-zot            # Install Zot in-cluster registry cache
just talos-upgrade v1.x.y # Rolling Talos OS upgrade (one node at a time, --wait)
```

## Talos Version Tracking

**Target version**: v1.13.9  
**Schematic**: `2514fe5d294a5f96447ce4ea8ba0ff5cd2939607c4158c5806ade76bd1b invoke7` (fuse3, iscsi-tools, nfs-utils, nut-client, nvme-cli, rockchip-rknn)

| Node | IP | Status as of 2026-09-02 |
|---|---|---|
| turingpi-1 | 192.168.30.103 | v1.13.6 — **needs upgrade** |
| turingpi-3 | 192.168.30.104 | v1.13.9 — current |
| turingpi-4 | 192.168.30.105 | v1.13.6 — **needs upgrade** |

**Why nodes keep reverting to v1.13.6**:
- The talosctl client certificate in `~/.talos/config` (and `infra/talos/clusterconfig/talosconfig`) expires annually.
- When the cert is expired, `talosctl upgrade --wait` fails mid-poll with i/o timeout. The node may have already rebooted into the new version, but the user sees the command fail and retries — overwriting the upgrade with a different version (downgrade).
- Cert expired: 2026-08-23. Regenerated: 2026-09-02. Next expiry: 2027-09-02.
- **Before any upgrade**: verify cert is valid with `talosctl config info` → check "Certificate expires".

**Upgrade command** (only upgrades nodes not already at target):
```bash
just talos-upgrade v1.13.9
```
Verify after: `talosctl -n 192.168.30.103,192.168.30.104,192.168.30.105 version | grep -E "NODE|Tag"`

**If a node reverts to v1.13.6 again**:
1. Check cert: `talosctl config info` — if expired, regenerate first
2. Check dmesg: `talosctl -n <node-ip> dmesg | grep -iE "rollback|upgrade"` — A/B rollback messages indicate the new version failed to boot
3. Check extension versions: `talosctl -n <node-ip> get extensions` — `rockchip-rknn` version must match Talos version
4. Check if upgrade completed before retrying: `talosctl -n <node-ip> version` — if already at target, do NOT re-run upgrade

## Critical Pitfalls (learned the hard way)

### 1. Kyverno blocks system namespace pods silently
`require-non-root`, `disallow-privileged`, `require-resource-limits` are all `Enforce` + `ADMISSION: true`.
Without namespace exemptions they block pod creation for cert-manager, istiod, ztunnel, Cilium — silently.
Symptom: ReplicaSet shows `DESIRED=1, CURRENT=0`, zero pods, zero `FailedCreate` events, only background `PolicyViolation` warnings.
Fix: `infra/k8s/kyverno/policies/baseline.yaml` must use `exclude.any` format and exempt:
`cert-manager, istio-system, kube-system, cilium, kyverno, spegel, registry, longhorn-system, longhorn-mount`

### 2. Cilium kubeProxyReplacement must be true
Talos disables kube-proxy via `cluster.proxy.disabled: true`. If Cilium also has `kubeProxyReplacement: false`, nothing handles service routing. Must be `true`.

### 3. bpf.masquerade must be false for Istio Ambient
BPF masquerade rewrites ztunnel's TPROXY mark and breaks Ambient health checks. Use `bpf.masquerade: false` + `enableIPv4Masquerade: true` (iptables SNAT).

### 4. istiod Certificate must use ClusterIssuer, not Issuer
The `istiod` Certificate lives in `istio-system` namespace. A namespace-scoped `Issuer` in `cert-manager` namespace cannot sign it. Must reference `Kind: ClusterIssuer`.
If `istiod-tls` Secret never gets created, check: `kubectl get certificate istiod -n istio-system -o jsonpath='{.spec.issuerRef}'`

### 5. ztunnel `tcp connect error` to istiod:15012
Root cause chain: `istiod-tls` Secret missing → istiod reads empty optional mount → `could not decode pem` → istiod never starts gRPC TLS on :15012 → ztunnel can't connect.
Not a networking or Cilium issue.

## Bootstrap Order
1. Cilium (nodes need CNI to become Ready)
2. Kyverno (must be before cert-manager — policies must be in place)
3. cert-manager
4. Create PKI Secrets (`istio-ca` TLS in cert-manager ns, `istio-root-ca` in cert-manager ns)
5. cert-manager-istio-csr
6. Istio Ambient (`istioctl install -f infra/k8s/istio/istio-ambient-csr.yaml`)

## Cluster Details
- Nodes: turingpi-1 (192.168.30.103), turingpi-3 (192.168.30.104), turingpi-4 (192.168.30.105)
- VIP: 192.168.30.99
- Pod CIDR: 10.244.0.0/16
- Service CIDR: 10.96.0.0/12
- All nodes are control-plane (3-node cluster, no dedicated workers)
- Talos config generated via `talhelper` from `infra/talos/talconfig.yaml`

## Secrets Management
- SOPS + age key at `key.txt.secret`
- Root CA exported from TinyCA: `infra/tinyca/pki/pki-export/pki-export.sops.yaml`
- Talos cluster secrets: `infra/talos/talsecret.sops.yaml`
- Decrypt: `SOPS_AGE_KEY_FILE=key.txt.secret sops --decrypt <file>`

## Full Documentation
See `infra/docs/CILIUM_ISTIO_AMBIENT_SETUP.md` for detailed setup guide and troubleshooting.

### 6. Longhorn engine binary split-namespace issue on turingpi-4 (NVMe at /var/lib/longhorn)
On turingpi-4, `/dev/nvme0n1` is mounted at `/var/lib/longhorn` on the HOST, but Talos's kubelet runs in an isolated mount namespace where `/var/lib/longhorn` is the SD card.
- Engine-image DaemonSet pod (no `mountPropagation`) inherits kubelet namespace → writes binary to SD card view
- Instance-manager uses `HostToContainer` → reads from HOST namespace → sees NVMe, not SD card → binary missing
- Symptom: instance manager logs `stat /host/var/lib/longhorn/engine-binaries/.../longhorn: no such file or directory`, all replicas stay `stopped`, all volumes fault
- **Permanent fix**: `infra/k8s/longhorn/engine-binary-sync-tp4.yaml` — a DaemonSet (nodeSelector: turingpi-4) with `privileged: true` + `Bidirectional` mountPropagation that copies the binary into the HOST (NVMe) namespace on every pod start. Idempotent — skips if binary already present.
- On Longhorn version upgrade: update the image tag AND hostPath version suffix in `engine-binary-sync-tp4.yaml`
- Do NOT add `kubelet.extraMounts` with `rshared` for `/var/lib/longhorn` — it creates a third namespace layer and makes the split worse
