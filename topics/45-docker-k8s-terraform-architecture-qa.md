# Docker, Kubernetes, Terraform & Architecture: Advanced Q&A and Scenario-Based Guide

## The Questions That Separate Senior Engineers from the Rest

---

Most engineers can explain what Docker is. Fewer can explain why a container with a running process still shows as unhealthy. Most engineers know Kubernetes runs containers. Fewer can explain why a deployment rollout hangs at 50% and how to unblock it without downtime.

This article covers the advanced, scenario-based questions that come up in senior DevOps, SRE, and Cloud Engineer interviews — and in production at 2 AM. Each section opens with the concept, then moves into the real questions that test deep understanding.

---

## Part 1 — Docker: Advanced Q&A

### What is the difference between CMD and ENTRYPOINT?

Both define what runs when a container starts — but they behave differently when you pass arguments at runtime.

```dockerfile
# ENTRYPOINT — always runs, cannot be overridden by docker run args
ENTRYPOINT ["nginx", "-g", "daemon off;"]

# CMD — default args, overridden by anything you pass to docker run
CMD ["-p", "80"]

# Together — ENTRYPOINT is the command, CMD is default args
ENTRYPOINT ["python", "app.py"]
CMD ["--port", "8080"]

# Override at runtime:
docker run myapp --port 9090
# Runs: python app.py --port 9090  (CMD overridden, ENTRYPOINT kept)
```

**Interview answer:** ENTRYPOINT defines the executable — it always runs. CMD defines default arguments — they can be overridden at runtime. Use ENTRYPOINT for the main process and CMD for default arguments that callers might want to change.

---

### What happens when you run `docker build` — layer by layer?

```
Dockerfile:
FROM node:18          → Layer 1: Pull base image (cached after first pull)
WORKDIR /app          → Layer 2: Set working directory
COPY package*.json .  → Layer 3: Copy package files
RUN npm install       → Layer 4: Install dependencies (EXPENSIVE — cache this)
COPY . .              → Layer 5: Copy source code (changes every build)
CMD ["node", "app.js"]→ No layer — metadata only

Key insight: Each RUN, COPY, ADD creates a new layer.
             Docker caches layers. If Layer 3 doesn't change,
             Layer 4 (npm install) uses cache — much faster builds.

Wrong order:
  COPY . .              → Layer 3: Copies everything (changes every build)
  RUN npm install       → Layer 4: NEVER cached — npm install runs every time

Right order:
  COPY package*.json .  → Layer 3: Only changes when dependencies change
  RUN npm install       → Layer 4: Cached until package.json changes
  COPY . .              → Layer 5: Source code (changes every build, but npm install cached)
```

---

### Scenario: Your Docker image is 2.1 GB. How do you reduce it?

This is a real problem — large images mean slow CI/CD, slow deployments, and large attack surface.

**Step 1 — Use a smaller base image:**
```dockerfile
# Before: 900MB base
FROM node:18

# After: 180MB base
FROM node:18-alpine
```

**Step 2 — Multi-stage builds (most impactful):**
```dockerfile
# Stage 1: Build (has compilers, build tools — heavy)
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build          # Produces /app/dist

# Stage 2: Runtime (only what's needed to run)
FROM node:18-alpine AS runtime
WORKDIR /app
COPY --from=builder /app/dist ./dist      # Copy only compiled output
COPY --from=builder /app/node_modules ./node_modules
CMD ["node", "dist/server.js"]

# Result: Build stage discarded. Final image = runtime stage only.
# Before: 2.1 GB   After: 180 MB
```

**Step 3 — Clean up in the same RUN layer:**
```dockerfile
# ❌ Wrong — creates layer with cache, then another layer deleting it
RUN apt-get update && apt-get install -y curl
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# ✅ Right — single layer, cache never written to final image
RUN apt-get update && apt-get install -y curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
```

---

### Scenario: Container runs fine locally but crashes in production with "permission denied"

```
Root cause: Container running as root locally, production enforces non-root (securityContext)

Diagnosis:
  kubectl describe pod <name>
  # Error: container has runAsNonRoot=true but image will run as root

Fix in Dockerfile:
  RUN addgroup -S appgroup && adduser -S appuser -G appgroup
  USER appuser                    # Switch to non-root user

Fix in Kubernetes (securityContext):
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000               # UID 1000, not root (0)
    readOnlyRootFilesystem: true  # Extra hardening
```

