# Graceful Shutdown, PDB, CRDs, and Custom S3 Plugin in Kubernetes

## Four Concepts That Separate Junior from Senior Kubernetes Engineers

---

Most engineers can deploy a pod. Fewer understand what happens when Kubernetes decides to remove one. Even fewer understand how to extend Kubernetes itself with custom resources and operators.

This article covers four interconnected topics: how to configure graceful shutdown so your app handles termination cleanly, how PodDisruptionBudgets protect availability during planned operations, what CRDs actually are and why they exist, and finally — a complete working example of building your own custom CRD and controller implemented as an S3 bucket manager.

---

# Part 1 — Graceful Shutdown

## What Happens When a Pod Is Terminated

Most engineers assume Kubernetes just kills a pod. The reality is a carefully orchestrated sequence that gives your application time to finish what it's doing.

```
Kubernetes decides to terminate a pod (scale down, node drain, rolling update)
          │
          ▼
Pod enters Terminating state
          │
          ├──► kube-proxy removes pod from iptables rules
          │    (new connections no longer routed to this pod)
          │
          ├──► Endpoints controller removes pod from Service endpoints
          │    (load balancer stops sending new requests here)
          │
          └──► SIGTERM sent to PID 1 in the container
                    │
                    │  terminationGracePeriodSeconds countdown starts
                    │  (default: 30 seconds)
                    ▼
               App handles SIGTERM:
                 → Stop accepting new connections
                 → Finish processing in-flight requests
                 → Close DB connections cleanly
                 → Flush logs and metrics
                    │
               If app exits within grace period → clean shutdown ✅
               If app does not exit → SIGKILL sent → forced kill ❌
```

## The Gap Between SIGTERM and Endpoint Removal

There is a critical race condition that most deployments ignore:

```
Problem:
  SIGTERM sent to pod at T=0
  Endpoints removal propagates across cluster at T=0 to T=2 seconds
  During that 2 second gap: load balancer may still send requests to the pod
  If your app stops accepting connections immediately on SIGTERM:
    → Requests sent during propagation lag → Connection refused → 502/503

Fix: Add a preStop sleep hook
  Pod receives SIGTERM
  preStop hook runs FIRST: sleep 5
  During those 5 seconds: endpoint removal propagates fully
  AFTER sleep: app receives SIGTERM and starts shutting down
  No requests arrive during shutdown → clean exit
```

## Complete Graceful Shutdown Deployment YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-api
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-api
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0    # Never remove old pod until new pod is Ready
      maxSurge: 1          # Create 1 extra pod during rollout
  template:
    metadata:
      labels:
        app: my-api
    spec:
      # Grace period must be longer than preStop sleep + app shutdown time
      # If terminationGracePeriodSeconds < preStop + shutdown → SIGKILL fires early
      terminationGracePeriodSeconds: 60

      containers:
        - name: api
          image: my-api:1.2.3

          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 10"]
                # sleep 10: gives kube-proxy and endpoints controller time
                # to propagate the pod removal before app stops accepting connections
                # During this sleep, app is still running and handling requests
                # After sleep, SIGTERM reaches the app process

          # Your application MUST handle SIGTERM:
          # Node.js:  process.on('SIGTERM', () => server.close(() => process.exit(0)))
          # Python:   signal.signal(signal.SIGTERM, graceful_shutdown)
          # Java:     Runtime.getRuntime().addShutdownHook(...)
          # Go:       signal.NotifyContext(ctx, syscall.SIGTERM)

          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
            failureThreshold: 3

          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 3

          startupProbe:
            httpGet:
              path: /health
              port: 8080
            failureThreshold: 30    # 30 × 10s = 5 min startup window
            periodSeconds: 10

          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "1000m"
              memory: "512Mi"
```

## Application-Level SIGTERM Handling

### Node.js

```javascript
const server = app.listen(8080);

