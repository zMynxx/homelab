# Cilium + Istio Ambient Setup on Talos (Turing Pi 2)

Verified working: Cilium 1.20.1, Istio 1.29.2, Talos v1.13.9, Kubernetes v1.36.2, cert-manager v1.21.1, cert-manager-istio-csr v0.17.0.

---

## Architecture

```
Talos (kube-proxy disabled)
  └── Cilium (eBPF kube-proxy replacement, L3/L4)
        └── Istio Ambient (ztunnel L4 mTLS, waypoints L7)
              └── cert-manager-istio-csr (workload cert signing)
                    └── ClusterIssuer istio-ca (intermediate CA)
                          └── Homelab Root CA (offline, YubiKey)
```

Cilium owns service routing via eBPF. Istio Ambient owns mTLS and L7 policy. They coexist without CNI chaining (`cni.exclusive: false`).

---

## Bootstrap Order

This order is mandatory. Deviating from it causes cascading failures.

1. Talos nodes up, kubeconfig retrieved
2. Cilium installed (`just talos-cilium`)
3. cert-manager installed
4. Kyverno installed with correct namespace exemptions (see below)
5. PKI secrets created (`istio-ca` TLS Secret, `istio-root-ca` Secret)
6. cert-manager-istio-csr installed
7. Istio Ambient installed via `istioctl install -f infra/k8s/istio/istio-ambient-csr.yaml`

---

## Cilium Configuration

Talos disables kube-proxy (`cluster.proxy.disabled: true`), so Cilium **must** replace it.

Key settings:

| Setting | Value | Reason |
|---------|-------|--------|
| `kubeProxyReplacement` | `true` | Talos disables kube-proxy; Cilium must own service routing |
| `bpf.masquerade` | `false` | **Critical for Istio Ambient**: ztunnel health checks fail with BPF masquerade active; use iptables SNAT instead |
| `socketLB.hostNamespaceOnly` | `true` | Prevents Cilium socket-LB from intercepting pod connections and bypassing ztunnel |
| `cni.exclusive` | `false` | Allows istio-cni to install alongside Cilium |
| `l7Proxy` | `false` | Istio owns L7; Cilium operates at L3/L4 only |
| `securityContext.privileged` | `true` | Talos requires privileged for BPF map/program operations |
| `cgroup.autoMount.enabled` | `false` | Talos manages cgroups at `/sys/fs/cgroup` |

Install via the justfile recipe which reads `infra/k8s/cilium/values.yaml`:
```bash
just talos-cilium
```

Verify kube-proxy replacement is active after install:
```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg status | grep KubeProxyReplacement
# Expected: KubeProxyReplacement: True
```

---

## Kyverno — Critical: Exempt System Namespaces Before Everything Else

**This is the #1 bootstrap pitfall.** Kyverno policies (`require-non-root`, `disallow-privileged`, `require-resource-limits`) are in `Enforce` mode with `ADMISSION: true`. Without namespace exemptions, they silently block pod creation for cert-manager, istiod, ztunnel, and Cilium.

The ReplicaSet shows `DESIRED=1, CURRENT=0` with no pods and no `FailedCreate` events — only background scan `PolicyViolation` warnings. This makes it look like a scheduling problem when it's actually an admission block.

Apply Kyverno first:
```bash
just talos-kyverno
```

The policy file at `infra/k8s/kyverno/policies/baseline.yaml` uses `exclude.any` format and exempts these namespaces from the container security/resource policies:

```
disk-wipe, kube-system, cert-manager, istio-system, cilium,
spegel, registry, kyverno, longhorn-system, longhorn-mount
```

If cert-manager or istiod pods ever have `0/1` replicas with no pod appearing at all, check Kyverno admission first:
```bash
kubectl describe replicaset -n cert-manager <rs-name> | grep Events -A 20
# PolicyViolation + no SuccessfulCreate/FailedCreate = Kyverno blocking admission
```

---

## cert-manager + istio-csr

### PKI Hierarchy
```
Homelab Root CA (EC P-384, offline YubiKey)
  └── istio-ca (Intermediate CA, signed by Root CA)
        └── Istio workload certs (ztunnel, waypoints, workloads)
```

### Required Secrets (create before cert-manager-istio-csr)

**`istio-ca`** TLS Secret in `cert-manager` namespace — the intermediate CA key/cert that backs the `ClusterIssuer istio-ca`:
```bash
kubectl create secret tls istio-ca -n cert-manager \
  --cert=<istio-ca.crt> --key=<istio-ca.key>
```

