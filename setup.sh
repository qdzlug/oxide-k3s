#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration files
TERRAFORM_VARS="infra/oxide/terraform.tfvars"
EXTERNAL_DNS_VARS="roles/external_dns/vars/main.yml"
CERT_MANAGER_VARS="roles/cert_manager/vars/main.yml"
ARGOCD_VARS="roles/argocd/vars/main.yml"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Tool validation functions
check_tool() {
    local tool=$1
    local package=${2:-$tool}
    
    if command -v "$tool" >/dev/null 2>&1; then
        log_success "$tool is installed"
        return 0
    else
        log_error "$tool is not installed. Please install $package"
        return 1
    fi
}

check_optional_tool() {
    local tool=$1
    local package=${2:-$tool}
    local description=$3
    
    if command -v "$tool" >/dev/null 2>&1; then
        log_success "$tool is installed"
        return 0
    else
        log_warning "$tool is not installed. $description"
        return 1
    fi
}

detect_terraform_tool() {
    if command -v "tofu" >/dev/null 2>&1; then
        TERRAFORM_TOOL="tofu"
        log_success "Using OpenTofu (tofu) for infrastructure management"
    elif command -v "terraform" >/dev/null 2>&1; then
        TERRAFORM_TOOL="terraform"
        log_success "Using Terraform for infrastructure management"
    else
        log_error "Neither terraform nor tofu found. Please install one of:"
        log_error "  - Terraform: https://www.terraform.io/downloads"
        log_error "  - OpenTofu: https://opentofu.org/docs/intro/install/"
        return 1
    fi
    return 0
}

validate_tools() {
    log_info "Validating required tools..."
    
    # Detect terraform/tofu first
    if ! detect_terraform_tool; then
        log_error "Infrastructure management tool is required"
        exit 1
    fi
    
    local required_tools=(
        "ansible:ansible"
        "git:git"
        "python3:python3"
        "kubectl:kubectl"
        "helm:helm"
    )
    
    local missing_tools=()
    
    for tool_entry in "${required_tools[@]}"; do
        IFS=':' read -r tool package <<< "$tool_entry"
        if ! check_tool "$tool" "$package"; then
            missing_tools+=("$package")
        fi
    done
    
    # Check for python3-venv
    if ! python3 -c "import venv" 2>/dev/null; then
        log_error "python3-venv is not available. Please install python3-venv"
        missing_tools+=("python3-venv")
    else
        log_success "python3-venv is available"
    fi
    
    # Check for ansible kubernetes collection
    if ! ansible-galaxy collection list | grep -q "kubernetes.core"; then
        log_warning "kubernetes.core collection not found. Run: ansible-galaxy collection install kubernetes.core"
    else
        log_success "kubernetes.core collection is installed"
    fi
    
    # Check for Python kubernetes library
    if ! python3 -c "import kubernetes" 2>/dev/null; then
        log_error "Python kubernetes library not found. Please install python3-kubernetes"
        missing_tools+=("python3-kubernetes")
    else
        log_success "Python kubernetes library is installed"
    fi
    
    # Check optional tools
    log_info "Checking optional tools..."
    check_optional_tool "k9s" "k9s" "k9s provides a nice terminal UI for Kubernetes. Install from: https://k9scli.io/"
    
    # Exit if required tools are missing
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install missing tools and run this script again"
        exit 1
    fi
    
    log_success "All required tools are available"
}

validate_oxide_env() {
    log_info "Validating Oxide environment variables..."
    
    if [ -z "$OXIDE_HOST" ]; then
        log_error "OXIDE_HOST environment variable is not set"
        log_info "Set it with: export OXIDE_HOST=your-oxide-host"
        return 1
    else
        log_success "OXIDE_HOST is set: $OXIDE_HOST"
    fi
    
    if [ -z "$OXIDE_TOKEN" ]; then
        log_error "OXIDE_TOKEN environment variable is not set"
        log_info "Set it with: export OXIDE_TOKEN=your-oxide-token"
        return 1
    else
        log_success "OXIDE_TOKEN is set (hidden for security)"
    fi
    
    return 0
}

