# ── Talos Cluster Management — TuringPi 2 ─────────────────────────────────

TALOS_DIR      := justfile_directory() + "/infra/talos"

HOMELAB_DIR    := justfile_directory()
SOPS_FILE      := HOMELAB_DIR + "/infra/tinyca/pki/pki-export/pki-export.sops.yaml"
AGE_KEY        := HOMELAB_DIR + "/key.txt.secret"
TALOSCONFIG    := TALOS_DIR + "/clusterconfig/talosconfig"
CP_NODES       := "192.168.30.103,192.168.30.104,192.168.30.105"
BOOTSTRAP_NODE := "192.168.30.103"
VIP            := "192.168.30.99"

# Generate Talos machine configs (decrypts TinyCA root CA + cluster secrets from SOPS, then runs talhelper)
talos-generate:
	#!/usr/bin/env bash
	set -euo pipefail
	TALSECRET_PLAIN="/tmp/talsecret-$$.yaml"
	trap 'rm -f "$TALSECRET_PLAIN"' EXIT

	echo "Decrypting cluster secrets from SOPS..."
	SOPS_AGE_KEY_FILE="{{AGE_KEY}}" sops --decrypt \
	  "{{TALOS_DIR}}/talsecret.sops.yaml" > "$TALSECRET_PLAIN"

	echo "Extracting TinyCA root CA from SOPS..."
	ROOT_CA=$(SOPS_AGE_KEY_FILE="{{AGE_KEY}}" sops --decrypt \
	  --extract '["root_ca_crt"]' "{{SOPS_FILE}}")

	echo "Writing patches/custom-ca.yaml..."
	cat > "{{TALOS_DIR}}/patches/custom-ca.yaml" <<-EOF
	machine:
	  files:
	    - content: |
	$(echo "$ROOT_CA" | sed 's/^/        /')
	      path: /etc/ssl/certs/homelab-root-ca.crt
	      permissions: 0644
	      op: create
	EOF

	echo "Running talhelper genconfig..."
	cd "{{TALOS_DIR}}" && talhelper genconfig \
	  --secret-file "$TALSECRET_PLAIN" \
	  --out-dir clusterconfig

	echo "Done. Configs written to infra/talos/clusterconfig/"

# Apply machine configs to all nodes (nodes must be in Talos maintenance mode)
# Current static IPs are .103/.104/.105 on VLAN 30 (nodes flashed, in maintenance mode)
talos-apply:
	#!/usr/bin/env bash
	set -euo pipefail
	for hostname in turingpi-1 turingpi-3 turingpi-4; do
	  case "$hostname" in
	    turingpi-1) ip="192.168.30.103" ;;
	    turingpi-3) ip="192.168.30.104" ;;
	    turingpi-4) ip="192.168.30.105" ;;
	  esac
	  cfg="{{TALOS_DIR}}/clusterconfig/turingpi-${hostname}.yaml"
	  echo "Applying config to $hostname ($ip)..."
	  talosctl apply-config --insecure --nodes "$ip" --file "$cfg"
	done
	echo "Configs applied. Nodes are rebooting — wait ~2 min before bootstrapping."

# Bootstrap etcd on the first control plane node (run once per cluster lifetime)
talos-bootstrap:
	#!/usr/bin/env bash
	set -euo pipefail
	echo "Waiting for {{BOOTSTRAP_NODE}} API to be up (maintenance mode ended)..."
	talosctl --talosconfig "{{TALOSCONFIG}}" \
	  -n {{BOOTSTRAP_NODE}} \
	  bootstrap
	echo "Bootstrap initiated. etcd quorum is forming across all 3 nodes."

# Fetch kubeconfig and merge into ~/.kube/config
talos-kubeconfig:
	talosctl --talosconfig "{{TALOSCONFIG}}" \
	  -n {{VIP}} \
	  kubeconfig --merge
	@echo "kubeconfig merged. Context: $(kubectl config current-context)"

# Install/upgrade Cilium CNI (run immediately after talos-kubeconfig — nodes won't Ready without it)
# kube-proxy is disabled in Talos; Cilium replaces it via eBPF (kubeProxyReplacement=true).
# Istio Ambient runs alongside via istio-cni (cni.exclusive=false, socketLB.hostNamespaceOnly=true).
talos-cilium:
	#!/usr/bin/env bash
	set -euo pipefail
	helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
	helm repo update cilium
	helm upgrade --install cilium cilium/cilium \
	  --namespace kube-system \
	  --wait --timeout 5m \
	  -f infra/k8s/cilium/values.yaml
	echo "Cilium installed."
	kubectl get nodes -o wide

