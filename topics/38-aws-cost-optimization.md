# AWS Cost Optimization: Cut Your AWS Bill Without Cutting Performance

## The $1 Million Mistake Most Teams Make on AWS

---

AWS bills are easy to ignore until they aren't. A startup pays $500/month and doesn't think twice. Six months later, the same architecture with more traffic costs $8,000/month. Nobody changed anything intentionally — the bill just grew, silently, predictably, and largely avoidably.

Cost optimization is not about being cheap. It's about being intentional — paying for what you use, not for what you forgot to turn off.

---

## Why AWS Bills Grow Uncontrollably

The three main culprits:

**1. Right-sizing neglect** — you launched with t3.xlarge "to be safe" and never revisited it even though the instance runs at 12% CPU.

**2. Idle resources** — dev environments running at weekends, test databases nobody uses, old snapshots piling up for years.

**3. Wrong purchasing model** — paying On-Demand prices for workloads that have been running 24/7 for 18 months.

---

## EC2 Pricing Models — This is Where Most Money is Saved

### On-Demand
Pay by the hour or second with no commitment.
```
Cost:       Full price — highest per-hour rate
Commitment: Zero
Best for:   Unpredictable workloads, short-term experiments, dev/test
```

### Reserved Instances (RI)
Commit to 1 or 3 years in exchange for a significant discount.
```
1-year commitment:   up to 40% discount vs On-Demand
3-year commitment:   up to 60% discount vs On-Demand

Payment options:
  All Upfront:      Largest discount
  Partial Upfront:  Medium discount
  No Upfront:       Smallest discount, no capital required

Best for: Production workloads running 24/7 — databases, always-on app servers
```

### Savings Plans
Like Reserved Instances but more flexible — commit to a dollar amount of spend per hour, not a specific instance type:

```
Compute Savings Plans:  Applies to EC2, Lambda, Fargate — any instance type, any region
EC2 Savings Plans:      Specific instance family, specific region

Example: "I commit to $0.10/hour of compute"
→ AWS gives you up to 66% discount on any EC2 or Fargate usage up to that amount
```

Savings Plans are almost always better than Reserved Instances for modern workloads because they're flexible across instance types.

### Spot Instances
Use spare AWS capacity at up to 90% discount — but AWS can reclaim the instance with 2-minute notice.

```
On-Demand t3.large:   $0.0832/hour
Spot t3.large:        $0.0124/hour  (~85% cheaper)

Best for:
  ✅ Batch processing (data pipelines, image processing)
  ✅ CI/CD build servers
  ✅ Dev/test workloads
  ✅ Stateless workers in an ASG (replace with new spot if interrupted)

Not for:
  ❌ Databases
  ❌ Stateful applications
  ❌ Anything that cannot tolerate sudden interruption
```

### The Mixed Strategy — What Mature Teams Do

```
Production Web Servers:   70% Reserved/Savings Plan + 30% On-Demand buffer
Background Workers:       100% Spot Instances (can tolerate interruption)
Database (RDS):           Reserved Instances (always running)
Dev/Test:                 On-Demand (shut down nights/weekends)
Lambda:                   Compute Savings Plan (covers Lambda too)
```

---

## Right-Sizing EC2 Instances

AWS Compute Optimizer analyzes CloudWatch metrics and recommends right-sized instances:

```
Current:   m5.2xlarge  (8 vCPU, 32 GB RAM)  — $0.384/hr
Actual use: 15% CPU, 25% memory average

Recommendation: m5.large (2 vCPU, 8 GB RAM) — $0.096/hr
Savings: $0.288/hr = $2,522/year per instance
```

Common right-sizing moves:
- Oversized EC2 → smaller instance type
- General purpose → compute/memory optimized (better fit, often cheaper)
- x86 → ARM Graviton (same workload, 20–40% cheaper, often better performance)

### AWS Graviton — The Hidden Gem

Graviton is AWS's custom ARM-based processor. For most web workloads:

```
m5.large (Intel x86):    $0.096/hr
m6g.large (Graviton ARM): $0.077/hr   (20% cheaper, often faster)

Graviton supports: EC2, RDS, ElastiCache, Lambda, ECS, EKS
```

If your application runs on Linux (it almost certainly does), Graviton is a near-free performance and cost win.

---

## S3 Cost Optimization

### S3 Storage Classes

```
S3 Standard:              Frequently accessed data         — $0.023/GB
S3 Standard-IA:           Infrequently accessed (>1/month) — $0.0125/GB (45% cheaper)
S3 One Zone-IA:           Non-critical, single AZ          — $0.01/GB
S3 Glacier Instant:       Archive, retrieved in ms          — $0.004/GB
S3 Glacier Flexible:      Archive, retrieved in minutes     — $0.0036/GB
S3 Glacier Deep Archive:  Long-term archive, 12hr retrieval — $0.00099/GB
```

### S3 Lifecycle Policies — Automate Cost Savings

```
Day 0:    Object uploaded → S3 Standard
Day 30:   Move to S3 Standard-IA    (accessed rarely after 30 days)
Day 90:   Move to S3 Glacier        (archived)
Day 365:  Move to Glacier Deep Archive or Delete
```

Lifecycle policies are free to configure and can save 70–90% on storage for logs, backups, and old data.

### S3 Intelligent-Tiering

AWS automatically moves objects between access tiers based on actual usage patterns — no lifecycle rules needed:

```
Frequently accessed  → Standard tier (no cost reduction)
Not accessed 30 days → IA tier (40% savings)
Not accessed 90 days → Archive Instant (68% savings)
Not accessed 180 days→ Deep Archive (95% savings)
```

