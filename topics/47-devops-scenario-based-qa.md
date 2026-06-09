# DevOps Scenario-Based Interview Q&A: Senior Level

## The Questions That Test Real Production Experience

---

Scenario-based interviews don't test what you've memorized. They test what you've actually done — or what you'd do when things go wrong at 2 AM. Every question in this article is drawn from real senior DevOps and SRE interviews at product companies and cloud-native teams.

The format: scenario first, then the answer a senior engineer gives — not textbook, but production-tested thinking.

---

## Section 1 — CI/CD Pipeline Scenarios

### Q: Your Jenkins pipeline is running fine for 3 months. Today it fails at the Docker build step with "no space left on device." What do you do?

**Immediate fix:**
```bash
# Jenkins agent / build server is out of disk space
# Docker build layers, old images, and dangling volumes pile up over time

# Step 1: Check disk usage
df -h
du -sh /var/lib/docker/*

# Step 2: Clean up Docker aggressively
docker system prune -af --volumes
# Removes: stopped containers, unused images, build cache, unused volumes

# Step 3: Check Jenkins workspace
ls -lah /var/jenkins_home/workspace/
# Old build workspaces pile up — delete unused ones

# Step 4: Immediate relief
docker image prune -af     # Remove all unused images
docker volume prune -f     # Remove unused volumes
docker builder prune -af   # Remove all build cache
```

**Permanent fix:**
```bash
# Add scheduled Docker cleanup to cron on build agents
0 2 * * * docker system prune -af --volumes >> /var/log/docker-cleanup.log 2>&1

# Or in Jenkins — add a post-build step to clean workspace
post {
  always {
    cleanWs()              // Clean workspace after every build
    sh 'docker system prune -f'  // Clean dangling images
  }
}

# Long-term: Separate build cache volume, monitor disk with CloudWatch
# Alert at 70% disk usage — not 99%
```

---

### Q: CI/CD pipeline deploys to ECS. After deployment, the new task definition is registered but old tasks are still running. What's happening?

```bash
# Cause: ECS service update not triggered, or update triggered but
# minimum healthy percent prevents termination of old tasks

# Step 1: Check ECS service desired vs running
aws ecs describe-services \
  --cluster production \
  --services my-app-service \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount,deployments:deployments}'

# Output shows 2 deployments active simultaneously:
# deployments:
#   - status: PRIMARY   taskDef: my-app:42   runningCount: 0   (new)
#   - status: ACTIVE    taskDef: my-app:41   runningCount: 3   (old — still running)

# Cause 1: minimumHealthyPercent = 100
# ECS won't stop old tasks until new tasks are healthy
# If new tasks are failing health checks → old tasks never stop → old code runs

# Diagnosis:
aws ecs describe-services --cluster production --services my-app-service \
  --query 'services[0].deploymentConfiguration'
# minimumHealthyPercent: 100  maximumPercent: 200

# Fix: Ensure new tasks pass ALB health checks
# Check target group health in ALB console

# Cause 2: Pipeline registered new task def but never called update-service
aws ecs update-service \
  --cluster production \
  --service my-app-service \
  --task-definition my-app:42 \
  --force-new-deployment    # Forces replacement of running tasks
```

---

### Q: GitLab CI pipeline takes 45 minutes. Team wants it under 10 minutes. How do you approach this?

```bash
# Step 1: Profile the pipeline — find where time is actually spent
# Check GitLab pipeline timing breakdown in UI
# Common time sinks:

# Problem 1: npm install / pip install runs from scratch every time
# Fix: Cache dependencies between pipeline runs
cache:
  key:
    files:
      - package-lock.json      # Cache key changes only when deps change
  paths:
    - node_modules/
    - .npm/

# Problem 2: Docker build doesn't use layer cache
# Fix: Pull previous image as cache source
before_script:
  - docker pull $CI_REGISTRY_IMAGE:latest || true

build:
  script:
    - docker build
        --cache-from $CI_REGISTRY_IMAGE:latest
        --tag $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
        --tag $CI_REGISTRY_IMAGE:latest .

# Problem 3: Jobs run sequentially that could run in parallel
# Fix: Use parallel stages
stages: [test, build, deploy]

unit-tests:
  stage: test
  parallel: 3          # Run 3 parallel test jobs

lint:
  stage: test          # Runs in parallel with unit-tests

# Problem 4: Running all tests even for small changes
# Fix: Only run affected tests
test:
  only:
    changes:
      - src/**/*       # Only run if src/ changed
      - tests/**/*

# Problem 5: Building image on every commit including non-main branches
# Fix: Only build/push image on main branch or tags
build-image:
  only:
    - main
    - tags
```

