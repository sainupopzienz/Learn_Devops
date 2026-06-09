# Data Engineering on AWS: Glue, Athena, Kinesis, and Redshift

## From Raw Data to Business Insight — The Complete AWS Data Stack

---

Every company is sitting on a goldmine of data — user behavior, transactions, logs, clickstreams — and most of it is either unanalyzed or stuck in operational databases that weren't designed for analytics. Querying a production RDS for business intelligence reports is how you bring down your production database on a Monday morning.

Data engineering solves this by building a separate system for storing, processing, and analyzing data at scale — without touching production.

---

## The Modern Data Architecture

```
Data Sources                Processing              Storage & Analytics
────────────                ──────────              ───────────────────
RDS (transactions)   ─┐
S3 (logs, files)     ─┤──► AWS Glue (ETL) ──────► S3 Data Lake ──► Athena (SQL queries)
DynamoDB (app data)  ─┤                                         ──► Redshift (warehouse)
Kinesis (streams)    ─┘──► Kinesis Analytics ───► S3/Redshift  ──► QuickSight (dashboards)
```

---

## Amazon S3 — The Data Lake Foundation

A **data lake** is a centralized repository that stores all your raw and processed data at any scale. S3 is the backbone of every AWS data architecture because it's:

- **Infinitely scalable** — no storage limits
- **Extremely cheap** — $0.023/GB for Standard storage
- **Supports any format** — CSV, JSON, Parquet, ORC, Avro, images, logs
- **Integrated with every AWS analytics service**

### Data Lake Organization

```
s3://my-company-data-lake/
├── raw/                          ← Untouched source data
│   ├── transactions/2024/01/15/
│   ├── clickstream/2024/01/15/
│   └── logs/2024/01/15/
├── processed/                    ← Cleaned and transformed data
│   ├── transactions_parquet/
│   └── user_events_parquet/
└── curated/                      ← Business-ready aggregated data
    ├── daily_revenue/
    └── user_cohorts/
```

Always store processed data in **Apache Parquet format** — columnar storage that is 10x faster for analytics queries and 75% smaller than CSV.

---

## AWS Glue — Managed ETL Service

ETL = Extract, Transform, Load. Glue extracts data from sources, transforms it (clean, enrich, join), and loads it into the destination.

### Glue Components

**Glue Data Catalog:**
A managed metadata repository — like a table of contents for your data lake. Other services (Athena, Redshift Spectrum, EMR) use the Catalog to understand what data exists and where.

```
Glue Crawler scans:  s3://data-lake/transactions/
Creates catalog:     Table "transactions" — columns: id, user_id, amount, timestamp
Athena queries:      SELECT * FROM transactions WHERE amount > 1000
(Athena finds the data location from the Catalog automatically)
```

**Glue ETL Jobs:**

```python
# Glue ETL Job — Python (PySpark under the hood)
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext

glueContext = GlueContext(SparkContext.getOrCreate())

# Read raw data from S3
datasource = glueContext.create_dynamic_frame.from_catalog(
    database="raw_data",
    table_name="transactions"
)

# Transform — filter, clean, rename columns
transformed = datasource.apply_mapping([
    ("transaction_id", "string", "id", "string"),
    ("user_id", "long", "user_id", "long"),
    ("amount", "double", "amount_usd", "double"),
    ("created_at", "string", "transaction_date", "date")
]).filter(lambda x: x["amount_usd"] > 0)  # Remove negative/zero amounts

# Write processed data to S3 in Parquet format
glueContext.write_dynamic_frame.from_options(
    frame=transformed,
    connection_type="s3",
    connection_options={"path": "s3://data-lake/processed/transactions/"},
    format="parquet"
)
```

**Glue Workflows** — chain multiple ETL jobs with triggers:
```
Trigger: Daily at 2 AM
  → Job: Extract from RDS → S3 raw
  → Job: Transform raw → processed Parquet
  → Job: Aggregate processed → curated daily summary
  → Notification: SNS alert on success/failure
```

---

## Amazon Athena — Query S3 with SQL

Athena lets you query data directly in S3 using standard SQL — no database to provision, no data to load.

```
SELECT
    DATE_TRUNC('day', transaction_date) as date,
    COUNT(*) as total_orders,
    SUM(amount_usd) as total_revenue,
    AVG(amount_usd) as avg_order_value
FROM transactions
WHERE transaction_date >= DATE('2024-01-01')
GROUP BY 1
ORDER BY 1;
```

Run that query against 500 GB of data in S3. Pay only for data scanned: ~$5 per TB.

### Athena Cost Optimization

```
CSV format:  Scans entire file — expensive
Parquet:     Columnar — scans only needed columns — 75% cheaper
ORC:         Similar to Parquet — also columnar

Partition your data by date:
s3://data-lake/transactions/year=2024/month=01/day=15/data.parquet

Query: WHERE year=2024 AND month=01
→ Athena only scans January data, ignores rest of the year
→ 12x cheaper and faster than scanning the full table
```

---

## Amazon Kinesis — Real-Time Data Streaming

For data that can't wait — clickstreams, IoT sensor data, application logs, financial ticks — Kinesis processes millions of events per second in real time.

### Kinesis Data Streams