# Input validation functions
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

validate_email() {
    local email=$1
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

validate_positive_number() {
    local num=$1
    if [[ $num =~ ^[0-9]+$ ]] && [ "$num" -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

# Input collection functions
get_input() {
    local prompt=$1
    local default_value=${2:-""}
    local validator_func=${3:-""}
    local is_secret=${4:-false}
    local allow_empty=${5:-false}
    local value
    
    while true; do
        if [ "$is_secret" = true ]; then
            read -s -p "$prompt: " value
            echo
        else
            if [ -n "$default_value" ]; then
                read -p "$prompt [$default_value]: " value
                value=${value:-$default_value}
            else
                read -p "$prompt: " value
            fi
        fi
        
        # Check if empty value is allowed
        if [ -z "$value" ] && [ -z "$default_value" ] && [ "$allow_empty" != true ]; then
            log_error "Value cannot be empty"
            continue
        fi
        
        # Skip validation if value is empty and empty is allowed
        if [ -n "$validator_func" ] && [ -n "$value" ] && ! "$validator_func" "$value"; then
            log_error "Invalid input format"
            continue
        fi
        
        echo "$value"
        break
    done
}

get_choice() {
    local prompt=$1
    shift
    local choices=("$@")
    local choice
    
    echo "$prompt" >&2
    for i in "${!choices[@]}"; do
        echo "$((i+1)). ${choices[i]}" >&2
    done
    echo >&2  # Add blank line for better readability
    
    while true; do
        read -p "Choose (1-${#choices[@]}): " choice
        if [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#choices[@]} ]; then
            echo "${choices[$((choice-1))]}"
            break
        else
            log_error "Invalid choice"
        fi
    done
}

# Memory/storage conversion functions
gb_to_bytes() {
    echo $(($1 * 1024 * 1024 * 1024))
}

bytes_to_gb() {
    echo $(($1 / 1024 / 1024 / 1024))
}

# Configuration collection functions
collect_infrastructure_config() {
    log_info "=== Infrastructure Configuration ==="
    
    # Project basics
    PROJECT_NAME=$(get_input "Project name" "oxide-k3s")
    VPC_NAME=$(get_input "VPC name" "$PROJECT_NAME")
    VPC_DNS_NAME=$(get_input "VPC DNS name" "$PROJECT_NAME")
    VPC_DESCRIPTION=$(get_input "VPC description" "VPC for $PROJECT_NAME cluster")
    
    # Node configuration
    TOTAL_NODES=$(get_input "Total number of nodes" "6" "validate_positive_number")
    SERVER_NODES=$(get_input "Number of control plane (server) nodes" "3" "validate_positive_number")
    AGENT_NODES=$((TOTAL_NODES - SERVER_NODES))
    
    if [ $AGENT_NODES -lt 0 ]; then
        log_error "Server nodes cannot exceed total nodes"
        exit 1
    fi
    
    log_info "This will create $SERVER_NODES control plane nodes and $AGENT_NODES worker nodes"
    
    # Node sizing
    NODE_MEMORY_GB=$(get_input "Memory per node (GB)" "4" "validate_positive_number")
    NODE_MEMORY=$(gb_to_bytes $NODE_MEMORY_GB)
    NODE_CPUS=$(get_input "CPU cores per node" "2" "validate_positive_number")
    NODE_DISK_GB=$(get_input "Disk size per node (GB)" "32" "validate_positive_number")
    NODE_DISK=$(gb_to_bytes $NODE_DISK_GB)
    
    # Load balancer sizing
    LB_MEMORY_GB=$(get_input "NGINX LB memory (GB)" "$NODE_MEMORY_GB" "validate_positive_number")
    LB_MEMORY=$(gb_to_bytes $LB_MEMORY_GB)
    LB_CPUS=$(get_input "NGINX LB CPU cores" "$NODE_CPUS" "validate_positive_number")
    LB_DISK_GB=$(get_input "NGINX LB disk size (GB)" "$NODE_DISK_GB" "validate_positive_number")
    LB_DISK=$(gb_to_bytes $LB_DISK_GB)
    
    # SSH and access
    if [ -f ~/.ssh/id_ed25519.pub ]; then
        DEFAULT_SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
    elif [ -f ~/.ssh/id_rsa.pub ]; then
        DEFAULT_SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
    else
        DEFAULT_SSH_KEY=""
    fi
    
    PUBLIC_SSH_KEY=$(get_input "SSH public key" "$DEFAULT_SSH_KEY")
    ANSIBLE_USER=$(get_input "SSH username for nodes" "ubuntu")
    
    # K3s configuration
    K3S_VERSION=$(get_input "K3s version" "v1.30.2+k3s1")
    K3S_TOKEN=$(get_input "K3s cluster token (will be auto-generated if empty)" "" "" false true)
    
    if [ -z "$K3S_TOKEN" ]; then
        if command -v openssl >/dev/null 2>&1; then
            K3S_TOKEN=$(openssl rand -base64 32 | tr -d '\n')
            log_info "Generated random K3s token"
        else
            K3S_TOKEN="changeme!"
            log_warning "Using default token. Consider changing this for production"
        fi
    fi
    
    # Ubuntu image ID (provider-specific)
    log_info "Find your Ubuntu image ID with: oxide image list | grep ubuntu"
    UBUNTU_IMAGE_ID=$(get_input "Ubuntu image ID (from 'oxide image list')" "")
}

collect_dns_config() {
    log_info "=== DNS and Certificate Configuration ==="
    
    # DNS provider selection
    log_info "DNS providers handle automatic DNS record creation and certificate validation"
    DNS_PROVIDER=$(get_choice "Select your DNS provider" \
        "dnsimple (API token required, full DNS-01 support)" \
        "cloudflare (API token required, requires webhook for DNS-01)" \
        "route53 (AWS credentials required, requires webhook for DNS-01)" \
        "digitalocean (API token required, requires webhook for DNS-01)" \
        "none (use self-signed certificates, no DNS automation)")
    
    # Extract provider name from descriptive choice
    if [[ "$DNS_PROVIDER" == *"dnsimple"* ]]; then
        DNS_PROVIDER_NAME="dnsimple"
        DNS_DOMAIN=$(get_input "Domain name" "" "validate_domain")
        DNS_TOKEN=$(get_input "DNSimple API token" "" "" true)
        DNS_ACCOUNT_ID=$(get_input "DNSimple account ID")
    elif [[ "$DNS_PROVIDER" == *"cloudflare"* ]]; then
        DNS_PROVIDER_NAME="cloudflare"
        DNS_DOMAIN=$(get_input "Domain name" "" "validate_domain")
        DNS_TOKEN=$(get_input "Cloudflare API token" "" "" true)
    elif [[ "$DNS_PROVIDER" == *"route53"* ]]; then
        DNS_PROVIDER_NAME="route53"
        DNS_DOMAIN=$(get_input "Domain name" "" "validate_domain")
        log_info "AWS credentials should be configured via AWS CLI or environment variables"
    elif [[ "$DNS_PROVIDER" == *"digitalocean"* ]]; then
        DNS_PROVIDER_NAME="digitalocean"
        DNS_DOMAIN=$(get_input "Domain name" "" "validate_domain")
        DNS_TOKEN=$(get_input "DigitalOcean API token" "" "" true)
    elif [[ "$DNS_PROVIDER" == *"none"* ]]; then
        DNS_PROVIDER_NAME="none"
        log_info "Self-signed certificates will be used - no external DNS automation"
        DNS_DOMAIN="k3s.local"
        DNS_TOKEN=""
        DNS_ACCOUNT_ID=""
    fi
    
    # Certificate manager configuration
    if [[ "$DNS_PROVIDER_NAME" == "none" ]]; then
        log_info "Using self-signed certificates (no Let's Encrypt)"
        CERT_CHALLENGE_TYPE="selfsigned (no Let's Encrypt, self-signed certs only)"
        CERT_CHALLENGE_NAME="selfsigned"
    else
        log_info "Certificate challenges prove domain ownership for Let's Encrypt"
        CERT_CHALLENGE_TYPE=$(get_choice "Certificate challenge type" \
            "dns01 (automatic DNS records, works behind firewalls)" \
            "http01 (requires public port 80 access)" \
            "selfsigned (no Let's Encrypt, self-signed certs only)")
        
        # Extract challenge type from descriptive choice
        if [[ "$CERT_CHALLENGE_TYPE" == *"dns01"* ]]; then
            CERT_CHALLENGE_NAME="dns01"
        elif [[ "$CERT_CHALLENGE_TYPE" == *"http01"* ]]; then
            CERT_CHALLENGE_NAME="http01"
        elif [[ "$CERT_CHALLENGE_TYPE" == *"selfsigned"* ]]; then
            CERT_CHALLENGE_NAME="selfsigned"
        fi
    fi
    
    if [ "$CERT_CHALLENGE_NAME" != "selfsigned" ]; then
        CERT_EMAIL=$(get_input "Email for Let's Encrypt certificates" "" "validate_email")
        
        # Environment selection for ACME
        CERT_ENVIRONMENT=$(get_choice "Let's Encrypt certificate environment" \
            "production (real certificates, rate limited)" \
            "staging (test certificates, no rate limits)")
        
        # Convert descriptive choice to boolean
        if [[ "$CERT_ENVIRONMENT" == *"production"* ]]; then
            CERT_PRODUCTION="true"
        else
            CERT_PRODUCTION="false"
        fi
        
        if [ "$CERT_CHALLENGE_NAME" = "dns01" ]; then
            # Validate DNS provider is compatible with DNS-01
            case $DNS_PROVIDER_NAME in
                "dnsimple")
                    log_success "DNS-01 challenge will use DNSimple webhook"
                    ;;
                "cloudflare")
                    log_warning "DNS-01 with Cloudflare requires additional webhook setup"
                    log_info "Consider using HTTP-01 challenge instead, or ensure Cloudflare webhook is available"
                    ;;
                "route53")
                    log_warning "DNS-01 with Route53 requires additional webhook setup"
                    log_info "Consider using HTTP-01 challenge instead, or ensure Route53 webhook is available"
                    ;;
                "digitalocean")
                    log_warning "DNS-01 with DigitalOcean requires additional webhook setup"
                    log_info "Consider using HTTP-01 challenge instead, or ensure DigitalOcean webhook is available"
                    ;;
                *)
                    log_warning "DNS-01 challenge may not be supported with $DNS_PROVIDER_NAME"
                    ;;
            esac
        elif [ "$CERT_CHALLENGE_NAME" = "http01" ]; then
            CERT_INGRESS_CLASS=$(get_input "Ingress class for HTTP-01 challenge" "traefik")
            log_info "HTTP-01 challenge requires ingress controller and public access to port 80"
        fi
    else
        log_info "Self-signed certificates will be used (no ACME configuration needed)"
        CERT_EMAIL=""
        CERT_PRODUCTION="false"
    fi
}

