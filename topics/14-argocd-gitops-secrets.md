# Secrets in ArgoCD / GitOps

> **ArgoCD does NOT store secrets.** Git is source of truth but you NEVER push actual secret values to git.

### Option 1 — Sealed Secrets (Bitnami)
```bash
kubeseal < secret.yaml > sealed-secret.yaml
# Push sealed-secret.yaml to git — safe to commit
# Controller decrypts inside the cluster
```

### Option 2 — External Secrets Operator ← Most Popular
- Secrets live in AWS Secrets Manager / HashiCorp Vault
- ESO syncs them into K8s secrets automatically
- Git only has ExternalSecret resource (no actual values)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-secret
spec:
  secretStoreRef:
    name: aws-secretsmanager
  target:
    name: db-credentials
  data:
  - secretKey: password
    remoteRef:
      key: prod/db/password
```

### Option 3 — ArgoCD Vault Plugin (AVP)
Secrets fetched from Vault at deploy time. Placeholders in manifests replaced during sync.

> **Best practice:** External Secrets Operator + AWS Secrets Manager
