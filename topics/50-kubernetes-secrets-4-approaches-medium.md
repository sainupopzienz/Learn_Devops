# Kubernetes Secrets Done Right: 4 Patterns Every Engineer Should Know

## ESO, CSI Driver, EKS Add-on, and Sealed Secrets — When to Use Each and Why

---

Managing secrets in Kubernetes is one of those things that looks easy until it isn't. You start with `kubectl create secret`, and for a while, that works. Then your team grows. You get a compliance audit. Someone commits a password to Git. Suddenly you're rewriting your entire secrets strategy.

This article walks through all four production patterns for managing secrets in Kubernetes — with a focus on AWS EKS. By the end you'll know exactly when to use each, what gets installed, and how data flows from source to your running pod.

---

## The Common Starting Point

Before any of the four approaches, two things need to exist: an OIDC provider (if you use IRSA for IAM) and the actual secret in AWS Secrets Manager.

**Associate the OIDC Provider (IRSA method):**

```bash
eksctl utils associate-iam-oidc-provider \
  --cluster my-cluster \
  --approve
```

**Create the secret in AWS Secrets Manager:**

```bash
aws secretsmanager create-secret \
  --name prod/nginx-secret \
  --secret-string '{"username":"admin","password":"mypassword"}'
```

> **Note on OIDC vs Pod Identity:** The OIDC step is only needed if you use IRSA (the older IAM method). If you use EKS Pod Identity (the newer recommended approach), you skip this step entirely. All four patterns below show the IRSA method since it works on any EKS version.

---

## Approach 1 — External Secrets Operator (ESO)

### What Is It?

ESO is a Kubernetes operator that acts as a bridge between your cluster and external secret stores — AWS Secrets Manager, HashiCorp Vault, GCP Secret Manager, Azure Key Vault, and 50+ others. You define what secret you want using a custom resource, and ESO fetches it and creates a native Kubernetes Secret for your pod to consume.

### How the Data Flows

```
AWS Secrets Manager
        │
        │  ESO fetches via IAM role
        ▼
External Secrets Operator (running in cluster)
        │
        │  creates
        ▼
Kubernetes Secret (stored in etcd)
        │
        │  pod reads
        ▼
Your Pod (as env var or volume)
```

### Installation

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
```

### IAM Setup

Create a policy that allows reading from Secrets Manager, then attach it to a role with an IRSA trust policy:

**Trust Policy for the IAM Role:**
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<OIDC_ID>"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.<region>.amazonaws.com/id/<OIDC_ID>:sub":
          "system:serviceaccount:external-secrets:eso-sa"
      }
    }
  }]
}
```

### Kubernetes Resources

**ServiceAccount — annotated with the IAM role:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: eso-sa
  namespace: external-secrets
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/eso-role
```

**SecretStore — tells ESO which AWS account and region to use:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-store
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-south-1
      auth:
        jwt:
          serviceAccountRef:
            name: eso-sa
```

**ExternalSecret — which specific secret to fetch:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: nginx-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-store
    kind: SecretStore
  target:
    name: nginx-k8s-secret
  data:
    - secretKey: password
      remoteRef:
        key: prod/nginx-secret
        property: password
```

**Pod — mounts the Kubernetes Secret as a volume:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
    - name: nginx
      image: nginx
      volumeMounts:
        - name: secretvol
          mountPath: /etc/secrets
  volumes:
    - name: secretvol
      secret:
        secretName: nginx-k8s-secret
```

### What to Know

The Kubernetes Secret created by ESO lives in etcd. It is base64 encoded — not encrypted by default. Anyone with sufficient RBAC access or etcd access can read the value. For most use cases this is acceptable. For compliance-heavy environments (PCI DSS, HIPAA), consider the CSI approach instead.

The `refreshInterval` field means ESO will re-fetch from Secrets Manager on a schedule. When the value in Secrets Manager changes, ESO updates the Kubernetes Secret automatically. However, running pods still need a restart to pick up the new value if they read it as an environment variable — volumes update without restart.

---

## Approach 2 — CSI Driver + AWS Provider (ASCP)

### What Is It?

The Secrets Store CSI Driver is a Kubernetes-native mechanism that mounts secrets directly as files inside pods. The AWS Secrets and Configuration Provider (ASCP) is the AWS-specific plugin that connects the CSI driver to Secrets Manager. Together, they deliver secrets straight into your pod at mount time — bypassing etcd entirely.

### How the Data Flows