---

### Q: ArgoCD shows application as "Synced" but pods are running old code. How?

```bash
# ArgoCD "Synced" means: Git state matches Kubernetes object spec
# It does NOT mean: pods are running the new image

# Scenario: Deployment YAML uses :latest tag
# ArgoCD syncs → kubectl apply → Kubernetes sees no diff (same tag)
# No new rollout triggered → old pods keep running

# Verify:
kubectl get pods -n production -o jsonpath=\
'{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].imageID}{"\n"}{end}'
# Shows SHA256 digest → compare with ECR to confirm which image is running

# Fix 1: Use commit SHA as image tag (never :latest)
# In GitLab CI:
- docker build -t myapp:$CI_COMMIT_SHA .
# ArgoCD detects tag change in YAML → triggers real rollout

# Fix 2: Use image updater (ArgoCD Image Updater)
# Automatically updates image tag in Git when new image pushed to ECR
# ArgoCD then syncs the updated YAML → real rollout

# Fix 3: Force rollout even when spec hasn't changed
# Add annotation that changes every deploy:
kubectl patch deployment my-app -p \
  '{"spec":{"template":{"metadata":{"annotations":{"deploy-time":"'$(date +%s)'"}}}}}'
# Changes the pod template → Kubernetes triggers rollout
```

---

## Section 2 — Kubernetes Production Scenarios

### Q: Node is showing "NotReady" in a production cluster. What's your process?

```bash
# Step 1: Understand the scope
kubectl get nodes
# Which node? How many are NotReady?

# Step 2: Check what's running on that node
kubectl get pods --all-namespaces --field-selector spec.nodeName=<node-name>
# Are critical workloads on this node? Are they being rescheduled?

# Step 3: Check node conditions
kubectl describe node <node-name>
# Look for Conditions:
#   Ready: False   Reason: KubeletNotReady
#   MemoryPressure: True
#   DiskPressure: True
#   NetworkUnavailable: True

# Step 4: SSH into the node (or use SSM Session Manager)
aws ssm start-session --target <instance-id>

# Step 5: Check kubelet status
systemctl status kubelet
journalctl -u kubelet -n 100 --no-pager
# Common errors:
#   "failed to run Kubelet: node not found" → node registration issue
#   "PLEG is not healthy" → Pod Lifecycle Event Generator issue, restart kubelet
#   "failed to garbage collect" → disk pressure

# Step 6: Check disk
df -h
# /var/lib/docker full? Container logs filling up?

# Step 7: Restart kubelet if safe to do so
systemctl restart kubelet
systemctl status kubelet

# If node is stuck and workloads are rescheduling elsewhere:
kubectl cordon <node-name>         # Prevent new pods from scheduling here
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data           # Safely evict all pods
# Then: terminate and replace the EC2 instance (if managed node group, AWS does this)
```

---

### Q: Your application has a memory leak. Pods OOMKill every 6 hours. You can't fix the code today. What do you do?

```bash
# Immediate mitigation while the code fix is being worked on:

# Option 1: Increase memory limit (buys time, doesn't fix leak)
kubectl patch deployment my-app -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"app","resources":{"limits":{"memory":"1Gi"}}}]}}}}'

# Option 2: Schedule periodic restarts (restart before OOMKill happens)
# Using kubectl rollout restart on a schedule via CronJob:
apiVersion: batch/v1
kind: CronJob
metadata:
  name: app-restart
spec:
  schedule: "0 */4 * * *"     # Every 4 hours (before 6hr OOMKill)
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: restart
            image: bitnami/kubectl:latest
            command:
            - kubectl
            - rollout
            - restart
            - deployment/my-app
            - -n
            - production

# Option 3: Add HPA to scale out when memory climbs
# More pods = each pod hits limit later (buys more time)

# Option 4: Add liveness probe with memory threshold
# Custom /healthz that returns 503 when memory > 80% of limit
# Kubernetes restarts the pod gracefully before OOMKill
# This gives the pod time to drain connections before restart

# Monitoring — alert BEFORE the OOMKill:
# CloudWatch/Prometheus alert: memory > 75% of limit for 10 minutes
# Gives you advance warning to act
```