process.on('SIGTERM', () => {
  console.log('SIGTERM received — starting graceful shutdown');

  // Stop accepting new connections
  server.close(() => {
    console.log('HTTP server closed');

    // Close database connections
    db.end(() => {
      console.log('Database connection closed');
      process.exit(0);
    });
  });

  // Force exit after 45 seconds (before SIGKILL at 60s)
  setTimeout(() => {
    console.error('Forcing exit after timeout');
    process.exit(1);
  }, 45000);
});
```

### Python (FastAPI / Flask)

```python
import signal
import sys

def graceful_shutdown(signum, frame):
    print("SIGTERM received — shutting down")
    # Close connections, flush queues
    db.close()
    cache.close()
    sys.exit(0)

signal.signal(signal.SIGTERM, graceful_shutdown)
```

### Go

```go
ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM)
defer stop()

<-ctx.Done()
log.Println("SIGTERM received — shutting down")

shutdownCtx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
defer cancel()
server.Shutdown(shutdownCtx)
```

## Timing Reference

```
terminationGracePeriodSeconds: 60   (set in pod spec)
preStop sleep:                 10s  (endpoint propagation buffer)
App shutdown time:             ~30s (close connections, flush queues)
Buffer before SIGKILL:         20s  (60 - 10 - 30 = 20s buffer)

Timeline:
  T=0:   Pod enters Terminating, preStop starts
  T=10:  preStop done, SIGTERM sent to app, endpoints fully removed
  T=40:  App finishes shutdown, exits cleanly
  T=60:  Would have been SIGKILL — but app already exited at T=40

Rule: terminationGracePeriodSeconds > preStop time + app shutdown time
```

---

# Part 2 — PodDisruptionBudget (PDB)

## What Is a PDB and Why Does It Exist

A PodDisruptionBudget is a Kubernetes resource that puts a hard limit on how many pods of a deployment can be voluntarily disrupted at the same time.

```
Without PDB:
  Engineer runs: kubectl drain node-1 (maintenance)
  Kubernetes evicts ALL pods on node-1 simultaneously
  If your deployment has 3 replicas all on node-1:
    All 3 evicted → 0 pods running → 503 for users
  Kubernetes followed your instructions exactly — your app had an outage

With PDB (minAvailable: 2):
  Engineer runs: kubectl drain node-1
  Kubernetes checks PDB: "must keep at least 2 pods running"
  Evicts Pod-1 → 2 remaining → OK (minAvailable met)
  Tries to evict Pod-2 → would leave 1 running → BLOCKED by PDB
  Drain pauses and waits until a replacement pod is Running elsewhere
  Then evicts Pod-2 → 2 remaining again → continues
  Users never see an outage
```

## PDB Configurations

### Option A — minAvailable (minimum healthy pods)

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-api-pdb
  namespace: production
spec:
  minAvailable: 2          # At least 2 pods must always be available
  selector:
    matchLabels:
      app: my-api
```

```
Deployment replicas: 3
minAvailable: 2
Max pods that can be disrupted at once: 3 - 2 = 1
→ Only 1 pod can be evicted at a time
→ Kubernetes waits for replacement before evicting another
```

### Option B — maxUnavailable (maximum down at once)

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-api-pdb
  namespace: production
spec:
  maxUnavailable: 1        # At most 1 pod can be down at any time
  selector:
    matchLabels:
      app: my-api
```

### Option C — Percentage Based

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-api-pdb
  namespace: production
spec:
  minAvailable: "75%"      # At least 75% of pods must be running
  selector:                # 3 replicas → at least 2 (75% of 3 rounded up)
    matchLabels:
      app: my-api
```

## Complete Setup — Deployment + PDB Together

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-api
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-api
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  template:
    metadata:
      labels:
        app: my-api
    spec:
      terminationGracePeriodSeconds: 60
      topologySpreadConstraints:
        # Spread pods across nodes — avoids all pods on one node
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: my-api
      containers:
        - name: api
          image: my-api:1.2.3
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 10"]
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            periodSeconds: 5
            failureThreshold: 3
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "1000m"
              memory: "512Mi"

