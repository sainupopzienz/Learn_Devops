# AWS Production Architecture: Capacity Planning, Connection Pooling, Memory Management & Auto Scaling

> A comprehensive guide with real-world examples for engineers designing and operating production systems on AWS.

---

## Table of Contents

1. [Understanding User Traffic](#1-understanding-user-traffic)
2. [Questions to Ask Before AWS Sizing](#2-questions-to-ask-before-aws-sizing)
3. [Read-Heavy vs Write-Heavy Applications](#3-read-heavy-vs-write-heavy-applications)
4. [Typical Production AWS Architecture](#4-typical-production-aws-architecture)
5. [Auto Scaling Strategies](#5-auto-scaling-strategies)
6. [Why CPU Usage Increases](#6-why-cpu-usage-increases)
7. [Why Memory Usage Increases](#7-why-memory-usage-increases)
8. [How an API Request Works](#8-how-an-api-request-works)
9. [Heap Memory Deep Dive](#9-heap-memory-deep-dive)
10. [Connection Pool Deep Dive](#10-connection-pool-deep-dive)
11. [Cache vs Memory Leak](#11-cache-vs-memory-leak)
12. [Load Testing](#12-load-testing)
13. [Interview Answer Cheat Sheet](#13-interview-answer-cheat-sheet)

---

## 1. Understanding User Traffic

Getting user traffic definitions wrong is one of the most common (and expensive) mistakes in infrastructure planning. Here's how to think through each layer carefully.

---

### 1.1 Registered Users

Registered users are everyone who has ever signed up — they may have logged in once and never returned.

**Example:**
> Swiggy (Indian food delivery app) may have **50 million registered users**, but only a fraction order food on any given day.

**Why it matters:** Registered users are useful for storage planning (how many user rows in your DB) but almost useless for infrastructure sizing.

---

### 1.2 Daily Active Users (DAU)

DAU counts distinct users who actually perform at least one action in a 24-hour window.

**Example:**
> An e-commerce site like Myntra might have:
> - 10 million registered users
> - 500,000 DAU on a normal weekday
> - 2,000,000 DAU during a sale (like Big Billion Days)

**Why it matters:** DAU tells you how much database read volume to expect per day. It also drives cache sizing — if 500K users hit the same product listings, you want those cached.

---

### 1.3 Concurrent Users

Concurrent users are those actively interacting with the system *at the same instant*.

**Real-World Example:**

> During the **IPL ticket sale on BookMyShow**, DAU might be 1 million, but in that 5-minute flash window when tickets go live, concurrent users could spike to **200,000 simultaneously**.

**Typical Conversion Ratios:**

| DAU | Expected Peak Concurrency | Scenario |
|-----|--------------------------|----------|
| 100,000 | 2,000 – 5,000 | Normal SaaS app |
| 500,000 | 10,000 – 25,000 | E-commerce |
| 1,000,000 | 50,000 – 100,000 | News/Media on breaking event |

> **Rule of Thumb:** Peak concurrent users ≈ 5–10% of DAU for most apps. During flash events (sales, elections, IPO listings), this can spike to 30–50%.

---

### 1.4 Requests Per Second (RPS)

RPS is the actual load hitting your servers every second.

**Formula:**

```
RPS = Concurrent Users × Requests per User per Second
    = Concurrent Users / Average Session Duration per Request (seconds)
```

**Real-World Examples:**

**Scenario A — News Website (Read-heavy, short requests):**
```
Concurrent Users = 10,000
Each user refreshes feed every 10 seconds
RPS = 10,000 / 10 = 1,000 RPS
```

**Scenario B — Ride-hailing App (Write-heavy, frequent polling):**
```
Concurrent Users = 5,000 (drivers + riders)
Location ping every 2 seconds
RPS = 5,000 / 2 = 2,500 RPS
```

**Scenario C — Banking App (Low concurrency, high processing):**
```
Concurrent Users = 500
Each transaction triggers 5 DB operations
RPS = 500 × 5 = 2,500 effective DB operations/sec
```

> **Key Insight:** 1,000 concurrent users on a chat app ≠ 1,000 concurrent users on a banking app. The banking app hits your DB and CPU far harder per request.

---

## 2. Questions to Ask Before AWS Sizing

When a stakeholder says *"We expect 10,000 users"*, that sentence alone is nearly useless for infrastructure planning.

Here's a full discovery checklist:

---

### Discovery Questionnaire

**Traffic Pattern Questions:**

| Question | Why It Matters |
|----------|----------------|
| Is "10,000 users" registered or concurrent? | Changes EC2 sizing by 10–50x |
| What is the expected RPS at peak? | Drives instance count |
| Are there predictable spikes (sales, paydays)? | Informs scheduled scaling |
| What geography are users in? | Drives CDN and multi-region decisions |
| What are your SLA requirements (99.9%? 99.99%)? | Determines redundancy level |

**Application Questions:**

| Question | Why It Matters |
|----------|----------------|
| Read-heavy or write-heavy? | Impacts replica vs primary DB sizing |
| Average response payload size? | Impacts network and memory |
| Any file uploads or media processing? | CPU-intensive, needs separate workers |
| Do you use WebSockets or long polling? | Changes concurrent connection math |
| Any batch jobs or scheduled reports? | Can cause surprise CPU spikes |

**Database Questions:**

| Question | Why It Matters |
|----------|----------------|
| RDBMS or NoSQL? | Different scaling strategies |
| Expected data volume now vs 2 years? | Drives storage tier choice |
| Complex JOIN queries? | Drives RDS instance class |
| Any full-text search needs? | May need Elasticsearch separately |

---

### Real-World Discovery Example

**Client says:** "We're launching a fintech lending app. We expect 10,000 users."

**After discovery:**
- 10,000 is total beta signups (not concurrent)
- Expected concurrent: ~200 at peak (loan applications during business hours)
- Write-heavy: Each application creates 8 DB records across 3 tables
- Heavy PDF generation per application
- Strict 99.9% SLA, regulated data

**Architecture Decision:**
- 2x `t3.large` EC2 (can grow to `m5.xlarge`) behind ALB
- RDS `db.r5.large` PostgreSQL Multi-AZ (not `t3` — regulated workloads need consistent performance)
- Separate worker fleet for PDF generation (CPU-isolated)
- S3 + Lambda for PDF storage, not local disk

---

## 3. Read-Heavy vs Write-Heavy Applications

This distinction fundamentally changes how you architect your database and caching layers.

---

### 3.1 Read-Heavy Applications

**Characteristics:**
- 80–99% of requests are SELECT queries
- Data changes infrequently relative to reads
- Caching is extremely effective
- Can use Read Replicas to distribute load

**Real-World Examples:**

| Application | Read % | Write % | Caching Strategy |
|-------------|--------|---------|-----------------|
| Zomato menu browsing | 97% | 3% | Redis TTL 5 min |
| Cricbuzz live scorecard | 95% | 5% | Redis TTL 2 sec |
| LinkedIn profile views | 90% | 10% | CDN + Redis |
| Amazon product catalog | 98% | 2% | CloudFront + ElastiCache |

**Architecture for Read-Heavy:**

```
User Request
    ↓
CloudFront (Cache static assets, API responses)
    ↓
ALB
    ↓
EC2 Fleet (Stateless API servers)
    ↓
Redis / ElastiCache  ←── Cache Hit (avoid DB)
    ↓ (Cache Miss)
RDS Primary  ← Writes
RDS Read Replica 1  ← Reads
RDS Read Replica 2  ← Reads
```

**Code Example (Spring Boot — Read with Cache):**

```java
@Service
public class ProductService {

    @Cacheable(value = "products", key = "#productId")  // Redis cache
    public Product getProduct(Long productId) {
        // Only hits DB on cache miss
        return productRepository.findById(productId)
            .orElseThrow(() -> new ProductNotFoundException(productId));
    }
}
```

**Cache hit ratio target:** > 85% for cost-effective read-heavy architecture.

---

### 3.2 Write-Heavy Applications

**Characteristics:**
- Majority of requests INSERT or UPDATE data
- Caching helps less (data is always changing)
- Database is the primary bottleneck
- Need write optimization: batching, async writes, partitioning

**Real-World Examples:**

| Application | Write Pattern | Challenge |
|-------------|--------------|-----------|
| UPI payment system | 1 payment = 5 DB writes | Consistency, rollback |
| Ola driver location | GPS ping every 2s per driver | High-throughput inserts |
| Stock trading platform | 1 trade = ledger + inventory + audit | ACID compliance |
| IoT sensor platform | 10,000 devices × 1 write/sec | 10K writes/sec throughput |

**Architecture for Write-Heavy:**

```
Write Requests
    ↓
ALB
    ↓
EC2 Fleet
    ↓
SQS / Kafka (Buffer writes, handle spikes)
    ↓
Write Workers (Consume queue, batch inserts)
    ↓
RDS Primary (with write-optimized settings)
    ↓
DynamoDB (for time-series / high-throughput writes)
```

**Code Example — Batching Writes:**

```java
// Bad: One DB call per event (kills DB at scale)
for (SensorReading reading : readings) {
    sensorRepository.save(reading);  // 10,000 individual INSERTs
}

// Good: Batch insert (single DB roundtrip)
sensorRepository.saveAll(readings);  // 1 bulk INSERT of 10,000 rows
```

**RDS Parameter Tuning for Write-Heavy:**
```
innodb_flush_log_at_trx_commit = 2  (slightly relaxed durability for speed)
innodb_buffer_pool_size = 75% of instance RAM
max_connections = sized to connection pool × EC2 count
```

---

### 3.3 Mixed Workload Example: Food Delivery App

```
GET /restaurants        → Read  (99% cache hit, served from Redis)
GET /menu/{id}          → Read  (CDN cached for 10 min)
POST /order             → Write (1 order = 4 DB writes: order, items, payment, inventory)
GET /order/{id}/status  → Read  (DB read, short TTL cache)
POST /review            → Write (1 write, rare operation)
PUT /delivery/location  → Write (high frequency, every 10s per driver)
```

**Insight:** Even "mixed" apps usually skew 80%+ read. Optimize reads first.

---

## 4. Typical Production AWS Architecture

### 4.1 Component-by-Component Breakdown

---

#### CloudFront (CDN Layer)

**What it does:** Serves static assets (HTML, JS, CSS, images) from 400+ edge locations globally. Can also cache API responses.

**Real-World Impact:**
> A Mumbai-based user accessing a server in `ap-south-1` (Mumbai) gets ~10ms latency.
> The same user accessing `us-east-1` directly gets ~200ms.
> CloudFront brings the content to the nearest edge — back to ~10ms.

**Cache behavior configuration:**
```json
{
  "PathPattern": "/api/products/*",
  "TTL": 300,
  "CachePolicy": "CachingOptimized",
  "OriginRequestPolicy": "AllViewer"
}
```

---

#### S3 (Static Frontend Hosting)

**What it does:** Hosts React/Vue/Angular build artifacts. Infinitely scalable, no server management.

**Cost comparison:**
```
EC2 t3.small to host frontend:  ~$15/month + ops overhead
S3 static hosting (1TB traffic): ~$25/month, zero ops, infinite scale
```

**Deployment pipeline:**
```
GitHub Push → CodePipeline → npm build → S3 sync → CloudFront invalidation
```

---

#### Application Load Balancer (ALB)

**What it does:** Distributes incoming HTTP/HTTPS traffic across EC2 instances. Supports path-based and host-based routing.

**Advanced routing example:**
```
/api/v1/*        → Target Group: API servers (m5.large)
/api/reports/*   → Target Group: Report workers (c5.2xlarge, CPU-heavy)
/api/uploads/*   → Target Group: Upload handlers (network-optimized)
/ws/*            → Target Group: WebSocket servers (sticky sessions)
```

**Health check configuration:**
```json
{
  "HealthCheckPath": "/actuator/health",
  "HealthCheckIntervalSeconds": 15,
  "HealthyThresholdCount": 2,
  "UnhealthyThresholdCount": 3,
  "HealthCheckTimeoutSeconds": 5
}
```

> **Real-World Lesson:** A slow health check (30s interval, 5 unhealthy threshold) means a dead instance serves traffic for 2.5 minutes. Tune health checks aggressively in production.

---

#### EC2 Auto Scaling Group

**What it does:** Maintains a fleet of EC2 instances, adding or removing them based on load.

**Instance selection guide:**

| Workload | Instance Type | Why |
|----------|--------------|-----|
| General API | `m5.large` / `m6i.large` | Balanced CPU + RAM |
| CPU-heavy (ML, encoding) | `c5.2xlarge` / `c6i.2xlarge` | Compute optimized |
| Memory-heavy (large caches, analytics) | `r5.xlarge` / `r6i.xlarge` | Memory optimized |
| Network-heavy (streaming) | `c5n.xlarge` | Network optimized |
| Dev/Staging (cost saving) | `t3.medium` / `t3.large` | Burstable |

> **Warning:** Never use `t3` instances for production workloads with consistent load. CPU credits deplete and performance collapses unpredictably.

---

#### Amazon RDS (Relational Database)

**What it does:** Managed PostgreSQL/MySQL with automated backups, patching, and Multi-AZ failover.

**Multi-AZ explained:**
```
Primary DB (ap-south-1a)
    ↕ Synchronous replication
Standby DB (ap-south-1b)

If Primary fails:
- RDS detects failure (60–120 seconds)
- Promotes Standby to Primary
- DNS CNAME updated automatically
- Application reconnects (connection pool handles this)
```

**RDS Instance sizing guide:**

| Daily Writes | Concurrent Connections | Recommended Class |
|-------------|----------------------|-------------------|
| < 10K | < 50 | `db.t3.medium` |
| < 100K | < 200 | `db.m5.large` |
| < 1M | < 500 | `db.m5.xlarge` |
| < 10M | < 1,000 | `db.r5.2xlarge` |
| > 10M | > 1,000 | Aurora + Read Replicas |

---

#### ElastiCache (Redis)

**What it does:** In-memory cache that sits between your app and database.

**Real-World Caching Strategy:**

```
Cache Layer 1: CloudFront (Public, long TTL — 5min to 1hr)
    Product listings, category pages, static API responses

Cache Layer 2: Redis / ElastiCache (Private, short TTL — 1s to 5min)
    User sessions, rate limit counters, real-time inventory

Cache Layer 3: Application local cache (In-process, very short TTL — 100ms to 10s)
    Config data, feature flags, lookup tables
```

**Redis data structure examples:**

```python
# Session storage (Hash)
redis.hset(f"session:{user_id}", {
    "cart_items": json.dumps(cart),
    "last_active": datetime.now().isoformat()
})
redis.expire(f"session:{user_id}", 3600)  # 1 hour TTL

# Rate limiting (Sliding window counter)
key = f"rate_limit:{user_id}:{minute}"
count = redis.incr(key)
redis.expire(key, 60)
if count > 100:
    raise RateLimitExceeded()

# Leaderboard (Sorted Set)
redis.zadd("game:leaderboard", {user_id: score})
top10 = redis.zrevrange("game:leaderboard", 0, 9, withscores=True)
```

---

### 4.2 Full Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                           INTERNET                                  │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │   CloudFront    │  ← Static assets, API caching
                    │   (Global CDN)  │
                    └────────┬────────┘
             ┌───────────────┴──────────────┐
             │                              │
    ┌────────▼────────┐           ┌─────────▼────────┐
    │   S3 Bucket     │           │       ALB         │  ← HTTPS termination
    │ (React/Vue SPA) │           │  (Load Balancer)  │
    └─────────────────┘           └─────────┬─────────┘
                                            │
                              ┌─────────────▼──────────────┐
                              │     Auto Scaling Group      │
                              │  ┌──────┐ ┌──────┐ ┌─────┐ │
                              │  │ EC2  │ │ EC2  │ │ EC2 │ │  ← API servers
                              │  └──┬───┘ └──┬───┘ └──┬──┘ │
                              └─────┼─────────┼─────────┼───┘
                                    │         │         │
                              ┌─────▼─────────▼─────────▼───┐
                              │    ElastiCache (Redis)       │  ← Cache layer
                              └─────────────────────────────┬┘
                                                            │ (cache miss)
                      ┌─────────────────────────────────────▼──────────┐
                      │                  Amazon RDS                     │
                      │  Primary (ap-south-1a) ←→ Standby (ap-south-1b)│
                      │  Read Replica 1        Read Replica 2           │
                      └────────────────────────────────────────────────┘
```

---

## 5. Auto Scaling Strategies

Auto Scaling is what separates "it works in dev" from "it survives production traffic".

---

### 5.1 Target Tracking Scaling (Recommended)

**How it works:** You set a target metric value, AWS continuously adds/removes instances to maintain it.

**Best for:** Applications with variable but gradually changing load.

**Real-World Configuration:**

```json
{
  "PolicyType": "TargetTrackingScaling",
  "TargetTrackingConfiguration": {
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "TargetValue": 60.0,
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }
}
```

**Why 60% CPU target (not 80%)?**
```
At 80% CPU target:
- Traffic spike → CPU hits 95% BEFORE new instances are ready
- Cold start takes 60–120 seconds (AMI boot + app warmup)
- Users experience degraded performance for 2 minutes

At 60% CPU target:
- Scaling starts earlier with 40% headroom
- By the time new instance is ready, you're at 70% not 95%
- Smooth scaling, no user impact
```

---

### 5.2 Step Scaling (Fine-Grained Control)

**How it works:** Define threshold brackets with different scaling actions at each level.

**Best for:** Applications with known traffic patterns where you want precise control.

**Real-World Example (E-commerce during sale):**

```
CloudWatch Alarm → Auto Scaling Policy

CPU 0–50%:    No action (Normal state)
CPU 51–70%:   Add 1 instance (Gentle scaling)
CPU 71–85%:   Add 3 instances (Moderate scaling)
CPU 86–95%:   Add 6 instances (Aggressive scaling)
CPU > 95%:    Add 10 instances + PagerDuty alert (Emergency)

Scale-in:
CPU < 40% for 10 min: Remove 1 instance (conservative scale-in)
```

**Terraform example:**
```hcl
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "scale-out-step"
  autoscaling_group_name = aws_autoscaling_group.api.name
  policy_type            = "StepScaling"
  adjustment_type        = "ChangeInCapacity"

  step_adjustment {
    scaling_adjustment          = 1
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 20  # CPU 70–90%
  }

  step_adjustment {
    scaling_adjustment          = 3
    metric_interval_lower_bound = 20  # CPU > 90%
  }
}
```

---

### 5.3 Scheduled Scaling

**How it works:** Pre-scale before known events.

**Best for:** Predictable traffic patterns.

**Real-World Examples:**

```
Scenario: Salary day traffic (1st and last day of month)
Action: Scale to 10 instances at 8:00 AM, scale back to 3 at 10:00 PM

Scenario: Big Billion Days Sale
Action: Pre-scale to 50 instances 2 hours before sale

Scenario: International cricket match (India vs Pak)
Action: Scale Hotstar/JioCinema to 200 instances before match start
```

**AWS CLI command:**
```bash
aws autoscaling put-scheduled-update-group-action \
    --auto-scaling-group-name my-api-asg \
    --scheduled-action-name "pre-scale-for-sale" \
    --start-time "2024-10-01T02:00:00Z" \
    --desired-capacity 50 \
    --min-size 50 \
    --max-size 100
```

---

### 5.4 Predictive Scaling

**How it works:** ML model analyzes historical patterns and pre-emptively scales before load arrives.

**Best for:** Recurring daily/weekly traffic patterns.

```
Monday historical data shows:
  9:00 AM: Traffic always spikes 200%
  1:00 PM: 50% drop (lunch)
  5:00 PM: 150% spike again

Predictive Scaling:
  8:45 AM: Automatically adds instances (15 min ahead)
  12:45 PM: Begins scale-in
  4:45 PM: Pre-scales again
```

---

### 5.5 Warm Pools (Advanced)

**Problem:** Cold start = 2–5 minutes for instance to be ready.

**Solution:** Keep pre-warmed EC2 instances in a "stopped" state. They start in ~30 seconds instead of 2 minutes.

```
Running Instances: 5  (serving traffic)
Warm Pool:         5  (stopped, ready to start in 30s)
Cold (unstarted):  ∞  (normal on-demand, 2+ min cold start)

Spike hits → Warm Pool instances start → Ready in 30s → Traffic served
```

**Cost:** You pay EC2 hourly rate for stopped warm pool instances, but avoid user-impacting cold starts.

---

## 6. Why CPU Usage Increases

Understanding CPU pressure helps you right-size instances and debug performance problems.

---

### 6.1 Request Volume

The most obvious cause — more requests = more work.

**Linear scaling example:**
```
Baseline:   100 RPS  → CPU 20%
2x load:    200 RPS  → CPU 38% (near linear)
5x load:    500 RPS  → CPU 65%
10x load:  1000 RPS  → CPU 90% (diminishing returns due to contention)
```

**Non-linear example (DB-bound app):**
```
100 RPS  → CPU 20%, DB wait 5ms per query   → Response: 50ms
500 RPS  → CPU 40%, DB wait 50ms per query  → Response: 150ms (DB saturating)
800 RPS  → CPU 55%, DB wait 500ms per query → Response: 800ms (DB thrashing)
```
> **Lesson:** CPU alone doesn't tell the full story. Always correlate with DB latency.

---

### 6.2 Complex Queries and Joins

**Bad query (unindexed, large JOIN):**
```sql
-- Run at 100 RPS, this kills your DB
SELECT o.*, u.name, u.email, p.*, r.*
FROM orders o
JOIN users u ON o.user_id = u.id
JOIN products p ON o.product_id = p.id
JOIN reviews r ON p.id = r.product_id
WHERE o.status = 'pending'
ORDER BY o.created_at DESC;
```

**DB CPU before/after indexing:**
```
Without index:  DB CPU = 85%, Query time = 2,000ms
With index:     DB CPU = 15%, Query time = 10ms

Index added:
CREATE INDEX idx_orders_status_created ON orders(status, created_at DESC);
```

---

### 6.3 Encryption and Cryptographic Operations

**JWT validation (every API request):**
```java
// This runs on EVERY authenticated request
Claims claims = Jwts.parserBuilder()
    .setSigningKey(publicKey)  // RSA-256: CPU-heavy operation
    .build()
    .parseClaimsJws(token);
```

**CPU cost comparison:**

| Algorithm | Operations/sec (single core) | Notes |
|-----------|------------------------------|-------|
| HMAC-SHA256 (JWT) | ~500,000/sec | Symmetric, fast |
| RSA-256 (JWT verify) | ~10,000/sec | Asymmetric, slower |
| bcrypt (password hash, cost=12) | ~15/sec | Intentionally slow |
| AES-256-GCM (data encryption) | ~1,000,000/sec | Hardware accelerated |

> **Real-World Lesson:** On a high-traffic auth service, switching JWT from RSA-256 to HMAC-SHA256 reduced CPU usage by 40% on the auth servers.

---

### 6.4 File Processing

**Image resize example:**
```
Scenario: Profile photo upload

User uploads 5MB JPEG
Server:
  1. Decode JPEG → in-memory bitmap (25MB RAM)
  2. Lanczos resize to 200x200 thumbnail (CPU: ~50ms)
  3. Re-encode to JPEG (CPU: ~20ms)
  4. Upload to S3

CPU per image: 70ms of one core
At 50 uploads/second = 3.5 CPU cores just for resizing
```

**Solution: Offload to workers**
```
User uploads → S3 directly → SQS trigger → Lambda/EC2 worker resizes
Main API servers: 0% CPU for image processing
Worker fleet: Auto-scaled separately based on queue depth
```

---

### 6.5 Garbage Collection (Java/JVM)

**Stop-the-World GC pauses:**
```
Normal operation: API responds in 50ms
GC pause (Full GC):
  - JVM freezes ALL threads for 200–2000ms
  - All in-flight requests are paused
  - CPU spikes to 100% during GC
  - Then drops back to 20%
  - Looks like periodic CPU spikes in CloudWatch
```

**JVM GC tuning for production:**
```bash
# Use G1GC (low-pause GC, default Java 9+)
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200    # Target max pause
-Xms2g -Xmx4g               # Pre-allocate heap, avoid dynamic resizing
-XX:+HeapDumpOnOutOfMemoryError  # Debug OOM crashes
-XX:HeapDumpPath=/tmp/heapdump.hprof
```

**Detecting GC issues in CloudWatch:**
```
Symptom: Regular CPU spikes every 30–60 seconds
Pattern: CPU 20% → spike to 95% for 2s → back to 20%
Diagnosis: Minor or Major GC events
Fix: Increase heap, tune GC algorithm, reduce object creation rate
```

---

## 7. Why Memory Usage Increases

Memory issues are subtle and often only appear under production load.

---

### 7.1 Concurrent Request Objects

**Every active request holds memory:**
```java
// Each request creates these objects in heap:
@RestController
public class OrderController {

    @GetMapping("/orders/{id}")
    public OrderResponse getOrder(@PathVariable Long id) {
        Order order = orderRepo.findById(id);  // Order object: ~2KB
        List<Item> items = order.getItems();    // List<Item>: ~500B each
        User user = userRepo.findById(order.getUserId());  // User: ~1KB
        return new OrderResponse(order, items, user);      // DTO: ~3KB
    }
}
```

**Memory math:**
```
1 request: ~8KB heap objects
100 concurrent requests: ~800KB
1,000 concurrent requests: ~8MB
10,000 concurrent requests: ~80MB

+ Thread stack memory:
Java thread default: 512KB per thread
1,000 threads: 512MB of stack memory alone!
```

**Solution: Virtual Threads (Java 21+) or Reactive:**
```java
// Traditional: 1 thread per request (500KB stack each)
// At 1000 concurrent: 500MB just for thread stacks

// Java 21 Virtual Threads: ~1KB per virtual thread
// At 1000 concurrent: ~1MB for stacks
@Bean
public AsyncTaskExecutor applicationTaskExecutor() {
    return new TaskExecutorAdapter(Executors.newVirtualThreadPerTaskExecutor());
}
```

---

### 7.2 Application-Level Caching

**Spring Cache — good until it isn't:**
```java
@Cacheable("products")
public List<Product> getAllProducts() {
    return productRepo.findAll();  // Returns 50,000 products
}

// This caches ALL 50,000 products in heap memory
// Each product: ~2KB
// Total: 100MB of heap just for this one cache
// + GC pressure, longer GC pauses
```

**Better approach — paginated cache:**
```java
@Cacheable(value = "products", key = "#page + '-' + #size")
public Page<Product> getProducts(int page, int size) {
    return productRepo.findAll(PageRequest.of(page, size));
}
// Cache key: "0-20", "1-20", etc.
// Each entry: ~40KB (20 products)
// Far more manageable
```

---

### 7.3 Large Response Payloads

**Memory amplification example:**
```
DB returns: 1MB of compressed data
Application:
  1. Decompress → 10MB byte array
  2. JSON parse → 10MB Object tree
  3. Apply business logic → 10MB modified objects
  4. JSON serialize → 10MB string
  5. HTTP response buffer → 10MB

Total heap: 40–50MB for ONE large report request
At 20 concurrent large reports: ~1GB heap used
```

**Solution — streaming:**
```java
@GetMapping("/reports/large")
public void streamReport(HttpServletResponse response) {
    response.setContentType("application/json");

    try (JsonGenerator gen = mapper.createGenerator(response.getOutputStream())) {
        gen.writeStartArray();
        // Fetch and serialize 1 row at a time — constant memory usage
        reportRepo.streamResults().forEach(row -> {
            try { gen.writeObject(row); }
            catch (IOException e) { throw new RuntimeException(e); }
        });
        gen.writeEndArray();
    }
    // Peak memory: ~1 row worth of objects, regardless of report size
}
```

---

### 7.4 Connection Pool Memory

**Memory per connection:**
```
PostgreSQL: Each connection = ~5–10MB on DB server
HikariCP (Java): Each connection object = ~100KB in app

Pool size 20:
  DB side:  20 × 8MB = 160MB DB RAM
  App side: 20 × 100KB = 2MB per instance

5 EC2 instances × pool 20:
  DB: 100 connections × 8MB = 800MB DB RAM reserved!
```

**Right-sizing connection pool:**
```
Formula: pool_size = (core_count * 2) + effective_spindle_count

For DB server with:
- 4 vCPU
- SSD storage (1 spindle equivalent)
- Max: (4 × 2) + 1 = 9 connections per client recommended

For 5 EC2 app servers:
- Per server: 9 connections
- Total: 45 connections
- RDS instance should support at least 60 (45 + 25% headroom)
```

---

## 8. How an API Request Works

Tracing a single request end-to-end reveals every point of resource consumption.

---

### 8.1 Request Lifecycle (Detailed)

**Example: `POST /api/orders` (Place an order)**

```
Step 1: HTTP Request arrives at ALB
  ├── SSL/TLS termination (CPU: RSA decryption)
  ├── Header parsing
  └── Route to healthy EC2 instance

Step 2: Application server receives request
  ├── Servlet/Spring DispatcherServlet
  ├── Filter chain: JWT validation (CPU), logging
  ├── Request deserialization: JSON → Java object (heap: ~5KB)
  └── Route to OrderController

Step 3: Business logic
  ├── Validate order (check inventory in Redis: network I/O)
  ├── Calculate pricing (CPU: discount rules, tax)
  └── Create Order domain object (heap: ~10KB)

Step 4: Database operations
  ├── Acquire connection from pool (wait if pool full)
  ├── BEGIN TRANSACTION
  ├── INSERT INTO orders (...) → row lock on orders table
  ├── UPDATE inventory SET quantity = quantity - 1 → row lock
  ├── INSERT INTO order_items (...) 
  ├── INSERT INTO payments (...)
  ├── COMMIT
  └── Return connection to pool

Step 5: Post-processing
  ├── Publish event to SQS (async: email notification, analytics)
  ├── Invalidate Redis cache for user's order list
  └── Serialize response → JSON (CPU, heap: ~3KB)

Step 6: HTTP Response
  ├── Send response bytes over TLS
  └── Objects become GC-eligible
```

**Resource consumption summary:**

| Resource | Amount | Duration |
|----------|--------|----------|
| CPU | 5–20ms active | Per request |
| Memory (heap) | 20–50KB | Duration of request |
| DB Connection | 1 | ~5ms (transaction duration) |
| Network | ~2KB sent, ~500B received | Per request |
| Redis operations | 2–3 | ~1ms each |

---

### 8.2 What Happens at High Load

**100 RPS:**
```
100 requests in flight
100 × 50KB heap = 5MB active heap
DB connection pool: 20–30 connections busy simultaneously
Response time: 50ms (fast)
```

**1,000 RPS:**
```
1,000 requests in flight (if avg 50ms response time)
1,000 × 50KB heap = 50MB active heap
DB connection pool: ALL 50 connections busy
New requests: WAIT for connection (adds 100ms latency)
Response time: 150ms (degrading)
```

**2,000 RPS (overwhelmed):**
```
2,000 requests in flight
DB connection wait queue: 500 requests waiting
Timeout errors starting to appear
Response time: 500ms–5,000ms (broken)
HikariCP throws: "Connection is not available, request timed out after 30000ms"
```

---

## 9. Heap Memory Deep Dive

Understanding heap memory is essential for diagnosing production OOM crashes.

---

### 9.1 JVM Heap Structure

```
JVM Memory Layout:
┌──────────────────────────────────────────────────────────┐
│                      JVM Process                         │
│  ┌─────────────────────────────────────────────────────┐ │
│  │                  Heap Memory (-Xmx)                 │ │
│  │  ┌──────────────────┐  ┌────────────────────────┐  │ │
│  │  │   Young Gen      │  │      Old Gen           │  │ │
│  │  │  ┌────┐ ┌─────┐ │  │  Long-lived objects    │  │ │
│  │  │  │Eden│ │Surv.│ │  │  (survived >15 GCs)    │  │ │
│  │  │  └────┘ └─────┘ │  └────────────────────────┘  │ │
│  │  └──────────────────┘                              │ │
│  └─────────────────────────────────────────────────────┘ │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │  Metaspace   │  │ Thread Stack │  │ Direct Buff  │   │
│  │ (class defs) │  │ per thread   │  │ (NIO, Netty) │   │
│  └──────────────┘  └──────────────┘  └──────────────┘   │
└──────────────────────────────────────────────────────────┘
```

**Object lifecycle in heap:**
```
1. Request arrives: Order object created in Eden space
2. Minor GC runs (every few seconds): 
   - If object still referenced → moved to Survivor space
   - If not referenced → collected (free)
3. After surviving 15 GCs: Object promoted to Old Gen
4. Major GC (Full GC): Old Gen cleaned (causes STW pause)
```

---

### 9.2 Memory Sizing for EC2

**Formula:**
```
Total EC2 RAM = JVM Heap (-Xmx)
              + Thread Stacks (threads × 512KB)
              + Metaspace (class definitions: ~256MB)
              + Direct Memory (NIO buffers: ~256MB)
              + OS and other processes (~500MB)
              + 20% safety margin

Example: App with 200 threads, 4GB heap target:
= 4,096 MB  (heap)
+ 200 × 0.5 MB = 100 MB  (stacks)
+ 256 MB  (metaspace)
+ 256 MB  (direct memory)
+ 500 MB  (OS)
= 5,208 MB → use 8GB EC2 (r5.large or m5.large)
```

---

### 9.3 Memory Leak — Real Production Example

**Scenario: E-commerce product search**

```java
// This code runs in production for months without issue
// Then OOM crashes start appearing
public class SearchService {

    // STATIC map — lives forever with the class
    private static final Map<String, List<Product>> searchCache = new HashMap<>();

    public List<Product> search(String query) {
        if (!searchCache.containsKey(query)) {
            List<Product> results = productRepo.search(query);
            searchCache.put(query, results);  // Added to static cache
                                               // Never removed!
        }
        return searchCache.get(query);
    }
}
```

**What happens over time:**
```
Day 1:   searchCache size = 5,000 queries  → Heap: +50MB
Week 1:  searchCache size = 50,000 queries → Heap: +500MB
Month 1: searchCache size = 200,000 queries → Heap: +2GB → OOM!
```

**Fix — bounded cache with eviction:**
```java
// Option 1: Guava Cache with size limit and TTL
private final Cache<String, List<Product>> searchCache = CacheBuilder.newBuilder()
    .maximumSize(10_000)          // Evict LRU after 10K entries
    .expireAfterWrite(5, TimeUnit.MINUTES)
    .recordStats()
    .build();

// Option 2: Spring Cache with Redis (externalized, no heap leak)
@Cacheable(value = "search", key = "#query")
public List<Product> search(String query) {
    return productRepo.search(query);  // Redis handles TTL and eviction
}
```

---

## 10. Connection Pool Deep Dive

Connection pooling is the #1 database performance optimization for most applications.

---

### 10.1 Why Connection Pooling Exists

**Without connection pooling:**
```
Every API request:
  1. TCP handshake to DB: 1ms
  2. TLS negotiation: 5ms
  3. PostgreSQL auth: 10ms
  4. Connection ready
  5. Execute query: 5ms
  6. TOTAL: 21ms overhead per request

At 1,000 RPS:
  - 1,000 new connections per second to DB
  - PostgreSQL spawns 1,000 processes per second
  - DB server overwhelmed just handling connections
```

**With HikariCP (connection pool):**
```
Pool initialized at startup:
  - 20 connections pre-created (one-time 21ms overhead each)

Every API request:
  1. Acquire connection from pool: 0.1ms
  2. Execute query: 5ms
  3. Return connection to pool: 0.1ms
  4. TOTAL: 5.2ms per request

Connections are reused — DB sees 20 stable, long-lived connections
```

---

### 10.2 HikariCP Configuration (Production)

```yaml
# application.yml — Spring Boot
spring:
  datasource:
    hikari:
      # Core sizing
      maximum-pool-size: 20       # Max DB connections this instance will open
      minimum-idle: 5             # Keep 5 connections warm even when quiet
      
      # Timeouts
      connection-timeout: 3000    # Wait max 3s for a connection from pool
      idle-timeout: 600000        # Close idle connections after 10 min
      max-lifetime: 1800000       # Replace connections every 30 min (avoid DB-side timeout)
      
      # Validation
      keepalive-time: 60000       # Send keepalive ping every 60s
      connection-test-query: SELECT 1  # Validate connection before use (PostgreSQL doesn't need this)
      
      # Naming (for monitoring)
      pool-name: api-pool-prod
      
      # Leak detection (development/staging only — disable in prod)
      leak-detection-threshold: 2000  # Warn if connection held > 2s
```

---

### 10.3 Connection Leak — Real Example

**Bug: Exception handling skips connection release**

```java
// BROKEN: Connection never returned if exception thrown
public void processOrder(Long orderId) {
    Connection conn = dataSource.getConnection();  // Acquired
    try {
        Statement stmt = conn.createStatement();
        stmt.execute("UPDATE orders SET status='processing' WHERE id=" + orderId);
        // Exception thrown here (e.g., constraint violation)
        doSomeRiskyOperation();  // ← Throws RuntimeException
        conn.close();  // ← NEVER REACHED
    } catch (Exception e) {
        throw e;  // Connection still not closed!
    }
}
```

**What happens:**
```
Request 1: acquires conn-1, throws exception, conn-1 leaked
Request 2: acquires conn-2, throws exception, conn-2 leaked
...
Request 20: pool exhausted, new requests block
All requests time out: "Connection is not available"
```

**Fix — try-with-resources:**
```java
public void processOrder(Long orderId) {
    try (Connection conn = dataSource.getConnection()) {  // Auto-closed on exit
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("UPDATE orders SET status='processing' WHERE id=?");
            doSomeRiskyOperation();
        }
    }
    // conn.close() guaranteed by try-with-resources, even on exception
}
```

**Detection in production:**
```
HikariCP metric: hikaricp.connections.pending → increasing over time
CloudWatch alarm: DB connections > 90% of pool size for > 2 minutes
HikariCP log (enable leak detection): "Connection leak detection triggered"
```

---

### 10.4 PgBouncer for High-Concurrency Applications

When you have many app servers, total DB connections can exceed what PostgreSQL handles well.

```
Problem:
  50 EC2 instances × pool size 20 = 1,000 DB connections
  PostgreSQL default: 100 max_connections
  PostgreSQL `db.r5.xlarge`: ~4,000 max, but each costs RAM

Solution: PgBouncer (Connection Multiplexer)

  50 EC2 × pool 20 → [PgBouncer] → 100 DB connections
  PgBouncer queues and multiplexes connections
  DB server sees 100 clients instead of 1,000
```

---

## 11. Cache vs Memory Leak

Understanding the difference between intentional caching and unintentional leaks.

---

### 11.1 Good Cache — Controlled, Bounded, Expiring

**Redis example:**
```python
def get_user_profile(user_id):
    cache_key = f"user:profile:{user_id}"
    
    # Try cache first
    cached = redis.get(cache_key)
    if cached:
        return json.loads(cached)
    
    # Cache miss → DB query
    profile = db.query("SELECT * FROM users WHERE id = %s", user_id)
    
    # Store in cache for 15 minutes
    redis.setex(cache_key, 900, json.dumps(profile))
    
    return profile
```

**Properties of good cache:**
- Bounded size (Redis maxmemory + eviction policy)
- TTL-based expiration
- Cache invalidation on writes (or tolerate eventual consistency)
- Observable (hit/miss ratio, memory usage metrics)

**Cache invalidation patterns:**

| Pattern | When to Use | Example |
|---------|------------|---------|
| TTL expiry | Tolerate slight staleness | Product prices (5 min TTL) |
| Write-through | Need immediate consistency | User session |
| Cache-aside | Complex invalidation logic | Order history |
| Event-driven | Microservices | Invalidate on Kafka event |

---

### 11.2 Memory Leak — Uncontrolled Growth

**Three patterns that cause leaks:**

**Pattern 1: Unbounded static collection**
```java
// Classic leak: event listeners never deregistered
public class EventBus {
    private static List<EventListener> listeners = new ArrayList<>();
    
    public void register(EventListener listener) {
        listeners.add(listener);  // Added on every request, never removed
    }
}
// After 1M requests: 1M listener objects in memory
```

**Pattern 2: ThreadLocal not cleaned**
```java
public class RequestContext {
    private static ThreadLocal<User> currentUser = new ThreadLocal<>();
    
    public static void setUser(User user) {
        currentUser.set(user);
    }
    
    // MISSING: remove() call after request
}
// With thread pool: threads are reused
// ThreadLocal values survive to next request
// Old User objects accumulate per thread
```

**Pattern 3: Closures capturing outer scope**
```javascript
// Node.js leak: timer captures large object
function processData(largeDataset) {  // 100MB object
    setInterval(() => {
        console.log("Processing: " + largeDataset.id);  // Keeps largeDataset alive
    }, 1000);
}
// Even after processData returns, closure prevents GC of largeDataset
```

---

### 11.3 Detecting Memory Leaks in Production

**CloudWatch signals:**
```
Metric: mem_used (EC2 CloudWatch agent)
Pattern: Gradual upward trend over hours/days, never returning to baseline
Alert: mem_used > 85% of total RAM for > 30 minutes
```

**JVM heap analysis:**
```bash
# Trigger heap dump on running process
jmap -dump:format=b,file=/tmp/heapdump.hprof <pid>

# Analyze with Eclipse MAT or VisualVM
# Look for: "Biggest objects by retained heap"
# Classic leak signature: 
#   java.util.HashMap$Entry[] → 2GB retained → not expected
```

**Node.js heap analysis:**
```javascript
// Add to your app for production heap snapshots
const v8 = require('v8');
app.get('/debug/heap-snapshot', (req, res) => {
    const filename = `/tmp/heap-${Date.now()}.heapsnapshot`;
    v8.writeHeapSnapshot(filename);
    res.json({ file: filename });
});
// Compare two snapshots in Chrome DevTools → Memory tab
```

---

## 12. Load Testing

Load testing is the only reliable way to understand your actual system capacity.

---

### 12.1 Why AWS Doesn't Give You RPS Numbers

**Reality check:**
```
Two apps, both on m5.large EC2:

App A: GET /health → return {"status": "ok"}
Handles: 50,000+ RPS

App B: POST /report → 10 DB queries, 3 external API calls, PDF generation
Handles: 3 RPS

Instance type is nearly irrelevant — application design is everything.
```

---

### 12.2 K6 Load Test — Real Example

**Test script:**
```javascript
// k6-test.js — E-commerce load test
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
    stages: [
        { duration: '2m', target: 100 },   // Ramp up to 100 users
        { duration: '5m', target: 100 },   // Hold at 100 users
        { duration: '2m', target: 500 },   // Ramp to 500 users (stress)
        { duration: '5m', target: 500 },   // Hold at 500 users
        { duration: '2m', target: 1000 },  // Spike to 1000 users
        { duration: '3m', target: 1000 },  // Hold spike
        { duration: '2m', target: 0 },     // Ramp down
    ],
    thresholds: {
        http_req_duration: ['p95<500'],    // 95th percentile < 500ms
        errors: ['rate<0.01'],             // Error rate < 1%
    },
};

const BASE_URL = 'https://api.myapp.com';

export default function () {
    // Realistic user flow
    const res1 = http.get(`${BASE_URL}/api/products?category=electronics`);
    check(res1, { 'products loaded': (r) => r.status === 200 });
    errorRate.add(res1.status !== 200);
    sleep(2);

    const res2 = http.get(`${BASE_URL}/api/products/${randomProductId()}`);
    check(res2, { 'product detail loaded': (r) => r.status === 200 });
    sleep(1);

    const res3 = http.post(`${BASE_URL}/api/cart/add`, JSON.stringify({
        productId: randomProductId(), quantity: 1
    }), { headers: { 'Content-Type': 'application/json' } });
    check(res3, { 'added to cart': (r) => r.status === 201 });
    sleep(3);
}

function randomProductId() {
    return Math.floor(Math.random() * 10000) + 1;
}
```

**Run:**
```bash
k6 run --out json=results.json k6-test.js
```

---

### 12.3 What to Monitor During Load Test

**AWS CloudWatch dashboards to watch:**

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| EC2 CPU | > 60% | > 85% | Scale out |
| EC2 Memory | > 70% | > 90% | Upgrade instance / fix leak |
| ALB Latency (p95) | > 500ms | > 2,000ms | Optimize queries / scale |
| ALB 5xx Error Rate | > 0.1% | > 1% | Check app logs |
| RDS CPU | > 60% | > 80% | Optimize queries / scale up |
| RDS Connections | > 70% of max | > 90% of max | Reduce pool size / scale |
| ElastiCache CPU | > 50% | > 70% | Evaluate cache eviction |
| SQS Queue Depth | Trending up | > 10,000 | Scale consumers |

---

### 12.4 Load Test Results Interpretation

**Example output analysis:**

```
K6 Results:
  scenarios: (100.00%) 1 scenario
  ✓ products loaded
  ✓ product detail loaded
  ✗ added to cart  ← Failing at high load!

  http_req_duration ............: avg=234ms min=12ms med=180ms 
                                   max=4239ms p(90)=512ms p(95)=893ms ← Breaching 500ms SLA
  http_req_failed ...............: 2.34% ✗ 2340 out of 100000

  Interpretation:
  ├── p95 > 500ms: SLA breach happening at high load
  ├── 2.34% error rate: POST /api/cart/add failing under stress
  ├── Likely cause: DB connection pool exhausted
  └── Action: Increase pool size? Add DB read replica? Optimize cart query?
```

**Bottleneck identification flow:**
```
High response time?
  ├── CPU maxed out → Scale EC2 horizontally (more instances)
  ├── Memory pressure → Upgrade instance class or fix leaks
  ├── DB slow → Analyze slow query log, add indexes, scale RDS
  ├── Network I/O → Check external API calls, add timeouts
  └── Connection pool exhausted → Increase pool size or reduce query time
```

---

### 12.5 Chaos Engineering (Advanced)

After load testing, simulate failures to verify resilience:

```bash
# AWS Fault Injection Service (FIS) experiments:

# Kill one EC2 instance — does ALB auto-route?
aws fis start-experiment --experiment-template-id <id>

# Spike RDS CPU — does app degrade gracefully?
# Throttle network — do timeouts fire correctly?
# Kill Redis — does app fall back to DB?

# Expected behavior:
# ✓ ALB health check removes failed instance in < 30s
# ✓ Auto Scaling replaces instance in < 3 minutes
# ✓ No user-visible errors during single-instance failure
# ✓ Cache miss fallback works (slower, not broken)
```

---

## 13. Interview Answer Cheat Sheet

### "How do you size EC2 instances?"

> "I start by understanding the actual workload — concurrent users, RPS, and whether it's read or write heavy. I'd deploy a baseline configuration, run load tests with K6 or JMeter, and monitor CPU, memory, DB latency, and error rates. Instance choice follows from what the bottleneck is: CPU-bound → compute optimized, memory-bound → memory optimized, general API → general purpose m5/m6i. I avoid t3 instances for production because burst CPU credit depletion is unpredictable under sustained load."

---

### "How do you handle a sudden 10x traffic spike?"

> "Ideally, I pre-warm with scheduled scaling if the event is known — like a sale or product launch. For unexpected spikes, target tracking auto scaling with a 60% CPU target gives enough headroom to scale before we're maxed out. I'd also ensure CloudFront caches as much as possible to reduce origin hits, Redis absorbs repeated DB reads, and the application degrades gracefully — showing cached data or a simplified response rather than timing out completely."

---

### "What causes memory leaks and how do you detect them?"

> "Memory leaks typically come from unbounded static collections, ThreadLocal values not cleaned up, or closures preventing garbage collection. In production, the signal is heap memory trending upward over hours without returning to baseline — even after traffic drops. I detect them with CloudWatch memory metrics, JVM heap dumps analyzed with Eclipse MAT, or heap snapshot comparisons in Chrome DevTools for Node.js. The fix is usually adding size bounds and TTLs to caches, or ensuring try-finally/try-with-resources properly releases resources."

---

### "How do you decide connection pool size?"

> "A common formula is `(cores × 2) + spindles`, which for a 4-core app server with SSD gives around 9 connections. But I validate this with load testing. I watch for HikariCP's `connections.pending` metric — if it's consistently non-zero, the pool is undersized. I also account for total connections across all app instances: 10 servers × 20 connections = 200 DB connections, and the RDS instance needs to comfortably handle that. For very high-scale systems, I put PgBouncer in front of PostgreSQL to multiplex thousands of app connections into a smaller set of actual DB connections."

---

*Last updated: June 2026 | For AWS production engineering teams*