---

### What is the difference between COPY and ADD in Dockerfile?

```
COPY:  Simply copies files/directories from host into image
       Transparent — does exactly what it says
       Preferred for most use cases

ADD:   Like COPY but with extra powers:
       - Can extract .tar.gz automatically into the image
       - Can fetch files from URLs (not recommended — use curl + cache control)

Best practice: Always use COPY unless you specifically need ADD's tar extraction.
               ADD from URLs skips cache and is unpredictable.
```

---

### Scenario: Docker container exits immediately after starting

```bash
# Debug steps:
docker ps -a                    # See exited containers with exit code
docker logs <container-id>      # See what happened before exit
docker inspect <container-id>   # Full config, exit code, OOMKilled flag

# Common causes:
Exit 0:  Process completed normally (it's a script, not a daemon)
         Fix: Make sure CMD runs a foreground process, not a script that exits
Exit 1:  Application error — check docker logs for exception
Exit 137: OOMKilled — container exceeded memory limit
           Fix: docker run -m 512m (increase memory)
Exit 127: Command not found — wrong CMD or ENTRYPOINT path

# Common mistake — running background process:
CMD ["nginx"]                   # nginx forks to background, PID 1 exits → container stops
CMD ["nginx", "-g", "daemon off;"]   # nginx stays foreground → container stays up
```

---

### How does Docker networking work — bridge, host, overlay?

```
Bridge (default):
  Each container gets its own IP on a virtual bridge network (172.17.0.0/16)
  Containers on same bridge can communicate
  Port must be published (-p 8080:80) for external access
  Use for: single-host, most use cases

Host:
  Container shares the host's network namespace
  No NAT, no port publishing needed — container uses host ports directly
  Use for: performance-critical apps, when you need host network speed
  Risk: no network isolation between container and host

Overlay:
  Spans multiple Docker hosts (Swarm/Kubernetes)
  Containers on different hosts can communicate as if on same network
  Use for: multi-host deployments, Kubernetes pod networking
  Kubernetes uses a CNI plugin (Calico, Flannel, Cilium) to implement this
```

---

## Part 2 — Kubernetes: Advanced Q&A

### Scenario: Deployment is stuck — rollout shows 50% updated, not progressing

```bash
# Check rollout status
kubectl rollout status deployment/my-app
# Output: Waiting for rollout to finish: 2 out of 4 new replicas updated...

# Check what's blocking it
kubectl get pods
# You see: 2 pods Running (old), 2 pods CrashLoopBackOff (new version)

# New version is crashing → rollout pauses (Kubernetes won't kill old pods
# if new pods aren't healthy — this is the safety mechanism working correctly)

# Debug the new pods
kubectl logs <new-crashing-pod>
kubectl describe pod <new-crashing-pod>

# Options:
# 1. Fix the bug, push a new image, rollout continues automatically
# 2. Roll back immediately:
kubectl rollout undo deployment/my-app

# Check rollout history
kubectl rollout history deployment/my-app
# Roll back to specific version:
kubectl rollout undo deployment/my-app --to-revision=3
```

**Why this happens:** Kubernetes `maxUnavailable` and `maxSurge` settings in the deployment strategy control how many pods can be updated at once. Default is 25%/25% — so for 4 replicas, it updates 1 at a time, checking health before proceeding.

---

### What is the difference between Deployment, StatefulSet, and DaemonSet?

```
Deployment:
  - Pods are identical and interchangeable
  - Any pod can die and be replaced with a new one, different IP is fine
  - Random pod names: my-app-7d4f8b-xkp2q
  - Use for: stateless apps — web servers, APIs, workers

StatefulSet:
  - Pods have stable identity (persistent hostname, stable storage)
  - Pods start in order (pod-0 before pod-1), scale down in reverse
  - Stable pod names: my-db-0, my-db-1, my-db-2
  - Each pod gets its own PVC — data is NOT shared between pods
  - Use for: databases (MySQL, MongoDB, Kafka, Zookeeper) — anything with state

DaemonSet:
  - Runs EXACTLY ONE pod on every node (or matching nodes)
  - When new node joins cluster, DaemonSet pod automatically created on it
  - When node removed, pod is deleted
  - Use for: log collectors (Fluentd), monitoring agents (Prometheus Node Exporter),
             security agents, CNI plugins (Calico, Flannel run as DaemonSet)
```