---
# pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-api-pdb
  namespace: production
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: my-api

---
# hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-api-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-api
  minReplicas: 3          # Always 3+ replicas so PDB is meaningful
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

## PDB Verification Commands

```bash
# Check PDB status
kubectl get pdb -n production

# Output:
# NAME          MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
# my-api-pdb    2               N/A               1                     5m
#                                                 ↑ How many pods can be
#                                                   disrupted right now

# If ALLOWED DISRUPTIONS = 0:
#   PDB is blocking all voluntary disruptions
#   Usually means: replicas < minAvailable + 1
#   Fix: scale up replicas or adjust minAvailable

# Describe for detail
kubectl describe pdb my-api-pdb -n production

# Test PDB during node drain (it will block appropriately):
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data
# Watch it pause when PDB constraint would be violated
```

## Common PDB Mistakes

```
Mistake 1: minAvailable equals replicas
  replicas: 3, minAvailable: 3
  ALLOWED DISRUPTIONS = 0
  Node drain blocked completely — maintenance impossible
  Fix: minAvailable should be replicas - 1 at minimum

Mistake 2: PDB with single replica
  replicas: 1, minAvailable: 1
  ALLOWED DISRUPTIONS = 0
  Node drain impossible — PDB blocks it
  Fix: Always run at least 2 replicas for anything with a PDB

Mistake 3: PDB selector doesn't match pod labels
  PDB selector: app=api
  Pod labels:   app=backend
  PDB has no effect — wrong pods matched
  Fix: Verify with kubectl get pods --show-labels
```

---

# Part 3 — Custom Resource Definitions (CRDs)

## Why CRDs Exist

Kubernetes ships with built-in resource types: Pod, Deployment, Service, ConfigMap, Secret. These cover the core use cases. But real systems have domain-specific concepts that don't map to any built-in type.

```
Examples of things Kubernetes doesn't know about natively:
  → A database cluster with primary + replicas (not just a pod)
  → A certificate that needs renewal before it expires
  → An S3 bucket that should be created alongside an application
  → A Redis cluster with specific replication topology
  → A machine learning training job with GPU requirements

CRD solves this:
  You define a new resource type (like defining a new class in code)
  Kubernetes stores instances of that type in etcd (just like Pods)
  You write a controller (operator) that watches for those instances
  Controller acts on them: creates AWS resources, manages state, etc.

Result:
  kubectl apply -f my-s3-bucket.yaml   ← creates an S3 bucket in AWS
  kubectl get s3buckets                 ← lists all your managed buckets
  kubectl delete s3bucket my-bucket    ← deletes the bucket from AWS
  S3 bucket management feels like native Kubernetes
```

## How CRDs Work

```
STEP 1: Define the CRD (schema of your new resource type)
  → Tells Kubernetes: "a resource called S3Bucket exists with these fields"
  → After applying: kubectl api-resources | grep s3bucket → shows up

STEP 2: Write a Controller (operator)
  → A program that watches for S3Bucket resources
  → When an S3Bucket is created → calls AWS SDK to create the real S3 bucket
  → When an S3Bucket is deleted → calls AWS SDK to delete the real S3 bucket
  → Runs reconciliation loop continuously

STEP 3: Users create instances
  → kubectl apply -f my-bucket.yaml
  → Controller sees the new resource
  → Controller creates the actual S3 bucket in AWS
  → Controller updates the resource status with the bucket ARN
```

## Built-in Kubernetes Resources That ARE CRDs

You are already using CRDs without knowing it:

```
kubectl get crd
# NAME                                      CREATED AT
# externalsecrets.external-secrets.io       2024-01-10  ← ESO CRD
# secretproviderclasses.secrets-store...    2024-01-10  ← CSI CRD
# certificates.cert-manager.io             2024-01-10  ← cert-manager CRD
# ingressroutes.traefik.io                 2024-01-10  ← Traefik CRD
# prometheusrules.monitoring.coreos.com    2024-01-10  ← Prometheus Operator CRD
# helmreleases.helm.toolkit.fluxcd.io      2024-01-10  ← Flux CRD

# Every time you install ESO, cert-manager, or any operator:
# They register their CRDs first
# Then you create instances of those CRDs
# Their controllers watch and act on your instances
```

