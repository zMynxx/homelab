# Talos Cluster Design — TuringPi 2

**Date:** 2026-07-12
**Status:** Approved

## Overview

Three-node Talos Linux cluster on a TuringPi 2 board. All nodes run as control plane + schedulable workers (proper etcd quorum, no dedicated worker tier). Cilium replaces kube-proxy. Istio provides strict mTLS. Spegel provides peer-to-peer image distribution. Zot provides an in-cluster pull-through cache for upstream registries. TinyCA (step-ca on RPi) is the external root of trust for all cluster certificates.

---

## Hardware

| Hostname | Slot | IP | RAM | SoC |
|---|---|---|---|---|
| `turingpi-1` | 1 | `192.168.30.11/24` | 8GB | RK3588 (RK1) |
| `turingpi-3` | 3 | `192.168.30.13/24` | 8GB | RK3588 (RK1) |
| `turingpi-4` | 4 | `192.168.30.14/24` | 16GB | RK3588 (RK1) |
| VIP | — | `192.168.30.99` | — | L2 Talos VIP |

- **Network:** VLAN 30 (`192.168.30.0/24`), gateway `192.168.30.1`
- **DHCP range:** `.100–.200` — all static IPs and VIP are below this range
- **`turingpi-4`** is the heavy-workload node (16GB): labeled `node-role=heavy` for `nodeSelector` targeting

---

## Talos Image

All nodes use the **Talos Image Factory** RK1 overlay:
- Architecture: `arm64`
- Board overlay: `turingpi-rk1` (includes RK3588 device tree + U-Boot)
- Exact schematic ID resolved at generate time via `talosctl image factory` or factory.talos.dev

Versions are pinned in `talconfig.yaml` and resolved to latest stable at generate time:
- `talosVersion`: latest stable
- `kubernetesVersion`: latest stable

---

## Directory Structure

```
infra/talos/
  talconfig.yaml          # single source of truth: cluster + all node definitions
  patches/
    all-nodes.yaml        # every node: Spegel mirrors, TinyCA root cert, sysctls, kernel modules
    controlplane.yaml     # CP-specific: VIP, etcd flags, API server admission plugins
  clusterconfig/          # gitignored — talhelper-generated per-node machineconfigs
  talosconfig             # gitignored — talosctl client config (contains cluster secrets)
  .gitignore
just/
  talos.just              # all operational recipes
justfile                  # gains: import 'just/talos.just'
```

`clusterconfig/` and `talosconfig` are gitignored because talhelper generates the Talos cluster CA key pair into them. The root CA cert is extracted from SOPS at generate time and never stored in plaintext.

`talsecret.sops.yaml` (SOPS-encrypted talhelper secrets file) is committed to the repo. It contains the cluster CA key pairs, bootstrap token, and a user-generated `secretboxEncryptionSecret` (XSalsa20Poly1305 — encrypts all Kubernetes secrets at rest in etcd). The plaintext `talsecret.yaml` is gitignored and shredded immediately after encryption.

---

## Machine Config Design

### `talconfig.yaml` key settings

```yaml
clusterName: turingpi
endpoint: https://192.168.30.99:6443   # VIP
allowSchedulingOnControlPlanes: true   # all 3 nodes run workloads
cniConfig:
  name: none                           # Cilium owns CNI
```

`cluster.proxy.disabled: true` is set via patch — Cilium replaces kube-proxy entirely via eBPF.

All 3 nodes are type `controlPlane`. Each node definition includes:
- Static IP, gateway, DNS
- VIP enabled on the primary interface
- Hostname matching slot number

### `patches/all-nodes.yaml`

- `machine.network` — static IP per node, gateway `.1`, DNS
- `machine.network.interfaces[*].vip` — VIP `192.168.30.99` on all CP nodes
- `machine.registries.mirrors` — Spegel + Zot + upstream fallback chain (see Registry Architecture)
- `machine.files` — TinyCA root CA cert written to `/etc/ssl/certs/homelab-root-ca.crt`
- `machine.sysctls` — inotify limits, net.core buffer sizes (required for Cilium + Istio)
- `machine.kernel.modules` — `br_netfilter`, `ip_tables`, `ip6_tables`
- `cluster.proxy.disabled: true`

### `patches/controlplane.yaml`

- etcd extra args (if needed for tuning)
- API server extra admission plugins
- OIDC config placeholder (for future auth integration)

---

## TinyCA Integration

### Layer 1 — Talos OS trust (machine config)

The step-ca root CA cert (EC P-384) is embedded into every node's OS trusted cert pool. This makes `containerd`, `talosctl`, and all OS-level TLS connections trust step-ca before Kubernetes exists.

The cert is extracted from SOPS at generate time by `just talos-generate`:
```bash
sops --decrypt --extract '["root_ca_crt"]' \
  ../../homelab/infra/tinyca/pki/pki-export/pki-export.sops.yaml
```
The extracted PEM is injected into `patches/all-nodes.yaml` as a `machine.files` entry. No plaintext in the repo or on disk after generate completes.

**Hard prerequisite:** step-ca must be running on `192.168.10.37:8443` before cert-manager can issue any certificates. Complete REBUILD.md phases 3–4 before bootstrapping the cluster.

