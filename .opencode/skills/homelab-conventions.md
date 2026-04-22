# Homelab Repository Conventions

> Trigger: convention, standard, layout, structure, naming, secret, pattern, best practice, repo, directory

## Repository Structure

```
homelab/
├── .justfile                  # Task runner (just)
├── .gitignore                 # Secrets, state, locks excluded
├── .opencode/skills/          # AI agent skills (this directory)
├── architecture.drawio        # Architecture diagram (draw.io)
├── LICENSE
├── README.md
│
├── Ansible/                   # Host provisioning (bare metal, appliances)
│   ├── 00-Init/               # Base host setup (static IP, apt)
│   └── 01-Passthrough/        # PCI passthrough config (HBA/NIC)
│
├── Terraform/                 # Infrastructure as Code
│   ├── mgmt/                  # Management infrastructure
│   ├── opnsense/              # OPNsense on Protectli Vault
│   ├── truenas/               # NAS configuration
│   └── ubuntu/                # General-purpose VMs
│
├── talos/                     # Talos Linux cluster provisioning
│   ├── _out/                  # Generated machine configs
│   ├── inventory/             # Ansible inventory for Talos
│   └── roles/                 # Ansible roles for Talos lifecycle
│
└── k8s/                       # Kubernetes manifests (GitOps root)
    ├── argocd/                # ArgoCD self-management
    ├── infrastructure/        # CNI, mesh, policies, storage
    ├── platform/              # Monitoring, logging, observability
    └── apps/                  # Application workloads
```

## Physical Topology

```
                    Internet
                       │
                  ┌────┴────┐
                  │   VPS   │  Pangolin + Caddy (reverse proxy)
                  └────┬────┘
                       │ WireGuard tunnel
                       │
              ┌────────┴────────┐
              │  Protectli Vault │  OPNsense (firewall) + Keycloak (SSO)
              └────────┬────────┘
                       │
            ┌──────────┼──────────┐
            │          │          │
       ┌────┴────┐ ┌───┴───┐ ┌───┴───┐
       │TuringPi2│ │TrueNAS│ │  RPi  │
       │  Talos  │ │Storage│ │step-ca│
       └─────────┘ └───────┘ └───────┘
```

## Naming Conventions

### Directories
- **Ansible**: `<sequence>-<PascalCase>` (e.g., `00-Init`, `01-Passthrough`)
- **Terraform**: `<lowercase>` component name (e.g., `opnsense`, `truenas`)
- **Kubernetes**: `<lowercase-kebab>` (e.g., `cert-manager`, `istio-system`)

### Files
- **YAML**: `.yaml` (never `.yml`) — be consistent across the repo
- **Terraform**: Standard naming (`main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, `versions.tf`)
- **Ansible tasks**: `<snake_case>.yaml` (e.g., `set_static_ip.yaml`, `apt_update_upgrade.yaml`)

### Kubernetes Resources
- **Labels** (required on every resource):
  - `app.kubernetes.io/name` — component name
  - `app.kubernetes.io/part-of` — parent application/system
  - `app.kubernetes.io/managed-by` — `argocd` for GitOps-managed resources
- **Namespaces**: One per application/service. Infrastructure in dedicated namespaces (`istio-system`, `cilium`, `kyverno`, `falco`).
- **Resource names**: lowercase kebab-case, matching the directory name.

## Secrets Handling

### What's Gitignored
```
**/**/*.tfvars          # Terraform variable files
**/**/*.pub             # Public keys (still sensitive context)
**/**/logs              # Log files
**/**/.terraform        # Provider cache
**/**/terraform.tfstate # State files
**/**/*secret*          # Anything with 'secret' in the name
```

### Rules
1. **Never commit plaintext secrets** — no passwords, tokens, keys, or certificates in Git.
2. **SOPS-encrypted secrets** (`*.sops.yaml`) → safe to commit. Encrypted with age post-quantum key (ML-KEM + X25519).
3. **Terraform secrets** → `.tfvars` files (gitignored).
4. **Ansible secrets** → `ansible-vault` encrypted files or `.secret` files (gitignored).
5. **Kubernetes secrets** → SOPS-encrypted `*.sops.yaml` manifests (never raw `kind: Secret` in Git).
6. **Certificates** → Private keys never in Git. Public certs (CA bundle) are acceptable.
7. If a file path contains `secret`, `credential`, `password`, `token`, or `key` — **do not commit it** unless it matches `*.sops.*`.

### SOPS + age

- **Config**: `.sops.yaml` at repo root — defines age recipient for each path pattern.
- **Private key**: `key.txt.secret` (gitignored). Store at `~/.config/sops/age/keys.txt` on each machine.
- **Naming**: secrets files use `*.sops.yaml` suffix so `.sops.yaml` creation rules auto-apply.
- **Encrypt**: `just sops-encrypt <file>` — encrypts in-place.
- **Decrypt**: `just sops-decrypt <file>` — decrypts to stdout.
- **Edit**: `just sops-edit <file>` — decrypt → `$EDITOR` → re-encrypt on save.
- **Key rotation**: `sops updatekeys <file>` after updating recipient in `.sops.yaml`.
- Full workflow documented in `gitops/README.md`.

## YAML Style Guide

- **Indentation**: 2 spaces (never tabs)
- **Quotes**: Use quotes only when needed (strings that look like numbers, booleans, or contain special chars)
- **Comments**: Inline comments for non-obvious values. Block comments above complex sections.
- **Multi-line strings**: Use `|` for literal blocks, `>` for folded. Prefer `|` for scripts and commands.
- **Empty lines**: One blank line between top-level sections. No trailing blank lines.

## Git Workflow

- **Main branch**: `main` — always deployable, ArgoCD syncs from here.
- **Feature branches**: `<type>/<short-description>` (e.g., `feat/add-grafana`, `fix/cilium-config`).
- **Commits**: Conventional commits — `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`.
- **No force push to main**.
- **PR required** for infrastructure changes (Terraform, Talos configs). Direct push for docs/minor fixes is acceptable.

## Tool Versions

Keep these pinned and documented:
- Talos: v1.7.0
- talosctl: v1.7.5
- kube-vip: v0.8.0
- MetalLB: v0.13.12
- Terraform: pin in `versions.tf`
- Ansible: track in `requirements.txt` or `ansible.cfg`

When upgrading any component, update the version reference in this file AND the relevant config (Ansible vars, Terraform versions, etc.).

## Adding New Components

1. Determine the layer: infrastructure, platform, or application.
2. Create the Kustomize directory structure under `k8s/<layer>/<component>/`.
3. Add an ArgoCD `Application` or ensure the `ApplicationSet` discovers it.
4. Add relevant Kyverno policies if the component introduces new workloads.
5. Update `architecture.drawio` if the component changes the architecture.
6. Add a Justfile recipe if the component needs manual operational tasks.
7. Document any new IP allocations, ports, or DNS entries.