---

# Part 4 — Building Your Own CRD: S3 Bucket Manager

## What We Are Building

A complete working CRD + controller that manages S3 buckets from Kubernetes:

```
You apply:
  kubectl apply -f s3-bucket-resource.yaml

Controller sees it:
  → Creates S3 bucket in AWS
  → Enables versioning if requested
  → Sets lifecycle policies if configured
  → Updates the resource status with bucket ARN and endpoint

You delete:
  kubectl delete s3bucket my-app-bucket

Controller sees deletion:
  → Empties and deletes the S3 bucket from AWS
  → Resource removed from Kubernetes
```

## Step 1 — Define the CRD (Schema)

```yaml
# crd-s3bucket.yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: s3buckets.myorg.io          # Must be: plural.group
spec:
  group: myorg.io                    # Your API group — like apiVersion prefix
  names:
    kind: S3Bucket                   # Resource type name (singular, CamelCase)
    plural: s3buckets                # Used in URLs and kubectl
    singular: s3bucket               # kubectl get s3bucket
    shortNames:
      - s3b                          # kubectl get s3b (shortcut)
  scope: Namespaced                  # Resources exist in a namespace
  versions:
    - name: v1alpha1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required: ["bucketName", "region"]
              properties:
                bucketName:
                  type: string
                  description: "S3 bucket name (must be globally unique)"
                  minLength: 3
                  maxLength: 63
                region:
                  type: string
                  description: "AWS region where bucket will be created"
                  enum:
                    - ap-south-1
                    - us-east-1
                    - eu-west-1
                versioningEnabled:
                  type: boolean
                  default: false
                  description: "Enable S3 versioning"
                publicAccessBlocked:
                  type: boolean
                  default: true
                  description: "Block all public access (recommended)"
                lifecycleDays:
                  type: integer
                  minimum: 1
                  maximum: 3650
                  description: "Days before objects transition to Glacier"
            status:
              type: object
              properties:
                phase:
                  type: string
                  enum: [Pending, Creating, Ready, Failed, Deleting]
                bucketArn:
                  type: string
                bucketEndpoint:
                  type: string
                message:
                  type: string
                lastSyncTime:
                  type: string
      additionalPrinterColumns:
        - name: Bucket
          type: string
          jsonPath: .spec.bucketName
        - name: Region
          type: string
          jsonPath: .spec.region
        - name: Status
          type: string
          jsonPath: .status.phase
        - name: Age
          type: date
          jsonPath: .metadata.creationTimestamp
```

```bash
# Apply the CRD
kubectl apply -f crd-s3bucket.yaml

# Verify it is registered
kubectl get crd s3buckets.myorg.io

# Now Kubernetes knows about S3Bucket resources
kubectl api-resources | grep s3bucket
# NAME        SHORTNAMES   APIVERSION           NAMESPACED   KIND
# s3buckets   s3b          myorg.io/v1alpha1    true         S3Bucket
```

## Step 2 — Create an Instance (User Perspective)

```yaml
# my-app-bucket.yaml
apiVersion: myorg.io/v1alpha1
kind: S3Bucket
metadata:
  name: my-app-assets
  namespace: production
spec:
  bucketName: "my-company-app-assets-prod"
  region: "ap-south-1"
  versioningEnabled: true
  publicAccessBlocked: true
  lifecycleDays: 90          # Move to Glacier after 90 days
```

```bash
kubectl apply -f my-app-bucket.yaml

# Check status
kubectl get s3bucket my-app-assets -n production
# NAME            BUCKET                          REGION        STATUS    AGE
# my-app-assets   my-company-app-assets-prod      ap-south-1    Pending   5s

# After controller runs:
# NAME            BUCKET                          REGION        STATUS    AGE
# my-app-assets   my-company-app-assets-prod      ap-south-1    Ready     30s
```

