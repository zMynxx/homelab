# Talos Linux Cluster on TuringPi2

> Trigger: talos, talosctl, machine config, cluster, node, upgrade, turing, rk1, controlplane, worker, kubelet

## Environment

- **Hardware**: TuringPi2 board with Turing RK1 compute modules (ARM64/amd64 mixed — current config targets amd64)
- **OS**: Talos Linux v1.7.0 (immutable, API-driven, no SSH)
- **Control Plane**: Single node at `192.168.1.34` with VIP at `192.168.1.100` via kube-vip v0.8.0
- **Workers**: `192.168.1.32`, `192.168.1.33`
- **Network interface**: `end0` (RK1 onboard NIC)
- **Boot disk**: `/dev/mmcblk0` (eMMC)
- **Data disk**: `/dev/nvme0n1` mounted at `/var/lib/longhorn` for persistent storage
- **Load Balancer**: MetalLB v0.13.12, IP range `192.168.1.80-192.168.1.90`, pool name `first-pool`
- **Config paths**: `talos/.talos/talosconfig`, generated configs in `talos/_out/`
- **Provisioning**: Ansible playbooks in `talos/` with roles: `install-talosctl`, `configure-talosctl`, `configure-cluster`, `apply-config`, `add-workers`

## Key Constraints

- **No SSH**: Talos is API-only. All operations go through `talosctl` or the Kubernetes API.
- **Immutable OS**: No package manager, no shell. System config is declarative via machine configs.
- **Scheduling on CP**: `cluster.allowSchedulingOnControlPlanes: true` — this is a small cluster, CP runs workloads.
- **Kubelet cert rotation**: Enabled via `rotate-server-certificates: true` + kubelet-serving-cert-approver.
- **Firmware source**: `https://firmware.turingpi.com/turing-rk1/talos/` — flash via BMC UI at `https://turingpi/`.
- **All certificates from homelab CA**: Every certificate in the cluster (Kubernetes CA, etcd CA, front-proxy CA, SA signing key) is pre-generated from step-ca on the RPi. Talos does NOT auto-generate its own PKI. See `pki-certificates` skill for the full secrets bundle procedure.

## Machine Config Structure

Control plane patch lives at `talos/_out/cp.patch.yaml`. When modifying machine configs:

1. **Never edit generated configs directly** (`controlplane.yaml`, `worker.yaml`). Edit patches instead.
2. **Patches are layered** — cp.patch.yaml is applied on top of the base config via `talosctl gen config`.
3. **Secrets bundle** — `talosctl gen config` MUST use `--with-secrets secrets.yaml` where the secrets bundle contains CAs pre-generated from step-ca. Never let Talos auto-generate PKI.
4. **VIP config** goes under `machine.network.interfaces[].vip` on the control plane only.
5. **Disk partitions** for longhorn go under `machine.disks[]` — mount NVMe at `/var/lib/longhorn`.
6. **Extra manifests** are URLs under `cluster.extraManifests[]` — applied at bootstrap time.
7. **Root CA trust** — the step-ca root certificate is injected via `machine.files[]` so all nodes trust it natively.

## Common Operations

```bash
# Apply config changes (no reboot needed for most changes)
talosctl apply-config --nodes <IP> --file <config.yaml>

# Upgrade Talos version
talosctl upgrade --nodes <IP> --image ghcr.io/siderolabs/installer:<version>

# Upgrade Kubernetes
talosctl upgrade-k8s --nodes <CP_IP> --to <k8s-version>

# Check cluster health
talosctl health --nodes 192.168.1.34

# Get kubeconfig
talosctl kubeconfig --nodes 192.168.1.34

# Reset a node (DESTRUCTIVE)
talosctl reset --nodes <IP> --graceful
```

## When Working on Talos Configs

- Validate YAML structure — Talos machine config is strict, unknown fields cause rejection.
- Use `talosctl validate` before applying.
- Keep `talos/inventory/group_vars/all.yaml` as the single source of truth for IPs, versions, and paths.
- Ansible roles in `talos/roles/` handle the provisioning lifecycle — don't bypass them for one-off operations in production-like flows.
- The cluster uses Longhorn for storage, which requires the NVMe partition. Never remove the disk config without migrating storage first.