collect_app_config() {
    log_info "=== Application Configuration ==="
    
    # ArgoCD hostname
    ARGOCD_HOSTNAME=$(get_input "ArgoCD hostname" "argocd.$DNS_DOMAIN" "validate_domain")
    
    # Git repository for ArgoCD applications
    ARGOCD_REPO_URL=$(get_input "Git repository URL for ArgoCD applications" "https://github.com/qdzlug/oxide-k3s.git")
    ARGOCD_REPO_BRANCH=$(get_input "Git repository branch" "main")
    
    # Demo application domains
    DEMO_NGINX_HOSTNAME=$(get_input "Demo nginx hostname" "demo.$DNS_DOMAIN" "validate_domain")
    JUPYTER_HOSTNAME=$(get_input "JupyterHub hostname" "jupyter.$DNS_DOMAIN" "validate_domain")
    WHOAMI_HOSTNAME=$(get_input "Whoami demo hostname" "whoami.$DNS_DOMAIN" "validate_domain")
    
    # Internal load balancer IP will be derived from Terraform/Ansible inventory
    log_info "NGINX LB IPs will be automatically derived from Terraform deployment"
}

# Configuration file generation functions
generate_terraform_vars() {
    log_info "Generating Terraform variables file..."
    
    cat > "$TERRAFORM_VARS" << EOF
# Project & VPC Configuration
project_name    = "$PROJECT_NAME"
vpc_name        = "$VPC_NAME"
vpc_dns_name    = "$VPC_DNS_NAME"
vpc_description = "$VPC_DESCRIPTION"

# Cluster & Instance Settings
instance_count = $TOTAL_NODES
server_count   = $SERVER_NODES
memory         = $NODE_MEMORY # ${NODE_MEMORY_GB}GB per node in bytes
ncpus          = $NODE_CPUS
disk_size      = $NODE_DISK # ${NODE_DISK_GB}GB in bytes

# NGINX LB
nginx_lb_memory    = $LB_MEMORY
nginx_lb_ncpus     = $LB_CPUS
nginx_lb_disk_size = $LB_DISK

# Image settings
ubuntu_image_id = "$UBUNTU_IMAGE_ID"

# SSH / Auth
public_ssh_key = "$PUBLIC_SSH_KEY"

# Ansible & k3s Settings
ansible_user = "$ANSIBLE_USER"
k3s_version  = "$K3S_VERSION"
k3s_token    = "$K3S_TOKEN"
EOF
    
    log_success "Generated $TERRAFORM_VARS"
}

