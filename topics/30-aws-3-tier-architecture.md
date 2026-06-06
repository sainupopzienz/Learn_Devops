# Building a Production-Grade 3-Tier Architecture on AWS

## The Blueprint Every Cloud Engineer Should Know

---

When companies say their application is "on AWS," most people imagine a single server somewhere in Amazon's data center. The reality of a well-designed production system looks nothing like that. It's a carefully layered, fault-tolerant, security-hardened system — built in tiers, each with a single responsibility.

This article walks you through designing a **3-Tier Architecture on AWS** from scratch — the same pattern used by startups and enterprises alike to serve millions of users reliably.

---

## What is a 3-Tier Architecture?

A 3-Tier Architecture separates your application into three distinct layers, each isolated from the other:

```
┌─────────────────────────────────────────────────────┐
│                     INTERNET                        │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│                  WEB TIER                           │
│         (Load Balancer + WAF)                       │
│              Public Subnets                         │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│                  APP TIER                           │
│        (EC2 / ECS + Auto Scaling Group)             │
│              Private Subnets                        │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│                   DB TIER                           │
│          (RDS Multi-AZ + ElastiCache Redis)         │
│              Private Subnets                        │
└─────────────────────────────────────────────────────┘
```

| Tier | What Lives Here | Subnet Type |
|---|---|---|
| Web Tier | Application Load Balancer, WAF | Public |
| App Tier | EC2 / ECS (Frontend + Backend) | Private |
| DB Tier | RDS, ElastiCache Redis | Private |

The golden rule: **only the Web Tier is exposed to the internet. Everything else is private.**

---

## Step 1 — The Foundation: VPC and Subnets

Everything starts with a **Virtual Private Cloud (VPC)** — your own isolated network inside AWS.

### Design your VPC with Availability Zones in mind

Always span your architecture across **at least 2 Availability Zones (AZs)**. An AZ is essentially a separate physical data center within the same region. If one goes down, the other keeps your app alive.

```
VPC — 10.0.0.0/16
│
├── AZ-1 (ap-south-1a)
│     ├── Public Subnet   10.0.1.0/24   ← ALB lives here
│     ├── Private Subnet  10.0.2.0/24   ← EC2/ECS lives here
│     └── Private Subnet  10.0.3.0/24   ← RDS, Redis live here
│
└── AZ-2 (ap-south-1b)
      ├── Public Subnet   10.0.4.0/24   ← ALB (standby)
      ├── Private Subnet  10.0.5.0/24   ← EC2/ECS (standby)
      └── Private Subnet  10.0.6.0/24   ← RDS (standby), Redis
```

> **Why multiple subnets per AZ?** Separation of concerns. Your app servers and databases are in different subnets so you can apply different security group rules and network ACLs to each layer independently.

---

## Step 2 — Web Tier: ALB + WAF

### Application Load Balancer (ALB)

The **ALB** sits in the **public subnet** and is the only entry point from the internet into your system. It:

- Distributes incoming traffic across multiple EC2/ECS instances in the App Tier
- Performs **health checks** — if an instance is unhealthy, it stops sending traffic there
- Supports **path-based and host-based routing** (e.g., `/api/*` → backend, `/*` → frontend)
- Terminates SSL/TLS — handles HTTPS so your app servers don't have to

### Security Group — ALB

```
ALB Security Group
┌─────────────────────────────────┐
│  Inbound:                       │
│  Port 80  (HTTP)  → 0.0.0.0/0  │  ← Allow all internet traffic
│  Port 443 (HTTPS) → 0.0.0.0/0  │  ← Allow all internet traffic
│                                 │
│  Outbound:                      │
│  Port [App Port]  → EC2 SG only │  ← Forward only to App Tier
└─────────────────────────────────┘
```

### WAF — Web Application Firewall

Place **AWS WAF** in front of the ALB. WAF inspects every HTTP/HTTPS request before it hits your load balancer and blocks:

- **SQL Injection** attacks
- **Cross-Site Scripting (XSS)** attacks
- **IP-based rate limiting** — blocks users sending too many requests (DDoS protection)
- **Geo-blocking** — block traffic from specific countries if needed
- **Known bad bots** using AWS Managed Rule Groups

> Think of WAF as the **bouncer at the door** — ALB is the reception desk inside. The bouncer decides who even gets to walk in.

