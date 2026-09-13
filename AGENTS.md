# AGENTS.md — Guidelines for AI Agents

Rules every agent (opencode, Claude Code, or otherwise) must follow when working
in this repository. This file complements — does not replace — `CLAUDE.md` (deep
operational runbook) and the skills under `.opencode/skills/`.

## Read first

- `CLAUDE.md` — cluster details, bootstrap order, and hard-won pitfalls (Cilium,
  Istio Ambient, Kyverno, Longhorn, Talos upgrades). Treat its "Critical
  Pitfalls" as binding.
- `.opencode/skills/` — load the matching skill before acting:
  `homelab-conventions`, `talos-cluster`, `gitops`, `pki-certificates`,
  `cks-security`, `infrastructure`.
- `memory/` and `.claude/memory/` — prior context and decisions. Check before
  re-solving something.

## Repository layout (actual)

```
homelab/
├── network/   # OPNsense, VLANs, AdGuard, switch/firewall config + runbooks
├── infra/     # Talos cluster: docs/, k8s/, opnsense/, talos/, tinyca/
│   └── k8s/   # Per-component dirs (argocd, cilium, istio, longhorn, kyverno, …)
├── gitops/    # ArgoCD GitOps workflow docs
├── just/      # just recipes (talos.just, sso.just, observability.just)
├── memory/    # Agent memory (feedback, notes)
└── old/       # Legacy Terraform/Ansible/Proxmox — reference only
```

Base new work on this real structure, not the aspirational tree in the
`homelab-conventions` skill.

## Hard rules

1. **Secrets — never commit plaintext.** Anything matching `*secret*`,
   `*.tfvars`, or containing keys/tokens/passwords stays out of Git. Only
   `*.sops.yaml` / `*.sops.bin` (SOPS + age encrypted) may be committed. The age
   key `key.txt.secret` is gitignored — never print, move, or commit it.
   Decrypt with `SOPS_AGE_KEY_FILE=key.txt.secret sops --decrypt <file>`.
2. **Do not modify `old/`.** It is kept for reference during migration.
3. **Destructive cluster ops require confirmation.** `talosctl`, `kubectl
   delete`, node reboots/upgrades, and anything touching Longhorn volumes must be
   proposed and confirmed before running — never run speculatively.
4. **Talos upgrades:** verify the talosctl client cert is valid
   (`talosctl config info`) BEFORE any upgrade, and never re-run an upgrade
   against a node already at target. See the Talos section in `CLAUDE.md`.
5. **GitOps is the source of truth.** `main` is always deployable; ArgoCD syncs
   from it. Prefer changing manifests over imperative `kubectl apply`; call out
   any manual/imperative step explicitly.
6. **Respect Kyverno.** New workloads in system namespaces need the exemptions
   documented in `CLAUDE.md` pitfall #1, or they are silently blocked.

## Conventions

- YAML uses `.yaml` (never `.yml`), 2-space indent.
- Kubernetes: lowercase-kebab names matching the component directory; one
  namespace per app; required `app.kubernetes.io/{name,part-of,managed-by}`
  labels (`managed-by: argocd` for GitOps resources).
- Operational tasks belong in a `just/*.just` recipe, not ad-hoc scripts.
- Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`);
  feature branches `<type>/<short-desc>`; no force-push to `main`.

## Working style

- Prefer editing existing files over creating new ones; do not create docs unless
  asked.
- Verify state before acting (`kubectl get`, `talosctl ... version`) and report
  outcomes honestly — if a step was skipped or a check failed, say so.
- When a task matches a skill's trigger, load that skill first.
- After changing any opencode config, agents, or skills, remind the user to
  restart opencode for changes to take effect.