```
AWS Secrets Manager
        │
        │  ASCP fetches at pod start using pod's IAM role
        ▼
CSI Driver (DaemonSet on every node)
        │
        │  mounts directly as file — no etcd, no K8s Secret
        ▼
Your Pod
  └── /mnt/secrets/password  ← file, content: mypassword
```

### Installation — Two Helm Charts

**Install the CSI driver base:**
```bash
helm repo add secrets-store-csi-driver \
  https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts

helm install csi-secrets-store \
  secrets-store-csi-driver/secrets-store-csi-driver \
  -n kube-system
```

**Install the AWS provider (ASCP):**
```bash
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
```

This deploys two DaemonSets — one for the base CSI driver and one for the AWS provider. Both run on every worker node because the secret mount happens locally on the node where the pod is scheduled.

### IAM Setup

This time the IAM role is for the application pod directly — not for ESO. The pod itself needs permission to read from Secrets Manager. The trust policy scopes the role to the pod's service account:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks..."
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "oidc...:sub": "system:serviceaccount:default:nginx-sa"
    }
  }
}
```

### Kubernetes Resources

**ServiceAccount — for the app pod, annotated with the IAM role:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nginx-sa
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/nginx-role
```

**SecretProviderClass — which secret, what type, how to mount:**
```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: aws-secrets
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "prod/nginx-secret"
        objectType: "secretsmanager"
```

**Pod — mounts via CSI volume, not a K8s Secret:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  serviceAccountName: nginx-sa
  containers:
    - name: nginx
      image: nginx
      volumeMounts:
        - name: secrets
          mountPath: /mnt/secrets
  volumes:
    - name: secrets
      csi:
        driver: secrets-store.csi.k8s.io
        volumeAttributes:
          secretProviderClass: aws-secrets
```

### What to Know

The secret value never touches etcd. No Kubernetes Secret object is created. The file at `/mnt/secrets/password` exists only in the pod's mounted filesystem — it lives in memory, not in any Kubernetes storage layer.

When Secrets Manager rotates the password, the CSI driver detects the change on its polling interval and updates the file in-place. The pod does not need to restart — the app simply re-reads the file on its next access. This is the primary operational advantage over the ESO approach.

---

## Approach 3 — EKS Add-on (Managed CSI)

### What Is It?

This is functionally identical to Approach 2. The difference is in who manages the CSI driver installation. Instead of two Helm installs and a kubectl apply, AWS installs and manages the CSI components as a native EKS add-on. The SecretProviderClass YAML and Pod YAML are unchanged.

### How the Data Flows

```
AWS Secrets Manager
        │
        │  AWS-managed CSI + ASCP fetches at pod start
        ▼
AWS Managed DaemonSets (on every node)
        │
        │  mounts as file — no etcd
        ▼
Your Pod  →  /mnt/secrets/password
```

### Installation — One AWS Command

```bash
aws eks create-addon \
  --cluster-name my-cluster \
  --addon-name aws-secrets-manager-csi-driver
```

That single command installs everything Approach 2 requires across two Helm installs. AWS handles version compatibility with your EKS cluster, manages upgrades, and monitors health through the standard addon lifecycle.

### What Changes vs Approach 2

Nothing in your application configuration changes. The SecretProviderClass, ServiceAccount, and Pod YAML are identical. The IAM role setup is identical. The only thing that changes is the installation method for the driver itself.

```
Approach 2 (self-managed):
  2 Helm installs → you own upgrades and version pinning

Approach 3 (AWS managed):
  1 aws eks create-addon → AWS owns upgrades and compatibility
```

Choose Approach 2 when you need precise version control or want to install in air-gapped environments. Choose Approach 3 when you want AWS to manage the underlying components and prefer fewer Helm releases to maintain.

---

## Approach 4 — Sealed Secrets

### What Is It?

Sealed Secrets takes a completely different philosophy. Instead of fetching secrets from an external store at runtime, it solves a different problem: how do you safely commit secrets to Git?

A SealedSecret is a Kubernetes resource that contains an encrypted version of your secret. It can be committed to a Git repository safely — only the Sealed Secrets controller running in your cluster has the private key to decrypt it. When you apply the SealedSecret, the controller decrypts it and creates a standard Kubernetes Secret.

### How the Data Flows

```
Your secret value
        │
        │  kubeseal encrypts with cluster's public key
        ▼
SealedSecret YAML (safe to commit to Git)
        │
        │  kubectl apply
        ▼
