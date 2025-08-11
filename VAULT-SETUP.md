# Ansible Vault Setup Instructions

> **Infrastructure Tool Detected**: tofu  
> **DNS Provider**: dnsimple  
> This setup script detected **tofu** for infrastructure management.

## When is Ansible Vault needed?

- **DNS Provider Secrets**: Required when using DNS providers (DNSimple, Cloudflare, etc.) for Let's Encrypt certificates
- **Self-signed Certificates**: NOT required when using self-signed certificates (DNS provider = "none")

## Automated Setup (Recommended)

Use the Makefile for easy vault management:

```bash
# Set up vault automatically (only if needed)
make setup-vault-optional

# Or force vault setup
make setup-vault
```

## Manual Setup

### 1. Create the encrypted vault file:
```bash
# Copy the example file
cp group_vars/all/vault.yml.example group_vars/all/vault.yml

# Encrypt the vault file (you'll be prompted for a password)
ansible-vault encrypt group_vars/all/vault.yml
```

### 2. To edit the vault file:
```bash
ansible-vault edit group_vars/all/vault.yml
```

### 3. Deployment with vault:

**Using make targets (handles vault automatically):**
```bash
make cert-manager     # Uses vault if available
make external-dns     # Uses vault if available  
make argocd          # Uses vault if available
```

**Manual playbook execution:**
```bash
# With password prompt
ansible-playbook -i inventory.yml playbooks/cert-manager.yaml --ask-vault-pass

# With password file
ansible-playbook -i inventory.yml playbooks/cert-manager.yaml --vault-password-file .vault-password
```

### 4. Create a vault password file (optional):
```bash
echo "your-vault-password" > .vault-password
chmod 600 .vault-password
```

**Important:** Add .vault-password to your .gitignore file if using a password file.

## Troubleshooting

- If vault setup fails, you can skip it for self-signed certificates
- Use `make show-vars` to check vault configuration status
- Use `make check-config-soft` for configuration validation with warnings only
- Remove vault with `make clean-config` (WARNING: destructive)

## DNS Provider Specific Notes

- **DNSimple**: Requires `dnsimple_token` in vault
- **Cloudflare**: Requires `cloudflare_api_token` in vault  
- **DigitalOcean**: Requires `digitalocean_token` in vault
- **None (self-signed)**: No vault needed
