# GitOps - ArgoCD Managed Applications

This directory will contain all Kubernetes applications managed via ArgoCD in a GitOps fashion.

## Planned Structure

```
gitops/
├── bootstrap/          # ArgoCD bootstrap configuration
├── apps/              # Application manifests
│   ├── base/          # Base Kustomize configurations
│   └── overlays/      # Environment-specific overlays
├── infrastructure/    # Infrastructure services (cert-manager, metallb, etc.)
└── platform/          # Platform services (monitoring, logging, etc.)
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

## Security

- SOPS-encrypted secrets (no plaintext credentials)
- age post-quantum keys for decryption (external to cluster)
- Network policies via Cilium
- Service mesh mTLS via Istio Ambient
- Admission control via Kyverno
- Runtime security via Falco

---

**Status**: Directory structure pending - will be populated during GitOps migration