generate_external_dns_vars() {
    log_info "Generating external-dns variables file..."
    
    case $DNS_PROVIDER_NAME in
        "dnsimple")
            cat > "$EXTERNAL_DNS_VARS" << EOF
---
external_dns_namespace: external-dns
external_dns_provider: dnsimple
dnsimple_domain: $DNS_DOMAIN
dnsimple_account_id: "$DNS_ACCOUNT_ID"
external_dns_image: registry.k8s.io/external-dns/external-dns:v0.16.1
external_dns_txt_owner_id: k8s
external_dns_txt_prefix: external-dns-

# Note: dnsimple_token should be set via Ansible Vault
# Run: ansible-vault create group_vars/all/vault.yml
# Add: dnsimple_token: "your_token_here"
EOF
            ;;
        "cloudflare")
            cat > "$EXTERNAL_DNS_VARS" << EOF
---
external_dns_namespace: external-dns
external_dns_provider: cloudflare
external_dns_image: registry.k8s.io/external-dns/external-dns:v0.16.1
external_dns_txt_owner_id: k8s
external_dns_txt_prefix: external-dns-

# Note: cloudflare_api_token should be set via Ansible Vault
EOF
            ;;
        "none")
            log_info "Skipping external-dns configuration (self-signed certificates)"
            cat > "$EXTERNAL_DNS_VARS" << EOF
