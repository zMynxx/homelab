# ── OPNsense Network Management ───────────────────────────────────────────────

ANSIBLE_DIR   := HOMELAB_DIR + "/network/ansible"

# Install Ansible collections (run once or after updating requirements.yaml)
network-install:
	cd "{{ANSIBLE_DIR}}" && \
	  pip3 install --upgrade httpx && \
	  ansible-galaxy collection install -r requirements.yaml

# Apply all OPNsense config (VLANs → aliases → firewall rules)
network-apply:
	cd "{{ANSIBLE_DIR}}" && \
	  SOPS_AGE_KEY_FILE="{{AGE_KEY}}" ansible-playbook playbooks/site.yaml

# Apply firewall aliases only
network-aliases:
	cd "{{ANSIBLE_DIR}}" && \
	  SOPS_AGE_KEY_FILE="{{AGE_KEY}}" ansible-playbook playbooks/aliases.yaml

# Apply firewall rules only
network-rules:
	cd "{{ANSIBLE_DIR}}" && \
	  SOPS_AGE_KEY_FILE="{{AGE_KEY}}" ansible-playbook playbooks/firewall_rules.yaml

# Apply VLAN definitions only
network-vlans:
	cd "{{ANSIBLE_DIR}}" && \
	  SOPS_AGE_KEY_FILE="{{AGE_KEY}}" ansible-playbook playbooks/vlans.yaml

# Dry-run (check mode) — show what would change without applying
network-check:
	cd "{{ANSIBLE_DIR}}" && \
	  SOPS_AGE_KEY_FILE="{{AGE_KEY}}" ansible-playbook playbooks/site.yaml --check --diff