---

### Q: You need to roll out a breaking database schema change to a 15-microservice system. How do you plan this?

```
This is a senior architect question. The right answer involves:

Phase 1 — Expand (backward-compatible change):
  Add new column (nullable or with default value)
  Old code: ignores new column, works fine
  New code: reads/writes new column if present
  Both versions can run simultaneously

Phase 2 — Migrate:
  Deploy new version of each service (one at a time)
  Run data backfill job to populate new column for existing rows
  Both old and new services still running

Phase 3 — Contract (cleanup):
  All services now on new version
  Make column NOT NULL (all rows have data now)
  Remove old column in the NEXT release (not this one)
  Old code is fully gone before you remove what it relied on

Rules:
  Never DROP a column in the same release you stop using it
  Never RENAME a column — add new, copy data, remove old (3 releases)
  Never add NOT NULL without a default or backfill
  Test migration on production-sized dataset — 10M rows takes different time than 100K

Tools:
  Flyway / Liquibase for versioned, tracked migrations
  Run migrations in CI/CD BEFORE the new code deployment
  Always have a rollback script for each migration
```

---

### Q: Kubernetes cluster upgrade from 1.27 to 1.29. Walk me through your process.

```bash
# Never skip minor versions in Kubernetes — go 1.27 → 1.28 → 1.29

# Phase 1: Pre-upgrade checks
kubectl version                          # Current versions
kubectl get nodes                        # Node health
kubectl get pods -A | grep -v Running    # Any unhealthy pods?

# Check deprecated APIs
kubectl-convert -f deployment.yaml --output-version apps/v1
# Or use: kubent (Kubernetes No Trouble) tool
kubent                                   # Scans for deprecated API usage

# Phase 2: Upgrade control plane (EKS managed)
aws eks update-cluster-version \
  --name production-cluster \
  --kubernetes-version 1.28
# Wait for control plane upgrade (15-20 minutes)
aws eks wait cluster-active --name production-cluster

# Phase 3: Upgrade add-ons (kube-proxy, CoreDNS, VPC CNI)
aws eks update-addon --cluster-name production-cluster \
  --addon-name kube-proxy --addon-version v1.28.x-eksbuild.1

# Phase 4: Upgrade node groups (one at a time)
# DO NOT upgrade all node groups simultaneously

# Cordon old nodes, let workloads move to new version nodes
aws eks update-nodegroup-version \
  --cluster-name production-cluster \
  --nodegroup-name workers \
  --kubernetes-version 1.28

# Phase 5: Verify after each node group upgrade
kubectl get nodes                        # All nodes on new version?
kubectl get pods -A                      # All pods running?
kubectl rollout status deployment --all-namespaces

# Phase 6: Repeat for 1.28 → 1.29
```

---

## Section 3 — AWS Infrastructure Scenarios

### Q: RDS CPU is at 95%. Application is degraded. What are your immediate and long-term actions?

```bash
# IMMEDIATE (restore service first):

# Step 1: Identify the killing queries
# Connect to RDS via RDS Proxy or Bastion
# MySQL:
SHOW PROCESSLIST;
SHOW FULL PROCESSLIST;
# Look for: long-running queries, locked queries, sleeping connections

# Kill the offending query
KILL QUERY <process_id>;

# PostgreSQL:
SELECT pid, now() - query_start AS duration, query, state
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY duration DESC;

SELECT pg_terminate_backend(<pid>);

# Step 2: Check CloudWatch — what spiked CPU?
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --period 300 \
  --statistics Average \
  --start-time $(date -d '2 hours ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --dimensions Name=DBInstanceIdentifier,Value=production-db

# Step 3: Reduce load immediately
# Add RDS Read Replica for read traffic (if not already)
# Point reporting/analytics queries to replica

# LONG-TERM:

# 1. Enable Performance Insights — identifies top SQL by wait time
# 2. Enable slow query log
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 1;  # Log queries > 1 second

# 3. Add missing indexes (most common CPU cause)
EXPLAIN ANALYZE SELECT ... FROM orders WHERE user_id = 123;
# If "Seq Scan" on large table → add index

# 4. Add RDS Proxy — pools connections, prevents connection storms
# 5. Move to Aurora — better auto-scaling, read replicas built-in
# 6. Cache repeated expensive queries with ElastiCache Redis
```

