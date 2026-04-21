#!/usr/bin/env just --justfile

# Set shell for non-Windows OSs:
set shell := ["/bin/bash", "-c"]

# default recipe to display help information
default:
	@echo "-=== Easy Managment Using Justfile ===-"
	@sleep 2
	@echo
	@echo "Initiating chooser...."
	@sleep 3
	@just --choose

# Run all terraform operations 
# execution sequence:  init -> plan -> apply -> credentails
terraform-all: terraform-init && terraform-plan terraform-apply

# Initialize the module
terraform-init:
	terraform init

# Run terraform plan 
terraform-plan:
	terraform plan -var-file ../vars/prod/00-provider-vars.auto.tfvars

# Run terraform apply
terraform-apply:
	terraform apply -var-file ../vars/prod/00-provider-vars.auto.tfvars

# Run terraform destroy 
terraform-destroy:
	terraform destroy -var-file ../vars/prod/00-provider-vars.auto.tfvars
