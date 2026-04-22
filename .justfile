#!/usr/bin/env just --justfile

# default recipe to display help information
default:
	@echo "-=== Easy Managment Using Justfile ===-"
	@sleep 2
	@echo
	@echo "Initiating chooser...."
	@sleep 3
	@just --choose

# Test ansible's connection to the targets
[script("bash")]
ansible-ping:
	cd ./Ansible/00-Init/ 
	ansible -m ping

# Run the main Ansible playbook
[script("bash")]
ansible-playbook:
	cd ./Ansible/00-Init/
	ansible-playbook playbook.yaml

# Run terraform Apply to set up OPNsense
[script("bash")]
terraform-opnsense-apply:
	cd ./Terraform/opnsense/
	terraform init
	terraform plan -var-file ./vars/prod/vars.auto.tfvars
	terraform apply -auto-approve -var-file ./vars/prod/vars.auto.tfvars

# Encrypt a file in-place using SOPS + age (requires SOPS_AGE_KEY or ~/.config/sops/age/keys.txt)
# Usage: just sops-encrypt path/to/file.sops.yaml
[script("bash")]
sops-encrypt file:
	sops --encrypt --in-place "{{file}}"

# Decrypt a SOPS-encrypted file to stdout
# Usage: just sops-decrypt path/to/file.sops.yaml
[script("bash")]
sops-decrypt file:
	sops --decrypt "{{file}}"

# Open a SOPS-encrypted file in $EDITOR for in-place editing
# Usage: just sops-edit path/to/file.sops.yaml
[script("bash")]
sops-edit file:
	sops "{{file}}"