## Step 3 — Write the Controller (Python)

```python
# controller.py
# Watches for S3Bucket resources and manages real S3 buckets in AWS

import kopf                 # Python operator framework for Kubernetes
import boto3
import logging

logger = logging.getLogger(__name__)
s3_client = boto3.client('s3')

# ─────────────────────────────────────────────
# HANDLER: S3Bucket CREATED
# Called when someone applies a new S3Bucket resource
# ─────────────────────────────────────────────
@kopf.on.create('myorg.io', 'v1alpha1', 's3buckets')
def on_create(spec, status, name, namespace, patch, **kwargs):
    bucket_name = spec['bucketName']
    region      = spec['region']
    versioning  = spec.get('versioningEnabled', False)
    block_public = spec.get('publicAccessBlocked', True)
    lifecycle_days = spec.get('lifecycleDays', None)

    logger.info(f"Creating S3 bucket: {bucket_name} in {region}")

    # Update status to Creating
    patch.status['phase'] = 'Creating'
    patch.status['message'] = f'Creating bucket {bucket_name}'

    try:
        # Step 1: Create the bucket
        if region == 'us-east-1':
            s3_client.create_bucket(Bucket=bucket_name)
        else:
            s3_client.create_bucket(
                Bucket=bucket_name,
                CreateBucketConfiguration={'LocationConstraint': region}
            )

        # Step 2: Block public access (security default)
        if block_public:
            s3_client.put_public_access_block(
                Bucket=bucket_name,
                PublicAccessBlockConfiguration={
                    'BlockPublicAcls': True,
                    'IgnorePublicAcls': True,
                    'BlockPublicPolicy': True,
                    'RestrictPublicBuckets': True
                }
            )

        # Step 3: Enable versioning if requested
        if versioning:
            s3_client.put_bucket_versioning(
                Bucket=bucket_name,
                VersioningConfiguration={'Status': 'Enabled'}
            )

        # Step 4: Add lifecycle policy if requested
        if lifecycle_days:
            s3_client.put_bucket_lifecycle_configuration(
                Bucket=bucket_name,
                LifecycleConfiguration={
                    'Rules': [{
                        'ID': 'TransitionToGlacier',
                        'Status': 'Enabled',
                        'Filter': {'Prefix': ''},
                        'Transitions': [{
                            'Days': lifecycle_days,
                            'StorageClass': 'GLACIER'
                        }]
                    }]
                }
            )

        # Step 5: Get bucket ARN and update status
        bucket_arn = f"arn:aws:s3:::{bucket_name}"
        bucket_endpoint = f"https://{bucket_name}.s3.{region}.amazonaws.com"

        patch.status['phase'] = 'Ready'
        patch.status['bucketArn'] = bucket_arn
        patch.status['bucketEndpoint'] = bucket_endpoint
        patch.status['message'] = 'Bucket created successfully'
        patch.status['lastSyncTime'] = str(kopf.datetime.datetime.utcnow())

        logger.info(f"S3 bucket {bucket_name} created successfully")

    except Exception as e:
        logger.error(f"Failed to create bucket {bucket_name}: {e}")
        patch.status['phase'] = 'Failed'
        patch.status['message'] = str(e)
        raise kopf.PermanentError(f"Bucket creation failed: {e}")


# ─────────────────────────────────────────────
# HANDLER: S3Bucket DELETED
# Called when someone deletes an S3Bucket resource
# ─────────────────────────────────────────────
@kopf.on.delete('myorg.io', 'v1alpha1', 's3buckets')
def on_delete(spec, **kwargs):
    bucket_name = spec['bucketName']

    logger.info(f"Deleting S3 bucket: {bucket_name}")

    try:
        # Must empty bucket before deleting
        bucket = boto3.resource('s3').Bucket(bucket_name)
        bucket.objects.all().delete()

        # Delete bucket
        s3_client.delete_bucket(Bucket=bucket_name)
        logger.info(f"S3 bucket {bucket_name} deleted successfully")

    except s3_client.exceptions.NoSuchBucket:
        logger.warning(f"Bucket {bucket_name} not found — already deleted")
    except Exception as e:
        logger.error(f"Failed to delete bucket {bucket_name}: {e}")
        raise kopf.TemporaryError(f"Deletion failed: {e}", delay=30)


# ─────────────────────────────────────────────
# HANDLER: S3Bucket UPDATED
# Called when spec changes (versioning toggled, lifecycle changed etc.)
# ─────────────────────────────────────────────
@kopf.on.update('myorg.io', 'v1alpha1', 's3buckets')
def on_update(spec, old, new, patch, **kwargs):
    bucket_name = spec['bucketName']

    # Check if versioning changed
    old_versioning = old['spec'].get('versioningEnabled', False)
    new_versioning = new['spec'].get('versioningEnabled', False)

    if old_versioning != new_versioning:
        status = 'Enabled' if new_versioning else 'Suspended'
        s3_client.put_bucket_versioning(
            Bucket=bucket_name,
            VersioningConfiguration={'Status': status}
        )
        logger.info(f"Versioning {status} on {bucket_name}")

    patch.status['phase'] = 'Ready'
    patch.status['lastSyncTime'] = str(kopf.datetime.datetime.utcnow())
```