**`istio-root-ca`** Opaque Secret in `cert-manager` namespace — the Homelab Root CA PEM, mounted by istio-csr for trust bundle:
```bash
kubectl create secret generic istio-root-ca -n cert-manager \
  --from-file=ca.pem=<homelab-root-ca.crt>
```

### istiod Certificate — Use ClusterIssuer, Not Issuer

**Critical**: the `istiod` Certificate in `istio-system` namespace must reference `Kind: ClusterIssuer`, NOT `Kind: Issuer`. A namespace-scoped Issuer in `cert-manager` cannot sign Certificates in `istio-system`.

If the `istiod-tls` Secret never gets created, check this first:
```bash
kubectl get certificate istiod -n istio-system -o jsonpath='{.spec.issuerRef}'
# Must show: {"group":"cert-manager.io","kind":"ClusterIssuer","name":"istio-ca"}
```

If wrong, patch it:
```bash
kubectl patch certificate istiod -n istio-system --type=merge \
  -p '{"spec":{"issuerRef":{"kind":"ClusterIssuer","name":"istio-ca","group":"cert-manager.io"}}}'
# Then delete the temporary key secret to unblock cert-manager:
kubectl delete secret istiod-tvrk9 -n istio-system 2>/dev/null || true
```

### cert-manager-istio-csr Crash Loop

istio-csr uses `--serving-certificate-duration=1h`. If the pod restarts during renewal, the watcher channel closes and the renewal fails. The pod will be in `Running` (not CrashLoopBackOff) but `0/1 Ready`, logging:

```
failed to fetch initial serving certificate in 10s: ... watcher channel closed; will retry
```

This usually self-heals once cert-manager is healthy. If it persists after cert-manager controller is confirmed running, restart the deployment:
```bash
kubectl rollout restart deployment/cert-manager-istio-csr -n cert-manager
```

---

## Istio Ambient

Install with:
```bash
istioctl install -f infra/k8s/istio/istio-ambient-csr.yaml
```

The `caAddress: cert-manager-istio-csr.cert-manager.svc:443` routes Istio's CA gRPC calls to istio-csr.

### ztunnel Not Ready

ztunnel connects to istiod at `istiod.istio-system.svc.cluster.local:15012` (gRPC XDS). If it shows `0/1` with `tcp connect error` in logs, istiod is not serving on port 15012. This is almost always because `istiod-tls` Secret doesn't exist.

Debug chain:
```bash
# 1. Check istiod logs for cert errors
kubectl -n istio-system logs deploy/istiod | grep -i "pem\|cert\|tls\|error"
# "could not decode pem" → istiod-tls Secret is missing or empty

# 2. Check istiod-tls Secret
kubectl get secret istiod-tls -n istio-system

# 3. Check istiod Certificate
kubectl get certificate istiod -n istio-system
# If READY=False, fix the issuerRef (see above)

# 4. Check cert-manager controller is running
kubectl get pods -n cert-manager | grep -v cainjector | grep -v webhook | grep -v istio-csr
# If no pod → Kyverno blocking (see Kyverno section above)
```

After fixing istiod-tls, restart istiod so it picks up the new Secret:
```bash
kubectl rollout restart deployment/istiod -n istio-system
```

---

## Verification

```bash
# Cilium: eBPF kube-proxy replacement active
kubectl -n kube-system exec ds/cilium -- cilium-dbg status | grep KubeProxyReplacement

# cert-manager: controller running and signing
kubectl get pods -n cert-manager
kubectl get certificate -A

# Istio Ambient: all components ready
kubectl get pods -n istio-system
# Expected: istio-cni-node (3/3), istiod (1/1), ztunnel (3/3)

# ztunnel cert chain
kubectl -n istio-system exec ds/ztunnel -- cat /var/run/secrets/istio/root-cert.pem | openssl x509 -noout -subject -issuer
```

---

## Reference Files

| File | Purpose |
|------|---------|
| `infra/k8s/cilium/values.yaml` | Cilium Helm values |
| `infra/k8s/istio/istio-ambient-csr.yaml` | IstioOperator for Ambient mode |
| `infra/k8s/kyverno/policies/baseline.yaml` | Kyverno ClusterPolicies with namespace exemptions |
| `infra/talos/patches/all-nodes.yaml` | Talos patches (kube-proxy disabled, kernel modules) |
| `just/talos.just` | All bootstrap recipes |
| `infra/tinyca/pki/pki-export/pki-export.sops.yaml` | SOPS-encrypted Root CA export |