Monitoring fee: $0.0025 per 1,000 objects/month. Worth it for unpredictable access patterns.

---

## RDS Cost Optimization

### Reserved Instances for RDS

Production databases are always running — Reserved Instances are almost always the right choice:

```
RDS db.t3.medium On-Demand:    $0.068/hr = $595/year
RDS db.t3.medium 1-yr RI:      $0.043/hr = $377/year (37% savings)
RDS db.t3.medium 3-yr RI:      $0.028/hr = $245/year (59% savings)
```

### RDS Aurora Serverless v2 — Pay Per Use

For databases with variable or unpredictable load, Aurora Serverless v2 scales compute in fine-grained increments:

```
Low traffic:   0.5 ACUs (Aurora Capacity Units) — minimum compute, minimum cost
High traffic:  128 ACUs — scales up automatically in seconds
Idle:          Pauses completely (Aurora Serverless v1 only) — $0 compute cost when idle
```

For dev and staging databases that sit idle most of the day, Aurora Serverless can be 80% cheaper than provisioned.

---

## Data Transfer Costs — The Hidden Bill

Data transfer is the sneaky cost most engineers miss:

```
Within same AZ:          FREE
Between AZs (same region): $0.01/GB each direction
Between regions:          $0.02–$0.09/GB
To internet:              $0.085–$0.09/GB (first 10 TB/month)
From internet (inbound):  FREE
```

### How to Reduce Data Transfer Costs

**Use VPC Endpoints for S3/DynamoDB** — traffic stays inside AWS, no NAT Gateway or internet data transfer charges.

**Use CloudFront** — instead of serving data directly from S3 or EC2 to the internet, CloudFront's data transfer rates are lower and the cache reduces origin calls.

**Keep traffic within the same AZ when possible** — design application tiers to prefer same-AZ communication.

```
EC2 in AZ-1 → RDS in AZ-1:  FREE
EC2 in AZ-1 → RDS in AZ-2:  $0.01/GB both directions
```

This is why RDS Multi-AZ reads should use read replicas in the same AZ as the application.

---

## Idle Resource Cleanup

### The Most Common Waste

```
Idle EC2 instances:    Running but <5% CPU for weeks — delete or stop
Unattached EBS volumes: EC2 terminated, volume left behind — $0.10/GB/month
Old snapshots:         Piling up for years — implement retention policies
Unused Elastic IPs:    $0.005/hr when not attached to a running instance
Unused Load Balancers: ALBs with no targets — $0.008/hr minimum
Forgotten NAT Gateways: Left running in unused VPCs — $0.045/hr
Old AMIs:              Hundreds of old machine images — deregister and delete snapshots
```

### AWS Cost Explorer — Your Best Friend

Cost Explorer shows exactly where your money is going:

```
Filter by:  Service, Region, Tag, Account, Instance Type
Group by:   Service (see EC2 vs RDS vs S3 breakdown)
Time range: Daily, monthly, quarterly
Forecast:   Predicts next month's bill based on current usage
```

Set up **AWS Budgets** to alert before overspending:
```
Budget: $500/month
Alert at 80% ($400) → email warning
Alert at 100% ($500) → urgent Slack alert
Alert at 120% ($600) → page on-call engineer
```

### Tagging — The Foundation of Cost Visibility

Without tags, you cannot allocate costs to teams, projects, or environments:

```
Required tags for every resource:
  Environment: production / staging / development
  Team:        backend / frontend / data / platform
  Project:     checkout / user-service / analytics
  Owner:       team-lead-email@company.com
```

Use AWS Config rule `required-tags` to alert on untagged resources automatically.

---

## Savings Checklist

```
EC2
✅ Savings Plans or RIs for all production instances running >6 months
✅ Spot Instances for batch processing and CI/CD workers
✅ Graviton (ARM) instances where possible
✅ Compute Optimizer recommendations reviewed monthly

S3
✅ Lifecycle policies on all buckets with aging data
✅ Intelligent-Tiering for unpredictable access patterns
✅ S3 Storage Lens for per-bucket cost visibility

RDS
✅ Reserved Instances for all production databases
✅ Aurora Serverless for dev/staging databases
✅ Automated backups retention set to minimum needed (not 35 days for dev)

Data Transfer
✅ VPC Endpoints for S3 and DynamoDB
✅ CloudFront for internet-facing content
✅ Same-AZ communication for hot data paths

Hygiene
✅ Idle EC2 instances stopped or terminated
✅ Unattached EBS volumes deleted
✅ EBS snapshot retention policy in place
✅ All resources tagged by environment and team
✅ AWS Budgets configured with alerts
✅ Cost Explorer reviewed weekly
```

---

## Key Takeaways

- **Savings Plans beat On-Demand for anything running >6 months** — the discount is too large to ignore
- **Spot Instances for stateless workers** — batch processing, CI/CD, and auto-scaling groups can save 85%
- **Graviton is a near-free upgrade** — 20–40% cheaper for the same workload on Linux
- **S3 Lifecycle Policies are free money** — automate tiering to Glacier for old data
- **Data transfer costs are invisible until they're not** — VPC Endpoints and CloudFront pay for themselves
- **Tags are the foundation** — you cannot optimize what you cannot attribute
- **AWS Budgets + Cost Explorer** — set alerts before you overspend, not after

---

*Found this useful? Follow for more AWS deep-dives — next up: Microservices and Event-Driven Architecture on AWS.*