## Step 4 — Controller Dockerfile

```dockerfile
# Dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN pip install kopf boto3 kubernetes

COPY controller.py .

CMD ["kopf", "run", "/app/controller.py", "--all-namespaces", "-v"]
```

```bash
# Build and push controller image
docker build -t my-registry/s3-operator:v1.0.0 .
docker push my-registry/s3-operator:v1.0.0
```

## Step 5 — Deploy the Controller to Kubernetes

```yaml
# controller-rbac.yaml
# Controller needs permission to read/write S3Bucket resources
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3-operator-sa
  namespace: s3-operator-system

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: s3-operator-role
rules:
  # Watch and update S3Bucket custom resources
  - apiGroups: ["myorg.io"]
    resources: ["s3buckets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # Update status subresource
  - apiGroups: ["myorg.io"]
    resources: ["s3buckets/status"]
    verbs: ["get", "update", "patch"]
  # Kopf needs to manage its own progress/finalizers
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create", "patch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: s3-operator-binding
subjects:
  - kind: ServiceAccount
    name: s3-operator-sa
    namespace: s3-operator-system
roleRef:
  kind: ClusterRole
  name: s3-operator-role
  apiGroup: rbac.authorization.k8s.io
```

```yaml
# controller-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: s3-operator
  namespace: s3-operator-system
spec:
  replicas: 1                       # Only 1 replica — kopf handles leader election
  selector:
    matchLabels:
      app: s3-operator
  template:
    metadata:
      labels:
        app: s3-operator
    spec:
      serviceAccountName: s3-operator-sa
      containers:
        - name: operator
          image: my-registry/s3-operator:v1.0.0
          env:
            - name: AWS_REGION
              value: "ap-south-1"
          # IAM credentials via Pod Identity or IRSA
          # The operator needs s3:CreateBucket, s3:DeleteBucket, etc.
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
```

```yaml
# controller-iam-policy.yaml (the operator needs these AWS permissions)
# Attach this policy to the operator's IAM role

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:PutBucketVersioning",
        "s3:PutBucketPublicAccessBlock",
        "s3:PutLifecycleConfiguration",
        "s3:ListBucket",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion"
      ],
      "Resource": "*"
    }
  ]
}
```

## Step 6 — Apply Everything in Order

