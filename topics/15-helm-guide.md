# Helm — What, Use Case, Parts, Package & Push

### What is Helm
Package manager for Kubernetes — like apt/yum but for K8s manifests. Deploy complex apps with one command, manage versions, rollbacks, and reuse templates.

### Chart Structure
```
mychart/
├── Chart.yaml        ← metadata (name, version)
├── values.yaml       ← default config values
├── templates/        ← K8s manifests with placeholders
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   └── _helpers.tpl  ← reusable snippets
└── charts/           ← sub-chart dependencies
```

### Package & Push
```bash
# Package
helm package ./mychart              # mychart-1.0.0.tgz

# Push to OCI (ECR / GHCR)
helm push mychart-1.0.0.tgz oci://ghcr.io/myorg/helm-charts
```

### Reuse for Different Environments
```bash
helm install myapp ./mychart -f values-prod.yaml
helm install myapp ./mychart -f values-dev.yaml

# From remote registry
helm install myapp oci://ghcr.io/myorg/helm-charts/mychart \
  --version 1.0.0 -f values-prod.yaml
```
