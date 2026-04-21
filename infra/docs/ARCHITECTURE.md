# Homelab Architecture v2.0 — Design Document

**Status**: Design Complete, Implementation Pending  
**Last Updated**: 2026-04-20  
**Goal**: Reproducible, declarative homelab infrastructure rebuildable in "a few clicks"

---

## Executive Summary

This architecture merges the existing `homelab` repo (Terraform/Ansible/Talos) with the `turningpi2-k3s-gitops` patterns into a unified, declarative monorepo. The design eliminates circular dependencies by:

1. **Externalizing the root of trust** — Step-CA runs on a dedicated Raspberry Pi with YubiKey, outside the cluster
2. **Stateless secrets** — SOPS + Age instead of Vault (no persistent storage dependency)
3. **Declarative OS** — talhelper replaces Ansible for Talos cluster generation
4. **GitOps-first** — ArgoCD manages all in-cluster state via SyncWaves

**Key principle**: Everything chains to the YubiKey root CA. No component generates its own PKI.

---

## Design Principles

| Principle | Implementation |
|-----------|----------------|
| **Single source of truth** | Git repo for everything, ArgoCD for cluster state |
| **No circular dependencies** | Step-CA and Age keys live outside the cluster |
| **Declarative by default** | Terraform, talhelper, Kustomize — no imperative scripts |
| **Defense in depth** | Cilium (L3/L4) → Istio Ambient (L4 mTLS + L7) → Kyverno (admission) → Falco (runtime) |
| **Minimal blast radius** | Cluster death ≠ CA death ≠ secrets loss |
| **CKS-aligned security** | All CKS requirements: network policies, pod security, runtime detection, image scanning |

---

## Physical Topology

```
                    Internet
                       │
                  ┌────┴────┐
                  │   VPS   │  Pangolin (planned, future public access)
                  └────┬────┘
                       │ WireGuard tunnel
                       │
              ┌────────┴────────┐
              │  Protectli Vault │  OPNsense (firewall) + Keycloak (SSO) + Caddy (reverse proxy)
              └────────┬─────────┘
                       │ 192.168.1.0/24
            ┌──────────┼──────────┬───────────┐
            │          │          │           │
       ┌────┴────┐ ┌───┴───┐ ┌───┴───┐ ┌─────┴─────┐
       │TuringPi2│ │TrueNAS│ │  RPi  │ │  Proxmox  │
       │  Talos  │ │Storage│ │step-ca│ │   Host    │
       │ (K8s)   │ │       │ │YubiKey│ │           │
       └─────────┘ └───────┘ └───────┘ └───────────┘
```

### Hardware Inventory

| Device | Role | IP Range | Notes |
|--------|------|----------|-------|
| **Proxmox Host** | Hypervisor | 192.168.1.x | Bare metal, runs Terraform-managed VMs |
| **TuringPi2** | Kubernetes cluster | 192.168.1.32-34, VIP .100 | 3x Turing RK1 ARM64 SBCs, Talos Linux |
| **Protectli Vault** | Firewall + SSO | 192.168.1.1 (assumed) | OPNsense, Keycloak, Caddy |
| **Raspberry Pi** | Certificate Authority | 192.168.1.x (TBD) | Step-CA with YubiKey USB attached |
| **TrueNAS** | Network storage | 192.168.1.x (TBD) | Managed by Terraform |
| **VPS** | Public tunnel (future) | Public IP | Pangolin reverse tunnel endpoint |

### Network Allocations

- **Talos control plane**: `192.168.1.34`
- **Talos workers**: `192.168.1.32`, `192.168.1.33`
- **Kube VIP** (API endpoint): `192.168.1.100`
- **MetalLB LoadBalancer pool**: `192.168.1.80-90`
- **Step-CA (RPi)**: `192.168.1.x` (to be assigned, must be reachable from Talos nodes + cluster pods)

---

## Technology Stack

### Infrastructure Layer

| Component | Version | Role |
|-----------|---------|------|
| **Talos Linux** | v1.9.5+ | Immutable Kubernetes OS on Turing RK1 |
| **talhelper** | Latest | Declarative Talos config generator |
| **Cilium** | Latest | CNI with kube-proxy replacement (eBPF dataplane) |
| **Istio Ambient** | Latest | Service mesh (ztunnel for L4 mTLS, waypoint for L7) |
| **Spegel** | Latest | Node-to-node container image cache sharing |
| **MetalLB** | Latest | L2 LoadBalancer (alternative: Cilium L2 announcements) |

### PKI Layer

| Component | Location | Role |
|-----------|----------|------|
| **Step-CA** | Raspberry Pi | Private CA with YubiKey-backed root certificate |
| **cert-manager** | In-cluster | Kubernetes certificate lifecycle automation |
| **istio-csr** | In-cluster | Bridges cert-manager → Istio workload identity |

### Security Layer (CKS-aligned)

| Component | Role |
|-----------|------|
| **Falco** | Runtime threat detection (eBPF driver) |
| **Kyverno** | Policy enforcement (admission controller) |
| **Trivy Operator** | Vulnerability scanning |
| **CiliumNetworkPolicy** | L3/L4 network segmentation |

### GitOps Layer

| Component | Role |
|-----------|------|
| **ArgoCD** | GitOps controller with ApplicationSets |
| **Kustomize** | Manifest templating (Helm charts consumed via Kustomize) |
| **SOPS + Age** | Secrets encryption (stateless, no Vault needed) |

### Observability