```
Producers:                    Kinesis Streams:          Consumers:
Mobile apps ──────────────►  ┌─────────────────┐  ───► Lambda (real-time alerts)
Web servers ──────────────►  │  Shard 1        │  ───► Kinesis Firehose (→ S3)
IoT sensors ──────────────►  │  Shard 2        │  ───► Kinesis Analytics (SQL)
Payment events ────────────► │  Shard 3        │  ───► Custom ECS consumer
                             └─────────────────┘
                             Data retained 1–365 days
                             Can replay from any point
```

One shard handles 1 MB/sec write and 2 MB/sec read. Add shards to scale.

### Kinesis Data Firehose — Easiest S3 Delivery

If you just need to reliably get streaming data into S3, Redshift, or Elasticsearch — Firehose is the simplest path:

```
Any producer → Kinesis Firehose → S3 (delivered every 60 seconds or 128 MB)
                                → Redshift (direct COPY command)
                                → OpenSearch (Elasticsearch)
                                → Splunk

Firehose handles: buffering, compression (gzip), format conversion, delivery, retries
You handle: nothing — fully managed
```

### Kinesis Data Analytics — SQL on Streams

Run SQL queries on streaming data in real time:

```sql
-- Real-time fraud detection: flag transactions > $10,000 in last 5 minutes
SELECT user_id, SUM(amount) as total
FROM transaction_stream
WINDOWED BY TUMBLING (INTERVAL '5' MINUTE)
GROUP BY user_id
HAVING SUM(amount) > 10000;
```

---

## Amazon Redshift — Cloud Data Warehouse

Redshift is a **petabyte-scale data warehouse** optimized for complex analytical queries (OLAP) across massive datasets.

```
Operational DB (RDS/DynamoDB):    Analytics DB (Redshift):
───────────────────────────────   ───────────────────────────
Row-based storage                 Columnar storage
Optimized for OLTP                Optimized for OLAP
Handles many small transactions   Handles few massive queries
Normalized schema                 Star/Snowflake schema (denormalized)
Terabytes                         Petabytes
```

### Redshift Architecture

```
┌──────────────────────────────────────────┐
│             Redshift Cluster              │
│                                          │
│  Leader Node:  Receives queries,         │
│                creates execution plan,   │
│                aggregates results        │
│                                          │
│  Compute Nodes: Actually execute queries │
│  Node 1: Slice 1 + Slice 2              │
│  Node 2: Slice 3 + Slice 4              │
│  Node 3: Slice 5 + Slice 6              │
└──────────────────────────────────────────┘
```

### Loading Data into Redshift

```sql
-- COPY from S3 — fastest bulk load method
COPY transactions
FROM 's3://data-lake/processed/transactions/'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftS3Role'
FORMAT AS PARQUET;

-- Millions of rows loaded in minutes using parallel S3 reads across all compute nodes
```

### Redshift Spectrum — Query S3 from Redshift

Query S3 data directly from Redshift without loading it:

```sql
-- Hot data: last 90 days in Redshift (fast)
-- Cold data: older data in S3 (cheaper storage)
-- One query spans both:

SELECT date, revenue
FROM redshift_transactions           -- Last 90 days, in Redshift
WHERE date >= '2024-10-01'
UNION ALL
SELECT date, revenue
FROM spectrum.s3_transactions        -- Older data, stays in S3
WHERE date < '2024-10-01';
```

---

## Amazon QuickSight — Business Intelligence Dashboards

Connect QuickSight to Athena, Redshift, S3, or RDS and build dashboards without code:

```
Athena/Redshift ──► QuickSight ──► Interactive dashboards
                                   Auto-generated insights (ML-powered)
                                   Embedded analytics in your application
                                   Mobile-friendly
```

QuickSight charges per user per month — no infrastructure to manage.

---

## The Complete Data Pipeline

```
Production Systems
  RDS (transactions) ─────────────────────────────────────┐
  DynamoDB (events)  ─── DMS (Change Data Capture) ───────┤
  Application logs   ─── CloudWatch → Kinesis Firehose ───┤
  Clickstream events ─── Kinesis Data Streams ─────────────┤
                                                           │
                                                           ▼
                                                  S3 Data Lake (raw/)
                                                           │
                                                           ▼
                                            AWS Glue (ETL jobs, daily)
                                            - Clean and validate data
                                            - Convert to Parquet
                                            - Partition by date
                                                           │
                                                 ┌─────────┴──────────┐
                                                 ▼                    ▼
                                          S3 Data Lake         Redshift
                                          (processed/)         (warehouse)
                                                 │                    │
                                                 ▼                    ▼
                                              Athena              QuickSight
                                         (ad-hoc SQL)          (dashboards)
```

---

## Key Takeaways

- **S3 is the data lake foundation** — everything lands in S3 first, always in Parquet format
- **Glue handles ETL** — crawl, catalog, and transform data without managing Spark clusters
- **Athena for ad-hoc queries** — SQL on S3, pay per TB scanned, partition to reduce costs
- **Kinesis for real-time** — stream processing at scale, fraud detection, live dashboards
- **Redshift for complex analytics** — petabyte-scale warehouse for business intelligence
- **Never run analytics on production RDS** — always copy to a separate analytics system
- **Parquet + partitioning** is the combination that makes Athena queries fast and cheap

---

*Found this useful? Follow for more AWS deep-dives — next up: AWS Well-Architected Framework — the 6 pillars every architect must know.*