```bash
# 1. Create namespace for the operator
kubectl create namespace s3-operator-system

# 2. Apply CRD first (must exist before creating instances)
kubectl apply -f crd-s3bucket.yaml

# 3. Verify CRD is registered
kubectl get crd s3buckets.myorg.io
# Should show: ESTABLISHED = True

# 4. Apply RBAC
kubectl apply -f controller-rbac.yaml

# 5. Deploy the controller
kubectl apply -f controller-deployment.yaml

# 6. Verify controller is running
kubectl get pods -n s3-operator-system
# NAME                        READY   STATUS    RESTARTS
# s3-operator-xxxxxxxxx-xxxx  1/1     Running   0

# 7. Check controller logs
kubectl logs -n s3-operator-system \
  -l app=s3-operator --tail=20

# Expected:
# [INFO] kopf is running
# [INFO] Watching for S3Bucket resources in all namespaces
```

## Step 7 — Use the Operator

```bash
# Create the S3Bucket resource
kubectl apply -f my-app-bucket.yaml

# Watch it in real time
kubectl get s3bucket my-app-assets -n production -w
# NAME            BUCKET                       REGION        STATUS     AGE
# my-app-assets   my-company-app-assets-prod   ap-south-1    Pending    0s
# my-app-assets   my-company-app-assets-prod   ap-south-1    Creating   2s
# my-app-assets   my-company-app-assets-prod   ap-south-1    Ready      8s

# Get full details including status
kubectl describe s3bucket my-app-assets -n production
# Status:
#   Phase: Ready
#   Bucket Arn: arn:aws:s3:::my-company-app-assets-prod
#   Bucket Endpoint: https://my-company-app-assets-prod.s3.ap-south-1.amazonaws.com
#   Message: Bucket created successfully

# Verify in AWS
aws s3 ls | grep my-company-app-assets-prod
# 2024-01-15 10:23:45 my-company-app-assets-prod

# Delete the bucket (deletes from AWS too)
kubectl delete s3bucket my-app-assets -n production
# Operator deletes objects, then deletes bucket from AWS
# Resource removed from Kubernetes
```

## Step 8 — Complete File Structure

```
s3-operator/
├── crd-s3bucket.yaml          # CRD definition — apply first
├── controller-rbac.yaml       # ServiceAccount + ClusterRole + Binding
├── controller-deployment.yaml # Operator Deployment in s3-operator-system ns
├── Dockerfile                 # Controller container image
├── controller.py              # The actual operator logic
└── examples/
    ├── dev-bucket.yaml        # Example S3Bucket for dev environment
    ├── staging-bucket.yaml    # Example for staging
    └── prod-bucket.yaml       # Example for production
```

---

## Summary — All Four Concepts Together

### Graceful Shutdown

```
preStop: sleep 10          → buffer for endpoint propagation
terminationGracePeriodSeconds: 60  → total shutdown window
App handles SIGTERM        → closes connections, flushes queues
maxUnavailable: 0          → rolling update never kills a pod before replacement is Ready
```

### PDB

```
minAvailable: 2            → node drains never take more than 1 pod at a time
Selector matches pods      → verify with kubectl get pods --show-labels
ALLOWED DISRUPTIONS > 0    → must always be > 0 for maintenance to work
Works with: kubectl drain, cluster upgrades, autoscaler scale-down
```

### CRDs

```
CustomResourceDefinition   → register a new resource type in Kubernetes
Controller/Operator        → watches CRD instances, calls external APIs
Status subresource         → controller writes back phase, ARN, errors
kubectl manages CRD        → get, describe, delete work just like built-in resources
```

### S3 Operator

```
Apply order:
  1. CRD                   → kubectl apply -f crd-s3bucket.yaml
  2. RBAC                  → kubectl apply -f controller-rbac.yaml
  3. Controller            → kubectl apply -f controller-deployment.yaml
  4. S3Bucket instance     → kubectl apply -f my-app-bucket.yaml
  5. Controller creates    → real S3 bucket in AWS via boto3
  6. kubectl delete        → controller deletes real S3 bucket from AWS
```

---

*CRDs turn Kubernetes into a control plane for anything — not just containers. Once you understand the CRD + controller pattern, every operator you install (cert-manager, ESO, Flux, ArgoCD) makes sense at a fundamental level.*