---

### Scenario: HPA (Horizontal Pod Autoscaler) is configured but pods are not scaling

```bash
# Check HPA status
kubectl get hpa
# Output: my-app   Deployment/my-app   cpu: 85%/50%   2/2/10   ... TARGETS: <unknown>

# <unknown> in TARGETS means metrics-server is not installed or not working

# Step 1: Check if metrics-server is running
kubectl get pods -n kube-system | grep metrics-server

# Step 2: If missing, install it
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Step 3: Verify metrics are flowing
kubectl top pods
kubectl top nodes

# Step 4: Check HPA events
kubectl describe hpa my-app
# Look for: "failed to get cpu utilization" or "unable to fetch metrics"

# Step 5: Ensure pods have resource REQUESTS set (HPA needs this to calculate %)
kubectl get pod <pod-name> -o yaml | grep -A5 resources
# resources.requests.cpu MUST be set — HPA calculates % against this value
# If requests.cpu is missing → HPA cannot calculate utilization → no scaling
```

**Key insight:** HPA scales based on `current usage / requested amount`. If `requests.cpu` is not set on the pod, HPA has no baseline to calculate percentage against — it will never trigger.

---

### What is a ConfigMap vs Secret — and when does each get updated in a running pod?

```
ConfigMap:  Non-sensitive configuration (feature flags, config files, env vars)
            Stored in plain text in etcd
            Mounted as volume or injected as env vars

Secret:     Sensitive data (passwords, API keys, TLS certs)
            Stored base64-encoded in etcd (not encrypted by default — enable KMS)
            Same mounting options as ConfigMap

Update behavior — CRITICAL difference:

Mounted as VOLUME:
  ConfigMap/Secret update → kubelet detects change → file updated in pod
  Delay: up to 2 minutes (kubelet sync period)
  App must re-read the file to pick up changes (not all apps do this)

Injected as ENV VAR:
  ConfigMap/Secret update → NOTHING happens to running pods
  Env vars are set at container start — they NEVER update in a running container
  Fix: Rolling restart → kubectl rollout restart deployment/my-app
```

---

### Scenario: Pod is running but application returns 503 — service is up but backend is not

This is one of the most common mid-production issues. See the dedicated troubleshooting file for the complete step-by-step — but the Kubernetes-specific causes are:

```
Kubernetes causes of 503 from a running pod:

1. Readiness probe failing → pod excluded from endpoints → 503 from ALB/ingress
   Check: kubectl get endpoints <service>  → empty?
   Fix:   Fix probe path/port/initialDelaySeconds

2. All pods in CrashLoopBackOff → 0 healthy endpoints → 503
   Check: kubectl get pods → restarts count
   Fix:   kubectl logs --previous → find crash reason

3. Resource limits hit → pod throttled → requests timing out → 503
   Check: kubectl top pod → near limits?
   Fix:   Increase limits or add HPA

4. Ingress misconfiguration → routing to wrong service/port → 503
   Check: kubectl describe ingress <name> → backend service + port
   Fix:   Correct serviceName and servicePort in ingress rules
```

---

### How does Kubernetes handle rolling updates and what controls the speed?

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1    # Max pods that can be unavailable during update
      maxSurge: 1          # Max extra pods that can be created above desired count

# Example: 4 replicas, maxUnavailable: 1, maxSurge: 1
# Desired: 4 pods

Step 1: Create 1 new pod (total: 5 — surge of 1)
Step 2: New pod passes health checks
Step 3: Terminate 1 old pod (total: 4)
Step 4: Repeat until all 4 are new version