---

## Step 3 — App Tier: EC2 + Auto Scaling Group

### EC2 with Auto Scaling Group (ASG)

Your application — both **frontend and backend** — runs on EC2 instances (or ECS containers) in the **private subnet**. They are never directly accessible from the internet.

The **Auto Scaling Group** ensures:

- Minimum instances are always running (e.g., min: 2)
- Automatically adds instances when CPU or request count spikes (scale out)
- Automatically removes instances when traffic drops (scale in)
- Always maintains instances across **multiple AZs** for high availability

```
                    ALB
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
    EC2 (AZ-1)            EC2 (AZ-2)
  [App Server]          [App Server]
  Private Subnet        Private Subnet
          │                     │
          └──────────┬──────────┘
                     │
                     ▼
              RDS / Redis
             Private Subnet
```

### Security Group — EC2 / ECS

```
EC2 Security Group
┌──────────────────────────────────────────────┐
│  Inbound:                                    │
│  Port [App Port]  → ALB Security Group only  │  ← NEVER open to internet
│                                              │
│  Outbound:                                   │
│  Port 3306 / 5432 → RDS Security Group only  │
│  Port 6379        → Redis Security Group only│
└──────────────────────────────────────────────┘
```

> **Key principle:** EC2 only accepts traffic from the ALB security group — not from any IP address. This means even if someone somehow knows your EC2's private IP, they cannot reach it directly.

### Connecting to EC2 — Session Manager (No SSH Needed)

Forget opening **port 22** for SSH. Instead, use **AWS Systems Manager Session Manager**:

- Connect to your EC2 instance directly from the AWS Console — no key pairs, no bastion host
- All session activity is **logged to CloudTrail and S3** for auditing
- No inbound ports need to be opened on your EC2 security group
- Works even in fully private subnets with no internet access

```
Developer → AWS Console → Session Manager → EC2 (Private Subnet)
                                            (Zero open inbound ports)
```

---

## Step 4 — DB Tier: RDS Multi-AZ + ElastiCache Redis

### RDS with Multi-AZ

Your database runs in the **private subnet** — never publicly accessible.

Enable **Multi-AZ** on RDS:

```
                 EC2 (App Tier)
                      │
                      ▼
          ┌─── RDS Primary (AZ-1) ───┐
          │     (Reads + Writes)      │
          │                           │
          │   Synchronous Replication │
          │                           │
          └─── RDS Standby (AZ-2) ───┘
                  (Failover only)
```

- RDS **synchronously replicates** data to a standby instance in another AZ
- If the primary goes down, AWS **automatically promotes the standby** — typically within 60–120 seconds
- Your application connects via the **RDS endpoint** — the same endpoint works after failover automatically (no app config change needed)

### Security Group — RDS

```
RDS Security Group
┌──────────────────────────────────────────────────┐
│  Inbound:                                        │
│  Port 3306 (MySQL) → EC2 Security Group only     │
│  Port 5432 (PgSQL) → EC2 Security Group only     │
│                                                  │
│  Outbound: None needed                           │
└──────────────────────────────────────────────────┘
```

> RDS accepts connections **only from EC2 security group** — not from any IP, not from the internet, not even from other AWS services unless explicitly allowed.

---

## Step 5 — Caching Layer: ElastiCache Redis

### What is Redis Doing Here?

Redis is an **in-memory key-value store** that sits between your application and your database. When your app needs data, it checks Redis first. If the data is there (cache hit), it returns instantly — **no database query needed**.

```
Request comes in
       │
       ▼
  Check Redis ──── HIT ────► Return data instantly (< 1ms)
       │
      MISS
       │
       ▼
  Query RDS ──────────────► Store result in Redis ──► Return data
                             (for next time)
```

### When Redis Makes Sense ✅

Redis is worth the added complexity when your app has:

- **Heavy read traffic** — thousands of requests per second hitting the same data
- **Repeated access to the same data** — e.g., a product page viewed by 10,000 users/hour
- **A clear need to reduce DB load** — your RDS CPU is consistently high
- **Session storage** — storing user login sessions across multiple EC2 instances
- **Rate limiting** — track API call counts per user in real time

### When Redis is NOT Needed ❌

Don't add Redis just because it sounds good. Skip it when:

