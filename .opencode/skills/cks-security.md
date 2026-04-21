# CKS Security Stack — Cilium, Istio, Kyverno, Falco

> Trigger: cilium, cni, network policy, istio, service mesh, mtls, ingress, gateway, kyverno, policy, falco, runtime, security, cks, ebpf, sidecar, envoy

## Stack Overview

This cluster runs a CKS-aligned security stack. Every component has a specific role — no overlap.

| Component | Role | Layer |
|-----------|------|-------|
| **Cilium** | CNI + NetworkPolicy + L3/L4 enforcement | Network |
| **Istio** | mTLS service mesh + Ingress Gateway + L7 policies | Service Mesh |
| **Kyverno** | Admission controller + policy enforcement | Admission |
| **Falco** | Runtime threat detection + audit logging | Runtime |
| **cert-manager** | Certificate lifecycle automation | PKI |

## Cilium (CNI)

- **Role**: Pod networking, NetworkPolicy enforcement, eBPF dataplane.
- **Replaces**: kube-proxy (Cilium runs in kube-proxy replacement mode on Talos).
- **Talos integration**: Cilium must be installed as an extra manifest or via ArgoCD since Talos ships without a CNI.
- **Key config**: Enable Hubble for observability. Use CiliumNetworkPolicy (not just vanilla NetworkPolicy) for L7 filtering.

### Rules
- **Default deny** NetworkPolicy in every namespace. Explicit allow only.
- Use `CiliumNetworkPolicy` for advanced L7 rules; vanilla `NetworkPolicy` for basic L3/L4.
- Never disable eBPF — it's the dataplane.
- Hubble UI should be exposed only internally (behind Istio gateway, not public).

## Istio (Service Mesh)

- **Role**: mTLS between all services, ingress gateway, L7 traffic management.
- **Mode**: Sidecar injection (ambient mesh can be evaluated later).
- **Ingress**: Istio `Gateway` + `VirtualService` for external traffic. MetalLB provides the LoadBalancer IP.
- **mTLS**: STRICT mode cluster-wide. No permissive fallback in production.
- **Certificates**: Istio's CA integrates with step-ca (see `pki-certificates` skill) for root CA trust.

### Rules
- Every namespace with workloads MUST have `istio-injection: enabled` label.
- `PeerAuthentication` set to `STRICT` at mesh level.
- `AuthorizationPolicy` on every service — no wide-open service-to-service communication.
- Gateway definitions go in `k8s/infrastructure/istio/` — not alongside app manifests.
- Use `DestinationRule` for circuit breaking and connection pool settings.

### Gateway API (preferred over Istio VirtualService for new work)
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: homelab-gateway
  namespace: istio-system
spec:
  gatewayClassName: istio
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - name: wildcard-tls
```

## Kyverno (Policy Engine)

- **Role**: Kubernetes admission controller — validate, mutate, generate resources.
- **Replaces**: OPA/Gatekeeper (Kyverno is more Kubernetes-native).

### Standard Policies (must exist)
1. **Disallow privileged containers** — no `privileged: true`
2. **Require resource limits** — every container must have CPU/memory limits
3. **Require labels** — `app.kubernetes.io/name`, `app.kubernetes.io/part-of`
4. **Disallow latest tag** — no `:latest` image tags
5. **Require non-root** — `runAsNonRoot: true`
6. **Restrict host namespaces** — no `hostNetwork`, `hostPID`, `hostIPC`
7. **Disallow NodePort** — all external traffic goes through Istio gateway
8. **Require Istio sidecar** — validate `istio-injection` label on namespaces
9. **Image registry whitelist** — only allow images from trusted registries

### Rules
- Policies go in `k8s/infrastructure/kyverno/policies/`.
- Use `ClusterPolicy` for cluster-wide rules, `Policy` for namespace-scoped exceptions.
- `validationFailureAction: Enforce` in production. Use `Audit` only during initial rollout.
- Generate policies (e.g., auto-create NetworkPolicy on namespace creation) go in a separate `generate/` subdirectory.

## Falco (Runtime Security)

- **Role**: Detect anomalous behavior at runtime — shell in containers, unexpected network connections, file access violations.
- **Dataplane**: eBPF driver (NOT kernel module — Talos doesn't support kernel modules).
- **Output**: Forward alerts to stdout → collected by logging stack (Loki/Promtail).

### Rules
- Custom Falco rules go in `k8s/infrastructure/falco/rules/`.
- Never disable default rules — only add custom ones or tune sensitivity.
- Falco must run as a DaemonSet with host PID namespace access.
- Alert on: shell spawned in container, unexpected outbound connections, sensitive file reads (`/etc/shadow`, `/etc/kubernetes/pki/*`).
- Integration: Falco alerts should fire Prometheus alerts via falco-exporter.

## Cross-Cutting Concerns

- **Defense in depth**: Cilium (network) → Istio (service) → Kyverno (admission) → Falco (runtime). All layers active simultaneously.
- **Audit logging**: Kubernetes audit logs + Falco alerts both feed into the logging stack.
- **Pod Security Standards**: Enforce `restricted` PSS baseline via Kyverno (not PSA, since Kyverno gives more control).
- **Secrets**: Never mount ServiceAccount tokens automatically. Set `automountServiceAccountToken: false` by default (enforced by Kyverno).