# If new pod fails health checks:
  Kubernetes stops the rollout (doesn't kill more old pods)
  You have a mix of old (working) + new (failing) pods
  Traffic still goes to old pods → partial service maintained
  kubectl rollout undo → rolls back automatically
```

---

### What is the difference between a ClusterIP, NodePort, and LoadBalancer service?

```
ClusterIP (default):
  Internal IP only — reachable only from within the cluster
  Use for: service-to-service communication (backend → database)

  Client (inside cluster) → ClusterIP:80 → Pod

NodePort:
  Opens a port (30000–32767) on every node
  External traffic: NodeIP:NodePort → Service → Pod
  Use for: development, on-premises without cloud load balancer
  Problem: Exposes a random high port, requires knowing node IPs

LoadBalancer:
  Creates a cloud provider load balancer (AWS ALB/NLB, GCP LB, Azure LB)
  External traffic → Cloud LB → NodePort → Service → Pod
  Use for: production workloads needing external access
  One LoadBalancer per service = expensive at scale (use Ingress instead)

Ingress (not a service type — a routing layer):
  One LoadBalancer → Ingress Controller → routes by path/host to multiple services
  /api/* → backend-service
  /     → frontend-service
  Use for: production, multiple services behind one load balancer
```

---

### Scenario: kubectl apply works but pods keep using old image

```bash
# Symptom: You updated the deployment with new image tag,
# kubectl apply succeeded, but pods are still running old version

# Cause 1: You used :latest tag and imagePullPolicy defaults to IfNotPresent
# Kubernetes pulled the image once, cached it, never pulls again
kubectl get pod <pod> -o yaml | grep -A3 imagePullPolicy
# Shows: imagePullPolicy: IfNotPresent  ← won't re-pull if image exists

# Fix: Use explicit version tags (never :latest in production)
image: myapp:1.2.3    # Not myapp:latest

# Or force re-pull:
imagePullPolicy: Always   # Pulls on every pod start (slower deployments)

# Cause 2: Deployment wasn't actually updated — same image tag
kubectl rollout history deployment/my-app
# If image tag didn't change, Kubernetes sees no diff → no rollout triggered

# Force a rolling restart without changing the image:
kubectl rollout restart deployment/my-app
```

---

### What is etcd and what happens if it goes down?

```
etcd is Kubernetes' brain — a distributed key-value store that holds:
  - All cluster state (pods, services, deployments, configmaps, secrets)
  - Node registrations
  - Current desired vs actual state

If etcd goes down:
  ✗ kubectl commands fail — API server cannot read/write state
  ✗ New pods cannot be scheduled — scheduler has no state
  ✗ New services cannot be created
  ✓ EXISTING running pods continue to run — kubelet runs independently
  ✓ Existing services continue routing traffic

Think of it like this:
  etcd down = control plane blind
  But the workers (nodes) keep doing what they were last told to do

Recovery:
  Restore from etcd snapshot:
  etcdctl snapshot restore /backup/etcd-snapshot.db
  Always back up etcd before cluster upgrades!
```

---

## Part 3 — Terraform: Advanced Q&A

### Scenario: `terraform apply` is destroying resources you didn't expect it to touch

```bash
# Always run plan first and read it carefully
terraform plan -out=tfplan

# Output shows:
# -/+ aws_instance.web (forces replacement)
#   ~ instance_type = "t3.micro" -> "t3.small"   # Just a change, no destroy
#   - tags.Name = "old-name"                      # Tag removal
#   + tags.Name = "new-name"                      # Tag addition

# Symbols:
# + = create
# - = destroy
# ~ = update in place (no destroy)
# -/+ = destroy and recreate (replacement — the dangerous one)
# <= = data source read

# Common causes of unexpected destroy:
# 1. Changed a resource argument that forces replacement (e.g., EC2 AZ, RDS engine)
# 2. Renamed a resource in .tf file (Terraform sees old=delete, new=create)
# 3. Moved resource to a module without terraform state mv

# Fix for rename — use moved block (Terraform 1.1+):
moved {
  from = aws_instance.web
  to   = aws_instance.web_server   # Rename without destroy/recreate
}
```

---

### What is Terraform state and what happens if two people apply at the same time?

```
Terraform state tracks the mapping between:
  Your .tf config (desired) ↔ Real AWS resources (actual)

Without state: Terraform cannot know what already exists
               Every apply would try to create everything again

Race condition — two engineers apply simultaneously:
  Engineer A: reads state → plans → applies (creates resource)
  Engineer B: reads state → plans → applies (tries to create same resource)
  Result: Duplicate resources, state corruption, or errors

Fix — DynamoDB state locking:
  terraform {
    backend "s3" {
      bucket         = "my-tfstate"
      key            = "prod/terraform.tfstate"
      region         = "ap-south-1"
      dynamodb_table = "terraform-locks"   # Acquires lock before apply
    }
  }

  When Engineer A runs apply:
    DynamoDB lock acquired → apply runs
  When Engineer B runs apply simultaneously:
    "Error: Error acquiring the state lock"
    Engineer B waits until A finishes — no corruption
```

---

### Scenario: Resource was manually changed in AWS console — how does Terraform handle it?

```bash
# Someone manually changed an EC2 security group in the console
# Your .tf file still has the old rules

terraform plan
# Output:
# ~ aws_security_group.web
#   + ingress: 0.0.0.0/0:443  (in .tf, not in AWS — Terraform will add it)
#   - ingress: 0.0.0.0/0:8080 (in AWS, not in .tf — Terraform will remove it)

# Terraform always makes AWS match your .tf files — manual changes get overwritten

# If you want to IMPORT the manual change into Terraform state:
terraform import aws_security_group.web sg-0abc123def456
# Now state reflects reality — plan shows no changes

# If you want to IGNORE certain attributes (not recommended):
resource "aws_instance" "web" {
  lifecycle {
    ignore_changes = [tags, user_data]   # Terraform ignores drift on these
  }
}
```

---

### What is the difference between terraform taint and terraform destroy?

```
terraform destroy:
  Destroys ALL resources managed by the current config/workspace
  Nuclear option — use with extreme caution in production

terraform taint <resource>:  (deprecated in Terraform 1.0+)
  Marks ONE specific resource for destruction + recreation on next apply
  Replacement for: terraform apply -replace=<resource>

# Modern approach — force replace one resource:
terraform apply -replace="aws_instance.web"

# Use case: EC2 instance is in bad state, you want to recreate just that one
# Without touching anything else in your infrastructure
```

---

### Scenario: Terraform plan shows no changes but AWS resource is different — why?

```
Terraform only knows about attributes it manages in state.

Causes:
1. Attribute not tracked by Terraform provider
   Some AWS resource attributes are not reflected in Terraform state
   The provider simply doesn't read that field back from AWS

2. ignore_changes lifecycle rule
   lifecycle { ignore_changes = [tags] }
   → Terraform intentionally ignores drift on those attributes

3. Data sources are always re-read but not managed
   data "aws_ami" "latest" { ... } — Terraform reads it but doesn't manage it

4. Resource created outside Terraform
   Terraform has no knowledge of it — it doesn't appear in plan at all
   Fix: terraform import to bring it under management

# How to detect all drift:
terraform plan -refresh-only
# Shows what changed in AWS vs Terraform state, without proposing changes
```

---

### How do you manage multiple environments (dev/staging/prod) in Terraform?

```
Option 1: Workspaces (simple, same backend)
  terraform workspace new staging
  terraform workspace new production
  terraform workspace select production
  terraform apply
  # Each workspace has separate state — same code, different state file

  Limitation: All environments share same backend config, same module versions
  Best for: Small teams, simple environments

Option 2: Separate directories (recommended for production)
  environments/
  ├── dev/
  │   ├── main.tf       # References shared modules
  │   └── terraform.tfvars  # dev-specific values
  ├── staging/
  │   ├── main.tf
  │   └── terraform.tfvars
  └── production/
      ├── main.tf
      └── terraform.tfvars

  Benefits: Completely isolated state, different module versions per env,
            blast radius limited — a bad apply in dev never touches prod

Option 3: Terragrunt (DRY wrapper)
  Eliminates repeated backend config across environments
  Single source of truth for module versions
  Best for: Large teams managing many environments
```

---

## Part 4 — Architecture: Advanced Scenario Q&A

### Scenario: Your monolithic application handles 10,000 users fine. At 100,000 users it crashes. What do you do?

This is a system design + architecture question. Walk through it layer by layer:

```
Step 1 — Identify the bottleneck (don't guess):
  CloudWatch metrics: Is it CPU? Memory? Database connections? Network?
  Application APM (X-Ray): Which endpoint/query is slow?
  Database: Is query time high? Connection pool exhausted?

Step 2 — Scale the bottleneck (not everything):
  Web tier:     Add more EC2/ECS instances behind ALB (horizontal scale)
  Database:     Add RDS read replicas for read-heavy workloads
  Session:      Move sessions to ElastiCache Redis (stateless EC2)
  Cache:        Add Redis for repeated expensive queries
  Static files: Move to S3 + CloudFront (remove from app server)

Step 3 — Medium-term architecture changes:
  Connection pooling: RDS Proxy (prevents DB connection exhaustion)
  Async operations:   Move email, notifications, reports to SQS + Lambda
  Database sharding:  If single RDS is the ceiling, shard by user_id range

Step 4 — Long-term (if monolith is the fundamental problem):
  Extract highest-load services as microservices first
  Don't rewrite everything — identify and extract the hot path
```

---

### Scenario: You need to design a system that processes 1 million image uploads per day

```
Requirements analysis:
  1M images/day = ~11.5 images/second average
  Peak could be 10x = 115 images/second

Architecture:

User uploads → API Gateway / ALB
                     │
                     ▼
              Lambda / ECS API
              - Validate file (type, size)
              - Generate pre-signed S3 URL
                     │
              Return pre-signed URL to client
                     │
User uploads directly to S3 (bypasses your servers — no bandwidth cost)
                     │
S3 Event Notification → SQS Queue
                     │
              Lambda Worker Pool
              - Download from S3
              - Resize / compress / watermark
              - Store processed versions in S3
              - Update DynamoDB (metadata, status)
                     │
CloudFront serves processed images globally

Why this design:
  ✓ Pre-signed S3 upload: Client uploads directly to S3, your servers never handle image bytes
  ✓ SQS decouples upload from processing: S3 spikes don't crash processing
  ✓ Lambda workers: Auto-scales to processing demand
  ✓ CloudFront: Images served globally from edge, not origin
  ✓ DynamoDB: Handles high-throughput metadata reads/writes
```

---

### How do you design for zero-downtime deployments?

```
Application level:
  Blue/Green:     Two identical environments, switch DNS/LB in seconds
  Canary:         Route 5% → 10% → 50% → 100% gradually, monitor error rate
  Rolling update: Replace pods one at a time (Kubernetes default)

Database level (hardest part):
  The application must be backward compatible with both old AND new schema
  during the deployment window

  Step 1: Add new column (nullable, with default) — old code ignores it, works
  Step 2: Deploy new code that reads new column if present
  Step 3: Backfill data in new column
  Step 4: Make column NOT NULL (now safe — all rows have data)
  Step 5: Remove old column in future release

  Never:  DROP COLUMN before old code is fully gone
  Never:  RENAME COLUMN in a single deployment

Infrastructure level:
  Health checks on all instances before routing traffic
  Connection draining on ALB (let existing connections finish before removing target)
  readinessProbe on Kubernetes (pod not ready = no traffic routed to it)
  Feature flags: Deploy code with feature disabled, enable via config without deploy
```

---

### What is the CAP theorem and how does it affect database choice?

```
CAP Theorem: A distributed system can guarantee at most 2 of 3:

C — Consistency:    Every read receives the most recent write
A — Availability:   Every request receives a response (not necessarily latest data)
P — Partition Tolerance: System continues operating even if network splits occur

In practice: Network partitions WILL happen. You must choose C or A.

CP (Consistency + Partition Tolerance):
  Returns error if it can't guarantee consistency
  Examples: HBase, MongoDB (with majority write concern), ZooKeeper
  Use for: Financial systems, inventory (cannot show wrong balance/stock)

AP (Availability + Partition Tolerance):
  Returns best available (possibly stale) data — never errors
  Examples: Cassandra, CouchDB, DynamoDB (eventually consistent reads)
  Use for: Social feeds, analytics, shopping carts (stale data acceptable)

AWS context:
  RDS (Strong consistency):  CP — returns error if replica can't confirm
  DynamoDB (default):        AP — eventually consistent reads by default
  DynamoDB (strong reads):   CP — reads always from primary, higher cost
  ElastiCache:               AP — Redis replication is async, stale reads possible
```

---

## Key Takeaways

- **Docker layers are your build cache** — order your Dockerfile from least-changing to most-changing
- **Multi-stage builds** are the single biggest image size reduction technique available
- **Kubernetes rollout safety** — Kubernetes won't remove healthy old pods if new pods are failing — use this safety net, don't fight it
- **HPA needs resource requests** — without `requests.cpu`, HPA cannot calculate utilization percentage and will never scale
- **ConfigMap env vars don't hot-reload** — rolling restart is required when injecting config as environment variables
- **Terraform state locking is non-negotiable in teams** — S3 + DynamoDB, always
- **Database migrations are the hardest part of zero-downtime deployments** — always make changes backward-compatible across at least one release cycle
- **CAP theorem is practical, not theoretical** — your database choice for each service should be consciously CP or AP based on what the business requires

---

*Found this useful? Follow for more advanced DevOps and cloud engineering content — next up: The Complete 503 Troubleshooting Guide for production incidents at 2 AM.*
