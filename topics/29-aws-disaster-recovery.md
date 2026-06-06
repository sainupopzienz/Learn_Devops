# AWS Disaster Recovery (DR)

## What is a Disaster?

Any event that has a negative impact on a company's business continuity or finances is considered a disaster. DR is about **preparing for and recovering from** a disaster.

## Types of Recovery Scenarios

- **On-Prem → On-Prem** — Traditional DR, very expensive
- **On-Prem → AWS Cloud** — Hybrid recovery
- **AWS Region → Another AWS Region** — Cloud-native DR

---

## Key Terms: RPO & RTO

### RPO — Recovery Point Objective
How often you back up your data. Defines the maximum acceptable amount of data loss measured in time.
- Example: If you back up every day, you could lose up to 24 hours of data.

### RTO — Recovery Time Objective
How much downtime the application can sustain.
- Example: The app must be back online within 15–30 minutes.

> **Note:** Always better to back up data frequently and run standby versions of your applications to reduce downtime.

---

## Backup Strategies (Cheapest → Most Expensive)

| Strategy | RTO | Cost | Mode |
|---|---|---|---|
| Backup & Restore | Highest (slowest) | Cheapest | Active/Passive |
| Pilot Light | Medium-High | Low | Active/Passive |
| Warm Standby | Medium | Medium | Active/Passive |
| Hot Site / Multi-Site | Lowest (seconds–minutes) | Most Expensive | Active/Active |

---

### 1. Backup and Restore

- **On-Prem → Cloud:** Transfer data to S3 using Storage Gateway
- Use **S3 Lifecycle Rules** and archive to **Glacier**
- Use **AWS Snowball** for large data transfers (there will be a delay)
- **Cloud → Cloud:** RTO is faster
  - Scheduled regular snapshots for **EBS, Redshift, and RDS**
  - Use **Golden AMI** for critical EC2 instances via lifecycle rules in AMI

---

### 2. Pilot Light

- A small version of the app is always running in the cloud
- Very similar to Backup and Restore but **faster** because critical systems are already up
- Example: **RDS is running**, but **EC2 is stopped**
- Use **Route 53 failover** or multi-routing policy to switch over the domain and start the application

---

### 3. Warm Standby

- Full system is up and running but at **minimum size** only
- Upon disaster, we **scale up** to full production load

---

### 4. Multi-Site / Hot Site Approach

- Very low RTO but very expensive (seconds to minutes)
- Full production scale is **running in AWS** on another region
- Primary region might be on-prem or another AWS region
- For databases: recommended to use **AWS Aurora Global Database** — available across any region

---

## Aurora Global Database for Disaster Recovery

### Why Aurora Global Database?

When a disaster strikes an entire AWS region (e.g., region goes down), you need your database to be available in another region **instantly** with minimal data loss and near-zero downtime. Aurora Global Database is specifically designed for this.

Aurora Global Database spans **multiple AWS regions**:
- **1 Primary Region** — handles all reads and writes
- **Up to 5 Secondary (Read-only) Regions** — replicate data from primary with typical lag of **< 1 second**

### What Happens During a Regional Disaster?

If the **primary region fails**, you promote one of the secondary regions to become the new primary:

```
Normal State:
  [Primary Region - us-east-1]  ──replicates──>  [Secondary Region - eu-west-1]
       (Read + Write)            < 1 sec lag           (Read Only)

Disaster — us-east-1 goes down:
  [Primary Region - us-east-1]  ✗ DOWN
                                         |
                                         ▼
                              [Secondary Region - eu-west-1]
                                   PROMOTED to Primary
                                   (Now Read + Write)
```

**Steps during failover:**
1. Detect primary region failure
2. **Promote** the secondary region's Aurora cluster to become the new primary — this takes typically **< 1 minute (RTO)**
3. Update your application's **writer endpoint** to point to the newly promoted region
4. The promoted region now accepts both reads and writes

### Why NOT just use RDS with a Read Replica across regions?

With standard **RDS cross-region Read Replica**, when disaster strikes:

