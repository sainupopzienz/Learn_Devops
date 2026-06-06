# AWS Cloud Migration

## What is Cloud Migration?

Cloud migration is the process of moving digital assets — applications, data, IT infrastructure — from on-premises environments to the cloud, or from one cloud to another. It requires careful planning, execution, and monitoring to be successful.

---

## Cloud Migration Phases

1. **Preparation**
2. **Planning**
3. **Migrate**
4. **Operate & Optimize**

---

## Why Migrate to Cloud?

- Microservices — how we need to move directly to microservices-based architecture
- Innovation — hold-and-shift micro services on a well-clearly based foundation
- Production — when a job 3 applications (or microservices/monolithic/foundational) is on our cloud/premises we need a well-built & our standardize e-migration tools / monolithic approach
- Contact: if this micro service / micro services / monolithic / foundational as our standardize e our standardize migration tools
- Community: phase of the process organization — 1 from

---

## Cloud Migration Strategies (The 7 Rs)

### 1. Retire
- Turn off things you no longer need
- Reduces the surface for attack, saves cost

### 2. Retain
- Keep what is critical (e.g., due to compliance, latency, or licensing)
- Revisit in the future

### 3. Relocate
- Move without changes
- Example: VMware Cloud on AWS — shift your infrastructure to cloud simply by migrating application to cloud (vSphere-based workloads)
- Do: minimal downtime, reduced cost
- Supports wide range of platforms: OSes, databases, cloud

### 4. Rehost ("Lift and Shift")
- Move applications to AWS without changes
- Simple migration using AWS Application Migration Service (MGN)
- Do: re-hosting microservices to achieve HA (scalability)
- Optimization for scalability + control placement on cardinal planning

### 5. Replatform ("Lift, Tinker, and Shift")
- Move to AWS with some optimizations
- Example: Move to managed RDS rather than self-managed database
- Do: no core architecture changes

### 6. Repurchase ("Drop and Shop")
- Move to a different product
- Example: CRM → Salesforce, HR → Workday, CMS → Drupal
- Do: if you're using a lot below where the product helps get

### 7. Refactor / Re-architect
- Re-imagine how the application is architected using Cloud-native features
- Driven by a need to add features, scale, or performance that is otherwise hard to achieve
- Example: Monolithic → Microservices, or moving to serverless
- Most expensive but most long-term beneficial

---

## Cloud Migration Approaches

### Lift and Shift (Rehost)

- AWS is a cloud solution which creates (shifting) simply by migrating application to cloud
- The AWS a column of cloud endpoints — migration service which replaces replacing AWS server running comes
- Converts your physical, virtual, & cloud-based servers to run natively on AWS
- Supports wide range of platforms, OSes
- Do: minimal downtime, reduced cost

### Hybrid Cloud Migration

- Some customers are not moving all their workloads to cloud because of challenges/requirements
- They may want to extend their on-premises environments but they are using on-premises data center then using a VM cloud
- Run your production workloads in our on-prem
- And run your production workloads in AWs via their hybrid — on-prem + cloud
- VMware cloud — your production workloads in our
- Use VMware hybrid environment — security & elasticity — VMs are private + VMware cloud

---

## Transferring Large Amounts of Data to AWS

### Example Scenario
Transferring 200 TB of data over a network, with 100 Mbps internal / site-to-site VPN connection.

**Immediate to submit 200 TB × 1000 GB × 1000 MB × 8 = (Mb)/100 Mbps × (60s) =**
- Will total **800 CTB × 1000 CB × (6d)** = approximately **185 days**

### Options for Data Transfer

**1. Over the Internet / Site-to-Site VPN:**
- Query the direct connect on time streaming count 9 — on timing streaming count 9 — is approximately 185 days

**2. Over Direct Connect (1 Gbps):**
- Will take a 1–3 snowballs in parallel
- 1 app → Will total 800 CTBs ≈ 12.5 days

**3. Over Snowball:**
- Ours snowball — will take a 1–3 snowballs in parallel to reduce round-to-total
- Table about 1 week per time under-total transfer

**For ongoing replication/transfers:**
- Can be combined with DMS — site-to-site VPN
- For ongoing replication/transfers — site-to-site, Direct Connect with DMS or EtherSpy/VPC

---

## AWS Application Migration Service (MGN)

- The AWS a column of cloud endpoints solution which creates (shifting) simply by migrating application to cloud
- Replaces AWS Server Migration Service (SMS)
- Converts your physical, virtual & cloud-based servers to run natively on AWS
- Supports a wide range of platforms, OSes, and databases
- Minimal downtime, reduced costs

### MGN Architecture Diagram

```
On-Prem / Other Cloud / AWS Cloud
  ┌──────────────────────┐
  │  EC2 / RDS / EFS     │
  │  (source servers)    │
  └──────────────────────┘
           │
           │  (continuously replicates)
           ▼
  AWS Cloud (Replication)
  ┌─────────────────────────────────┐
  │  AWS Cloud Application          │
  │  Migration                      │
  │  (loaded data + staging area)   │
  │     EC2 + EBS  →  target EC2    │
  │                    target EBS   │
  └─────────────────────────────────┘
           │
           ▼
  AWS Cloud (Final)
  launch EC2, launch EBS
  launch target EBS
```

