# GitOps - ArgoCD Managed Applications

This directory will contain all Kubernetes applications managed via ArgoCD in a GitOps fashion.

## Structure

```
gitops/
├── bootstrap/                    # ArgoCD self-management
│   ├── root.yaml                 # Root app-of-apps (apply once to bootstrap)
│   └── argocd/
│       ├── values.yaml           # ArgoCD Helm values (SOPS/age, CMP, Dex, Dragonfly cache)
│       ├── caddy-local-ca-cm.yaml
│       ├── dex-tls-cert.yaml
│       ├── oidc/                 # OIDC secret (SOPS encrypted)
│       └── policies/             # ArgoCD RBAC AuthorizationPolicies
├── apps/                         # ArgoCD Application CRDs (app-of-apps; root points here)
│   ├── repositories.yaml         # ArgoCD repository secrets
│   ├── argocd-oidc.yaml
│   ├── argocd-policies.yaml
│   ├── cilium.yaml
│   ├── cilium-lb-ipam.yaml
│   ├── cert-manager.yaml
│   ├── cert-manager-extras.yaml
│   ├── cert-manager-istio-csr.yaml
│   ├── kyverno.yaml
│   ├── kyverno-policies.yaml
│   ├── longhorn.yaml
│   ├── metrics-server.yaml
│   ├── externaldns.yaml
│   ├── spegel.yaml
│   ├── reloader.yaml
│   ├── cnpg.yaml
│   ├── dragonfly-operator.yaml
│   ├── dragonfly-argocd-cache.yaml
│   ├── istio-ingress.yaml
│   ├── kanidm.yaml
│   ├── kaniop.yaml
│   ├── oauth2-proxy.yaml
│   ├── databases.yaml
│   ├── grafana.yaml
│   ├── otel-collector.yaml
│   ├── tempo.yaml
│   ├── victoria-logs.yaml
│   ├── victoria-metrics.yaml
│   └── zot.yaml
├── infrastructure/               # Configs for cluster infrastructure components
│   ├── cilium/                   # CNI + LB IPAM pool
│   ├── cert-manager/             # cert-manager + istio-csr + step-issuer
│   ├── kyverno/                  # Kyverno + policies/
│   ├── longhorn/                 # Storage + nvme-wipe job
│   ├── metrics-server/
│   ├── externaldns/
│   ├── spegel/                   # OCI image cache
│   ├── cnpg/                     # CloudNativePG operator
│   ├── dragonfly/                # DragonflyDB operator + ArgoCD cache CR
│   └── istio-ingress/            # Gateway + certificate
└── platform/                     # Configs for platform/application services
    ├── observability/
    │   ├── grafana/
    │   ├── otel-collector/
    │   ├── tempo/
    │   ├── victoria-logs/
    │   └── victoria-metrics/
    ├── kanidm/                   # Identity provider (kaniop CRs)
    ├── oauth2-proxy/             # SSO gateway (SOPS secret)
    ├── databases/                # CNPG cluster CRs (Kustomize)
    └── zot/                      # OCI registry
```

## GitOps Workflow

1. All cluster state declared in Git
2. ArgoCD monitors this directory for changes
3. Automatic synchronization with SyncWaves for dependency ordering
4. Secrets managed via SOPS + age encryption (see below)

## Secrets Management: SOPS + age