| Component | Role |
|-----------|------|
| **kube-prometheus-stack** | Prometheus + Grafana + Alertmanager |
| **Loki** | Log aggregation |
| **Alloy** | Metrics/logs/traces collector (Grafana's successor to Promtail) |
| **Hubble** | Cilium network observability UI |

### Storage

| Component | Role |
|-----------|------|
| **Longhorn** | Distributed block storage on NVMe (`/dev/nvme0n1`) |

---

## Repository Structure

```
homelab/
├── justfile                          # Task automation (just bootstrap, just destroy, etc.)
├── .sops.yaml                        # SOPS config (age public keys)
├── .gitignore                        # Secrets, Terraform state, .tfvars
├── .opencode/skills/                 # AI agent context (updated for v2.0)
│   ├── talos-cluster.md              # Updated: talhelper, v1.9+
│   ├── pki-certificates.md           # Updated: ambient mesh integration
│   ├── homelab-conventions.md        # Updated: new repo structure
│   ├── gitops.md                     # Updated: ApplicationSets patterns
│   ├── cks-security.md               # Updated: Cilium+Istio coexistence
│   └── infrastructure.md             # No changes needed
│
├── docs/
│   ├── ARCHITECTURE.md               # This file
│   ├── BOOTSTRAP.md                  # Step-by-step deployment guide
│   └── TROUBLESHOOTING.md            # Common failure modes + fixes
│
├── Ansible/                          # Proxmox host bootstrap only (minimal)
│   ├── 00-Init/
│   │   ├── playbook.yaml
│   │   └── tasks/
│   └── 01-Passthrough/
│       ├── playbook.yaml
│       └── tasks/
│
├── Terraform/                        # Infrastructure outside Kubernetes
│   ├── mgmt/
│   │   ├── 00-versions.tf
│   │   ├── 01-providers.tf
│   │   ├── 02-resources.tf
│   │   ├── 03-data-sources.tf
│   │   ├── 04-variables.tf
│   │   ├── 05-outputs.tf
│   │   └── vars/prod/vars.auto.tfvars  # Gitignored
│   ├── opnsense/
│   ├── truenas/
│   └── ubuntu/
│
├── pki/                              # Step-CA integration (RPi-based CA)
│   ├── root_ca.crt                   # Public root cert (safe to commit)
│   ├── gen-secrets-bundle.sh         # Generates K8s PKI from step-ca
│   ├── README.md                     # YubiKey + RPi setup instructions
│   └── yubikey-setup.md              # One-time YubiKey initialization
│
├── talos/                            # Talos cluster OS configuration
│   ├── talconfig.yaml                # Declarative cluster definition (talhelper)
│   ├── patches/
│   │   ├── cilium.yaml               # Disable kube-proxy, CNI=none
│   │   ├── spegel.yaml               # Registry mirror config
│   │   ├── custom-ca.yaml            # Inject step-ca root cert
│   │   ├── longhorn.yaml             # NVMe partition mount
│   │   ├── kubelet.yaml              # Seccomp, cert rotation
│   │   └── etcd-encryption.yaml      # Encryption-at-rest for etcd
│   ├── talenv.sops.yaml              # Encrypted: cluster token, VIP config
│   └── talsecret.sops.yaml           # Encrypted: PKI bundle from step-ca
│
└── k8s/                              # GitOps root (ArgoCD watches this)
    ├── argocd/                       # ArgoCD self-management
    │   ├── base/
    │   │   ├── kustomization.yaml
    │   │   └── namespace.yaml
    │   └── overlays/prod/
    │       ├── kustomization.yaml    # helmCharts: argo-cd
    │       ├── applicationset-infrastructure.yaml
    │       ├── applicationset-security.yaml
    │       ├── applicationset-platform.yaml
    │       ├── applicationset-apps.yaml
    │       ├── root-app.yaml         # App-of-apps entry point
    │       └── patches/
    │
    ├── bootstrap/                    # Applied BEFORE ArgoCD (script-driven)
    │   ├── cilium/
    │   │   └── values.yaml           # Helm values for Cilium
    │   ├── argocd/
    │   │   └── values.yaml           # Helm values for ArgoCD
    │   └── README.md                 # Bootstrap sequence documentation
    │
    ├── infrastructure/               # SyncWave 0 — core platform
    │   ├── cert-manager/
    │   │   ├── base/
    │   │   │   ├── kustomization.yaml    # helmCharts: cert-manager
    │   │   │   ├── step-issuer.yaml      # ClusterIssuer → step-ca
    │   │   │   └── root-ca-secret.yaml   # Step-CA root cert
    │   │   └── overlays/prod/
    │   ├── istio-base/               # Istio CRDs + ambient profile
    │   │   ├── base/
    │   │   └── overlays/prod/
    │   ├── istio-cni/                # Istio CNI plugin (coexists with Cilium)
    │   │   └── ...
    │   ├── istio-ztunnel/            # Ambient mesh L4 proxy
    │   │   └── ...
    │   ├── istio-csr/                # cert-manager → Istio mTLS bridge
    │   │   └── ...
    │   ├── spegel/                   # Image cache sharing
    │   │   └── ...
    │   ├── metallb/                  # L2 LoadBalancer
    │   │   ├── base/
    │   │   │   ├── kustomization.yaml
    │   │   │   ├── ipaddresspool.yaml    # 192.168.1.80-90
    │   │   │   └── l2advertisement.yaml
    │   │   └── overlays/prod/
    │   ├── longhorn/                 # Distributed block storage
    │   │   └── ...
    │   └── network-policies/         # Default deny CiliumNetworkPolicies
    │       ├── base/
    │       │   ├── kustomization.yaml
    │       │   └── default-deny-all.yaml
    │       └── overlays/prod/
    │
    ├── security/                     # SyncWave 1 — CKS stack
    │   ├── falco/
    │   │   ├── base/
    │   │   │   ├── kustomization.yaml
    │   │   │   ├── values.yaml           # eBPF driver, stdout alerts
    │   │   │   └── custom-rules/
    │   │   └── overlays/prod/
    │   ├── kyverno/
    │   │   ├── base/
    │   │   │   ├── kustomization.yaml
    │   │   │   └── policies/             # All 9 standard CKS policies
    │   │   │       ├── disallow-privileged.yaml
    │   │   │       ├── require-resource-limits.yaml
    │   │   │       ├── require-labels.yaml
    │   │   │       ├── disallow-latest-tag.yaml
    │   │   │       ├── require-non-root.yaml
    │   │   │       ├── restrict-host-namespaces.yaml
    │   │   │       ├── disallow-nodeport.yaml
    │   │   │       ├── require-istio-sidecar.yaml
    │   │   │       └── image-registry-whitelist.yaml
    │   │   └── overlays/prod/
    │   └── trivy-operator/
    │       └── ...
    │
    ├── platform/                     # SyncWave 2 — observability
    │   ├── kube-prometheus-stack/
    │   │   └── ...
    │   ├── loki/
    │   │   └── ...
    │   └── alloy/                    # Grafana's unified telemetry collector
    │       └── ...
    │
    └── apps/                         # SyncWave 3 — workloads
        ├── nextcloud/
        │   └── ...
        ├── cloudnative-pg/
        │   └── ...
        ├── minio/
        │   └── ...
        └── ...
```

---

## Bootstrap Sequence

This is the **dependency-correct** order to build the entire homelab from scratch.

### Phase 0: One-Time Prerequisites (Manual)

These steps are done once and the outputs are backed up securely.

1. **Generate Age keypair for SOPS**
   ```bash
   age-keygen -o ~/.config/sops/age/keys.txt
   # Backup this file to multiple secure locations (USB, password manager, printed QR code)
   ```

2. **Initialize YubiKey with root CA on Raspberry Pi**
   - Set up Raspberry Pi with Debian/Ubuntu
   - Install step-ca and YubiKey PKCS#11 libraries
   - Initialize step-ca with YubiKey as root CA key storage
   - See `pki/yubikey-setup.md` for detailed steps
   - Export `root_ca.crt` (public key only) → commit to `pki/root_ca.crt`

3. **Configure SOPS**
   - Add Age public key to `.sops.yaml`
   - Test encryption: `sops -e test.yaml`

**Checkpoint**: You should have:
- Age private key backed up (never committed)
- Step-CA running on RPi with YubiKey attached
- `pki/root_ca.crt` committed to the repo

---

### Phase 1: Infrastructure Provisioning (Terraform)

Deploy everything that runs **outside** Kubernetes.

```bash
# From repo root
just tf-init       # terraform init for all modules
just tf-plan       # Review changes
just tf-apply      # Apply Proxmox, OPNsense, TrueNAS configs
```

**What this does**:
- Proxmox: Creates management users, ACLs, PCI passthrough mappings
- OPNsense: Configures firewall rules, NAT, VLANs (if applicable)
- TrueNAS: Sets up NFS exports, datasets

**Manual step**: Ensure RPi step-ca is reachable from the network (test with `step ca health --ca-url https://<rpi-ip>:8443`)

**Checkpoint**: Proxmox, OPNsense, TrueNAS are running and configured.

---

### Phase 2: PKI — Generate Kubernetes Secrets Bundle

Talos does NOT auto-generate PKI. All Kubernetes CAs must be issued by step-ca.

```bash
just pki-gen-secrets
```

**What this does** (`pki/gen-secrets-bundle.sh`):
1. Requests intermediate certs from step-ca:
   - Kubernetes CA (`CN=kubernetes`)
   - etcd CA (`CN=etcd`)
   - Front-proxy CA (`CN=front-proxy`)
   - Service account signing key (RSA keypair)
2. Assembles a Talos-compatible `secrets.yaml` bundle
3. Encrypts it with SOPS → `talos/talsecret.sops.yaml`

**Checkpoint**: `talos/talsecret.sops.yaml` exists and contains encrypted PKI material.

---

### Phase 3: Talos Cluster OS

Generate and apply Talos machine configs.

```bash
# Generate machine configs using talhelper
just talos-gen

# Apply configs to nodes (requires nodes to be booted into Talos maintenance mode)
just talos-apply

# Bootstrap the control plane
talosctl bootstrap -n 192.168.1.34 --talosconfig talos/clusterconfig/talosconfig
```

**What `talos-gen` does**:
- Reads `talos/talconfig.yaml`
- Decrypts `talos/talsecret.sops.yaml` (PKI bundle from step-ca)
- Applies patches:
  - `cilium.yaml`: Disables default CNI and kube-proxy
  - `custom-ca.yaml`: Injects step-ca root cert into OS trust store
  - `spegel.yaml`: Configures containerd registry mirrors
  - `longhorn.yaml`: Mounts NVMe partition at `/var/lib/longhorn`
  - `kubelet.yaml`: Enables seccomp profiles, cert rotation
  - `etcd-encryption.yaml`: Enables encryption-at-rest for etcd
- Generates per-node machine configs in `talos/clusterconfig/`

**What `talos-apply` does**:
- Runs `talosctl apply-config` for each node (CP + workers)
- Nodes reboot and join the cluster
- Kubernetes control plane starts but **no CNI** → pods stuck in `Pending`

**Checkpoint**: Cluster is up, API server reachable at `https://192.168.1.100:6443`, but no CNI yet.

---

### Phase 4: Bootstrap Core Services (Script-driven, Pre-ArgoCD)

Install the services ArgoCD depends on.

```bash
just bootstrap-core
```

**What this does**:

1. **Install Cilium** (Helm)
   ```bash
   helm repo add cilium https://helm.cilium.io/
   helm install cilium cilium/cilium -n kube-system \
     -f k8s/bootstrap/cilium/values.yaml
   ```
   - Enables kube-proxy replacement
   - Disables Cilium encryption (Istio will handle mTLS)
   - Disables L7 policy (Istio waypoints will handle L7)
   - Sets `cni.exclusive: false` (allows Istio CNI to coexist)
   - **Result**: Pods can now schedule and network

2. **Inject SOPS Age Secret** (kubectl)
   ```bash
   kubectl create namespace argocd
   kubectl create secret generic sops-age -n argocd \
     --from-file=keys.txt=$HOME/.config/sops/age/keys.txt
   ```
   - **Result**: ArgoCD can decrypt SOPS-encrypted manifests

3. **Install ArgoCD** (Helm + root app)
   ```bash
   helm repo add argo https://argoproj.github.io/argo-helm
   helm install argocd argo/argo-cd -n argocd \
     -f k8s/bootstrap/argocd/values.yaml

   kubectl apply -f k8s/argocd/overlays/prod/root-app.yaml
   ```
   - **Result**: ArgoCD is running and watching `k8s/` directory

**Checkpoint**: Cilium running, pods scheduling, ArgoCD installed and syncing.

---

### Phase 5: GitOps Takes Over (ArgoCD SyncWaves)

From this point, all cluster state is managed by ArgoCD. The ApplicationSets in `k8s/argocd/overlays/prod/` discover directories and create Applications automatically.

#### SyncWave 0: Infrastructure

ArgoCD deploys (in order):

1. **cert-manager**
   - Installs cert-manager CRDs and controller
   - Creates `ClusterIssuer` pointing to step-ca on RPi
   - Creates `root-ca-secret` with step-ca root cert

2. **Istio Ambient Mesh**
   - `istio-base`: CRDs + ambient profile
   - `istio-cni`: CNI plugin (coexists with Cilium via `cni.chained: true`)
   - `istio-ztunnel`: DaemonSet for transparent L4 mTLS
   - `istio-csr`: Bridges cert-manager to Istio workload identity

3. **Spegel**
   - DaemonSet for node-to-node image cache sharing
   - Talos containerd config already points to Spegel endpoints (from `spegel.yaml` patch)

4. **MetalLB**
   - IP pool: `192.168.1.80-90`
   - L2 advertisement mode

5. **Longhorn**
   - Distributed block storage on NVMe
   - Talos nodes already have `/var/lib/longhorn` partition mounted

6. **Network Policies**
   - Default deny `CiliumNetworkPolicy` in all namespaces

#### SyncWave 1: Security (CKS Stack)

1. **Falco**
   - eBPF driver (modern_ebpf)
   - Alerts to stdout → collected by Alloy

2. **Kyverno**
   - 9 standard CKS policies enforced (see repo structure for list)
   - `validationFailureAction: Enforce`

3. **Trivy Operator**
   - Scans workloads for vulnerabilities
   - Results exposed as Kubernetes CRs

#### SyncWave 2: Platform (Observability)

1. **kube-prometheus-stack**
   - Prometheus, Grafana, Alertmanager
   - Scrapes Falco, Cilium Hubble, Istio metrics

2. **Loki**
   - Log aggregation backend

3. **Alloy**
   - Collects logs, metrics, traces
   - Sends to Loki + Prometheus

#### SyncWave 3: Applications

ApplicationSet discovers all directories in `k8s/apps/` and deploys them.

**Checkpoint**: Full stack deployed and healthy.

---

## Component Integration Details

### Cilium + Istio Ambient: Conflict Resolution

Both use eBPF and intercept traffic. This is the most delicate integration.

**Configuration Rules**:

1. **Cilium** (in `k8s/bootstrap/cilium/values.yaml`):
   ```yaml
   kubeProxyReplacement: true
   k8sServiceHost: 192.168.1.100
   k8sServicePort: 7445      # KubePrism port
   ipam:
     mode: kubernetes
   encryption:
     enabled: false           # CRITICAL: Istio owns mTLS
   l7Proxy: false             # CRITICAL: Istio waypoints own L7
   socketLB:
     hostNamespaceOnly: true  # Avoid conflicts with ztunnel
   bpf:
     masquerade: true
   cni:
     exclusive: false         # CRITICAL: Allow Istio CNI to coexist
   hubble:
     enabled: true
     relay:
       enabled: true
     ui:
       enabled: true
   ```

2. **Istio CNI** (in Istio Helm values):
   ```yaml
   cni:
     chained: true            # CRITICAL: Chain with Cilium
     cniBinDir: /opt/cni/bin
     cniConfDir: /etc/cni/net.d
   ```

3. **Verify CNI ordering**:
   ```bash
   # On any Talos node
   talosctl -n <node-ip> ls /etc/cni/net.d/
   # Should show: 05-cilium.conflist, 10-istio-cni.conflist (or similar)
   # Cilium MUST be first
   ```

**What Cilium does**: IPAM, pod routing, kube-proxy replacement, L3/L4 CiliumNetworkPolicy, Hubble observability

**What Istio Ambient does**: L4 mTLS via ztunnel, L7 policy via waypoint proxies, ingress gateway, Gateway API

**What to avoid**:
- Do NOT enable Cilium encryption (WireGuard/IPsec) — Istio ztunnel provides mTLS
- Do NOT enable Cilium L7 proxy — Istio waypoints provide L7
- Do NOT set `cni.exclusive: true` in Cilium — Istio CNI must inject its plugin

---

### Step-CA Integration: All PKI from YubiKey Root

**Hard rule**: Nothing in this homelab auto-generates certificates.

#### Kubernetes Control Plane PKI

Generated in Phase 2 (`pki/gen-secrets-bundle.sh`):

```bash
# Request intermediates from step-ca
step ca certificate "kubernetes" k8s-ca.crt k8s-ca.key \
  --ca-url https://<rpi-ip>:8443 \
  --root pki/root_ca.crt \
  --not-after=87600h  # 10 years

step ca certificate "etcd" etcd-ca.crt etcd-ca.key \
  --ca-url https://<rpi-ip>:8443 \
  --root pki/root_ca.crt \
  --not-after=87600h

step ca certificate "front-proxy" front-proxy-ca.crt front-proxy-ca.key \
  --ca-url https://<rpi-ip>:8443 \
  --root pki/root_ca.crt \
  --not-after=87600h

# Generate SA signing key (not from CA, just a keypair)
openssl genrsa -out sa.key 4096
openssl rsa -in sa.key -pubout -out sa.pub

# Assemble secrets.yaml
cat <<EOF > secrets.yaml
cluster:
  id: $(openssl rand -base64 32)
  secret: $(openssl rand -base64 32)
certs:
  etcd:
    cert: $(base64 -w0 < etcd-ca.crt)
    key: $(base64 -w0 < etcd-ca.key)
  k8s:
    cert: $(base64 -w0 < k8s-ca.crt)
    key: $(base64 -w0 < k8s-ca.key)
  k8s-aggregator:
    cert: $(base64 -w0 < front-proxy-ca.crt)
    key: $(base64 -w0 < front-proxy-ca.key)
  k8s-serviceaccount:
    key: $(base64 -w0 < sa.key)
EOF

# Encrypt with SOPS
sops -e secrets.yaml > talos/talsecret.sops.yaml
```

#### In-Cluster TLS (cert-manager)

`ClusterIssuer` in `k8s/infrastructure/cert-manager/base/step-issuer.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: step-ca-issuer
spec:
  acme:
    server: https://<rpi-ip>:8443/acme/acme/directory
    privateKeySecretRef:
      name: step-ca-account-key
    caBundle: <base64-encoded-root-ca-cert>
    solvers:
      - http01:
          ingress:
            class: istio
```

#### Istio Workload Identity (istio-csr)

`istio-csr` intercepts Istio workload CSRs and signs them via cert-manager, which delegates to step-ca.

Result: All Istio mTLS certificates chain to the YubiKey root CA.

#### Talos Node Trust

Inject step-ca root cert via `talos/patches/custom-ca.yaml`:

```yaml
machine:
  files:
    - content: |
        -----BEGIN CERTIFICATE-----
        <step-ca root cert PEM>
        -----END CERTIFICATE-----
      permissions: 0o644
      path: /etc/ssl/certs/homelab-root-ca.crt
      op: create
```

All Talos nodes trust this CA natively at the OS level.

---

### Secrets Management: SOPS + Age

**Why not Vault?**

Vault requires:
- Persistent storage (Longhorn)
- Longhorn requires nodes up
- Nodes require secrets to bootstrap
- **Circular dependency**

**Why SOPS + Age?**

- **Stateless**: Age private key lives outside the cluster (on your workstation, backed up)
- **Git-native**: Encrypted files committed directly to Git
- **Zero runtime dependencies**: ArgoCD decrypts on the fly using the `sops-age` secret

**Workflow**:

1. Create a secret manifest:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: example-secret
   stringData:
     password: super-secret
   ```

2. Encrypt with SOPS:
   ```bash
   sops -e secret.yaml > secret.enc.yaml
   ```

3. Commit `secret.enc.yaml` to Git (the plaintext never touches Git)

4. ArgoCD uses the KSOPS plugin to decrypt on sync

**Recovery scenario**: If the cluster dies:
- Rebuild from Phase 1 (Terraform)
- Phase 2 (PKI) regenerates Kubernetes CAs from step-ca (YubiKey still has root)
- Phase 3 (Talos) rebuilds nodes
- Phase 4 (Bootstrap) re-injects the Age secret from your backup
- Phase 5 (GitOps) ArgoCD syncs and decrypts all secrets

**The Age private key is the master secret. Back it up like your life depends on it.**

---

## etcd Encryption at Rest

Configured in `talos/patches/etcd-encryption.yaml`:

```yaml
cluster:
  secretboxEncryptionSecret: <auto-generated-base64-key>
```

This key is auto-generated by `talhelper gensecret` and stored (SOPS-encrypted) in `talos/talsecret.sops.yaml`.

All Kubernetes Secrets in etcd are encrypted with XSalsa20-Poly1305.

**Verification**:

```bash
# Check etcd encryption status
kubectl get secrets -A -o json | jq '.items[0].metadata.managedFields'

# Verify encryption key is set
talosctl -n 192.168.1.34 get secretboxencryptionsecret
```

---

## Disaster Recovery

### Scenario 1: Cluster Dies (Nodes Fail)

**What survives**:
- Step-CA on RPi (independent hardware)
- Age private key (backed up offline)
- Git repo (all cluster state)
- Terraform state (Proxmox, OPNsense, TrueNAS configs)

**Recovery**:
1. Reflash Turing RK1 nodes with Talos
2. Run Phase 2 (regenerate Kubernetes PKI from step-ca)
3. Run Phase 3 (apply Talos configs)
4. Run Phase 4 (bootstrap Cilium + ArgoCD)
5. Phase 5 (GitOps sync) restores all workloads

**Time**: ~30 minutes (assuming Terraform infra is still up)

### Scenario 2: Step-CA Raspberry Pi Dies

**What survives**:
- YubiKey (root CA key is on the YubiKey, not the RPi disk)
- `pki/root_ca.crt` (committed to Git)
- Step-CA config (documented in `pki/README.md`)

**Recovery**:
1. Get a new Raspberry Pi
2. Install step-ca
3. Re-initialize with the same YubiKey (root key never left the YubiKey)
4. Restore step-ca config (ACME provisioners, JWK, etc.)
5. Existing cluster certificates continue to work (no re-issue needed until renewal)

**Time**: ~1 hour

### Scenario 3: Age Private Key Lost

**Impact**: Cannot decrypt SOPS-encrypted secrets in Git.

**Recovery**: **NONE**. This is catastrophic. All encrypted secrets are unrecoverable.

**Mitigation**: Back up the Age private key to:
- Password manager (1Password, Bitwarden)
- Encrypted USB drive (stored offsite)
- Printed QR code (in a safe)
- Additional workstation (encrypted disk)

**Test recovery annually**.

### Scenario 4: YubiKey Lost/Destroyed

**Impact**: Cannot issue new certificates. Existing certs work until expiry.

**Recovery**: **Root CA rotation required**. This is a multi-day operation:
1. Generate a new root CA (on a new YubiKey or HSM)
2. Cross-sign with the old root (if possible, otherwise hard cutover)
3. Re-issue all intermediate CAs
4. Re-issue all leaf certificates
5. Update trust stores everywhere (Talos nodes, clients, browsers)

**Mitigation**: YubiKey FIPS models support backup. Use two YubiKeys (primary + backup) and keep them in separate physical locations.

---

## Potential Pitfalls & Mitigations

| Pitfall | Symptom | Mitigation |
|---------|---------|------------|
| **Istio Ambient on ARM64** | ztunnel pods crash or fail to start | Pin to a known-good Istio version. Test ztunnel on ARM before committing. Watch Istio release notes for ARM support. |
| **Cilium + Istio CNI race** | Pods fail with "network not ready" | Verify `/etc/cni/net.d/` ordering (Cilium first, Istio second). Set `cni.exclusive: false` in Cilium. |
| **Spegel mirrors before Spegel exists** | Nodes fail to pull images on first boot | Talos containerd config has fallback to public registries. First boot is slower, subsequent boots use Spegel cache. |
| **YubiKey touch requirement** | Step-CA hangs during cert signing | Configure YubiKey touch policy to `cached` or `never` for the CA signing slot. |
| **SOPS key loss** | Cannot decrypt secrets in Git | **BACKUP THE AGE KEY**. Test recovery quarterly. |
| **3-node ARM cluster resource pressure** | OOMKills, pod evictions | Monitor memory. ztunnel is ~50MB, Falco eBPF ~100MB. Budget carefully. Consider dropping Istio Ambient and using Cilium's native mTLS. |
| **Step-CA RPi unreachable** | cert-manager fails to issue certs | Add health checks. Configure firewall to allow step-ca port (8443) from cluster subnet. |
| **Talos upgrade breaks Cilium** | CNI fails after OS upgrade | Pin Cilium version. Test Talos upgrades in a dev cluster first. |

---

## Key Configuration Decisions

### Decision: Step-CA on RPi (Not In-Cluster)

**Rationale**:
- Cluster death ≠ CA death
- YubiKey USB passthrough is simpler on bare metal than in a VM/container
- RPi failure is independent of cluster failure (different hardware)
- Recovery is faster (rebuild cluster without touching PKI)

**Alternative considered**: Step-CA as a Kubernetes StatefulSet with YubiKey passed through to a dedicated node. **Rejected** because cluster bootstrap requires CA to already exist (chicken-and-egg).

### Decision: SOPS + Age (Not Vault)

**Rationale**:
- Stateless (no storage dependency)
- Git-native (encrypted files committed directly)
- Disaster recovery is trivial (Age key + Git = full restore)

**Alternative considered**: HashiCorp Vault. **Rejected** because Vault requires Longhorn, which requires the cluster to be up, which requires secrets. Circular.

### Decision: Cilium for L3/L4 Only, Istio Ambient for mTLS + L7

**Rationale**:
- Cilium is battle-tested for CNI and kube-proxy replacement
- Istio Ambient provides mTLS without sidecar overhead (critical on 3-node ARM cluster)
- Separation of concerns: Cilium = dataplane, Istio = control plane

**Alternative considered**: Cilium-only (Cilium has native mTLS via SPIFFE). **Deferred** because Cilium's mTLS doesn't chain to a custom CA root easily. If Step-CA integration becomes too complex, revisit this.

### Decision: MetalLB L2 (Not BGP, Not Cilium L2)

**Rationale**:
- Home network has no BGP router
- L2 ARP is simple and works on a flat network
- MetalLB is well-documented and stable

**Alternative considered**: Cilium L2 announcements. **Deferred** to reduce integration complexity. MetalLB is proven. Cilium L2 can be evaluated later to reduce component count.

### Decision: talhelper (Not Ansible)

**Rationale**:
- Fully declarative (Ansible playbooks are imperative)
- SOPS integration for secrets
- Single `talconfig.yaml` replaces 5 Ansible roles
- Easier to version control and reproduce

**Alternative considered**: Keep Ansible. **Rejected** because Ansible introduces state drift (playbooks can be run partially, tasks can fail midway). talhelper is atomic.

### Decision: Longhorn (Not OpenEBS, Not Rook/Ceph)

**Rationale**:
- Already running and familiar
- Lightweight (Ceph is overkill for 3 nodes)
- NVMe provides enough performance for homelab workloads

**Alternative considered**: OpenEBS LocalPV. **Deferred** because Longhorn replication is useful for DR. If resource pressure becomes critical, revisit.

---

## Security Posture

This homelab meets all CKS (Certified Kubernetes Security Specialist) requirements:

| CKS Domain | Implementation |
|------------|----------------|
| **Cluster Setup** | RBAC enabled, anonymous auth disabled, audit logging enabled |
| **Cluster Hardening** | Pod Security Standards enforced via Kyverno, no privileged containers |
| **System Hardening** | Talos immutable OS, no SSH, no shell access, AppArmor/Seccomp enabled |
| **Minimize Microservice Vulnerabilities** | Trivy Operator scans all images, Kyverno blocks `:latest` tags |
| **Supply Chain Security** | Image registry whitelist, image signature verification (future: Sigstore) |
| **Monitoring, Logging, Runtime Security** | Falco eBPF, Kubernetes audit logs, Prometheus alerts |

**Additional hardening**:
- All services behind Istio mTLS (no plaintext service-to-service communication)
- Default deny NetworkPolicy in every namespace
- No ServiceAccount token auto-mounting
- All ingress through Istio Gateway (no NodePort, no HostPort)
- Keycloak OIDC for human access (no shared credentials)

---

## Observability Stack

```
┌─────────────────────────────────────────────────────────────┐
│                         Grafana                              │
│  (Dashboards for metrics, logs, traces, security alerts)    │
└───────────────┬─────────────────────────────────────────────┘
                │
        ┌───────┴────────┬─────────────┬────────────┐
        │                │             │            │
   ┌────▼─────┐   ┌──────▼──────┐  ┌──▼────┐  ┌────▼─────┐
   │Prometheus│   │     Loki    │  │ Tempo │  │Falco     │
   │(metrics) │   │    (logs)   │  │(traces│  │(security)│
   └────▲─────┘   └──────▲──────┘  └──▲────┘  └────▲─────┘
        │                │            │            │
   ┌────┴─────┐   ┌──────┴──────┐  ┌──┴────┐  ┌────┴─────┐
   │  Alloy   │   │    Alloy    │  │ Alloy │  │  Alloy   │
   │(scraper) │   │(log agent)  │  │(OTLP) │  │(alerts)  │
   └────▲─────┘   └──────▲──────┘  └──▲────┘  └────▲─────┘
        │                │            │            │
   ┌────┴──────────┬─────┴────────────┴────────────┴──────┐
   │  Pods (metrics, logs, traces, syscalls)              │
   └──────────────────────────────────────────────────────┘
```

**Key integrations**:
- Prometheus scrapes: Cilium Hubble, Istio telemetry, Falco metrics, kube-state-metrics
- Loki ingests: Pod logs (via Alloy), Falco alerts, Kubernetes audit logs
- Grafana dashboards: Pre-built for Cilium, Istio, Falco, Kubernetes

---

## Network Flow Example

**External user accesses Nextcloud**:

```
Client
  │
  ▼
Internet
  │
  ▼
Protectli Vault (OPNsense firewall)
  │
  ▼
Caddy (reverse proxy, TLS termination with step-ca cert)
  │
  ▼
Keycloak (OIDC authentication)
  │
  ▼ (if authenticated)
Istio Gateway (LoadBalancer IP from MetalLB)
  │
  ▼
Istio ztunnel (L4 mTLS encryption)
  │
  ▼
Nextcloud Pod (via Cilium CNI routing)
  │
  ▼
Longhorn PVC (persistent data)
```

**Security layers traversed**:
1. OPNsense firewall rules
2. Caddy TLS (step-ca cert)
3. Keycloak OIDC (user identity)
4. Istio AuthorizationPolicy (service-level RBAC)
5. Istio ztunnel mTLS (workload identity)
6. Kyverno policies (enforced at admission time)
7. CiliumNetworkPolicy (L3/L4 egress controls)
8. Falco runtime detection (monitors syscalls)

---

## Future Enhancements

### Planned (v2.1)

1. **Pangolin on VPS** — Public access without port forwarding
   - WireGuard tunnel from homelab to VPS
   - Caddy on VPS or tunnel through to Protectli Vault Caddy
   - Terraform module: `Terraform/vps/`

2. **Sigstore Cosign** — Image signature verification
   - Sign all custom images with Cosign
   - Kyverno policy to verify signatures before admission

3. **Gateway API migration** — Replace Istio VirtualService with Gateway API
   - More portable, Kubernetes-native API
   - Istio Ambient natively supports Gateway API

4. **Multi-cluster** — Add a second Talos cluster for dev/staging
   - ArgoCD ApplicationSet targets multiple clusters
   - Step-CA issues certs for both clusters

### Under Consideration

- **Cilium-only mTLS** — Drop Istio Ambient, use Cilium's native SPIFFE mTLS
  - **Pro**: Reduces resource usage, simpler stack
  - **Con**: Cilium mTLS doesn't chain to step-ca root easily
  - **Decision pending**: Test Cilium's cert-manager integration

- **Vault for secrets** — Revisit after cluster stability is proven
  - **Pro**: Industry-standard, better audit trail
  - **Con**: Requires Longhorn, more complex DR
  - **Decision pending**: SOPS is working, no strong reason to change

- **Talos on Proxmox VMs** — Migrate from Turing RK1 to Proxmox VMs
  - **Pro**: More flexible, easier to scale
  - **Con**: Loses dedicated hardware for Kubernetes
  - **Decision pending**: Current hardware is sufficient

---

## Justfile Recipes (Planned)

```makefile
# Bootstrap recipes
bootstrap: bootstrap-infra bootstrap-pki bootstrap-talos bootstrap-core bootstrap-gitops
bootstrap-infra: tf-init tf-apply
bootstrap-pki: pki-gen-secrets
bootstrap-talos: talos-gen talos-apply talos-bootstrap
bootstrap-core: cilium-install sops-inject argocd-install
bootstrap-gitops: argocd-root-app

# Terraform
tf-init:
    cd Terraform/mgmt && terraform init
    cd Terraform/opnsense && terraform init
    cd Terraform/truenas && terraform init

tf-plan:
    cd Terraform/mgmt && terraform plan -var-file vars/prod/vars.auto.tfvars
    cd Terraform/opnsense && terraform plan -var-file vars/prod/vars.auto.tfvars
    cd Terraform/truenas && terraform plan -var-file vars/prod/vars.auto.tfvars

tf-apply:
    cd Terraform/mgmt && terraform apply -auto-approve -var-file vars/prod/vars.auto.tfvars
    cd Terraform/opnsense && terraform apply -auto-approve -var-file vars/prod/vars.auto.tfvars
    cd Terraform/truenas && terraform apply -auto-approve -var-file vars/prod/vars.auto.tfvars

# PKI
pki-gen-secrets:
    bash pki/gen-secrets-bundle.sh

# Talos
talos-gen:
    cd talos && talhelper genconfig

talos-apply:
    talosctl apply-config --nodes 192.168.1.34 --file talos/clusterconfig/homelab-cp-1.yaml
    talosctl apply-config --nodes 192.168.1.32 --file talos/clusterconfig/homelab-worker-1.yaml
    talosctl apply-config --nodes 192.168.1.33 --file talos/clusterconfig/homelab-worker-2.yaml

talos-bootstrap:
    talosctl bootstrap -n 192.168.1.34 --talosconfig talos/clusterconfig/talosconfig
    sleep 60
    talosctl kubeconfig -n 192.168.1.34 --force --talosconfig talos/clusterconfig/talosconfig

# Cluster bootstrap
cilium-install:
    helm repo add cilium https://helm.cilium.io/
    helm repo update
    helm upgrade --install cilium cilium/cilium -n kube-system \
      -f k8s/bootstrap/cilium/values.yaml

sops-inject:
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic sops-age -n argocd \
      --from-file=keys.txt=$HOME/.config/sops/age/keys.txt \
      --dry-run=client -o yaml | kubectl apply -f -

argocd-install:
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo update
    helm upgrade --install argocd argo/argo-cd -n argocd \
      -f k8s/bootstrap/argocd/values.yaml

argocd-root-app:
    kubectl apply -f k8s/argocd/overlays/prod/root-app.yaml

# Destroy (DANGEROUS)
destroy: destroy-cluster destroy-infra

destroy-cluster:
    @echo "This will DESTROY the Kubernetes cluster. Type 'yes' to confirm:"
    @read confirm && [ "$confirm" = "yes" ] || exit 1
    talosctl reset -n 192.168.1.34,192.168.1.32,192.168.1.33 --graceful

destroy-infra:
    @echo "This will DESTROY all Terraform-managed infrastructure. Type 'yes' to confirm:"
    @read confirm && [ "$confirm" = "yes" ] || exit 1
    cd Terraform/truenas && terraform destroy -auto-approve -var-file vars/prod/vars.auto.tfvars
    cd Terraform/opnsense && terraform destroy -auto-approve -var-file vars/prod/vars.auto.tfvars
    cd Terraform/mgmt && terraform destroy -auto-approve -var-file vars/prod/vars.auto.tfvars

# Health checks
health: health-step-ca health-talos health-cilium health-argocd

health-step-ca:
    step ca health --ca-url https://<rpi-ip>:8443 --root pki/root_ca.crt

health-talos:
    talosctl health -n 192.168.1.34 --talosconfig talos/clusterconfig/talosconfig

health-cilium:
    kubectl -n kube-system exec -it ds/cilium -- cilium status

health-argocd:
    kubectl -n argocd get applications
```

---

## Next Steps for Implementation

This is a **design document**. The next session will implement it in phases. Suggested order:

### Session 1: Repository Restructure
- Move existing files to new structure
- Create placeholder directories
- Update `.gitignore`
- Create `justfile` with initial recipes

### Session 2: PKI Setup
- Write `pki/gen-secrets-bundle.sh`
- Write `pki/yubikey-setup.md`
- Test secret bundle generation (requires step-ca on RPi)

### Session 3: Talos Configuration
- Write `talos/talconfig.yaml`
- Write all patches in `talos/patches/`
- Test `talhelper genconfig` (dry-run)

### Session 4: Bootstrap Manifests
- Write `k8s/bootstrap/cilium/values.yaml`
- Write `k8s/bootstrap/argocd/values.yaml`
- Write ArgoCD ApplicationSets

### Session 5: Infrastructure Layer
- Write cert-manager + Step-CA ClusterIssuer
- Write Istio Ambient manifests
- Write Spegel, MetalLB, Longhorn configs

### Session 6: Security Layer
- Write 9 Kyverno policies
- Write Falco custom rules
- Write Trivy Operator config

### Session 7: Platform Layer
- Write kube-prometheus-stack values
- Write Loki + Alloy configs
- Wire up Grafana dashboards

### Session 8: GitOps Wiring
- Test ApplicationSets with dummy apps
- Verify SyncWaves ordering
- Test SOPS decryption

### Session 9: Integration Testing
- End-to-end bootstrap on a test cluster
- Verify Cilium + Istio coexistence
- Verify all certs chain to step-ca root

### Session 10: Documentation
- Write `BOOTSTRAP.md` (step-by-step deployment guide)
- Write `TROUBLESHOOTING.md`
- Update skills in `.opencode/skills/`

---

## Maintenance & Operations

### Regular Tasks

| Task | Frequency | Command |
|------|-----------|---------|
| Update Talos | Monthly | `talosctl upgrade --image ghcr.io/siderolabs/installer:v<version>` |
| Update Kubernetes | Quarterly | `talosctl upgrade-k8s --to v<version>` |
| Rotate step-ca intermediate certs | Annually | `step ca certificate <cn> ... --not-after=87600h` |
| Backup Age key | Quarterly | Verify backup integrity |
| ArgoCD sync | Automatic | Monitor via Grafana dashboard |
| Security patches | Weekly | Renovate bot PRs + manual approval |

### Monitoring

Key metrics to watch:

- **Cluster health**: Talos node status, API server latency
- **Network**: Cilium connectivity, Hubble flow logs
- **Security**: Falco alert rate, Kyverno policy violations
- **Certificates**: cert-manager renewal status, expiry warnings
- **Storage**: Longhorn volume health, disk usage
- **GitOps**: ArgoCD sync status, sync failures

Grafana dashboards:
- Talos Overview (official)
- Cilium Hubble (official)
- Istio Mesh (official)
- Falco Security (community)
- ArgoCD Application Health (official)

---

## Glossary

| Term | Definition |
|------|------------|
| **Ambient Mesh** | Istio's sidecar-less service mesh architecture using ztunnel for L4 mTLS |
| **CKS** | Certified Kubernetes Security Specialist (CNCF certification) |
| **Kube-proxy replacement** | Cilium's eBPF-based implementation of Kubernetes service load balancing (replaces kube-proxy) |
| **KubePrism** | Talos Linux feature providing a local caching load balancer for the Kubernetes API |
| **SOPS** | Secrets OPerationS — tool for encrypting secrets in Git |
| **SyncWave** | ArgoCD feature for controlling deployment order via annotations |
| **talhelper** | Tool for generating Talos machine configs from a declarative YAML spec |
| **YubiKey** | Hardware security key (HSM) storing the CA root private key |
| **ztunnel** | Zero-trust tunnel — Istio Ambient's L4 proxy component |

---

## References

- **Talos Linux**: https://www.talos.dev/
- **talhelper**: https://budimanjojo.github.io/talhelper/
- **Cilium**: https://cilium.io/
- **Istio Ambient**: https://istio.io/latest/docs/ambient/
- **Step-CA**: https://smallstep.com/docs/step-ca/
- **ArgoCD**: https://argo-cd.readthedocs.io/
- **Kyverno**: https://kyverno.io/
- **Falco**: https://falco.org/
- **SOPS**: https://github.com/getsops/sops
- **CKS Exam**: https://www.cncf.io/certification/cks/

---

**End of Architecture Document**

Next: `BOOTSTRAP.md` — Step-by-step deployment guide