---

### Q: S3 bucket accidentally made public. Security team is alerted. What's your response?

```bash
# IMMEDIATE — lock it down in under 60 seconds

# Step 1: Block all public access immediately
aws s3api put-public-access-block \
  --bucket compromised-bucket \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,\
    BlockPublicPolicy=true,RestrictPublicBuckets=true

# Step 2: Remove public ACL
aws s3api put-bucket-acl --bucket compromised-bucket --acl private

# Step 3: Check what was exposed (CloudTrail logs)
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=compromised-bucket \
  --start-time $(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%SZ)
# Who accessed it? From where? What files?

# Step 4: Check S3 access logs
aws s3 cp s3://logging-bucket/compromised-bucket/ ./logs/ --recursive
# Identify which objects were accessed, from which IPs

# Step 5: Assess data sensitivity
# Was it PII? Payment data? Credentials?
# If yes → trigger breach response plan, legal/compliance team

# PREVENT RECURRENCE:

# AWS Config rule — alert on any S3 bucket made public
aws configservice put-config-rule --config-rule '{
  "ConfigRuleName": "s3-bucket-public-read-prohibited",
  "Source": {
    "Owner": "AWS",
    "SourceIdentifier": "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
}'

# SCP (Service Control Policy) — prevent public S3 at org level
# Even if admin tries to make bucket public, SCP blocks it

# Terraform: enforce private by default
resource "aws_s3_bucket_public_access_block" "all_buckets" {
  bucket = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

---

### Q: Your application's costs doubled this month. How do you investigate and fix it?

```bash
# Step 1: Identify the biggest cost change
aws ce get-cost-and-usage \
  --time-period Start=2024-12-01,End=2025-01-01 \
  --granularity MONTHLY \
  --group-by Type=DIMENSION,Key=SERVICE \
  --metrics BlendedCost

# Open AWS Cost Explorer → Group by Service → Sort by cost change

# Common culprits:
# EC2: Instances scaled out and didn't scale back in
# Data Transfer: Cross-AZ traffic, NAT Gateway charges
# RDS: Switched from Reserved to On-Demand (RI expired)
# S3: Storage grew, or Glacier retrieval charges spiked
# CloudWatch: Log volume explosion

# Step 2: Drill into the biggest offender
# If EC2:
aws ec2 describe-instances --query \
  'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`].Value]' \
  --output table
# Find: Running instances you don't recognize

# If Data Transfer:
# Check NAT Gateway bytes out — cross-AZ traffic is $0.01/GB each way
# Move EC2 and RDS to same AZ for high-throughput paths

# If CloudWatch Logs:
aws logs describe-log-groups \
  --query 'logGroups[*].[logGroupName,storedBytes]' \
  --output table | sort -k2 -n -r | head -20
# Find log groups with no retention policy — set 30-day retention

# Step 3: Immediate actions
# Tag everything → attribute cost to teams
aws ec2 create-tags --resources <instance-id> \
  --tags Key=Team,Value=backend Key=Environment,Value=production

# Delete/stop unused resources
# EC2 < 5% CPU for 2 weeks → right-size or stop
# RDS dev instances → stop outside business hours (RDS can be stopped 7 days)

# Savings Plans — immediate commitment for running workloads
aws ce create-savings-plans-purchase-recommendation \
  --savings-plans-type COMPUTE_SP \
  --term-in-years ONE_YEAR \
  --payment-option NO_UPFRONT \
  --lookback-period-in-days THIRTY_DAYS
```

---

## Section 4 — Monitoring and Observability Scenarios

### Q: Alert fires at 3 AM: "API latency p99 > 5 seconds." Walk through your investigation.

```bash
# p99 > 5s means 1 in 100 requests is taking > 5 seconds — severe degradation

# Step 1: Establish timeline — when did it start?
# Check Grafana/CloudWatch → latency graph → when did p99 spike?
# Did it coincide with a deployment? Traffic spike? Cron job?

# Step 2: Is it all endpoints or specific ones?
# Grafana: filter by route/endpoint
# CloudWatch: filter ALB logs by request_processing_time

# Step 3: Is it all pods or specific ones?
kubectl top pods -n production
# One pod at 950m/1000m CPU → throttled → slow

