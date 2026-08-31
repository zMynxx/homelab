# Talos + Cilium + Istio Ambient Setup - Complete Documentation

## Cluster Overview
- **Platform**: Talos Linux v1.13.6 on Turing Pi 2 (RK1 ARM64 nodes)
- **Nodes**: 3 control planes (turingpi-1/3/4) at 192.168.30.103/.104/.105
- **VIP**: 192.168.30.99
- **Kubernetes**: v1.36.2
- **Cilium**: v1.20.1 (with kube-proxy, not kube-proxy replacement)
- **Istio**: Ambient mode with cert-manager-istio-csr
- **Cert-manager**: v1.21.1 with step-issuer (ACME to step-ca at 192.168.10.37:8443)
- **Spegel**: v0.7.4 — node-local P2P image mirror (DaemonSet, `hostPort 5001`)
- **Zot**: v2.1.20 — in-cluster pull-through registry cache, HTTPS (`:5000`, cert from `homelab-ca` ClusterIssuer → YubiKey root)
- **Kyverno**: admission policy engine (HA, 2 replicas/controller) with 5 baseline CKS ClusterPolicies

---

## Critical Configuration Fixes

### 1. Talos Machine Config (`infra/talos/patches/all-nodes.yaml`)
```yaml
cluster:
  proxy:
    disabled: true
  network:
    forwardKubeDNSToHost: false  # CRITICAL: Required when using BPF masquerade with CoreDNS
```

### 2. Cilium Configuration (`infra/k8s/cilium/values.yaml`)
Key settings:
- `kubeProxyReplacement: false` - Keep kube-proxy (recommended for Istio)
- `bpf.masquerade: false` - **CRITICAL**: Must be false for Istio Ambient health checks
- `socketLB.enabled: true` with `socketLB.hostNamespaceOnly: true`
- `cni.exclusive: false` (no chaining)
- `securityContext.privileged: true` (required on Talos)

### 3. kube-proxy Deployment
Fixed RBAC issues:
```bash
# Added ClusterRole with permissions for:
# - endpointslices (discovery.k8s.io)
# - servicecidrs (networking.k8s.io)
# - events (events.k8s.io)
```
Deployed as DaemonSet with ConfigMap config.

### 4. CoreDNS
Fixed with external forwarders:
```yaml
Corefile: |
  .:53 {
      kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
          ttl 30
      }
      forward . 1.1.1.1 8.8.8.8 {
         max_concurrent 1000
      }
      cache 30
      loop
      reload
      loadbalance
  }
```

### 5. cert-manager Webhook
Fixed by removing custom `command` override - use image's default entrypoint with `args` only:
```yaml
# Remove command override, use args only:
args:
  - --v=2
  - --secure-port=10250
  - --dynamic-serving-ca-secret-namespace=$(POD_NAMESPACE)
  # ... other args
```

### 6. cert-manager-istio-csr
- ClusterIssuer `istio-ca` (CA type, secret `istio-ca` in cert-manager namespace)
- `istio-root-ca` secret with Homelab Root CA from SOPS
- Values: `caTrustedNodeAccounts: istio-system/ztunnel`, port 6443, trust domain `cluster.local`

### 7. Istio Ambient Installation
```bash
istioctl install -f infra/k8s/istio/istio-ambient-csr.yaml
```
With `caAddress: cert-manager-istio-csr.cert-manager.svc:443` and `cni.enabled: true` for istio-cni

### 8. Spegel (node-local image mirror)
```bash
just talos-spegel   # helm oci://ghcr.io/spegel-org/helm-charts/spegel
```
- DaemonSet on all nodes; serves OCI registry on `hostPort 5001` (containerd mirror chain: `localhost:5001` first).
- `ambient.istio.io/redirection: disabled` so ztunnel doesn't break the registry protocol.
- Talos already points containerd at `localhost:5001` (see `infra/talos/patches/all-nodes.yaml`).

### 9. Zot (in-cluster pull-through cache)
```bash
just talos-zot   # raw Deployment/Service/ConfigMap + cert-manager Certificate
```
- HTTPS on `:5000`, cert issued by the `homelab-ca` ClusterIssuer (CA type, backed by the `istio-ca` intermediate secret → YubiKey root). Containerd trusts it via the machine root CA (`custom-ca.yaml`).
- Pull-through via `extensions.sync` (`onDemand: true`) for docker.io / ghcr.io / quay.io / registry.k8s.io.
- Talos mirror endpoint is `https://zot.registry.svc.cluster.local:5000` (requires regenerated + reapplied machine config).
- **Storage is currently `emptyDir`** (ephemeral cache). Replace with a Longhorn PVC once the storage layer is deployed.

