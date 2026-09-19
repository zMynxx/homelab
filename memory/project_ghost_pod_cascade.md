---
name: ghost-pod-cascade-crash
description: Ghost pod accumulation causing node crash cascade and Kanidm 502 — root cause and fix
metadata:
  type: project
---

**What**: 212 orphaned `ContainerStatusUnknown`/`Error` pods (116 on turingpi-3, 93+ on turingpi-1/4) caused a resource exhaustion → node crash → more ghosts → crash faster cycle. This made turingpi-3 go `NodeNotReady` every ~1-2 hours, which kept the istio-ingressgateway pod's readiness probe failing, which made Cilium mark the endpoint as `(maintenance)`, which caused the Kanidm 502.

**Why**: Ghost pods accumulate when a node goes NotReady and recovers too quickly (within the ~5 min eviction tolerance window). Kubernetes GC can't keep up with repeated rapid crashes. Dead containers still consume cgroup/memory resources, adding pressure and accelerating the next crash.

**Where**: `kube-system` (93+ cilium-operator ghosts on turingpi-1/3/4), `reloader` (2), `argocd` (1). The cilium-operator (replicas=2) had 116 ghost pods on turingpi-3 alone from ReplicaSet `7d7ccd455d`.

**Learned**:
- `ContainerStatusUnknown` pods do NOT self-clean during rapid NodeNotReady/Ready cycles — must be bulk-deleted manually.
- When Cilium marks an endpoint `(maintenance)` (endpoint `ready=false` in EndpointSlice), traffic is silently dropped at the LB level — manifests as 502 with ZERO Envoy access log entries.
- The L2 announcement lease holder and the pod node can differ; traffic crosses nodes via Cilium DNAT. Check BOTH the lease holder's `cilium service list` (looking for `active` vs `maintenance`) AND the EndpointSlice `ready` condition.
- The Kanidm 502 had a second root cause: Kyverno policy `add-istio-ambient-label` was labeling `istio-ingress` namespace with `istio.io/dataplane-mode=ambient`, causing ztunnel to intercept all ingress gateway traffic. Fixed in `infra/k8s/kyverno/policies/istio-ambient.yaml` by adding `istio-ingress` to both the admission `exclude` block and the `mutate.targets` selector.

**Fix command (bulk ghost pod cleanup)**:
```bash
for NS in kube-system reloader argocd; do
  kubectl get pods -n $NS \
    -o go-template='{{range .items}}{{if ne .status.phase "Running"}}{{if ne .status.phase "Pending"}}{{if ne .status.phase "Succeeded"}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}{{end}}{{end}}' \
    | xargs -r kubectl delete pod -n $NS --grace-period=0 --force
done
```

**How to apply**: If a node is crashing repeatedly and you see hundreds of ghost pods on it (`kubectl get pods --all-namespaces | grep ContainerStatusUnknown | wc -l`), this is likely the culprit. Clean ghosts first before investigating other causes.

---

## Kanidm 502 — secondary root cause: double-TLS via DestinationRule + PASSTHROUGH

**What**: DestinationRule `mode: SIMPLE` on `kanidm.kanidm.svc.cluster.local:8443` applies to ALL traffic to that cluster, including the Istio TLS PASSTHROUGH route on Gateway port 8443. When Caddy sent a TLS ClientHello through the PASSTHROUGH listener, Envoy wrapped it in a NEW TLS connection (DestinationRule TLS origination) before forwarding to kanidm via HBONE. The result: kanidm's HTTP response came back as plaintext bytes to Caddy → OpenSSL `packet length too long` → Caddy 502.

**Fix**: Removed port 8443 PASSTHROUGH from Gateway and VirtualService. Caddy now connects to port 443 (SIMPLE — Envoy terminates TLS with `*.opnsense.internal` wildcard cert, then re-originates TLS to kanidm:8443 per the DestinationRule). Commit `605c7fb`.

**Rule**: A DestinationRule `mode: SIMPLE` on a host:port applies to ALL Envoy clusters for that host:port, including TCP PASSTHROUGH routes — they cannot be scoped per gateway route. Never use TLS PASSTHROUGH + DestinationRule TLS origination on the same cluster.