Sealed Secrets Controller (running in cluster)
        │
        │  decrypts with private key, creates K8s Secret
        ▼
Kubernetes Secret in etcd → Pod reads as env var
```

### Installation

**Install the controller in your cluster:**
```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
```

**Install the CLI tool on your machine:**
```bash
brew install kubeseal
# or: download binary from GitHub releases for Linux/Windows
```

**Fetch the cluster's public key:**
```bash
kubeseal --fetch-cert > pub.pem
```

### Sealing a Secret

**Create a standard Secret YAML (do NOT apply this — seal it instead):**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
type: Opaque
data:
  password: bXlwYXNz   # base64 of "mypass"
```

**Encrypt it into a SealedSecret:**
```bash
kubeseal --cert pub.pem < sec.yaml > sealed.yaml
```

**`sealed.yaml` is now safe to commit to Git and apply to the cluster:**
```bash
kubectl apply -f sealed.yaml
```

**Pod reads the resulting Kubernetes Secret as a normal env var:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
    - name: nginx
      image: nginx
      env:
        - name: PASSWORD
          valueFrom:
            secretKeyRef:
              name: my-secret
              key: password
```

### What to Know

Sealed Secrets solves GitOps — you can store all your application manifests including secrets in Git, run ArgoCD or Flux, and have fully declarative secret management without leaking values.

It does not solve the etcd problem. The Kubernetes Secret created after decryption is stored in etcd just like any other secret. The advantage is in the Git layer, not the runtime layer.

No IAM. No cloud provider. Works identically on EKS, GKE, AKS, or on-premises — anywhere Kubernetes runs.

The key rotation story is different too. If you need to rotate the sealing key (for compliance or because it was compromised), all SealedSecrets must be re-encrypted and re-applied. This is a meaningful operational burden at scale.

---

## The Complete Comparison

| | ESO | CSI + ASCP | EKS Add-on | Sealed Secrets |
|---|---|---|---|---|
| **Secret source** | AWS → K8s | AWS → Pod | AWS → Pod | Git → K8s |
| **Stored in etcd?** | Yes | No | No | Yes |
| **IAM required?** | Yes | Yes | Yes | No |
| **Cloud provider** | Any (50+) | AWS | AWS | Any |
| **Pod reads via** | Env var or volume | File mount | File mount | Env var or volume |
| **Auto-rotation** | Yes (ESO re-syncs) | Yes (file updates) | Yes (file updates) | Manual re-seal |
| **Pod restart on rotation?** | Yes (env var) / No (volume) | No | No | Yes |
| **GitOps friendly?** | Partial | Partial | Partial | Yes (by design) |
| **Installation** | Helm | 2x Helm | 1 AWS command | kubectl apply + CLI |
| **Best for** | Multi-cloud, existing K8s | High security, AWS, compliance | High security, fully AWS managed | GitOps, any cluster |

---

## The One-Line Memory

```
ESO      → Fetch from AWS → Kubernetes Secret → Pod
CSI      → Fetch from AWS → File in Pod (no etcd)
Add-on   → AWS manages CSI → File in Pod (no etcd)
Sealed   → Encrypted in Git → Kubernetes Secret → Pod
```

---

## How to Choose

**Start with ESO** if your team is already using Helm, your secrets are medium-sensitivity, and you want support for multiple secret backends or cloud providers. It is the simplest setup and works for the majority of use cases.

**Use CSI Driver or EKS Add-on** when secrets must never touch etcd — database passwords, private keys, payment credentials, anything under compliance requirements. Choose Helm (Approach 2) for version control, choose the managed Add-on (Approach 3) if you prefer AWS to own the upgrade lifecycle.

**Use Sealed Secrets** when GitOps is a hard requirement — you want every resource including secrets committed to a repository, and your team works with tools like ArgoCD or Flux. Combine with ESO or CSI for the most complete solution: Sealed Secrets handles Git-safe storage, ESO or CSI handles runtime injection.

---

## Production Reality

Most mature teams do not pick just one. A typical production cluster runs:

- **ESO** for non-sensitive application configuration, feature flags, and API keys stored in Secrets Manager
- **CSI Driver or Add-on** for database credentials and TLS private keys that must never appear in etcd
- **Sealed Secrets** alongside ArgoCD for GitOps workflows where all manifests live in a repository

The patterns are not mutually exclusive. They solve different layers of the same problem.

---

*The right secrets strategy is the one your team will actually maintain. Start simple. Add complexity only when a real security requirement demands it.*