- The read replica exists in another region — ✅ data is there
- But the **replication lag can be minutes**, not sub-second — meaning you could lose more data (**higher RPO**)
- To failover, you must **manually promote** the read replica to a standalone DB — this takes several **minutes to complete** (**higher RTO**)
- After promotion, the old primary is completely disconnected — there is **no automatic re-sync** if the original region comes back
- You must **update your application's connection strings** to point to the new DB endpoint manually

**Updating only the Reader Endpoint is NOT sufficient with RDS because:**
- The reader endpoint is a **read-only** endpoint — it cannot accept write traffic
- After promoting a read replica, a **brand new writer endpoint** is created — the reader endpoint of the old replica cluster does NOT automatically become a writer
- Any application still pointing to the old reader endpoint will get **connection errors or stale read-only access**
- There is no automatic DNS flip of write traffic — you must explicitly update your app config or Route 53 records to point to the **new writer endpoint** of the promoted DB

### Aurora Global DB vs RDS Read Replica — DR Comparison

| Feature | Aurora Global Database | RDS Cross-Region Read Replica |
|---|---|---|
| Replication Lag | < 1 second | Minutes (async) |
| RPO (data loss) | Near zero (< 1 sec) | Minutes of data loss possible |
| RTO (recovery time) | < 1 minute (promote) | Several minutes (manual promote) |
| Failover Type | Managed promotion | Manual promotion |
| Writer Endpoint after failover | New primary writer auto-available | Must manually update app endpoints |
| Re-sync after recovery | Supported | Not automatic |
| Cost | Higher | Lower |

### Summary

> Use **Aurora Global Database** for DR when you need **sub-second RPO** and **< 1 minute RTO** across regions. Simply **promote the secondary region** to primary on disaster — the new writer endpoint becomes active. Do **not** rely on just updating the reader endpoint, as reader endpoints are read-only and cannot serve write traffic after failover.

---

## DR Recovery Tips

### Backup
- EBS snapshots, RDS automated backups/snapshots
- Regular pushes to S3 / S3-IA / Glacier using lifecycle policies
- Enable **CRR (Cross-Region Replication)** on S3 + versioning
- From on-prem to cloud: use **AWS Snowball** or **Storage Gateway**

### High Availability (HA)
- Use **Route 53** to migrate DNS over from one region to another
- **RDS Multi-AZ**, **ElastiCache Multi-AZ**, **EFS**, and **S3** with cross-region replication + versioning
- Use **Storage Gateway**

### Automation
- Use **CloudFormation / Elastic Beanstalk** (PaaS) to re-create a whole new environment
- Recover/reboot EC2 instances with **CloudWatch** alarms (e.g., instance health check failed)
- Use **AWS Lambda functions** for custom automations

### Chaos Engineering (Testing DR)
- **Netflix's Simian Army** — randomly terminates EC2 instances to test resilience
- If DR is set up correctly, alerts will fire and the system will self-heal
- This strategy is called the **Chaos Strategy**

---

## AWS Backup Vault

- Write once, read many (WORM) — write once, you store it in
- Enables you to create and enforce backup policies
- Additional layers of defense to protect your backups against:
  - Updates by writing operations or malicious deletions
  - Shortened retention period
- Even the root user cannot delete the backup during the retention period

```
[+] -----> Backup Vault
            Backup Vault's can be deleted
```

---

## AWS Application Discovery Service

**Discovery service** — discovers projects by gathering information about on-premises data and dependency analysis.

- Gathers information about on-premises data & dependency analysis
- Important: **migration decisions** are important
- **Agentless discovery** (AWS Agentless Discovery Connector):
  - VM inventory, configuration, and performance history such as CPU, memory, and disk usage
- **Agent-based discovery** (AWS Application Discovery Agent):
  - System configuration, system performance, running processes, and details of the network connections between systems
- Resulting data can be viewed within **AWS Migration Hub**

---

## AWS Migration Hub

- Provides a **central location** to collect servers & application inventory data for the assessment, planning, and tracking of migrations to AWS
- **AWS Migration Evaluator** (formerly TSO Logic):
  - Provides a business case for migration
  - Gives a data-driven business case to find the most cost-effective path to AWS
- Helps track all migrating data on a **data-canopy** basis

---

## AWS Backup (fully managed service)