---
# External DNS disabled - using self-signed certificates
# No DNS automation will be configured
external_dns_enabled: false
EOF
            ;;
        *)
            log_warning "DNS provider $DNS_PROVIDER_NAME not fully implemented yet"
            ;;
    esac
    
    log_success "Generated $EXTERNAL_DNS_VARS"
}

generate_cert_manager_vars() {
    log_info "Generating cert-manager variables file..."
    
    cat > "$CERT_MANAGER_VARS" << EOF
---
# cert-manager configuration
cert_manager_challenge_type: "$CERT_CHALLENGE_NAME"
dns_provider_name: "$DNS_PROVIDER_NAME"
cert_manager_helm_repo: "https://charts.jetstack.io"
cert_manager_helm_version: "v1.14.5"
EOF
    
    if [ "$CERT_CHALLENGE_NAME" = "selfsigned" ]; then
        cat >> "$CERT_MANAGER_VARS" << EOF

# Self-signed certificate configuration
# No additional configuration needed for self-signed certificates
EOF
    else
        # ACME configuration (DNS-01 or HTTP-01)
        cat >> "$CERT_MANAGER_VARS" << EOF

# ACME Let's Encrypt configuration
cert_manager_email: "$CERT_EMAIL"
cert_manager_production: $CERT_PRODUCTION
cert_manager_webhook_group_name: acme.$DNS_DOMAIN
EOF
        
        if [ "$CERT_CHALLENGE_NAME" = "dns01" ]; then
            case $DNS_PROVIDER_NAME in
                "dnsimple")
                    cat >> "$CERT_MANAGER_VARS" << EOF