# Check cluster health (Talos + Kubernetes + etcd)
talos-health:
	#!/usr/bin/env bash
	set -euo pipefail
	echo "=== Talos node health ==="
	talosctl --talosconfig "{{TALOSCONFIG}}" \
	  -n {{CP_NODES}} health --server=false
	echo ""
	echo "=== Kubernetes nodes ==="
	kubectl get nodes -o wide
	echo ""
	echo "=== etcd members ==="
	talosctl --talosconfig "{{TALOSCONFIG}}" \
	  -n {{BOOTSTRAP_NODE}} etcd members

# Rolling Talos upgrade (usage: just talos-upgrade v1.9.5)
talos-upgrade version:
	#!/usr/bin/env bash
	set -euo pipefail
	SCHEMATIC_ID=$(grep talosImageURL "{{TALOS_DIR}}/talconfig.yaml" | \
	  head -1 | sed 's|.*factory.talos.dev/installer/||' | tr -d '"')
	IMAGE="factory.talos.dev/installer/${SCHEMATIC_ID}:{{version}}"
	echo "Upgrading all nodes to {{version}} (image: $IMAGE)"
	for NODE in 192.168.30.103 192.168.30.104 192.168.30.105; do
	  echo "Upgrading $NODE..."
	  talosctl --talosconfig "{{TALOSCONFIG}}" \
	    -n "$NODE" upgrade --image "$IMAGE" --wait
	  echo "$NODE done."
	done

# Hard reset all nodes — DESTRUCTIVE, requires 'yes' confirmation
talos-reset:
	#!/usr/bin/env bash
	set -euo pipefail
	echo "WARNING: This wipes all 3 nodes. All cluster data will be lost."
	echo -n "Type 'yes' to confirm: "
	read -r CONFIRM
	[[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 1; }
	for NODE in 192.168.30.103 192.168.30.104 192.168.30.105; do
	  echo "Resetting $NODE..."
	  talosctl --talosconfig "{{TALOSCONFIG}}" \
	    -n "$NODE" reset --graceful=false --wait=false 2>/dev/null || true
	done
	echo "Reset sent to all nodes. They will reboot into maintenance mode."
	echo "Run before re-bootstrapping:"
	echo "  rm -rf infra/talos/clusterconfig infra/talos/talosconfig"

# ── Post-bootstrap platform components ─────────────────────────────────────

# Spegel — node-local P2P image mirror (containerd hits localhost:5001 first)
talos-spegel:
	#!/usr/bin/env bash
	set -euo pipefail
	# Spegel is an OCI-only chart (no classic repo).
	helm upgrade --install spegel oci://ghcr.io/spegel-org/helm-charts/spegel \
	  --version 0.7.4 \
	  --namespace spegel --create-namespace \
	  --wait --timeout 5m \
	  -f infra/k8s/spegel/values.yaml
	echo "Spegel installed. Verify: kubectl -n spegel get ds"

# Zot — in-cluster pull-through registry cache (+ TLS cert from step-ca)
talos-zot:
	#!/usr/bin/env bash
	set -euo pipefail
	# cert-manager must be installed (it is) so the Certificate below provisions.
	kubectl apply -f infra/k8s/zot/certificate.yaml
	kubectl apply -f infra/k8s/zot/configmap.yaml
	kubectl apply -f infra/k8s/zot/deployment.yaml
	kubectl apply -f infra/k8s/zot/service.yaml
	echo "Zot applied. Verify: kubectl -n registry get pods,certificate,svc"

# Kyverno — admission policy engine (CKS security layer)
talos-kyverno:
	#!/usr/bin/env bash
	set -euo pipefail
	helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
	helm repo update kyverno
	helm upgrade --install kyverno kyverno/kyverno \
	  --namespace kyverno --create-namespace \
	  --wait --timeout 5m \
	  -f infra/k8s/kyverno/values.yaml
	kubectl apply -f infra/k8s/kyverno/policies/baseline.yaml
	echo "Kyverno installed. Verify: kubectl -n kyverno get pods"