# Check if specific nodes are slow
kubectl top nodes

# Step 4: Check X-Ray / distributed traces
# X-Ray service map → which service in the chain is slow?
# Common: DB query slow, Redis miss, external API timeout

# Step 5: Database investigation
# Check RDS CloudWatch: ReadLatency, WriteLatency, DatabaseConnections
# Connection pool exhausted? Add RDS Proxy

# Step 6: Check for lock contention
SHOW FULL PROCESSLIST;
# "Waiting for table metadata lock" → table-level lock from migration or long transaction

# Step 7: Immediate mitigation
# Scale out ECS tasks (more containers = more concurrent request handling)
aws ecs update-service \
  --cluster production \
  --service my-api \
  --desired-count 8    # Was 4 → doubled

# If DB is the bottleneck → route reads to read replica immediately
```

---

### Q: Prometheus is scraping correctly but Grafana dashboard shows "No data" for the last hour. What happened?

```bash
# Step 1: Is Prometheus itself healthy?
kubectl get pods -n monitoring | grep prometheus
kubectl logs prometheus-server-xxx -n monitoring | tail -50

# Step 2: Is the data in Prometheus?
# Open Prometheus UI (port-forward):
kubectl port-forward svc/prometheus-server 9090:80 -n monitoring

# Query directly: http://localhost:9090
# Enter: up{job="my-app"}
# No results = scrape target is down

# Step 3: Check scrape targets
# Prometheus UI → Status → Targets
# Look for: State: DOWN, Error: "connection refused" or "context deadline exceeded"

# Step 4: Check if pods have correct annotations
kubectl get pod <pod-name> -o yaml | grep -A5 annotations
# Required annotations for Prometheus scraping:
# prometheus.io/scrape: "true"
# prometheus.io/port: "8080"
# prometheus.io/path: "/metrics"

# Step 5: Is it a Grafana datasource issue?
# Grafana → Configuration → Data Sources → Prometheus → Test
# "Data source connected" = Grafana can reach Prometheus
# If not connected → Prometheus service endpoint changed?

# Step 6: Is it a time range issue?
# Grafana dashboard time range set to "last 1 hour"
# Prometheus retention is only 15 days by default
# But if time range in dashboard is in the future → no data (timezone mismatch)

# Step 7: Check Prometheus storage
kubectl exec -it prometheus-server-xxx -n monitoring -- df -h /data
# If disk full → Prometheus stops writing → no new data
```

---

## Section 5 — Security and Compliance Scenarios

### Q: Your team accidentally committed an AWS access key to a public GitHub repo. What do you do?

```bash
# This is a security incident. Move fast — bots scan GitHub in minutes.

# WITHIN MINUTES:

# Step 1: Revoke the key immediately
aws iam delete-access-key \
  --access-key-id AKIAIOSFODNN7EXAMPLE \
  --user-name cicd-user
# Key is now invalid — any attacker holding it is locked out

# Step 2: Check if the key was used maliciously
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=AKIAIOSFODNN7EXAMPLE \
  --start-time $(date -d '48 hours ago' -u +%Y-%m-%dT%H:%M:%SZ)
# Look for: unusual regions, EC2 launches, IAM changes, S3 access

# Step 3: Check for unauthorized resources
aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,Region,Tags]'
# Were any EC2 instances launched (crypto mining)?
aws s3 ls   # Any new buckets?

# Step 4: Rotate all related credentials
# If the key was for a service account:
# Rotate the key (not just delete — delete + create new)
aws iam create-access-key --user-name cicd-user
# Update the new key in: GitHub Secrets, CI/CD environment, Vault

# Step 5: Remove from Git history (won't help if already public but do it)
git filter-branch --force --index-filter \
  'git rm --cached --ignore-unmatch path/to/credentials.file' HEAD
git push origin --force --all

# LONG-TERM PREVENTION:
# Pre-commit hook — scan for secrets before commit
pip install detect-secrets
detect-secrets scan > .secrets.baseline
# Add to pre-commit:
# - repo: https://github.com/Yelp/detect-secrets
#   hooks: [{id: detect-secrets}]

# Use OIDC instead of long-term access keys in CI/CD
# Replace access keys with IAM roles assumed via OIDC — no key to leak
```

---

### Q: Audit team says you need to prove that no unauthorized changes were made to production infrastructure in the last 90 days. How?

```bash
# CloudTrail is your answer — it logs every AWS API call

# Step 1: Query CloudTrail for infrastructure changes
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=ModifyDBInstance \
  --start-time 2024-10-01T00:00:00Z \
  --end-time 2025-01-01T00:00:00Z

# Events to check for unauthorized changes:
# EC2: RunInstances, TerminateInstances, ModifyInstanceAttribute
# IAM: CreateUser, AttachUserPolicy, CreateAccessKey
# S3: PutBucketAcl, DeleteBucket, PutBucketPolicy
# VPC: AuthorizeSecurityGroupIngress (opening ports)
# RDS: ModifyDBInstance, DeleteDBInstance

# Step 2: Cross-reference with change management
# Every API call in CloudTrail has: who, what, when, from where
# Compare CloudTrail events with your JIRA/ServiceNow change tickets
# If a CloudTrail event has no corresponding change ticket = unauthorized

# Step 3: AWS Config history
aws configservice get-resource-config-history \
  --resource-type AWS::EC2::SecurityGroup \
  --resource-id sg-0abc123 \
  --start-time 2024-10-01T00:00:00Z
# Shows exact configuration at any point in time + what changed

# Step 4: Terraform — if IaC is your source of truth
# Every terraform apply is committed to Git
# Git log shows exactly what changed, when, by whom
# Any AWS resource that doesn't match Terraform state = unauthorized change
terraform plan   # Drift = evidence of unauthorized change

# Step 5: Export evidence
# CloudTrail logs → S3 → Athena query → CSV report for auditors
```

---

## Section 6 — High Availability and Disaster Recovery Scenarios

### Q: One AWS AZ goes down. Walk through what happens to your architecture and what manual steps (if any) are needed.

```bash
# Well-designed architecture: mostly automatic

# What AWS handles automatically:
# ALB:     Stops routing to unhealthy targets in failed AZ
#          Routes all traffic to healthy AZs (may see latency spike)
# ECS:     Tasks in failed AZ marked unhealthy
#          ECS service scheduler places replacement tasks in healthy AZs
#          (requires: desiredCount > 1, multi-AZ subnet config)
# RDS:     Multi-AZ → automatic failover to standby in another AZ
#          Typically < 60 seconds, connection string stays same
# NAT GW:  If only one NAT GW → private subnets lose internet
#          Fix: One NAT GW per AZ

# What may need manual intervention:
# ElastiCache: If primary node in failed AZ → automatic failover to replica
#              But: read replicas in failed AZ need to be recreated
# EKS Nodes:   Spot instances in failed AZ → ASG replaces in other AZs
#              But: may take 5-10 minutes → workloads temporarily reduced capacity

# Your job during AZ failure:
# 1. Confirm it's AWS, not your code
aws health describe-events --filter '{"eventStatusCodes":["open","upcoming"]}'

# 2. Watch ECS/EKS service recovery
watch kubectl get pods -n production
watch aws ecs describe-services --cluster prod --services my-service

# 3. Scale up capacity in remaining AZs (preemptive)
aws ecs update-service --cluster prod --service my-service --desired-count 8
# Was running 6 (2 per AZ × 3 AZ) → now 8 split across 2 AZs

# 4. Communicate status to stakeholders
# 5. Document timeline for postmortem
```

---

## Key Takeaways

- **Restore first, investigate second** — in any production incident, user impact reduction comes before root cause analysis
- **CloudTrail is your audit log, X-Ray is your trace log, Prometheus is your metrics** — know which tool answers which question
- **Multi-AZ is not enough** — you also need one NAT Gateway per AZ, ECS tasks distributed across AZs, and RDS Multi-AZ enabled
- **Commit SHA as image tag** — eliminates an entire class of CI/CD bugs where :latest delivers the wrong version
- **Database migrations are separate from application deployments** — deploy schema changes backward-compatibly before deploying new code
- **Security incidents have a clock** — bots scan public GitHub repos in minutes; revoke first, investigate second
- **Cost investigation starts with the biggest line item** — don't optimize S3 when EC2 Reserved Instance expired and costs tripled
- **kubectl rollout status --timeout** belongs in every CI/CD pipeline — it's the difference between "deployed" and "working"

---

*These scenarios are drawn from real production systems. The best preparation is building and breaking your own infrastructure — every incident you debug teaches you more than any documentation.*
