# Makefile for Oxide K3s Cluster Deployment
#
SHELL = /bin/bash

# Configuration
TERRAFORM_TOOL ?= tofu
TERRAFORM_DIR = infra/oxide
TERRAFORM_VARS = $(TERRAFORM_DIR)/terraform.tfvars
VAULT_FILE = group_vars/all/vault.yml
VAULT_PASSWORD_FILE = .vault-password

# Extract variables from terraform.tfvars if it exists
ifneq (,$(wildcard $(TERRAFORM_VARS)))
	project_name := $(shell grep '^project_name' $(TERRAFORM_VARS) 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/')
	vpc_name := $(shell grep '^vpc_name' $(TERRAFORM_VARS) 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/')
	instance_count := $(shell grep '^instance_count' $(TERRAFORM_VARS) 2>/dev/null | sed 's/.*= *\([0-9]*\).*/\1/')
	k3s_version := $(shell grep '^k3s_version' $(TERRAFORM_VARS) 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/')
	ansible_user := $(shell grep '^ansible_user' $(TERRAFORM_VARS) 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/')
	k3s_token := $(shell grep '^k3s_token' $(TERRAFORM_VARS) 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/')
endif

# Ansible vault parameters
VAULT_PARAMS = $(if $(wildcard $(VAULT_PASSWORD_FILE)),--vault-password-file $(VAULT_PASSWORD_FILE),$(if $(wildcard $(VAULT_FILE)),--ask-vault-pass,))

# Check for required Oxide environment variables
.PHONY: check-oxide-vars
check-oxide-vars:
	@if [ -z "$$OXIDE_HOST" ]; then \
		echo "[ERROR] OXIDE_HOST environment variable is not set"; \
		echo "   Set it with: export OXIDE_HOST=your-oxide-host"; \
		exit 1; \
	fi
	@if [ -z "$$OXIDE_TOKEN" ]; then \
		echo "[ERROR] OXIDE_TOKEN environment variable is not set"; \
		echo "   Set it with: export OXIDE_TOKEN=your-oxide-token"; \
		exit 1; \
	fi
	@echo "[OK] Oxide environment variables are set"

# Comprehensive configuration validation
.PHONY: check-config
check-config: check-oxide-vars
	@echo "[CHECK] Validating project configuration..."
	@echo ""
	
	# Check required files exist
	@echo "[FILES] Checking required files:"
	@if [ ! -f "$(TERRAFORM_VARS)" ]; then \
		echo "[ERROR] $(TERRAFORM_VARS) not found"; \
		echo "   Run: make setup"; \
		exit 1; \
	else \
		echo "[OK] $(TERRAFORM_VARS)"; \
	fi
	
	@if [ ! -f "inventory.yml" ]; then \
		echo "[ERROR] inventory.yml not found"; \
		echo "   Run: make infra-up (after setup)"; \
		exit 1; \
	else \
		echo "[OK] inventory.yml"; \
	fi
	
	# Check role configuration files
	@echo ""
	@echo "[CONFIG]  Checking role configurations:"
	@for role in cert_manager external_dns argocd; do \
		if [ ! -f "roles/$$role/vars/main.yml" ]; then \
			echo "[WARNING] roles/$$role/vars/main.yml not found"; \
			echo "   Run: make setup (if you haven't configured this role yet)"; \
		else \
			echo "[OK] roles/$$role/vars/main.yml"; \
		fi; \
	done
	
	# Check critical variables are set
	@echo ""
	@echo "[VARS] Checking critical variables:"
	@if [ -z "$(project_name)" ]; then \
		echo "[ERROR] project_name not set in $(TERRAFORM_VARS)"; \
		exit 1; \
	else \
		echo "[OK] project_name: $(project_name)"; \
	fi
	
	@if [ -z "$(k3s_version)" ]; then \
		echo "[ERROR] k3s_version not set in $(TERRAFORM_VARS)"; \
		exit 1; \
	else \
		echo "[OK] k3s_version: $(k3s_version)"; \
	fi
	
	@if [ -z "$(ansible_user)" ]; then \
		echo "[ERROR] ansible_user not set in $(TERRAFORM_VARS)"; \
		exit 1; \
	else \
		echo "[OK] ansible_user: $(ansible_user)"; \
	fi
	
	# Check vault configuration
	@echo ""
	@echo "[VAULT] Checking vault configuration:"
	@if [ -f "$(VAULT_FILE)" ]; then \
		echo "[OK] Ansible Vault file exists"; \
		if [ -f "$(VAULT_PASSWORD_FILE)" ]; then \
			echo "[OK] Vault password file exists"; \
		else \
			echo "[WARNING] No vault password file (will prompt for password)"; \
		fi; \
	else \
		echo "[WARNING] No Ansible Vault file found"; \
		echo "   This is optional for self-signed certificates"; \
		echo "   Run: make setup-vault (if you need DNS provider secrets)"; \
	fi
	
	@echo ""
	@echo "[OK] Configuration validation passed!"

# Soft configuration check (warns but doesn't fail on missing vars)
.PHONY: check-config-soft
check-config-soft: check-oxide-vars
	@echo "[CHECK] Checking project configuration (soft)..."
	@echo ""
	
	# Check required files exist
	@echo "[FILES] Checking required files:"
	@if [ ! -f "$(TERRAFORM_VARS)" ]; then \
		echo "[ERROR] $(TERRAFORM_VARS) not found - Run: make setup"; \
	else \
		echo "[OK] $(TERRAFORM_VARS)"; \
	fi
	
	@if [ ! -f "inventory.yml" ]; then \
		echo "[ERROR] inventory.yml not found - Run: make infra-up"; \
	else \
		echo "[OK] inventory.yml"; \
	fi
	
	# Check role configuration files (warn only)
	@echo ""
	@echo "[CONFIG]  Checking role configurations:"
	@for role in cert_manager external_dns argocd; do \
		if [ ! -f "roles/$$role/vars/main.yml" ]; then \
			echo "[WARNING] roles/$$role/vars/main.yml not found (using defaults)"; \
		else \
			echo "[OK] roles/$$role/vars/main.yml"; \
		fi; \
	done
	
	@echo ""
	@echo "[OK] Soft configuration check complete"

VENV := .venv
PYTHON := $(VENV)/bin/python
ANSIBLE := $(VENV)/bin/ansible-playbook

.PHONY: help
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Setup & Configuration:"
	@echo "  setup           - Run interactive setup script to configure project"
	@echo "  setup-vault     - Set up Ansible Vault for secrets management (required for DNS providers)"
	@echo "  show-vars       - Display all current variables and configuration status"
	@echo "  check-oxide-vars - Verify OXIDE_HOST and OXIDE_TOKEN are set"
	@echo "  check-config    - Validate all required configuration before deployment"
	@echo "  check-config-soft - Check configuration (warns but allows defaults)"
	@echo ""
	@echo "Environment:"
	@echo "  venv            - Create Python virtual environment with requirements"
	@echo "  validate        - Validate Terraform configuration"
	@echo ""
	@echo "Infrastructure:"
	@echo "  infra-up        - Deploy infrastructure with Terraform and wait for hosts"
	@echo "  infra-plan      - Show Terraform execution plan"
	@echo "  destroy         - Destroy infrastructure with Terraform"
	@echo ""
	@echo "Cluster Deployment:"
	@echo "  deploy          - Deploy K3s cluster (main deployment)"
	@echo "  fix-kubeconfig  - Fix kubeconfig to use external IP"
	@echo ""
	@echo "Services & Applications:"
	@echo "  nginx-lb        - Configure NGINX load balancer"
	@echo "  cert-manager    - Deploy cert-manager for TLS certificates"
	@echo "  external-dns    - Deploy external-dns for DNS automation"
	@echo "  longhorn        - Deploy Longhorn distributed storage"
	@echo "  argocd          - Deploy ArgoCD with demo applications"
	@echo ""
	@echo "Utility:"
	@echo "  check           - Check cluster and pod status"
	@echo "  lint            - Run linting on Terraform and Ansible files"
	@echo "  clean           - Clean temporary files and reset state"
	@echo "  clean-config    - Remove all configuration files (WARNING: destructive)"
	@echo ""
	@echo "Complete Workflows:"
	@echo "  full-setup      - Complete setup from configuration to running cluster"
	@echo "  full-deploy     - Deploy infrastructure and all services"

# Setup & Configuration
.PHONY: setup
setup:
	@echo "Running interactive setup to configure project..."
	@echo -e "\033[1;32m==>\033[0m ./setup.sh"
	./setup.sh

.PHONY: setup-vault
setup-vault:
	@if [ ! -f group_vars/all/vault.yml.example ]; then \
		echo "[WARNING] vault.yml.example not found."; \
		echo "   This is normal for self-signed certificate setups."; \
		echo "   Run 'make setup' first if you need DNS provider secrets."; \
	elif [ ! -f $(VAULT_FILE) ]; then \
		echo "Setting up Ansible Vault..."; \
		cp group_vars/all/vault.yml.example $(VAULT_FILE); \
		ansible-vault encrypt $(VAULT_FILE); \
		echo "[OK] Vault file created and encrypted at $(VAULT_FILE)"; \
	else \
		echo "[OK] Vault file already exists at $(VAULT_FILE)"; \
	fi

.PHONY: setup-vault-optional
setup-vault-optional:
	@if [ -f group_vars/all/vault.yml.example ]; then \
		$(MAKE) setup-vault; \
	else \
		echo "[INFO] No vault setup needed (self-signed certificates)"; \
	fi

.PHONY: venv
venv:
	@test -d $(VENV) || python3 -m venv $(VENV)
	$(VENV)/bin/pip install -U pip
	$(VENV)/bin/pip install -r requirements.txt
	$(VENV)/bin/ansible-galaxy collection install -r collections/requirements.yml || true

.PHONY: validate
validate: check-oxide-vars
	@echo "Validating Terraform configuration in $(TERRAFORM_DIR)..."
	@echo -e "\033[1;32m==>\033[0m cd $(TERRAFORM_DIR) && $(TERRAFORM_TOOL) validate"
	cd $(TERRAFORM_DIR) && $(TERRAFORM_TOOL) validate

.PHONY: infra-plan
infra-plan: check-oxide-vars
	@echo "Planning Terraform deployment..."
	@echo -e "\033[1;32m==>\033[0m cd $(TERRAFORM_DIR) && $(TERRAFORM_TOOL) plan"
	cd $(TERRAFORM_DIR) && $(TERRAFORM_TOOL) plan

.PHONY: show-vars
show-vars:
	@echo "=== Environment Variables ==="
	@echo "  OXIDE_HOST: $${OXIDE_HOST:-[ERROR] NOT SET}"
	@echo "  OXIDE_TOKEN: $$([ -n "$$OXIDE_TOKEN" ] && echo "[OK] SET (hidden)" || echo "[ERROR] NOT SET")"
	@echo "  TERRAFORM_TOOL: $(TERRAFORM_TOOL)"
	@echo ""
	@echo "=== Configuration Files ==="
	@echo "  Terraform vars: $(TERRAFORM_VARS) $$([ -f "$(TERRAFORM_VARS)" ] && echo "[OK]" || echo "[ERROR]")"
	@echo "  Vault file: $(VAULT_FILE) $$([ -f "$(VAULT_FILE)" ] && echo "[OK]" || echo "[ERROR]")"
	@echo "  Vault password: $(VAULT_PASSWORD_FILE) $$([ -f "$(VAULT_PASSWORD_FILE)" ] && echo "[OK]" || echo "[ERROR]")"
	@echo "  Inventory: inventory.yml $$([ -f "inventory.yml" ] && echo "[OK]" || echo "[ERROR]")"
	@echo ""
	@if [ -f "$(TERRAFORM_VARS)" ]; then \
		echo "=== Project Variables (from terraform.tfvars) ==="; \
		echo "  project_name: $(project_name)"; \
		echo "  vpc_name: $(vpc_name)"; \
		echo "  instance_count: $(instance_count)"; \
		echo "  k3s_version: $(k3s_version)"; \
		echo "  ansible_user: $(ansible_user)"; \
		echo "  k3s_token: $(if $(k3s_token),[OK] SET (hidden),[ERROR] NOT SET)"; \
	else \
		echo "=== Project Variables ==="; \
		echo "  [ERROR] $(TERRAFORM_VARS) not found. Run 'make setup' first."; \
	fi
	@echo ""
	@echo "=== Vault Parameters ==="
	@echo "  Current vault params: $(VAULT_PARAMS)"

.PHONY: infra-up
infra-up: check-oxide-vars venv
	@if [ ! -f $(TERRAFORM_VARS) ]; then \
		echo "[ERROR] $(TERRAFORM_VARS) not found. Run 'make setup' first."; \
		exit 1; \
	fi
	@echo "Initializing and applying Terraform configuration..."
	@echo -e "\033[1;32m==>\033[0m cd $(TERRAFORM_DIR) && $(TERRAFORM_TOOL) init && $(TERRAFORM_TOOL) apply -auto-approve"
	cd $(TERRAFORM_DIR) && $(TERRAFORM_TOOL) init && $(TERRAFORM_TOOL) apply -auto-approve
	@echo "Waiting for all hosts to respond to ansible-ping..."
	@until $(VENV)/bin/ansible all -m ping -i inventory.yml; do \
		echo "Hosts not reachable yet, waiting 10 seconds..."; \
		sleep 10; \
	done
	@echo "[OK] All hosts are reachable."

.PHONY: deploy
deploy: venv
	@echo "Deploying K3s cluster with Ansible..."
	@echo -e "\033[1;32m==>\033[0m $(ANSIBLE) playbooks/site.yml -i inventory.yml $(VAULT_PARAMS)"
	$(ANSIBLE) playbooks/site.yml -i inventory.yml $(VAULT_PARAMS)

.PHONY: nginx-lb
nginx-lb: venv
	@echo "Configuring NGINX load balancer..."
	@echo -e "\033[1;32m==>\033[0m $(ANSIBLE) playbooks/nginx-lb.yaml -i inventory.yml $(VAULT_PARAMS)"
	$(ANSIBLE) playbooks/nginx-lb.yaml -i inventory.yml $(VAULT_PARAMS)

.PHONY: cert-manager
cert-manager: check-config-soft venv
	@echo "Deploying cert-manager for TLS certificates..."
	@echo -e "\033[1;32m==>\033[0m $(ANSIBLE) playbooks/cert-manager.yaml -i inventory.yml $(VAULT_PARAMS)"
	$(ANSIBLE) playbooks/cert-manager.yaml -i inventory.yml $(VAULT_PARAMS)

.PHONY: external-dns
external-dns: check-config-soft venv
	@echo "Deploying external-dns for DNS automation..."
	@echo -e "\033[1;32m==>\033[0m $(ANSIBLE) playbooks/external-dns.yaml -i inventory.yml $(VAULT_PARAMS)"
	$(ANSIBLE) playbooks/external-dns.yaml -i inventory.yml $(VAULT_PARAMS)

.PHONY: longhorn
longhorn: check-config-soft venv
	@echo "Deploying Longhorn distributed storage..."
	@echo -e "\033[1;32m==>\033[0m $(ANSIBLE) playbooks/longhorn.yml -i inventory.yml $(VAULT_PARAMS)"
	$(ANSIBLE) playbooks/longhorn.yml -i inventory.yml $(VAULT_PARAMS)

.PHONY: argocd
argocd: check-config-soft venv
	@echo "Deploying ArgoCD with demo applications..."
	@echo -e "\033[1;32m==>\033[0m $(ANSIBLE) playbooks/argocd.yml -i inventory.yml $(VAULT_PARAMS)"
	$(ANSIBLE) playbooks/argocd.yml -i inventory.yml $(VAULT_PARAMS)

.PHONY: fix-kubeconfig
fix-kubeconfig: venv
	@echo "Fixing kubeconfig to use external IP..."
	@echo -e "\033[1;32m==>\033[0m $(ANSIBLE) infra/oxide/fix-kubeconfig.yml -i inventory.yml"
	$(ANSIBLE) infra/oxide/fix-kubeconfig.yml -i inventory.yml

.PHONY: check
check:
	@echo "Checking cluster nodes..."
	@echo -e "\033[1;32m==>\033[0m kubectl get nodes"
	kubectl get nodes
	@echo "Checking pods in all namespaces..."
	@echo -e "\033[1;32m==>\033[0m kubectl get pods --all-namespaces"
	kubectl get pods --all-namespaces
	@echo "Checking ArgoCD applications..."
	@echo -e "\033[1;32m==>\033[0m kubectl -n argocd get applications"
	kubectl -n argocd get applications || echo "ArgoCD not deployed yet"

.PHONY: destroy
destroy: check-oxide-vars
	@echo "[WARNING]  Destroying infrastructure with Terraform..."
	@echo "This will DELETE all infrastructure. Press Ctrl+C within 10 seconds to cancel."
	@sleep 10
	@echo -e "\033[1;32m==>\033[0m cd $(TERRAFORM_DIR) && $(TERRAFORM_TOOL) destroy -auto-approve"
	cd $(TERRAFORM_DIR) && $(TERRAFORM_TOOL) destroy -auto-approve

.PHONY: clean
clean:
	@echo "Cleaning temporary files..."
	@rm -rf .terraform/
	@rm -rf infra/oxide/.terraform/
	@rm -f terraform.tfstate*
	@rm -f infra/oxide/terraform.tfstate*
	@rm -f *.retry
	@echo "[OK] Temporary files cleaned"
	@echo ""
	@if [ -f "$(TERRAFORM_VARS)" ] || [ -f "inventory.yml" ] || [ -f "roles/cert_manager/vars/main.yml" ] || [ -f "roles/external_dns/vars/main.yml" ] || [ -f "roles/argocd/vars/main.yml" ] || [ -f "$(VAULT_FILE)" ]; then \
		echo "Configuration files found:"; \
		[ -f "$(TERRAFORM_VARS)" ] && echo "  * $(TERRAFORM_VARS)"; \
		[ -f "inventory.yml" ] && echo "  * inventory.yml"; \
		[ -f "roles/cert_manager/vars/main.yml" ] && echo "  * roles/cert_manager/vars/main.yml"; \
		[ -f "roles/external_dns/vars/main.yml" ] && echo "  * roles/external_dns/vars/main.yml"; \
		[ -f "roles/argocd/vars/main.yml" ] && echo "  * roles/argocd/vars/main.yml"; \
		[ -f "$(VAULT_FILE)" ] && echo "  * $(VAULT_FILE)"; \
		echo ""; \
		echo "To also remove configuration files, run: make clean-config"; \
	fi

.PHONY: clean-config
clean-config:
	@echo "[WARNING] This will remove ALL configuration files!"
	@echo "The following files will be deleted:"
	@[ -f "$(TERRAFORM_VARS)" ] && echo "  * $(TERRAFORM_VARS)"
	@[ -f "inventory.yml" ] && echo "  * inventory.yml"
	@[ -f "roles/cert_manager/vars/main.yml" ] && echo "  * roles/cert_manager/vars/main.yml"
	@[ -f "roles/external_dns/vars/main.yml" ] && echo "  * roles/external_dns/vars/main.yml"
	@[ -f "roles/argocd/vars/main.yml" ] && echo "  * roles/argocd/vars/main.yml"
	@[ -f "$(VAULT_FILE)" ] && echo "  * $(VAULT_FILE)"
	@[ -f "group_vars/all/vault.yml.example" ] && echo "  * group_vars/all/vault.yml.example"
	@echo ""
	@echo "Press Ctrl+C within 10 seconds to cancel, or wait to continue..."
	@sleep 10
	@rm -f "$(TERRAFORM_VARS)"
	@rm -f inventory.yml
	@rm -f roles/cert_manager/vars/main.yml
	@rm -f roles/external_dns/vars/main.yml
	@rm -f roles/argocd/vars/main.yml
	@rm -f "$(VAULT_FILE)"
	@rm -f group_vars/all/vault.yml.example
	@echo "[OK] Configuration files removed"
	@echo "Run 'make setup' to reconfigure the project"

.PHONY: lint
lint: venv
	@echo "Formatting Terraform files..."
	@echo -e "\033[1;32m==>\033[0m cd $(TERRAFORM_DIR) && $(TERRAFORM_TOOL) fmt -recursive"
	cd $(TERRAFORM_DIR) && $(TERRAFORM_TOOL) fmt -recursive
	@echo "Checking Terraform file formatting..."
	@echo -e "\033[1;32m==>\033[0m $(TERRAFORM_TOOL) fmt -check -recursive $(TERRAFORM_DIR)"
	$(TERRAFORM_TOOL) fmt -check -recursive $(TERRAFORM_DIR)
	@echo "Linting Ansible playbooks..."
	$(VENV)/bin/ansible-lint playbooks/

# Complete Workflows
.PHONY: full-setup
full-setup: setup setup-vault-optional venv validate infra-up deploy fix-kubeconfig nginx-lb cert-manager external-dns longhorn argocd check
	@echo ""
	@echo "[SUCCESS] Complete setup finished!"
	@echo "Your K3s cluster is ready with:"
	@echo "  [OK] Infrastructure deployed"
	@echo "  [OK] K3s cluster running"
	@echo "  [OK] NGINX load balancer configured"
	@echo "  [OK] cert-manager for TLS certificates"
	@echo "  [OK] external-dns for DNS automation"
	@echo "  [OK] Longhorn distributed storage"
	@echo "  [OK] ArgoCD with demo applications"

.PHONY: full-deploy
full-deploy: venv validate infra-up deploy fix-kubeconfig nginx-lb cert-manager external-dns longhorn argocd check
	@echo ""
	@echo "[SUCCESS] Full deployment complete!"
	@echo "Run 'make check' to verify cluster status anytime."

# Legacy aliases for backwards compatibility 
.PHONY: cert-mgr
cert-mgr: cert-manager