- The **app is small or early stage** — added complexity with zero benefit
- **DB load is already acceptable** — if RDS CPU is at 20%, Redis won't help meaningfully
- **Data changes very frequently** — if data updates every second, your cache becomes stale immediately and you spend more time invalidating than benefiting
- **Your queries are already fast** — adding a cache layer adds network hops; if DB responds in 2ms, Redis won't feel faster

### Security Group — Redis

```
Redis Security Group
┌──────────────────────────────────────────────────┐
│  Inbound:                                        │
│  Port 6379 → EC2 Security Group only             │
│                                                  │
│  Outbound: None needed                           │
└──────────────────────────────────────────────────┘
```

---

## The Complete Architecture at a Glance

```
                        INTERNET
                            │
                            ▼
                    ┌──────────────┐
                    │  AWS WAF     │  ← Blocks attacks before they enter
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │     ALB      │  ← Public Subnet, ports 80/443 open
                    └──────┬───────┘
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
      ┌─────────────┐            ┌─────────────┐
      │  EC2 / ECS  │            │  EC2 / ECS  │  ← Private Subnet
      │   (AZ-1)    │            │   (AZ-2)    │    App port open to ALB SG only
      └──────┬──────┘            └──────┬──────┘
             │                          │
             └────────────┬─────────────┘
                          │
             ┌────────────┴────────────┐
             ▼                         ▼
      ┌─────────────┐          ┌─────────────┐
      │  RDS Primary│          │  Redis      │  ← Private Subnet
      │  Multi-AZ   │          │  ElastiCache│    Open to EC2 SG only
      └─────────────┘          └─────────────┘
             │
      ┌──────▼──────┐
      │ RDS Standby │  ← Auto-failover, different AZ
      └─────────────┘
```

---

## Who Decides What? — The People Behind the Architecture

A production architecture is never designed by one person in isolation. Three roles collaborate:

### 👨‍💻 Developer
Knows the application inside out:
- Which API endpoints are called most frequently?
- Which database queries are expensive and repeated?
- What data is safe to cache and for how long?
- Where are the bottlenecks under load?

The developer's input directly determines **whether Redis is needed** and **what gets cached**.

### 🏗️ Solutions Architect / Software Architect
Owns the big picture decisions:
- Which AWS services to use and why
- Trade-offs between cost, performance, and complexity
- Failover strategy — what happens when each component fails?
- Consistency requirements — can we serve slightly stale data from cache?
- Overall security design — network topology, IAM roles, encryption

### ⚙️ DevOps Engineer
Ensures the architecture is **operable in production**:
- How is the infrastructure provisioned? (Terraform / CloudFormation)
- How are deployments rolled out? (Blue-Green, Rolling)
- How is the system monitored? (CloudWatch, alerts, dashboards)
- What are the cost implications of running this 24/7?
- Failover testing — does Multi-AZ actually work when triggered?

> **The architecture on paper and the architecture in production are only the same when all three collaborate.** A beautiful design that's impossible to deploy is worthless. An easily deployed design with no thought for failure is dangerous.

---

## Step 6 — CDN Layer: Amazon CloudFront

### What is a CDN and Why Does it Belong Here?

So far, every user request travels all the way from their browser → across the internet → to your ALB → to your EC2 → back again. If your servers are in Mumbai and a user is in London, that round trip adds **200–300ms of latency** on every single request. For a user in the same city it feels fast. For a global user base, it feels sluggish.

A **Content Delivery Network (CDN)** solves this by caching your content at **edge locations** — servers physically distributed across the globe, close to your users. AWS's CDN service is called **Amazon CloudFront**, and it has **400+ edge locations** worldwide.

```
WITHOUT CloudFront:
User (London) ──── 250ms ────► ALB (Mumbai) ──► EC2 ──► Response

WITH CloudFront:
User (London) ──── 10ms ─────► CloudFront Edge (London) ──► Response
                                     (cached content served instantly)
```

---

### How CloudFront Fits Into the Architecture

CloudFront sits **in front of everything** — it becomes the very first thing users hit, before WAF, before ALB, before your servers:

```
                        INTERNET
                            │
                            ▼
                  ┌──────────────────┐
                  │   CloudFront     │  ← Global Edge Locations
                  │   Distribution   │    400+ locations worldwide
                  └────────┬─────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
   ┌─────────────────┐       ┌──────────────────┐
   │   Cache HIT     │       │   Cache MISS      │
   │                 │       │                   │
   │ Serve from Edge │       │ Forward to Origin │
   │ (No trip to AWS)│       │ (ALB → EC2)       │
   └─────────────────┘       └──────────────────┘
```