Sensitive values are encrypted with [SOPS](https://github.com/getsops/sops) using an [age](https://github.com/FiloSottile/age) post-quantum key (ML-KEM + X25519 hybrid, requires age ≥ v1.3.1 and SOPS ≥ v3.9).

Encrypted files (`*.sops.yaml`) are safe to commit. Only the holder of the age private key can decrypt them.

### First-time Setup (new machine)

1. **Install dependencies**

   ```bash
   brew install age sops
   ```

2. **Restore your private key**

   ```bash
   mkdir -p ~/.config/sops/age
   cp key.txt.secret ~/.config/sops/age/keys.txt
   chmod 600 ~/.config/sops/age/keys.txt
   ```

   > `key.txt.secret` is gitignored. Back it up out-of-band (password manager, encrypted USB).

3. **Verify decryption works**

   ```bash
   just sops-decrypt network/secrets.sops.yaml
   ```

### Key Details

| Property | Value |
|----------|-------|
| Algorithm | ML-KEM-768 + X25519 (post-quantum hybrid) |
| age version required | ≥ v1.3.1 |
| SOPS version required | ≥ v3.9 |
| Private key location | `key.txt.secret` (gitignored) / `~/.config/sops/age/keys.txt` |
| Config file | `.sops.yaml` (repo root) |

### Daily Workflow

**Decrypt to stdout** (read secrets without writing plaintext to disk):

```bash
just sops-decrypt network/secrets.sops.yaml
```

**Edit a secret interactively** (SOPS decrypts → opens `$EDITOR` → re-encrypts on save):

```bash
just sops-edit network/secrets.sops.yaml
```

**Add a new secrets file**:

```bash
# 1. Create the plaintext YAML at the destination path (*.sops.yaml)
cat > path/to/my-component/secrets.sops.yaml << 'EOF'
some_password: hunter2
some_token: abc123
EOF

# 2. Encrypt in-place (SOPS picks up the key from .sops.yaml + ~/.config/sops/age/keys.txt)
just sops-encrypt path/to/my-component/secrets.sops.yaml

# 3. Commit the encrypted file
git add path/to/my-component/secrets.sops.yaml
```

**Never** create intermediate plaintext files outside of `sops-edit`. Use a heredoc directly to the `.sops.yaml` destination, then immediately encrypt.

### File Naming Convention

| Pattern | Use |
|---------|-----|
| `*.sops.yaml` | Any SOPS-encrypted secret (env vars, API keys, tokens) |
| `gitops/**/secret*.yaml` | Kubernetes `Secret` manifests encrypted for cluster consumption |

The `.sops.yaml` creation rules auto-apply the correct age key for both patterns — no need to pass `--age` manually.

### Key Rotation

```bash
# Generate a new key
age-keygen -o key.txt.secret

# Update the age: recipient in .sops.yaml with the new public key, then:
sops updatekeys path/to/file.sops.yaml
```

### What Is and Is Not Committed

| File | Committed | Reason |
|------|-----------|--------|
| `*.sops.yaml` | ✅ Yes | SOPS-encrypted, safe |
| `*secret*` (no `.sops.`) | ❌ No | Gitignored plaintext |
| `key.txt.secret` | ❌ No | Private key — never commit |
| `.sops.yaml` | ✅ Yes | Contains only the public key |

## Cutover: Switching the Live Cluster

The live ArgoCD root Application still points to `infra/k8s/argocd/apps`. To cut over:

1. **Push this commit to `main`** (both old and new paths must exist in git simultaneously during cutover).

2. **Apply the new root app** imperatively to update the live root Application:
   ```bash
   kubectl apply -f gitops/bootstrap/root.yaml
   ```

3. **Verify ArgoCD syncs from the new path** — the root app should show `gitops/apps` as its source and all child apps should remain healthy.

4. **Remove the old sources** once confirmed stable:
   ```bash
   git rm -r infra/k8s/argocd/apps infra/k8s/argocd/oidc infra/k8s/argocd/policies
   git rm -r infra/k8s/cilium infra/k8s/cert-manager infra/k8s/kyverno infra/k8s/longhorn
   git rm -r infra/k8s/metrics-server infra/k8s/externaldns infra/k8s/spegel infra/k8s/cnpg
   git rm -r infra/k8s/dragonfly infra/k8s/istio-ingress infra/k8s/databases
   git rm -r infra/k8s/observability infra/k8s/kanidm infra/k8s/oauth2-proxy infra/k8s/zot
   ```

> The ArgoCD Helm Application (`argocd` itself) and its values still live in `infra/k8s/argocd/values.yaml` on the cluster — that file is now mirrored at `gitops/bootstrap/argocd/values.yaml`. Update the ArgoCD Application manifest's `$values` ref accordingly when you manage ArgoCD via GitOps.

## Security

- SOPS-encrypted secrets (no plaintext credentials)
- age post-quantum keys for decryption (external to cluster)
- Network policies via Cilium
- Service mesh mTLS via Istio Ambient
- Admission control via Kyverno
- Runtime security via Falco

---

**Status**: Migration complete. Old sources remain under `infra/k8s/` until the live root Application is updated (see Cutover below).