- **Fully manages** a service for centrally managing and automating backups across AWS services
- No need to create custom scripts or manual processes
- Supported services: EC2, EBS, EFS, Amazon FSx (Lustre & Windows), RDS (all DBs), Aurora, DynamoDB, Storage Gateway (Volume Gateway)
- Supports **cross-region backups**
- Supports **cross-account backups**
- Supports PITR (Point-in-Time Recovery) for supported services
- On-demand and scheduled backups
- **Tag-based backup policies**
- Backup policies known as **Backup Plans**:
  - Backup frequency (every 12 hours, daily, weekly, monthly, cron expression)
  - Backup window
  - Transition to cold storage (never, days, weeks, months, years)
  - Retention period (always, days, weeks, months, years)

---

## DMS — Database Migration Service

Quickly and securely migrate databases to AWS — **resilient** and **self-healing**.

- The **source database remains available** during the migration
- Supports:
  - **Homogeneous Migrations:** e.g., Oracle → Oracle
  - **Heterogeneous Migrations:** e.g., Microsoft SQL Server → Aurora
- Continuous data replication using **CDC (Change Data Capture)**
- You must create an **EC2 instance** to perform the replication tasks (DMS is installed inside that EC2)

### DMS Sources & Targets

**Sources:**
- On-premises & EC2 instance databases: Oracle, MS SQL Server, MySQL, MariaDB, PostgreSQL, MongoDB, SAP, DB2
- Azure SQL Database
- Amazon RDS (all including Aurora)
- Amazon S3

**Targets:**
- On-premises & EC2 instance databases: Oracle, MS SQL Server, MySQL, MariaDB, PostgreSQL, SAP
- Amazon RDS
- Amazon Redshift
- Amazon DynamoDB
- Amazon S3
- ElasticSearch Service
- Amazon Kinesis Data Streams
- DocumentDB

---

## AWS Schema Conversion Tool (SCT)

- Converts your database's schema from one engine to another
- Example: OLTP (SQL Server or Oracle) → MySQL, PostgreSQL, or Aurora
- Example: OLAP (Teradata or Oracle) → Amazon Redshift
- You **do not need to use SCT** if you are migrating from a PostgreSQL DB within the same engine (if you are migrating the same DB engine like PostgreSQL → PostgreSQL)

```
Oracle ──────────────────────────> Amazon RDS
         [SCT converts schema]

on-prem DB ──[SCT]──> master ──> target (AWS DB)
                         |
                    (converted schema)
```

- DMS = (EC2 + SCT-installed) — it is a database migration environment
- Alternatively noted as: `DMS = (ECa + SCT = includes/full) + ARS is this platform`

---

## RDS & Aurora Migrations

### RDS MySQL → Aurora

- **Option 1:** RDS MySQL snapshot → restore as Aurora MySQL
- **Option 2:** RDS MySQL → create Aurora Read Replica from RDS MySQL interval as 0, promote it as its own cluster

### External MySQL → Aurora MySQL

- **Option 1:** Use Percona XtraBackup to create a file backup in S3, then create Aurora MySQL DB from S3
- **Option 2:** Create an Aurora MySQL DB and use the `mysqldump` utility to migrate MySQL into Aurora (slower than S3 method)
- External PostgreSQL → Aurora PostgreSQL: Create a backup and put it in S3, then import using the `aws_s3` Aurora extension

### DMS (Database Migration Service) for Aurora
- Use DMS if both databases are running

---

## On-Premise Strategy with AWS

- **Ability to download** Amazon Linux 2 AMI as a VM (ISO format) — VMware, KVM, VirtualBox, Microsoft Hyper-V
- **VM Import/Export:**
  - Migrate existing applications to EC2
  - Create a DR strategy for your on-premises VMs
  - Can export back to on-premises if needed
- **AWS Application Discovery Service:**
  - Gather information about your on-premises servers to plan a migration
  - Server utilization and dependency mappings
  - Track with **AWS Migration Hub**
- **AWS Database Migration Service (DMS):**
  - Replicate on-premises → AWS, AWS → AWS, AWS → on-premises
  - Works with various database technologies (Oracle, MySQL, DynamoDB, etc.)
- **AWS Server Migration Service (SMS):**
  - Incremental replication of on-premises live servers to AWS
  - Migrates existing on-premises servers to AWS
