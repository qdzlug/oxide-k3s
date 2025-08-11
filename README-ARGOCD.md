# ArgoCD Demo Applications

This document describes the automated application deployments created to demonstrate the power of ArgoCD and GitOps on our K3s cluster.

## 🚀 Demo Applications Deployed

### 1. **Nginx Demo Landing Page**
- **URL**: https://demo.virington.com
- **Features**: Custom landing page showcasing the cluster architecture
- **Status**: ✅ Running (2 replicas)
- **Description**: A beautiful landing page that provides an overview of the cluster topology and links to other demo services

### 2. **WhoAmI Service** 
- **URL**: https://whoami.virington.com
- **Features**: Shows load balancing across multiple pods
- **Status**: ✅ Running (2 replicas)
- **Demo Value**: Great for showing how requests are distributed across pods
- **Usage**: Refresh the page multiple times to see different pod responses

### 3. **Jupyter Notebook Server**
- **URL**: https://jupyter.virington.com
- **Features**: Full SciPy stack with JupyterLab interface
- **Authentication**: Token: `demo123`
- **Resources**: 512Mi-2Gi RAM, 250m-1000m CPU
- **Demo Value**: Shows how to deploy complex interactive applications

## 🔧 Infrastructure Features Demonstrated

### GitOps with ArgoCD
- **Automated Deployment**: Apps deployed via ArgoCD Applications
- **Self-Healing**: Configured with `syncPolicy.automated.selfHeal: true`
- **Pruning**: Unused resources automatically cleaned up
- **Git Source**: Applications sync from GitHub repository
- **Declarative**: All configurations stored as YAML manifests

### Network & Security Stack
- **TLS Certificates**: Automatic Let's Encrypt certificates via cert-manager
- **DNS Management**: Automatic DNS records via external-dns pointing to internal LB
- **Load Balancing**: NGINX LB (172.21.252.144) → Traefik NodePorts → Services
- **HTTPS Redirect**: All HTTP traffic automatically redirected to HTTPS
- **Ingress Classes**: Traefik ingress controller with proper routing

### Scalability & Reliability
- **Multi-replica deployments** showing load distribution
- **Resource limits** and requests configured for optimal scheduling
- **Horizontal scaling** ready - can be scaled via ArgoCD or kubectl
- **Pod Anti-Affinity** (where configured) for high availability

## 🎯 Demo Script Ideas

### 1. GitOps in Action
```bash
# Show current state
kubectl get applications -n argocd
kubectl get pods -A | grep -E "(jupyter|whoami|nginx-demo)"

# Modify replica count in Git repository
# ArgoCD will automatically sync and scale pods

# Watch the sync happen in ArgoCD UI
open https://argocd.virington.com
```

### 2. Load Balancing Demo
```bash
# Hit whoami service repeatedly to see different pod responses
for i in {1..10}; do curl https://whoami.virington.com; echo "---"; done

# Scale pods up/down and watch load distribution
kubectl scale deployment whoami -n whoami --replicas=4
```

### 3. Disaster Recovery
```bash
# Delete a pod → Watch it self-heal
kubectl delete pod -n whoami -l app=whoami --force

# Delete entire deployment → ArgoCD restores it
kubectl delete deployment nginx-demo -n nginx-demo
# Check ArgoCD - it will restore the deployment automatically
```

### 4. Security & Compliance Demo
```bash
# Show automatic TLS certificate provisioning
kubectl get certificates -A
kubectl describe certificate demo-tls -n nginx-demo

# Show external DNS record management
kubectl logs -n external-dns deployment/external-dns --tail=20

# Show resource constraints and limits
kubectl describe pod -n jupyter -l app=jupyter-notebook
```

## 📁 Application Structure

Each application follows a consistent structure:
```
argocd-apps/
├── application-*.yaml          # ArgoCD Application manifests
├── jupyter/
│   ├── namespace.yaml          # Namespace definition
│   ├── deployment.yaml         # Pod specification
│   ├── service.yaml           # Service definition
│   └── ingress.yaml           # Ingress with TLS and external-dns
├── whoami/
│   └── (same structure)
└── nginx-demo/
    ├── configmap.yaml         # Custom HTML content
    └── (same structure)
```

## 🔑 Access Information

### ArgoCD Dashboard
- **URL**: https://argocd.virington.com
- **Username**: `admin`
- **Password**: `HlwyGwNi6acTVULn`

### Application Endpoints
- **Demo Landing**: https://demo.virington.com
- **Load Balancer Test**: https://whoami.virington.com  
- **Jupyter Notebook**: https://jupyter.virington.com (token: `demo123`)

## 🚀 Adding New Applications

To add new applications to the GitOps workflow:

1. **Create Application Manifests**:
   ```bash
   mkdir argocd-apps/myapp
   # Create namespace.yaml, deployment.yaml, service.yaml, ingress.yaml
   ```

2. **Create ArgoCD Application**:
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: myapp
     namespace: argocd
   spec:
     project: default
     source:
       repoURL: 'https://github.com/qdzlug/oxide-k3s.git'
       path: argocd-apps/myapp
       targetRevision: HEAD
     destination:
       server: 'https://kubernetes.default.svc'
       namespace: myapp
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
       syncOptions:
       - CreateNamespace=true
   ```

3. **Deploy via ArgoCD**:
   ```bash
   kubectl apply -f argocd-apps/application-myapp.yaml
   ```

## 🔧 Troubleshooting

### Common Issues

**Application not syncing from Git**:
- Ensure Git repository is accessible
- Check ArgoCD Application status: `kubectl describe application myapp -n argocd`

**Pods not starting**:
- Check resource constraints: `kubectl describe pod -n namespace podname`
- Verify image availability: `kubectl get events -n namespace`

**Ingress not accessible**:
- Verify DNS propagation: `dig appname.virington.com`
- Check certificate status: `kubectl get certificates -A`
- Confirm external-dns logs: `kubectl logs -n external-dns deployment/external-dns`

### Useful Commands
```bash
# Check ArgoCD application status
kubectl get applications -n argocd

# Force sync an application
kubectl patch application myapp -n argocd --type merge --patch='{"spec":{"source":{"targetRevision":"HEAD"}}}'

# Watch external-dns create records
kubectl logs -n external-dns deployment/external-dns --follow

# Check certificate provisioning
kubectl get certificaterequests -A
kubectl describe clusterissuer letsencrypt-dns
```

This GitOps setup demonstrates a production-ready Kubernetes deployment with automated certificate management, DNS provisioning, and application lifecycle management through ArgoCD.