> **Cache HIT** = CloudFront already has the content at the edge → returns it instantly, your servers never get involved.

> **Cache MISS** = CloudFront doesn't have it yet → fetches from your ALB (origin), caches it at the edge for future requests.

---

### What CloudFront Caches vs What It Doesn't

This is the most important thing to understand. CloudFront is not a magic switch — you control precisely what gets cached.

**Cache these (static, rarely changing):**

```
/static/images/*      → Profile pictures, product images, icons
/static/css/*         → Stylesheets
/static/js/*          → JavaScript bundles
/static/fonts/*       → Web fonts
/downloads/*          → PDFs, files
```

**Never cache these (dynamic, user-specific):**

```
/api/user/profile     → Different for every logged-in user
/api/orders           → Real-time data, must always be fresh
/api/checkout         → Payment flows, must never be cached
/api/auth/*           → Login, logout, token refresh
```

### How to Implement This — Behaviors

In CloudFront, you set up **Behaviors** — rules that tell CloudFront what to do based on the URL path:

| Path Pattern | Cache | TTL | Goes To |
|---|---|---|---|
| `/static/*` | ✅ Yes | 1 year | S3 or ALB |
| `/images/*` | ✅ Yes | 30 days | S3 or ALB |
| `/api/*` | ❌ No | 0 | ALB → EC2 |
| `/*` (default) | ✅ Yes | 1 day | ALB → EC2 |

---

### CloudFront + S3 — The Best Combo for Static Assets

For static files (images, CSS, JS), the ideal setup is:

```
Browser
   │
   ▼
CloudFront Edge
   │
   │── Cache HIT  ──────────────────────────────► Serve instantly
   │
   └── Cache MISS ──► S3 Bucket (Private)  ──► Cache & Serve
                       (Origin Access Control)
```

Store all your static assets in an **S3 bucket** — make the bucket **private** (no public access). Then give CloudFront exclusive access to that bucket using **Origin Access Control (OAC)**. This means:

- Users can never directly access your S3 bucket URL
- All traffic goes through CloudFront — giving you caching, HTTPS, and access control in one place
- S3 costs are lower because CloudFront serves cached files instead of S3 fetching them repeatedly

---

### CloudFront + WAF — Security at the Edge

Here's an important upgrade from our earlier WAF setup. Previously we placed WAF in front of the ALB — which means malicious traffic still travels all the way to your AWS region before being blocked.

With CloudFront, you can attach WAF **at the edge**:

```
BEFORE (WAF on ALB):
Attacker (London) ──► travels to Mumbai ──► WAF blocks ──► ALB

AFTER (WAF on CloudFront):
Attacker (London) ──► CloudFront Edge (London) ──► WAF blocks ──► Request never reaches Mumbai
```

This is significantly better because:
- Malicious traffic is blocked **closest to its source**
- Your ALB and EC2 instances never see the attack traffic at all
- Reduces load on your origin infrastructure during attacks
- **DDoS protection** (AWS Shield Standard) is automatically included with CloudFront at no extra cost

---

### CloudFront + HTTPS — SSL Everywhere

CloudFront handles your **SSL certificate** using **AWS Certificate Manager (ACM)**:

- Request a free SSL certificate from ACM for your domain (e.g., `yourdomain.com`)
- Attach it to your CloudFront distribution
- CloudFront enforces HTTPS between users and the edge
- Between CloudFront and your ALB, use another certificate on the ALB (can also be ACM)

```
User ──HTTPS──► CloudFront (ACM cert) ──HTTPS──► ALB (ACM cert) ──HTTP──► EC2
     encrypted                        encrypted                  internal only
```

> You get **end-to-end encryption** without your EC2 instances ever needing to deal with SSL termination. CloudFront and ALB handle it all.

---

### When CloudFront Makes Sense ✅

- Your users are **geographically distributed** — India, US, Europe, Southeast Asia
- You serve **large amounts of static content** — images, videos, JS bundles
- You want to **reduce load on your EC2 instances** — cache at the edge, fewer origin requests
- You want **DDoS protection** built in without extra configuration
- You want **faster page loads globally** — sub-10ms for cached content from edge

