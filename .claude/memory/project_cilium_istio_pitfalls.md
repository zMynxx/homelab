---
name: cilium-istio-ambient-pitfalls
description: Critical pitfalls discovered during Cilium + Istio Ambient setup on Talos — Kyverno blocking cert-manager, istiod Certificate issuer bug, bpf.masquerade breaking Istio health checks
metadata:
  type: project
---

**What**: Three cascading issues that silently broke Istio Ambient for 27h

**Why**: Non-obvious interactions between Kyverno admission enforcement, cert-manager namespace scoping, and Cilium BPF masquerade behavior

**Where**: `infra/k8s/kyverno/policies/baseline.yaml`, `infra/k8s/cilium/values.yaml`, `istiod` Certificate in `istio-system`

**Learned**:

1. **Kyverno blocks cert-manager silently**: `require-non-root`, `disallow-privileged`, `require-resource-limits` are all `Enforce` + `ADMISSION: true`. ReplicaSet shows `DESIRED=1, CURRENT=0` with zero pods and no `FailedCreate` events — only background scan `PolicyViolation` warnings. Must exempt `cert-manager`, `istio-system`, `kube-system`, `cilium`, `kyverno`, `spegel`, `registry`, `longhorn-system`, `longhorn-mount` from these policies. Kyverno uses `exclude.any` format (not bare `exclude` list).

2. **istiod Certificate must use ClusterIssuer**: The `istiod` Certificate in `istio-system` had `Kind: Issuer` pointing to an Issuer only in `cert-manager` namespace. Namespace-scoped Issuers cannot sign Certificates in other namespaces. Must be `Kind: ClusterIssuer`. Fix: `kubectl patch certificate istiod -n istio-system --type=merge -p '{"spec":{"issuerRef":{"kind":"ClusterIssuer",...}}}'` then delete the `istiod-tvrk9` temporary key Secret to unblock cert-manager reconciliation.

3. **bpf.masquerade: false required for Istio Ambient**: BPF masquerade rewrites ztunnel's TPROXY mark, breaking Ambient health checks. Use iptables masquerade (`enableIPv4Masquerade: true` + `bpf.masquerade: false`).

4. **kubeProxyReplacement must be true**: Talos disables kube-proxy via `cluster.proxy.disabled: true`. Setting `kubeProxyReplacement: false` in Cilium means nothing handles service routing.

5. **ztunnel `tcp connect error` to istiod:15012** traces back to `istiod-tls` Secret not existing → istiod reads empty file → `could not decode pem` → never starts gRPC TLS server on :15012.