# DNSimple DNS-01 challenge configuration
dnsimple_account_id: "$DNS_ACCOUNT_ID"

# Note: dnsimple_token should be set via Ansible Vault
# Run: ansible-vault create group_vars/all/vault.yml
# Add: dnsimple_token: "your_token_here"
EOF
                    ;;
                "cloudflare")
                    cat >> "$CERT_MANAGER_VARS" << EOF

# Cloudflare DNS-01 challenge configuration
# Note: Requires cloudflare-webhook to be installed
# Note: cloudflare_api_token should be set via Ansible Vault
EOF
                    ;;
                "route53")
                    cat >> "$CERT_MANAGER_VARS" << EOF

# AWS Route53 DNS-01 challenge configuration
# Note: Requires route53-webhook to be installed
# Note: AWS credentials should be configured via environment or IAM roles
EOF
                    ;;
                "digitalocean")
                    cat >> "$CERT_MANAGER_VARS" << EOF

# DigitalOcean DNS-01 challenge configuration
# Note: Requires digitalocean-webhook to be installed
# Note: digitalocean_api_token should be set via Ansible Vault
EOF
                    ;;
            esac
        elif [ "$CERT_CHALLENGE_NAME" = "http01" ]; then
            cat >> "$CERT_MANAGER_VARS" << EOF

# HTTP-01 challenge configuration
cert_manager_http01_ingress_class: "$CERT_INGRESS_CLASS"
EOF
        fi
    fi
    
    log_success "Generated $CERT_MANAGER_VARS"
}

generate_argocd_vars() {
    log_info "Generating ArgoCD variables file..."
    
    cat > "$ARGOCD_VARS" << EOF
# ArgoCD configuration
argocd_hostname: "$ARGOCD_HOSTNAME"
argocd_tls_issuer: "letsencrypt-dns"
argocd_version: "v2.12.3"

# ArgoCD applications configuration
argocd_repo_url: "$ARGOCD_REPO_URL"
argocd_repo_branch: "$ARGOCD_REPO_BRANCH"

# Demo application hostnames
demo_nginx_hostname: "$DEMO_NGINX_HOSTNAME"
jupyter_hostname: "$JUPYTER_HOSTNAME"
whoami_hostname: "$WHOAMI_HOSTNAME"

# Infrastructure (nginx_lb_internal_ip derived from inventory)
dns_domain: "$DNS_DOMAIN"
EOF
    
    log_success "Generated $ARGOCD_VARS"
}

create_vault_instructions() {
    log_info "Creating Ansible Vault instructions..."
    
    # Create group_vars directory structure if it doesn't exist
    mkdir -p group_vars/all
    
    # Create a sample vault file (unencrypted for now, user must encrypt)
    cat > "group_vars/all/vault.yml.example" << EOF
---
# Ansible Vault file for sensitive variables
# Encrypt this file with: ansible-vault encrypt group_vars/all/vault.yml
# Edit with: ansible-vault edit group_vars/all/vault.yml

# DNS Provider secrets
EOF
    
    case $DNS_PROVIDER_NAME in
        "dnsimple")
            cat >> "group_vars/all/vault.yml.example" << EOF
dnsimple_token: "$DNS_TOKEN"
EOF
            ;;
        "cloudflare")
            cat >> "group_vars/all/vault.yml.example" << EOF
cloudflare_api_token: "$DNS_TOKEN"
EOF
            ;;
        "none")
            cat >> "group_vars/all/vault.yml.example" << EOF
# No DNS provider tokens needed - using self-signed certificates
EOF
            ;;
    esac
    
    # Create instructions file
    cat > "VAULT-SETUP.md" << EOF
