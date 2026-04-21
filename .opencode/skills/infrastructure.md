# Infrastructure — Terraform, Ansible, Justfile

> Trigger: terraform, ansible, opnsense, truenas, protectli, justfile, just, provision, infrastructure, iac, playbook, hba, passthrough, pci, pangolin, caddy, keycloak, vps

## Infrastructure Components

| Component | Tool | Path | Purpose |
|-----------|------|------|---------|
| OPNsense firewall | Terraform | `Terraform/opnsense/` | Firewall/router config on Protectli Vault |
| TrueNAS storage | Terraform | `Terraform/truenas/` | NAS configuration |
| Ubuntu VMs | Terraform | `Terraform/ubuntu/` | General-purpose VMs |
| Management | Terraform | `Terraform/mgmt/` | Management infrastructure |
| Host initialization | Ansible | `Ansible/00-Init/` | Static IP, apt config |
| PCI passthrough | Ansible | `Ansible/01-Passthrough/` | HBA/NIC passthrough |
| Talos provisioning | Ansible | `talos/` | Talos cluster lifecycle |

## Physical Hardware

| Device | Role | Notes |
|--------|------|-------|
| **TuringPi2** | Kubernetes cluster | RK1 compute modules running Talos Linux |
| **Protectli Vault** | Firewall/router | Dedicated appliance running OPNsense |
| **Raspberry Pi** | Certificate authority | Runs step-ca (private CA) |
| **TrueNAS** | Network storage | Managed via Terraform |

## Reverse Proxy & SSO (Current)

Caddy and Keycloak both run on the Protectli Vault alongside OPNsense.

| Component | Location | Role |
|-----------|----------|------|
| **Caddy** | Protectli Vault (OPNsense box) | Reverse proxy for internal services, automatic HTTPS via step-ca |
| **Keycloak** | Protectli Vault (OPNsense box) | SSO/identity provider, OIDC for all services |

### Current Flow
```
Client (LAN) → Caddy (Protectli Vault) → Keycloak (OIDC) → upstream service in cluster
```
- **Caddy** handles TLS termination using step-ca issued certs for internal services.
- **Keycloak** provides OIDC/SAML SSO. Runs on the same box as the firewall.
- **Auth flow**: Caddy validates OIDC tokens from Keycloak before proxying to upstream.

## Public Access via Pangolin (Planned)

In the future, a VPS running Pangolin will provide public access without port forwarding.

```
Internet → VPS (Pangolin) → WireGuard/Tunnel → Protectli Vault → Cluster
```

| Component | Location | Role |
|-----------|----------|------|
| **Pangolin** | VPS (cloud, future) | Tunnel endpoint, public entry point |

### Design Notes
- **No port forwarding** — Pangolin establishes an outbound tunnel from homelab to VPS.
- Caddy and Keycloak remain on the Protectli Vault. Pangolin tunnels traffic to them.
- Public TLS termination strategy TBD when Pangolin is implemented (Caddy on VPS vs Caddy on Protectli Vault).
- Pangolin config will go in a new `Terraform/vps/` or standalone directory.

## Terraform Conventions

### File Structure (per module)
```
Terraform/<component>/
├── main.tf           # Resources
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── providers.tf      # Provider config
├── versions.tf       # Terraform + provider version constraints
└── vars/
    └── prod/
        └── vars.auto.tfvars  # Environment-specific values (gitignored)
```

### Rules
1. **`.tfvars` are gitignored** — never commit them. They contain sensitive values (IPs, credentials).
2. **State files are gitignored** — `terraform.tfstate` and backups stay local (or move to remote backend).
3. **`.terraform.lock.hcl` is gitignored** — regenerated on `terraform init`.
4. **Variable-file pattern**: `terraform plan -var-file ./vars/prod/vars.auto.tfvars`.
5. **No `terraform apply` without `plan` first** — the Justfile enforces this pattern.
6. Use `terraform fmt` before committing.
7. Pin provider versions explicitly in `versions.tf`.

### Sensitive Values
- Terraform variables marked `sensitive = true` for passwords, API keys.
- Proxy credentials, API tokens go in `.tfvars` (gitignored).
- For remote backends, use encryption at rest.

## Ansible Conventions

### Structure
```
Ansible/<sequence>-<name>/
├── playbook.yaml       # Main playbook
├── inventory.yaml      # Target hosts
├── tasks/              # Task files (included by playbook)
│   ├── task_a.yaml
│   └── task_b.yaml
└── ansible.secret      # Vault-encrypted secrets (gitignored pattern)
```

### Rules
1. **Numbered prefixes** (`00-Init`, `01-Passthrough`) indicate execution order.
2. **`ansible.secret`** files are gitignored — contain vault passwords or sensitive vars.
3. **User**: `develeap` with sudo (`ansible_become: true`).
4. **Tasks are modular** — one file per logical operation (e.g., `set_static_ip.yaml`, `apt_update_upgrade.yaml`).
5. Use `ansible-vault` for any secrets that must live in the repo.
6. **Idempotency** — every task must be safe to run multiple times.
7. Test connectivity first: `ansible -m ping` (via Justfile recipe).

### Talos-specific Ansible
- Lives in `talos/` (separate from `Ansible/`) because it manages a different lifecycle.
- Uses its own `inventory/group_vars/all.yaml` for cluster-specific vars.
- Ansible collection dependency: `talos/collections/requirements.yaml`.
- Roles follow the Talos lifecycle: install → configure → apply → add-workers.

## Justfile (Task Runner)

Located at `.justfile` in repo root. Used for common operations.

### Current Recipes
- `ansible-ping` — Test Ansible connectivity
- `ansible-playbook` — Run init playbook
- `terraform-opnsense-apply` — Plan + apply OPNsense Terraform

### Rules for New Recipes
1. Use `[script("bash")]` for multi-line recipes.
2. Set working directory with `cd` inside the script block.
3. Destructive operations (apply, destroy) should include confirmation or `--auto-approve` explicitly.
4. Name pattern: `<tool>-<component>-<action>` (e.g., `terraform-truenas-plan`).
5. Add a comment above each recipe describing what it does.
6. The default recipe runs `just --choose` for interactive selection.

## Network Topology

- **Homelab subnet**: `192.168.1.0/24`
- **Talos nodes**: `.32` (worker), `.33` (worker), `.34` (controlplane)
- **Kube VIP**: `192.168.1.100` (Kubernetes API)
- **MetalLB range**: `192.168.1.80-90` (LoadBalancer services)
- **Protectli Vault (OPNsense)**: Gateway/firewall + Caddy (reverse proxy) + Keycloak (SSO)
- **TrueNAS**: Network storage, managed via Terraform
- **Raspberry Pi (step-ca)**: Private CA, separate device on same subnet
- **VPS (planned)**: Pangolin for public access tunnel

When adding new infrastructure, update this network map and avoid IP conflicts with existing allocations.