### Layer 2 — In-cluster PKI (post-bootstrap)

Installed in order after bootstrap:

| Component | Role |
|---|---|
| `cert-manager` | Certificate lifecycle management |
| `step-issuer` | `ClusterIssuer` backed by step-ca ACME at `https://192.168.10.37:8443/acme/acme/directory` |
| `istio-csr` | Bridges cert-manager → Istio workload identity; replaces Istio's built-in CA |

cert-manager's `ClusterIssuer` includes `caBundle` (base64 root CA cert) to verify step-ca's TLS. This value is stored as a SOPS-encrypted secret, decrypted in-cluster by the SOPS operator.

Istio runs in strict mTLS mode. Every sidecar receives a short-lived cert issued by step-ca via istio-csr, rotated automatically.

---

## Registry Architecture

### Pull chain

```
containerd → Spegel (localhost:5001) → Zot (in-cluster ClusterIP) → upstream internet
```

Talos `machine.registries.mirrors` configures this ordered fallback for:
`docker.io`, `ghcr.io`, `quay.io`, `registry.k8s.io`

During bootstrap (before Spegel and Zot are deployed), containerd falls through all mirrors to the internet. This is expected — a small number of bootstrap images (Cilium, SOPS operator) hit upstream directly once. After Zot is deployed and Spegel's DaemonSet is running, all subsequent pulls are served from cache.

### Spegel

- Runs as a DaemonSet on all nodes
- Serves OCI registry protocol on port `5001`
- Distributes images peer-to-peer between nodes (avoids every node pulling from Zot separately)
- **Istio exclusion required:** Spegel pods must carry annotation:
  ```yaml
  traffic.sidecar.istio.io/excludeInboundPorts: "5001"
  ```
  Istio's sidecar intercepts TCP and will break the OCI registry protocol otherwise.

### Zot

- Runs in-cluster as a `Deployment` + `PersistentVolumeClaim`
- Configured as a pull-through cache (proxy) for all upstream registries
- Also serves as a private registry for internal images
- Deployed via GitOps (post-bootstrap, same tier as cert-manager)
- TLS certificate issued by cert-manager / step-ca

---

## Cilium + Istio Integration

Cilium runs with `kubeProxyReplacement=true` (full kube-proxy replacement via eBPF). With Istio co-installed, Cilium must run in **native routing mode** — `tunnelMode: disabled`. This avoids double-encapsulation with Istio's sidecar.

Cilium is installed during bootstrap (step 5) before any workloads schedule. Istio is installed post-bootstrap after cert-manager and istio-csr are ready.

---

## Bootstrap Sequence

### Prerequisites

- [ ] step-ca service running and healthy on `192.168.10.37:8443`
- [ ] `key.txt.secret` (age key) present in homelab repo root
- [ ] `talosctl`, `talhelper`, `kubectl`, `helm` installed on local workstation
- [ ] All 3 RK1 nodes booted from Talos RK1 image (maintenance mode)

### Steps

| # | Recipe | Description |
|---|---|---|
| 1 | `just talos-generate` | Decrypt root CA via SOPS, render talhelper → `clusterconfig/` |
| 2 | `just talos-apply` | Push machine configs to all 3 nodes |
| 3 | `just talos-bootstrap` | Bootstrap etcd on `turingpi-1` |
| 4 | `just talos-kubeconfig` | Fetch and merge kubeconfig (via VIP `192.168.30.99`) |
| 5 | `just talos-cilium` | Install Cilium via Helm (nodes become Ready) |
| 6 | `just talos-health` | Verify all nodes Ready, etcd quorum healthy |
| — | *(separate plan)* | SOPS operator → Zot → cert-manager → step-issuer → Spegel → istio-csr → Istio |

### `just talos.just` recipes

| Recipe | Description |
|---|---|
| `just talos-generate` | Decrypt root CA, run `talhelper generate` |
| `just talos-apply` | Apply configs to all nodes (or `--node` for one) |
| `just talos-bootstrap` | Bootstrap etcd on `turingpi-1` |
| `just talos-kubeconfig` | Fetch and merge kubeconfig |
| `just talos-cilium` | Install Cilium with correct Helm values |
| `just talos-health` | `talosctl health` + `kubectl get nodes` |
| `just talos-upgrade` | Rolling Talos version upgrade across all nodes |
| `just talos-reset` | Hard reset all nodes — destructive, requires confirmation |

---

## Post-Bootstrap Components (out of scope — separate plan)

Installed via GitOps after step 6:

1. SOPS operator + age key seed
2. Zot (in-cluster pull-through registry)
3. cert-manager
4. step-issuer ClusterIssuer (points to `https://192.168.10.37:8443`)
5. Spegel DaemonSet
6. istio-csr
7. Istio (strict mTLS)

---

## Local Tooling

| Tool | Purpose |
|---|---|
| `talosctl` | Apply configs, bootstrap, node interaction |
| `talhelper` | Render machine configs from `talconfig.yaml` + patches |
| `kubectl` | Post-bootstrap cluster interaction |
| `helm` | Install Cilium during bootstrap |
| `step` | Extract root CA cert from SOPS for patch injection |
| `sops` | Decrypt secrets at generate time |
