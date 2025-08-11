# ArgoCD Role

This role deploys ArgoCD on Kubernetes using Helm with Traefik ingress and cert-manager integration.

## Prerequisites

- Kubernetes cluster with Traefik ingress controller
- cert-manager deployed (for TLS certificates)
- external-dns deployed (for automatic DNS management)
- Python kubernetes library installed
- Ansible kubernetes.core collection

## Variables

### Required Variables (set in vars/main.yml)
- `argocd_hostname`: Hostname for ArgoCD access (e.g., "argocd.example.com")

### Optional Variables (with defaults in defaults/main.yml)
- `argocd_namespace`: Namespace for ArgoCD (default: "argocd")
- `argocd_version`: ArgoCD image version (default: "v2.12.3")
- `argocd_tls_issuer`: cert-manager ClusterIssuer (default: "letsencrypt-dns")
- `argocd_server_insecure`: Run server in insecure mode for Traefik (default: true)
- `argocd_enable_metrics`: Enable metrics collection (default: true)
- `argocd_enable_applicationset`: Enable ApplicationSet controller (default: true)
- `argocd_enable_notifications`: Enable notifications controller (default: false)

## Usage

### Using the dedicated playbook
```bash
ansible-playbook -i inventory.yml playbooks/argocd.yml
```

### Using the role directly
```yaml
- hosts: "{{ groups['server'][0] }}"
  roles:
    - role: argocd
```

## Post-deployment

After successful deployment, the role will display:
- ArgoCD URL
- Admin username (always "admin")
- Initial admin password

## Troubleshooting

If ArgoCD is not accessible:

1. Check pods status:
```bash
kubectl -n argocd get pods
```

2. Check services:
```bash
kubectl -n argocd get svc
```

3. Check ingress:
```bash
kubectl -n argocd get ingress
```

4. Check ArgoCD server logs:
```bash
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-server
```

5. Verify DNS resolution and certificate:
```bash
nslookup <argocd_hostname>
curl -I https://<argocd_hostname>
```

## Features

- ✅ Secure TLS termination with cert-manager
- ✅ Automatic DNS record management with external-dns
- ✅ ApplicationSet controller enabled
- ✅ Metrics collection enabled
- ✅ Proper wait conditions for reliable deployment
- ✅ Initial admin password retrieval
- ✅ Health checks and status validation