### When CloudFront is Overkill ❌

- Your entire user base is in **one city or country** — latency gains are minimal
- Your app is **fully dynamic** — every response is unique per user, caching gives no benefit
- You're in **early stage** — traffic is low, the complexity isn't justified yet

---

### The Complete Architecture — Now With CloudFront

```
                          INTERNET
                              │
                              ▼
                  ┌───────────────────────┐
                  │      CloudFront       │  ← Global CDN, 400+ edge locations
                  │   + WAF (at edge)     │  ← Blocks attacks at source
                  │   + Shield Standard   │  ← DDoS protection (free)
                  └───────────┬───────────┘
                              │
               ┌──────────────┴──────────────┐
               ▼                              ▼
     Static Assets (Cache HIT)        Dynamic Requests (Cache MISS)
               │                              │
               ▼                              ▼
      ┌─────────────────┐          ┌──────────────────┐
      │   S3 Bucket     │          │      ALB          │  ← Public Subnet
      │ (Private, OAC)  │          │  ports 80 / 443   │
      └─────────────────┘          └────────┬─────────┘
                                            │
                              ┌─────────────┴─────────────┐
                              ▼                             ▼
                       ┌─────────────┐             ┌─────────────┐
                       │  EC2 / ECS  │             │  EC2 / ECS  │  ← Private Subnet
                       │   (AZ-1)    │             │   (AZ-2)    │
                       └──────┬──────┘             └──────┬──────┘
                              │                           │
                              └──────────┬────────────────┘
                                         │
                            ┌────────────┴────────────┐
                            ▼                          ▼
                     ┌─────────────┐          ┌─────────────┐
                     │  RDS        │          │   Redis     │  ← Private Subnet
                     │  Multi-AZ   │          │ ElastiCache │
                     └─────────────┘          └─────────────┘
```

---

## Security Summary — Port Rules at a Glance

| Component | Port | Open To |
|---|---|---|
| CloudFront | 80, 443 | Internet (0.0.0.0/0) |
| ALB | 80, 443 | CloudFront IPs only (via prefix list) |
| EC2 / ECS | App Port (e.g., 8080) | ALB Security Group only |
| RDS | 3306 / 5432 | EC2 Security Group only |
| Redis | 6379 | EC2 Security Group only |
| S3 | — | CloudFront OAC only (bucket policy) |
| EC2 SSH | ❌ Closed | Use Session Manager instead |

> **Pro tip:** Once you add CloudFront, lock down your ALB so it **only accepts traffic from CloudFront IP ranges** — not from the open internet. This prevents attackers from bypassing CloudFront/WAF by hitting your ALB directly.

---

## Key Takeaways

- **Never expose your app servers or databases directly to the internet** — only the ALB lives in a public subnet, and even that should only accept CloudFront traffic
- **CloudFront is your global front door** — cache static assets at the edge, dramatically reducing latency for users worldwide
- **WAF belongs on CloudFront, not just ALB** — block attacks at the edge before they ever reach your region
- **S3 + CloudFront + OAC** is the gold standard for serving static assets — private bucket, cached globally, always HTTPS
- **Multi-AZ is non-negotiable for production** — both RDS and your EC2 ASG should span multiple AZs
- **Session Manager over SSH** — more secure, fully audited, no open ports needed
- **Add Redis only when the problem is real** — premature caching adds complexity without benefit
- **Security groups are layered** — each tier only talks to the tier directly below it, never across tiers

---

## Final Thought

A production architecture is never finished — it evolves. Start with the 3-tier core (ALB + EC2 + RDS), prove your product works, then layer in Redis when your database starts sweating and CloudFront when your users start complaining about speed. Every addition should be driven by a real problem, not a desire to use interesting technology.

The architecture described here — VPC, subnets across AZs, ALB, WAF, EC2 with ASG, RDS Multi-AZ, ElastiCache Redis, CloudFront with S3 — is genuinely what powers applications serving millions of users daily. Not because it's complex, but because every single piece earns its place.

Build it understanding *why* each piece exists. That understanding is what separates an engineer who configures AWS from one who architects on it.

---

*Found this useful? Follow for more AWS deep-dives — next up: Infrastructure as Code with Terraform to deploy everything in this article automatically.*