---

## On-Premise Strategy with AWS

- **Ability to download** Amazon Linux 2 AMI as a VM — VMware, KVM, VirtualBox, Microsoft Hyper-V
- **VM Import/Export:**
  - Migrate existing applications to EC2
  - Create a DR repository for your on-premises VMs
  - Can export back to on-premises if needed
- **AWS Application Discovery Service:**
  - Gather information about your on-premises servers to plan a migration
  - Server utilization and dependency mappings
  - Track with **AWS Migration Hub**
- **AWS Database Migration Service (DMS):**
  - Replicate on-premises → AWS, AWS → AWS, AWS → on-premises
  - Works with various DB technologies (Oracle, MySQL, DynamoDB, etc.)
- **AWS Server Migration Service (SMS):**
  - Incremental replication of on-premises live servers to AWS

---

## AWS Migration Hub

Central location to collect servers & application inventory data for assessment, planning, and tracking of migrations to AWS.

---

## AWS Application Discovery Service

- Gathers information about on-premises servers to plan a migration
- **Agentless Discovery** (AWS Agentless Discovery Connector):
  - VM inventory, configuration, and performance history (CPU, memory, disk usage)
- **Agent-based Discovery** (AWS Application Discovery Agent):
  - System configuration, system performance, running processes, and network connection details
- Results can be viewed within **AWS Migration Hub**

---

## AWS Fully Managed Backup Service (AWS Backup)

- Fully manages a service for centrally managing and automating backups across AWS services
- Across AWS services: fully managed service that allows creating backup policies and automation

**Supports:**
- No manual processes required — AWS automatically provisions resources and custom scripts

**AWS Backup Supports cross-region backup:**
- Supports cross-account backup

**AWS Backup — create backup plan:**
- Frequency (every 12 hours, daily, weekly, monthly, cron expression)
- Backup window
- Transition to cold storage (never, days, weeks, months, years)
- Retention period (always, days, weeks, months, years)

---

## RDS & Aurora Migrations

### RDS MySQL → Aurora MySQL

- **Option 1:** RDS MySQL snapshot → restore as Aurora MySQL
- **Option 2:** Create Aurora Read Replica from RDS MySQL (interval as 0) → promote it as its own cluster

### External MySQL → Aurora MySQL

- **Option 1 (Percona XtraBackup):**
  - Create a file backup in S3
  - Create an Aurora MySQL DB from S3
- **Option 2 (mysqldump):**
  - Create an Aurora MySQL DB
  - Use `mysqldump` utility to migrate MySQL into Aurora (slower than S3 method)

### External PostgreSQL → Aurora PostgreSQL

- Create a backup → put it in S3 → import using `aws_s3` Aurora extension

---

## DMS — Database Migration Service

Quickly and securely migrate databases to AWS — **resilient** and **self-healing**.

- The source database **remains available** during migration
- Supports:
  - **Homogeneous:** Oracle → Oracle
  - **Heterogeneous:** Microsoft SQL Server → Aurora
- Continuous data replication using **CDC**
- You must create an **EC2 instance** to perform replication tasks

### DMS Sources

- On-premises & EC2 databases: Oracle, MS SQL Server, MySQL, MariaDB, PostgreSQL, MongoDB, SAP, DB2
- Azure SQL Database
- Amazon RDS (all, including Aurora)
- Amazon S3

### DMS Targets

- On-premises & EC2 databases: Oracle, MS SQL Server, MySQL, MariaDB, PostgreSQL, SAP
- Amazon RDS
- Redshift
- DynamoDB
- S3
- ElasticSearch Service
- Kinesis Data Streams
- DocumentDB

---

## AWS Schema Conversion Tool (SCT)

- Converts your database schema from one engine to another
- **Example OLTP:** SQL Server or Oracle → MySQL, PostgreSQL, Aurora
- **Example OLAP:** Teradata or Oracle → Amazon Redshift
- You **do not need SCT** if migrating the same DB engine (e.g., PostgreSQL → PostgreSQL)

```
On-prem DB ──[SCT]──> master ──> target (AWS DB)
```

---

## Cloud Migration in AWS (Summary Strategies)

### Cloud Migration Strategies

- **Rehost** — Lift & shift
- **Replatform** — Lift & reshape
- **Refactor** — Re-architect
- **Repurchase** — Drop & Shop
- **Retain** — Keep on-prem
- **Retire** — Decommission
- **Relocate** — Move as-is (VMware)

---

## Snowball Migration Checklist

### Minimizing with Snowball (Large Transfers)

- You do not need to use SCT if you are migrating the same DB engine
- Migrating sources like: on-premise DB learning is still PostgreSQL DB engine (if you're migrating on-premise PostgreSQL to AWS RDS PostgreSQL)

```
DMS = (ECa + SCT-installed) — database migration environment
     → master
     → target (aws)
```

- **DMS = EC2 + SCT + included** — it is a database migration environment
- Alternatively: `DMS = (ECa+SCT=includes/full) + ARS is this platform`
- It is a **database migration environment**