# Ansible Vault Setup Instructions

> **Infrastructure Tool Detected**: $TERRAFORM_TOOL  
> **DNS Provider**: $DNS_PROVIDER_NAME  
> This setup script detected **$TERRAFORM_TOOL** for infrastructure management.

## When is Ansible Vault needed?

- **DNS Provider Secrets**: Required when using DNS providers (DNSimple, Cloudflare, etc.) for Let's Encrypt certificates
- **Self-signed Certificates**: NOT required when using self-signed certificates (DNS provider = "none")

## Automated Setup (Recommended)

Use the Makefile for easy vault management:

\`\`\`bash
# Set up vault automatically (only if needed)
make setup-vault-optional

# Or force vault setup
make setup-vault
\`\`\`

## Manual Setup

### 1. Create the encrypted vault file:
\`\`\`bash
# Copy the example file
cp group_vars/all/vault.yml.example group_vars/all/vault.yml

# Encrypt the vault file (you'll be prompted for a password)
ansible-vault encrypt group_vars/all/vault.yml
\`\`\`

### 2. To edit the vault file:
\`\`\`bash
ansible-vault edit group_vars/all/vault.yml
\`\`\`

### 3. Deployment with vault:

**Using make targets (handles vault automatically):**
\`\`\`bash
make cert-manager     # Uses vault if available
make external-dns     # Uses vault if available  
make argocd          # Uses vault if available
\`\`\`

**Manual playbook execution:**
\`\`\`bash
# With password prompt
ansible-playbook -i inventory.yml playbooks/cert-manager.yaml --ask-vault-pass

# With password file
ansible-playbook -i inventory.yml playbooks/cert-manager.yaml --vault-password-file .vault-password
\`\`\`

### 4. Create a vault password file (optional):
\`\`\`bash
echo "your-vault-password" > .vault-password
chmod 600 .vault-password
\`\`\`

**Important:** Add .vault-password to your .gitignore file if using a password file.

## Troubleshooting

- If vault setup fails, you can skip it for self-signed certificates
- Use \`make show-vars\` to check vault configuration status
- Use \`make check-config-soft\` for configuration validation with warnings only
- Remove vault with \`make clean-config\` (WARNING: destructive)

## DNS Provider Specific Notes

- **DNSimple**: Requires \`dnsimple_token\` in vault
- **Cloudflare**: Requires \`cloudflare_api_token\` in vault  
- **DigitalOcean**: Requires \`digitalocean_token\` in vault
- **None (self-signed)**: No vault needed
EOF
    
    log_success "Created vault example and instructions"
    log_warning "Remember to encrypt group_vars/all/vault.yml before committing!"
}

# Main execution
main() {
    echo -e "${BLUE}"
    echo "============================================="
    echo "    Oxide K3s Cluster Setup Script"
    echo "============================================="
    echo -e "${NC}"
    
    # Validate tools first
    validate_tools
    
    # Validate Oxide environment variables
    if ! validate_oxide_env; then
        log_error "Oxide environment variables must be set before running setup"
        log_info "Please set OXIDE_HOST and OXIDE_TOKEN environment variables and try again"
        exit 1
    fi
    
    # Collect configuration
    collect_infrastructure_config
    collect_dns_config
    collect_app_config
    
    # Generate configuration files
    generate_terraform_vars
    generate_external_dns_vars
    generate_cert_manager_vars
    generate_argocd_vars
    create_vault_instructions
    
    # Summary
    log_info "=== Configuration Summary ==="
    log_info "Infrastructure Tool: $TERRAFORM_TOOL"
    log_info "Infrastructure: $SERVER_NODES control plane + $AGENT_NODES worker nodes"
    log_info "Node specs: ${NODE_CPUS} CPU, ${NODE_MEMORY_GB}GB RAM, ${NODE_DISK_GB}GB disk"
    log_info "DNS Provider: $DNS_PROVIDER_NAME"
    log_info "Domain: $DNS_DOMAIN"
    log_info "Certificate Type: $CERT_CHALLENGE_NAME"
    if [ "$CERT_CHALLENGE_NAME" != "selfsigned" ]; then
        log_info "Certificate Environment: $CERT_ENVIRONMENT"
    fi
    log_info "ArgoCD URL: https://$ARGOCD_HOSTNAME"
    
    echo
    log_success "Configuration complete! Next steps:"
    echo
    echo "[FILES] Generated configuration files:"
    echo "  * $TERRAFORM_VARS - Infrastructure configuration"
    echo "  * $EXTERNAL_DNS_VARS - DNS provider settings" 
    echo "  * $CERT_MANAGER_VARS - Certificate manager config"
    echo "  * $ARGOCD_VARS - ArgoCD and application settings"
    echo "  * group_vars/all/vault.yml.example - Secrets template"
    echo "  * VAULT-SETUP.md - Vault setup instructions"
    echo
    echo "[DEPLOYMENT] You have two options for deployment:"
    echo
    echo ">>> OPTION 1: AUTOMATED DEPLOYMENT (RECOMMENDED) <<<"
    echo "The Makefile provides automated deployment with error checking:"
    echo
    echo "1. Complete setup (one command does everything):"
    echo "   make full-setup"
    echo
    echo "2. Or step-by-step automated deployment:"
    echo "   make setup-vault    # Set up encrypted secrets"
    echo "   make infra-up       # Deploy infrastructure and wait for hosts"
    echo "   make deploy         # Deploy K3s cluster"
    echo "   make nginx-lb       # Configure load balancer"
    echo "   make cert-manager   # Deploy certificate management"
    echo "   make external-dns   # Deploy DNS automation"
    echo "   make longhorn       # Deploy distributed storage"
    echo "   make argocd         # Deploy GitOps and demo apps"
    echo
    echo "3. Check deployment status anytime:"
    echo "   make check          # Verify cluster health"
    echo "   make show-vars      # Review configuration"
    echo
    echo ">>> OPTION 2: MANUAL DEPLOYMENT <<<"
    echo "For users who prefer manual control or troubleshooting:"
    echo
    echo "1. Set up Ansible Vault (see VAULT-SETUP.md):"
    echo "   cp group_vars/all/vault.yml.example group_vars/all/vault.yml"
    echo "   # Edit vault.yml with your secrets"
    echo "   ansible-vault encrypt group_vars/all/vault.yml"
    echo
    echo "2. Deploy infrastructure:"
    echo "   cd infra/oxide && $TERRAFORM_TOOL init && $TERRAFORM_TOOL plan && $TERRAFORM_TOOL apply"
    echo
    echo "3. Deploy Kubernetes cluster:"
    echo "   ansible-playbook -i inventory.yml playbooks/site.yml --ask-vault-pass"
    echo
    echo "4. Configure load balancer:"
    echo "   ansible-playbook -i inventory.yml playbooks/nginx-lb.yaml --ask-vault-pass"
    echo
    echo "5. Deploy services (cert-manager, external-dns, longhorn):"
    echo "   ansible-playbook -i inventory.yml playbooks/cert-manager.yaml --ask-vault-pass"
    echo "   ansible-playbook -i inventory.yml playbooks/external-dns.yaml --ask-vault-pass"
    echo "   ansible-playbook -i inventory.yml playbooks/longhorn.yml --ask-vault-pass"
    echo
    echo "6. Deploy ArgoCD and demo applications:"
    echo "   ansible-playbook -i inventory.yml playbooks/argocd.yml --ask-vault-pass"
    echo
    echo "[IMPORTANT] Prerequisites for deployment:"
    echo "  * Ensure OXIDE_HOST and OXIDE_TOKEN environment variables are set"
    echo "  * Have your DNS provider credentials ready (if not using self-signed certs)"
    echo "  * Review and encrypt your vault file with secrets before deploying"
    echo
    echo "[HELP] Available make targets:"
    echo "  * make help         - Show all available targets"
    echo "  * make full-setup   - Complete automated setup"
    echo "  * make show-vars    - Review current configuration"
    echo "  * make check-config - Validate configuration before deployment"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi