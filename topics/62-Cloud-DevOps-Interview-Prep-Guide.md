# Cloud DevOps Engineer Interview Prep Guide
### AWS + Terraform + CI/CD + Security + Compliance + Observability

---

## Table of Contents

1. [Job Role Overview](#job-role)
2. [Topic Weightage](#topic-weightage)
3. [AWS Interview Questions](#aws-questions)
4. [Terraform Interview Questions](#terraform-questions)
5. [ECS vs EKS](#ecs-vs-eks)
6. [CI/CD Questions](#cicd-questions)
7. [Security & Compliance](#security-compliance)
8. [Observability Questions](#observability-questions)
9. [Production Scenarios](#production-scenarios)
10. [System Design Questions](#system-design)
11. [Mock Interview Answers](#mock-interview)
12. [One-Day Revision Sheet](#revision-sheet)
13. [Final Advice](#final-advice)

---

## Job Role Overview

This guide focuses on roles covering:

```
AWS Infrastructure          ← VPC, ECS, EKS, RDS, IAM
Terraform                   ← Modules, State, Drift
CI/CD Pipelines             ← GitHub Actions, Docker, ECR
Security Engineering        ← IAM, KMS, GuardDuty
Compliance                  ← HIPAA, SOC2, HITRUST
Observability               ← Prometheus, Grafana, FluentBit
Customer Cloud Deployments  ← Cross-account, AssumeRole
```

Tech stack you must know:

| Category | Tools |
|----------|-------|
| Cloud | AWS (primary), Azure (awareness) |
| IaC | Terraform, CloudFormation |
| Containers | Docker, ECS, EKS |
| CI/CD | GitHub Actions, Jenkins |
| Observability | Prometheus, Grafana, FluentBit, OpenTelemetry |
| Languages | Python, Bash |
| Security | GuardDuty, Security Hub, Macie, WAF |

---

## Topic Weightage

If you have one day to prepare, focus here:

```
Terraform                 30% ← most likely to be grilled
AWS Networking & IAM      30% ← VPC design, security groups, cross-account
CI/CD & Containers        20% ← pipeline design, Docker, ECR
Security & Compliance     15% ← HIPAA, SOC2, encryption
Observability              5% ← Prometheus, Grafana, FluentBit
```

---

## AWS Interview Questions

### Q1 — How would you design a HIPAA-compliant VPC?

**Answer:**

*"A HIPAA-compliant VPC follows strict isolation principles. The architecture has three subnet tiers — public subnets for load balancers only, private application subnets for ECS/EKS workloads, and isolated data subnets for RDS and ElastiCache. No application server or database has a public IP.*

*For data protection all storage is encrypted with KMS — RDS encryption, EBS encryption, S3 server-side encryption. Secrets are in AWS Secrets Manager, never environment variables. TLS enforced on all connections.*

*For audit and monitoring CloudTrail is enabled in all regions with log file integrity validation. VPC Flow Logs capture all network traffic. Config Rules enforce compliance — unencrypted RDS triggers an alert. GuardDuty detects threats continuously. CloudWatch alarms on root account usage, unauthorized API calls, and security group changes.*

*The key HIPAA requirements are encryption at rest, encryption in transit, audit logging, access controls, and the ability to prove data was not tampered with — all of which this architecture covers."*

```
Architecture:

Internet
    │
ALB (public subnet)
    │
ECS/EKS (private subnet — app tier)
    │
RDS Multi-AZ (data subnet — isolated)

Controls:
  KMS encryption on all data
  IAM least privilege
  Security groups: allow only required traffic
  CloudTrail + VPC Flow Logs
  Config Rules for compliance automation
  GuardDuty for threat detection
```

---

### Q2 — IAM User vs IAM Role

**Answer:**

```
IAM User:
  Permanent identity
  Long-term credentials (access key + secret)
  Used for: humans who need console or API access
  Risk: credentials can be leaked
  MFA required to reduce risk

IAM Role:
  Temporary identity
  Short-lived credentials via STS (15min - 12hr)
  Used for: EC2 instances, Lambda, ECS tasks,
            cross-account access, federated users
  No permanent credentials
  Best practice: always use roles for applications

Rule:
  Never use IAM Users for applications
  Never embed access keys in code
  Use IAM Roles attached to services
```

---

### Q3 — Why use multiple AWS accounts?

**Answer:**

```
Benefits:

1. Blast radius reduction:
   Compromised dev account cannot affect prod

2. Billing separation:
   Each team/project/customer has own bill
   Clear cost attribution

3. Security boundary:
   IAM policies in dev cannot touch prod
   SCPs apply at account level

4. Compliance isolation:
   HIPAA workloads in dedicated account
   PCI DSS scope reduction

5. Independent limits:
   Each account has own service quotas
   No cross-environment resource contention

Typical structure:
  Management Account    ← AWS Organizations, SCPs
  Shared Services       ← logging, monitoring, AD
  Development           ← developer sandboxes
  Staging               ← pre-prod testing
  Production            ← live workloads
  Customer Accounts     ← per-customer isolation
```

---

### Q4 — How does cross-account deployment work?

**Answer:**

*"For deploying into customer AWS accounts I use STS AssumeRole. The customer creates a Terraform deployment role in their account with a trust policy that allows our AWS account to assume it. We add an ExternalId condition as a security measure — this prevents confused deputy attacks where a third party tricks our service into deploying into the wrong account.*

*In Terraform I configure a provider alias with the assume_role block pointing to the customer's role ARN. Terraform automatically calls STS, gets temporary credentials, and uses those for all API calls in that account. The credentials are scoped to exactly what the role allows — nothing more.*

*This pattern scales well for multi-tenant SaaS where we deploy infrastructure into each customer's account — each customer has their own role, we assume it on demand, deploy, and the temporary credentials expire automatically."*

---

## Terraform Interview Questions

### Q1 — What are Terraform Modules?

**Answer:**

```
Modules are reusable, versioned infrastructure components.

Why modules:
  DRY — don't repeat yourself
  Consistency — same VPC pattern every time
  Version control — pin module versions
  Easier maintenance — fix once, update everywhere

Examples from production:
  module "vpc"    — VPC, subnets, NAT, routing
  module "ecs"    — ECS cluster, task def, service, ALB
  module "rds"    — RDS Multi-AZ, subnet group, SG
  module "iam"    — roles, policies, instance profiles
  module "monitoring" — CloudWatch alarms, dashboards

Structure:
  modules/
  └── vpc/
      ├── main.tf       ← resources
      ├── variables.tf  ← inputs
      ├── outputs.tf    ← outputs
      └── versions.tf   ← provider requirements

Root module calls it:
  module "prod_vpc" {
    source      = "./modules/vpc"
    cidr_block  = var.vpc_cidr
    environment = "production"
  }
```

---

### Q2 — How do you manage Terraform State?

**Answer:**

```
State must be:
  Remote       ← S3 backend, shared across team
  Locked       ← DynamoDB, prevents concurrent applies
  Encrypted    ← KMS, state contains sensitive data
  Versioned    ← S3 versioning, restore if corrupted

Backend config:
  terraform {
    backend "s3" {
      bucket         = "company-terraform-state"
      key            = "prod/terraform.tfstate"
      region         = "ap-south-1"
      encrypt        = true
      dynamodb_table = "terraform-state-lock"
    }
  }

State per environment:
  prod/terraform.tfstate
  staging/terraform.tfstate
  dev/terraform.tfstate
  Separate state files = separate blast radius

Never:
  Commit state to Git
  Use local state in a team
  Share state across unrelated environments
```

---

### Q3 — What is Terraform Drift?

**Answer:**

```
Drift = difference between Terraform state
        and actual AWS infrastructure

How it happens:
  Engineer manually changes security group
  Someone uses AWS console to resize RDS
  External process creates a resource
  Terraform state is lost or corrupted

Detection:
  terraform plan
  Shows resources that differ from state

Types of drift:
  Manual change   → terraform apply reverts it
  Missing resource → terraform apply recreates it
  Unknown resource → invisible to terraform plan
                     requires terraform import

Prevention:
  IAM policy denying direct resource changes
  SCP at organization level
  Daily scheduled terraform plan (drift detection)
  Alert when terraform plan shows changes

Response:
  Intentional drift → update .tf code to match
  Unauthorized drift → revert via terraform apply
  Document in post-mortem
```

---

### Q4 — Explain Terraform Workspace vs Separate State Files

**Answer:**

```
Workspaces:
  Same code, different state
  terraform workspace new staging
  State: s3://bucket/env:/staging/terraform.tfstate

  Pros: simple, one codebase
  Cons: easy to run apply in wrong workspace
        state files share same bucket prefix

Separate directories/state files (recommended):
  environments/
  ├── prod/
  │   ├── main.tf
  │   └── terraform.tfvars
  └── staging/
      ├── main.tf
      └── terraform.tfvars

  Pros: explicit, hard to confuse prod and staging
        separate IAM permissions per environment
        truly isolated state
  Cons: some code duplication (use modules to minimize)

Production recommendation:
  Separate directories with shared modules
  Each environment has own state file
  Each environment's pipeline uses its own IAM role
```

---

## ECS vs EKS

### When to Choose ECS

```
Choose ECS when:
  Team is AWS-focused, no Kubernetes experience
  Faster time to market is priority
  Simplicity preferred over flexibility
  AWS-native integrations are sufficient
  Small to medium team (< 50 engineers)

ECS advantages:
  Lower operational overhead
  Native ALB integration
  IAM task roles work seamlessly
  Fargate eliminates server management
  Simpler debugging (fewer moving parts)
  Faster deployment setup
```

### When to Choose EKS

```
Choose EKS when:
  Team has Kubernetes expertise
  Multi-cloud strategy (same manifests on GKE/AKS)
  Large microservices ecosystem (50+ services)
  Need Kubernetes-native tooling:
    Helm charts
    ArgoCD GitOps
    Istio service mesh
    Prometheus operator
    Custom operators

EKS advantages:
  Portability — run same workload anywhere
  Large open-source ecosystem
  Fine-grained scheduling (affinity, taints)
  Better for large teams with platform team
```

### Comparison Table

| Factor | ECS Fargate | EKS |
|--------|------------|-----|
| Learning curve | Low | High |
| AWS integration | Native and deep | Good with extra config |
| Portability | AWS only | Multi-cloud |
| Operational overhead | Minimal | Higher |
| Cost | Pay per task | Pay per node + management |
| Ecosystem | AWS services | Massive open-source |
| GitOps | Limited | ArgoCD native |
| Custom scheduling | Limited | Full control |

---

## CI/CD Questions

### Q1 — Design a Production Deployment Pipeline

```
Pipeline flow:

Developer pushes code
    │
GitHub Actions triggers
    │
Unit Tests
    │ (fail = block)
Static Analysis (SonarQube/Semgrep)
    │ (fail = block)
Dependency Scan (Snyk)
    │ (fail on CRITICAL)
Docker Build
    │
Container Scan (Trivy)
    │ (fail on CRITICAL CVE)
Push to ECR
    │
Terraform Plan
    │ (review plan)
Deploy to Staging
    │
Integration Tests
    │
OWASP ZAP DAST Scan
    │ (fail on HIGH)
Manual Approval Gate
    │
Deploy to Production
    │
Smoke Tests
    │
Monitor 15 minutes
    │
If errors → Auto Rollback
```

---

### Q2 — How do you implement Rollback?

**Answer:**

```
Method 1 — ECS Task Definition rollback:
  Each deploy creates new Task Definition revision
  Rollback = update service to previous revision
  aws ecs update-service --task-definition myapp:45
  Zero downtime with blue-green

Method 2 — Docker image tag:
  Every build tagged with git SHA
  Rollback = point to previous SHA
  kubectl set image deployment/app app=myapp:abc123

Method 3 — Blue-Green deployment:
  Blue = current production
  Green = new version
  Switch: ALB listener rule update
  Rollback: switch back to Blue instantly
  Zero downtime, instant rollback

Method 4 — Canary:
  5% traffic to new version
  Monitor error rate
  If errors > threshold → shift back to 100% old
  If OK → gradually increase to 100% new
  Limited blast radius

Recommendation:
  Blue-Green for most services
  Canary for high-risk or high-traffic services
  Always keep previous Docker image available
  Set ECS Task Definition deregistration delay
```

---

## Security & Compliance

### Q1 — How do you secure workloads for HIPAA?

```
HIPAA requires:

Encryption at rest:
  ✅ RDS storage encrypted (KMS)
  ✅ EBS volumes encrypted
  ✅ S3 server-side encryption
  ✅ Secrets in AWS Secrets Manager

Encryption in transit:
  ✅ TLS on all endpoints (ACM certificates)
  ✅ ALB HTTPS only, redirect HTTP
  ✅ Force SSL on RDS (rds.force_ssl)
  ✅ VPC endpoints for AWS services

Audit logging:
  ✅ CloudTrail all regions, log validation enabled
  ✅ VPC Flow Logs
  ✅ RDS audit logs
  ✅ Application access logs

Access controls:
  ✅ IAM least privilege
  ✅ MFA for all human users
  ✅ No hardcoded credentials
  ✅ Regular access reviews

Monitoring:
  ✅ GuardDuty enabled
  ✅ Security Hub CIS benchmark
  ✅ Config Rules for compliance
  ✅ CloudWatch alarms for security events

Business Associate Agreement:
  ✅ Signed BAA with AWS required
  ✅ Only use HIPAA-eligible services
```

---

### Q2 — What is IMDSv2?

**Answer:**

*"IMDSv2 is Instance Metadata Service Version 2. The original IMDS (v1) allowed any process on the instance — including containers and web applications — to make a simple HTTP GET request to 169.254.169.254 and retrieve instance metadata including IAM role credentials. This was exploitable via SSRF attacks — if your web application had an SSRF vulnerability, an attacker could make it fetch the metadata endpoint and steal IAM credentials.*

*IMDSv2 adds a token-based session — you must first make a PUT request to get a token, then use that token in subsequent GET requests. The PUT request cannot be made across network hops, so an SSRF vulnerability in a web application cannot be used to get the metadata token — it requires a direct request from the instance itself. I enforce IMDSv2 in Terraform using metadata_options { http_tokens = required } and at the organization level with an SCP."*

---

### Q3 — SOC2 vs HIPAA vs HITRUST

```
HIPAA (Health Insurance Portability and Accountability Act):
  What: US federal law for healthcare data protection
  Who: Healthcare providers, insurers, business associates
  Focus: PHI (Protected Health Information) security
  Enforcement: Government — fines for violations
  AWS: Must sign BAA, use HIPAA-eligible services only

SOC2 (Service Organization Control 2):
  What: Auditing standard by AICPA
  Who: Any SaaS/cloud service company
  Focus: 5 trust criteria: Security, Availability,
         Processing Integrity, Confidentiality, Privacy
  Enforcement: Audit by CPA firm, report issued
  AWS: AWS has SOC2 reports — covers infrastructure
       Your app needs its own SOC2 audit

HITRUST (Health Information Trust Alliance):
  What: Comprehensive security framework
  Who: Healthcare IT — stricter than HIPAA alone
  Focus: Risk management, combines HIPAA + SOC2 + ISO27001
  Enforcement: HITRUST certification by assessors
  AWS: AWS has HITRUST CSF certification

For most healthcare SaaS:
  HIPAA compliance is legal requirement
  SOC2 Type II is market requirement (customers ask for it)
  HITRUST is enterprise healthcare requirement
```

---

## Observability Questions

### Q1 — Explain Prometheus

**Answer:**

*"Prometheus is a pull-based metrics collection system. It scrapes HTTP endpoints that expose metrics in Prometheus format, stores them as time-series data, and allows querying with PromQL. For Kubernetes I run Prometheus via the Prometheus Operator — it uses ServiceMonitor and PodMonitor CRDs to automatically discover what to scrape based on labels.*

*I use it to track the four golden signals — latency (request duration histogram), traffic (request rate), errors (error rate), and saturation (CPU/memory utilization). AlertManager handles routing of alerts to Slack, PagerDuty, or email with deduplication and silencing."*

---

### Q2 — Explain FluentBit

**Answer:**

*"FluentBit is a lightweight log processor and forwarder. I deploy it as a DaemonSet in Kubernetes — one FluentBit pod per node — that reads container logs from /var/log/containers on the node filesystem, enriches them with Kubernetes metadata like pod name, namespace, and labels, and ships them to a centralized destination.*

*In production I send logs to CloudWatch Logs for retention and compliance, and optionally to OpenSearch for full-text search. The key benefit over Fluentd is that FluentBit uses significantly less memory — it is written in C and designed for edge and IoT, making it the right choice for DaemonSets where you run one agent per node."*

---

### Q3 — Explain OpenTelemetry

**Answer:**

*"OpenTelemetry is a vendor-neutral observability framework that provides standardized APIs and SDKs for collecting metrics, logs, and distributed traces. Instead of being locked to Datadog SDK or New Relic SDK, you instrument your code once with OTel and can export to any backend — Jaeger, Zipkin, Prometheus, CloudWatch, or a commercial vendor.*

*In practice I use OTel for distributed tracing. When a request comes into the API gateway it gets a trace ID. As it passes through microservices, each service adds a span with timing and metadata. When something is slow I look at the trace to see exactly which service took how long and where the bottleneck is. Without tracing you are guessing — with tracing you see it instantly."*

---

## Production Scenarios

### Scenario 1 — Application Response Times Spike

```
Situation: P99 latency jumps from 200ms to 3000ms

Investigation steps:

1. CloudWatch / Grafana
   Check: ECS CPU, ECS Memory, RDS connections,
          ALB target response time, request count
   Goal:  Which component is slow?

2. If ECS CPU high:
   Check: Recent deployment (did this just start?)
   Action: Roll back if recent deploy
   OR Scale out ECS tasks if traffic spike

3. If RDS metrics degraded:
   Check: DatabaseConnections, ReadLatency, CPUUtilization
   Check: Slow query log in CloudWatch
   Action: Connection pooling, query optimization,
           read replica for read traffic

4. Grafana/Prometheus traces:
   OpenTelemetry traces show exactly which
   service is slow in the call chain

5. FluentBit → CloudWatch Logs:
   Application error logs during the incident
   Look for: timeouts, connection failures, OOM

Resolution pattern:
  Immediate: Rollback or scale out to restore SLA
  Short-term: Fix root cause
  Long-term: Add better alerting to catch earlier
```

---

### Scenario 2 — Terraform Deployment Fails Midway

```
Situation: terraform apply fails halfway
           Some resources created, some not

Steps:

1. Review error message
   What failed? Which resource? Why?

2. Run terraform plan
   See what state thinks exists
   vs what code wants

3. Check partially created resources
   AWS Console or CLI
   Were any resources created before failure?

4. If resources exist but not in state:
   terraform import aws_s3_bucket.main my-bucket-name
   terraform import aws_instance.web i-0abc123

5. Fix the root cause of failure
   (IAM permission denied, resource limit, etc.)

6. Re-run terraform apply
   Terraform is idempotent
   Already created resources will show no changes
   Failed resources will be created

Prevention:
  Always run terraform plan first
  Review plan output carefully
  Test in staging before production
  Use -target to apply specific resources
  Store state in S3 with versioning (restore if corrupted)
```

---

### Scenario 3 — Deploy into Customer AWS Account

```
Situation: New customer wants their infrastructure
           in their own AWS account

Approach: Cross-account AssumeRole

1. Customer creates IAM role in their account:
   TrustPolicy: allows our AWS account to assume it
   Permissions: terraform needs to create/modify/delete

2. Customer shares role ARN with us:
   arn:aws:iam::CUSTOMER-ACCOUNT-ID:role/TerraformRole

3. We configure Terraform provider:
   provider "aws" {
     assume_role {
       role_arn     = var.customer_role_arn
       external_id  = var.external_id
     }
   }

4. CI/CD pipeline:
   Each customer has their own pipeline
   Pipeline assumes customer role
   Deploys into their account
   State stored in customer's S3 OR our central state

5. Ongoing operations:
   Updates go through same AssumeRole flow
   Customer retains full control of their account
   We deploy but cannot exceed role permissions
```

---

## System Design Questions

### Design a Multi-Tenant HIPAA-Compliant SaaS Platform

```
Requirements:
  Multiple customers
  Data isolation
  HIPAA compliance
  99.9% availability

Architecture:

Option A — Shared infrastructure, logical isolation:
  Single ECS cluster
  Tenant ID in all data
  Row-level security in RDS
  Pros: cost efficient
  Cons: harder to prove isolation for HIPAA

Option B — Separate VPC per customer (recommended for HIPAA):
  Each customer has own VPC
  Own RDS instance
  Own S3 bucket
  Own KMS key
  Pros: strong isolation, easy compliance proof
  Cons: higher cost, more infrastructure to manage

Option C — Separate AWS account per customer:
  Maximum isolation
  Separate billing
  Separate compliance scope
  Required for largest enterprise customers

Production recommendation:
  Start with Option B (separate VPC)
  Move to Option C (separate account) for
  enterprise customers with strict requirements

AWS services:
  ALB → tenant routing by subdomain
  ECS Fargate → application tier (no servers to patch)
  RDS PostgreSQL Multi-AZ → per-tenant or per-region
  KMS → per-customer key
  Secrets Manager → per-tenant secrets
  CloudTrail → per-account audit trail
  GuardDuty + Security Hub → threat detection
```

---

### Design a Secure CI/CD Platform

```
Requirements:
  Automated deployment
  Security scanning at every stage
  Rollback support
  Compliance evidence generation

Architecture:

Code Repository: GitHub
  Branch protection on main
  Required reviews + status checks
  Signed commits

CI Stages (GitHub Actions):
  1. Secret detection (detect-secrets, gitleaks)
  2. SAST (SonarQube, Semgrep)
  3. Dependency scan (Snyk)
  4. Docker build
  5. Container scan (Trivy)
  6. IaC scan (tfsec, Checkov)
  7. Push to ECR (only if all gates pass)

CD Stages:
  1. Terraform validate + plan
  2. Deploy to staging
  3. Integration tests
  4. DAST (OWASP ZAP)
  5. Manual approval (optional)
  6. Deploy to production (blue-green)
  7. Smoke tests
  8. Automatic rollback on failure

Compliance evidence:
  SonarQube reports archived per build
  Trivy CVE reports in S3
  ZAP scan reports in S3
  CloudTrail records all deployments
  All artifacts traceable to commit SHA
```

---

## Mock Interview Answers

### Tell Me About a Terraform Project

*"I built a complete Terraform module library for our platform team. The library included modules for VPC (with multi-AZ subnets, NAT gateways, VPC endpoints), ECS clusters with Fargate support, RDS with Multi-AZ and encryption, IAM roles with least-privilege policies, and a monitoring module with CloudWatch dashboards and alarms.*

*State was managed in S3 with DynamoDB locking, encryption with KMS, and versioning enabled. We used separate state files per environment — prod, staging, dev — each with their own S3 key and DynamoDB lock table. Deployment was automated through GitHub Actions — every PR runs terraform plan, the plan is posted as a PR comment, and merge to main triggers terraform apply.*

*The impact was significant — infrastructure provisioning went from 4 hours of manual work to 15 minutes, and we eliminated configuration drift because all changes go through code review."*

---

### Describe a Production Issue You Resolved

*"We experienced elevated P99 latency during peak traffic — users were seeing 3-4 second response times on what should be a 200ms API.*

*I opened Grafana and immediately saw ECS task CPU was at 95% across all tasks. Prometheus showed the spike started at 14:23, which coincided exactly with a deployment 20 minutes earlier. I checked the ECS service events and saw the new task definition was deployed at 14:21.*

*I rolled back to the previous task definition immediately — response times dropped to normal within 2 minutes. Then I investigated the root cause. OpenTelemetry traces showed that a database query introduced in the new version was performing a full table scan on a 50M row table without using an index. The developer had tested with the dev database which had 1000 rows — it was instant. In production the same query took 800ms.*

*The fix was adding a database index and running EXPLAIN ANALYZE to verify query plan. We also added a query performance test in the CI pipeline using production-like data volumes, and added a P99 latency alarm in CloudWatch to catch regressions before users notice."*

---

## One-Day Revision Sheet

### AWS

```
VPC:
  Public subnet = route to IGW
  Private subnet = route to NAT
  Security group = stateful, instance level
  NACL = stateless, subnet level
  VPC Flow Logs, CloudTrail for audit

IAM:
  Users = humans, long-term credentials
  Roles = services/apps, temporary credentials
  Policies = JSON documents defining permissions
  Least privilege always
  MFA for all humans

ECS:
  Task Definition = container blueprint
  Service = desired count + load balancer
  Fargate = serverless, no EC2 to manage
  Task Role = IAM permissions for the container

RDS:
  Multi-AZ = synchronous standby for HA
  Read Replica = asynchronous copy for read scaling
  Parameter Group = DB engine configuration
  Option Group = additional DB features
```

### Terraform

```
terraform init    → download providers
terraform plan    → preview changes
terraform apply   → create/update resources
terraform destroy → delete resources
terraform import  → bring existing resource into state

state            → tracks what Terraform manages
remote backend   → S3 + DynamoDB for team use
workspace        → multiple states from same code
module           → reusable infrastructure component
variable         → input to module or root
local            → computed value inside module
output           → export value from module
data source      → read existing AWS resource
```

### Compliance Quick Reference

```
HIPAA:
  PHI = Protected Health Information
  BAA = Business Associate Agreement (must sign with AWS)
  Requires: encryption at rest + transit, audit logs,
            access controls, breach notification

SOC2:
  5 Trust Criteria: Security, Availability,
  Processing Integrity, Confidentiality, Privacy
  Type I = design assessment at a point in time
  Type II = operational effectiveness over 6-12 months
  Your app needs its own audit (AWS SOC2 covers infra)

HITRUST CSF:
  Combines HIPAA + SOC2 + ISO 27001 + PCI DSS
  Required by large healthcare enterprise customers
  More controls than HIPAA alone
```

---

## Final Advice

```
What separates strong candidates:

1. Terraform + AWS Networking
   Most candidates know services
   Few can confidently design:
     Secure VPC architecture
     Cross-account deployment patterns
     Terraform module structure
     State management at scale

2. Security thinking built in
   Don't just say "add security"
   Be specific:
     "IMDSv2 required"
     "Object Lock Compliance for HIPAA"
     "SCP to prevent disabling GuardDuty"

3. Production scenarios
   Every answer should reference
   something you actually did
   Use the STAR format:
     Situation, Task, Action, Result

4. Compliance is a technical problem
   HIPAA/SOC2/HITRUST have specific
   technical requirements
   Know what they are and how
   you implement them in AWS/Terraform

5. Observability is the glue
   Every design should include:
     CloudWatch alarms
     Prometheus metrics
     FluentBit log collection
     OpenTelemetry tracing
   Show you care about post-deployment
   not just deployment

Practice saying answers out loud
Time each answer (target: 60-90 seconds)
Have a specific example for every topic
```

---

*References: AWS Well-Architected Framework | Terraform Best Practices | HIPAA AWS Whitepaper | CIS AWS Foundations Benchmark | OWASP DevSecOps Guideline*