### 10. Kyverno (admission policy)
```bash
just talos-kyverno   # helm kyverno/kyverno
kubectl apply -f infra/k8s/kyverno/policies/baseline.yaml
```
- HA (2 replicas per controller). `kyverno` namespace is exempt from Talos PodSecurity (see `controlplane.yaml`).
- 5 baseline CKS ClusterPolicies enforcing: non-root, no privileged, no `:latest`, resource limits, no NodePort.

---

## Bootstrap Sequence (from scratch)

### 1. Talos Bootstrap
```bash
just talos-generate      # Decrypt SOPS, generate configs
just talos-apply         # Apply configs to all 3 nodes
just talos-bootstrap     # Bootstrap etcd on node 1
just talos-kubeconfig    # Fetch kubeconfig
```

### 2. Cilium
```bash
just talos-cilium  # Uses kube-proxy (kubeProxyReplacement=false) for Istio compatibility
```

### 3. kube-proxy
Apply DaemonSet + ConfigMap + RBAC manifests

### 3. CoreDNS
Apply ConfigMap with kubernetes plugin + external forwarders

### 4. cert-manager + istio-csr
```bash
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --set installCRDs=true \
  --set webhook.hostNetwork=false \
  --set webhook.containerSecurityContext.allowPrivilegeEscalation=false \
  --set 'webhook.containerSecurityContext.capabilities.drop={ALL}'

# Apply istio-ca Certificate + ClusterIssuer + cert-manager-istio-csr
```

### 3. Istio Ambient
```bash
istioctl install -f infra/k8s/istio/istio-ambient-csr.yaml -y
```

---

## Current Status
- ✅ 3 Talos nodes Ready
- ✅ Cilium CNI working (NetworkPolicy, Hubble)
- ✅ kube-proxy running (service LB via iptables)
- ✅ CoreDNS Ready (2/2 pods)
- ✅ cert-manager + webhook + cainjector Ready
- ✅ cert-manager-istio-csr Ready
- ✅ istio-csr Ready
- ✅ Istio Ambient (istiod, istio-cni) Running
- ✅ Spegel DaemonSet Running on all 3 nodes (P2P image mirror, `:5001`)
- ✅ Zot Running (HTTPS `:5000`, pull-through cache verified end-to-end)
- ✅ Kyverno Running (HA) + 5 baseline CKS ClusterPolicies enforcing
- ⚠️ ztunnel not Ready (DNS resolution to istiod failing - CoreDNS NXDOMAIN for `kubernetes.default.svc.cluster.local`)

---

## Known Issues
1. **CoreDNS NXDOMAIN for `kubernetes.default.svc.cluster.local`** - kubernetes plugin may not be working correctly despite external forwarders
2. **ztunnel can't reach istiod** - DNS resolution failure (istiod.istio-system.svc:15012)
3. **cert-manager-webhook** - Works now but required removing `command` override

---

## Preserved Assets (pre-wipe)
- `/tmp/opencode/preserve/istio-ca.crt` - Root-signed intermediate cert
- `/tmp/opencode/preserve/istio-ca.key` - Intermediate key (EC P-384)
- `/tmp/opencode/preserve/istio-root-ca.pem` - Homelab Root CA
- SOPS files: `infra/talos/talsecret.sops.yaml`, `infra/tinyca/pki/pki-export/pki-export.sops.yaml`
- Age key: `key.txt.secret`

---

## Key Files
- `infra/talos/talconfig.yaml` - Cluster definition
- `infra/talos/patches/all-nodes.yaml` - Node patches (registry mirror chain → Spegel → Zot→upstream)
- `infra/talos/patches/controlplane.yaml` - Control plane patches (PodSecurity exemptions incl. kyverno)
- `infra/k8s/cilium/values.yaml` - Cilium Helm values
- `infra/k8s/istio/istio-ambient-csr.yaml` - IstioOperator manifest
- `infra/k8s/cert-manager/step-issuer.yaml` - ClusterIssuer
- `infra/k8s/spegel/values.yaml` - Spegel Helm values (OCI chart)
- `infra/k8s/zot/{configmap,deployment,service,certificate}.yaml` - Zot raw manifests + `homelab-ca` ClusterIssuer
- `infra/k8s/kyverno/values.yaml` + `policies/baseline.yaml` - Kyverno Helm values + CKS policies
- `infra/tinyca/` - PKI scripts and SOPS