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
