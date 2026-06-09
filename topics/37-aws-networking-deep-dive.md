# AWS Networking Deep Dive: VPC, Transit Gateway, and PrivateLink

## The Invisible Backbone of Every AWS Architecture

---

Networking is the part of AWS that most engineers understand just enough to get things working — and not enough to understand why things break. A misconfigured route table, a missing NAT Gateway, a security group rule pointing the wrong way — any of these can silently break your architecture in ways that take hours to debug.

This article goes deep on AWS networking — VPCs, subnets, routing, peering, Transit Gateway, PrivateLink, and Route 53.

---

## VPC — Your Private Network on AWS

A VPC is your own isolated network inside AWS. Every resource you create lives inside a VPC.

```
AWS Cloud
┌─────────────────────────────────────────────┐
│  Your VPC (10.0.0.0/16)                     │
│  ┌──────────────┐  ┌──────────────┐         │
│  │ Public Subnet│  │Private Subnet│         │
│  │ 10.0.1.0/24  │  │ 10.0.2.0/24 │         │
│  │ EC2 (ALB)    │  │ EC2 (App)   │         │
│  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────┘
```

### Public vs Private Subnets

The difference is one thing: a route to an Internet Gateway.

```
Public Subnet:  Route 0.0.0.0/0 → Internet Gateway  (two-way internet)
Private Subnet: Route 0.0.0.0/0 → NAT Gateway       (outbound only)
```

### Internet Gateway vs NAT Gateway

**Internet Gateway (IGW):** Enables two-way internet for public subnets. Free.

**NAT Gateway:** Allows private subnet resources to make outbound internet requests. Internet cannot initiate connections inbound. Costs ~$0.045/hour. Deploy one per AZ for HA.

```
Private EC2 → NAT Gateway → Internet Gateway → Internet → Response
Internet    → NAT Gateway → BLOCKED (cannot reach private resources)
```

---

## Route Tables

Every subnet has a route table:

```
Public Subnet Route Table:
  10.0.0.0/16  → local        (stays inside VPC)
  0.0.0.0/0    → igw-xxxxx   (internet bound)

Private Subnet Route Table:
  10.0.0.0/16  → local        (stays inside VPC)
  0.0.0.0/0    → nat-xxxxx   (outbound via NAT)
```

---

## Security Groups vs Network ACLs

| Feature | Security Group | Network ACL |
|---|---|---|
| Level | Instance/service | Subnet |
| State | Stateful | Stateless |
| Rules | Allow only | Allow + Deny |
| Use for | Primary access control | Block IP ranges at subnet |

### Security Group Chaining — The Right Way

```
# Wrong — hardcoded IP breaks when EC2 scales
RDS SG: Allow port 3306 from 10.0.2.45/32

# Right — references the security group ID
RDS SG: Allow port 3306 from sg-app-server
```

---

## VPC Endpoints — Stay Inside AWS

By default, EC2 to S3 traffic goes over the public internet. Endpoints keep it inside AWS.

**Gateway Endpoints (free):** S3 and DynamoDB only.
**Interface Endpoints (paid ~$0.01/hr):** All other AWS services (Secrets Manager, SSM, ECR, CloudWatch).

```
EC2 (private) → VPC Endpoint → S3 (stays inside AWS, no NAT Gateway needed)
```

---

## VPC Peering — Connecting Two VPCs

Creates a direct private connection between two VPCs:

```
VPC A (10.0.0.0/16) ←── Peering ──► VPC B (10.1.0.0/16)
```

**Key constraints:**
- No transitive peering — A peers B, B peers C, A cannot reach C via B
- CIDR ranges cannot overlap
- Works cross-region and cross-account

---

## AWS Transit Gateway — Network Hub

For more than 3 VPCs, peering becomes a mesh. Transit Gateway is a central hub:

```
WITHOUT TGW (6 peering connections for 4 VPCs):
A↔B, A↔C, A↔D, B↔C, B↔D, C↔D

WITH Transit Gateway:
VPC-A ──┐
VPC-B ──┤──► Transit Gateway ◄── VPN/Direct Connect
VPC-C ──┤
VPC-D ──┘
```

TGW routing tables control which VPCs can talk to each other — production cannot accidentally reach dev.

---

## AWS PrivateLink — Expose Services Privately

Lets you expose a service to other VPCs without peering or public internet:

```
Provider VPC (Your Service + NLB) ←── PrivateLink ──► Consumer VPC EC2
(traffic never leaves AWS network)
```

---

## Route 53 — DNS and Traffic Routing

### Routing Policies

**Simple:** One IP, no logic.

**Weighted:**
```
80% → Server A,  20% → Server B
Use for: A/B testing, canary deployments
```

**Latency-Based:**
```
Mumbai user → ap-south-1,  London user → eu-west-1
Use for: Global apps — route to closest region automatically
```

**Failover:**
```
Primary: ALB us-east-1 (health check passing)
Failover: ALB eu-west-1 (activates only if primary fails)
Use for: Disaster recovery — automatic DNS failover
```

**Geolocation:**
```
India → ap-south-1,  Europe → eu-west-1,  USA → us-east-1
Use for: Data residency, localized content
```

---

## Direct Connect vs VPN

| Feature | VPN (Site-to-Site) | Direct Connect |
|---|---|---|
| Connection | Over public internet (encrypted) | Dedicated private line |
| Bandwidth | Up to 1.25 Gbps | 1–100 Gbps |
| Latency | Variable | Consistent, low |
| Setup time | Hours | Weeks to months |
| Best for | Dev/test, small workloads | Enterprise, compliance |

---

## Global Accelerator vs CloudFront

```
CloudFront:         CDN, caches content, Layer 7 (HTTP), reduces origin load
Global Accelerator: Routes TCP/UDP through AWS backbone, Layer 4, no caching
                    Best for gaming, IoT, VoIP, non-HTTP workloads
                    Provides 2 static Anycast IPs that work globally
```

---

## Complete Network Architecture

```
Internet
    │
Route 53 (DNS + health checks + failover)
    │
CloudFront (CDN + WAF + DDoS)
    │
Internet Gateway
    │
┌───────────────────────────────────────────────────┐
│  VPC (10.0.0.0/16)                               │
│  Public Subnets:  ALB, NAT Gateway               │
│  Private Subnets: ECS, VPC Endpoints             │
│  Data Subnets:    RDS Multi-AZ, ElastiCache      │
└───────────────────────────────────────────────────┘
    │
    ├── Transit Gateway ──► Other VPCs
    └── Direct Connect  ──► On-premises
```

---

## Key Takeaways

- **Public subnet = route to IGW, private = route to NAT** — that is the only real difference
- **Security group chaining** — reference SG IDs, never hardcode IP addresses
- **VPC Endpoints save NAT Gateway costs** and keep AWS traffic off the internet
- **Peering for 2–3 VPCs, Transit Gateway for anything more** — avoid peering meshes
- **Route 53 routing policies are a DR tool** — failover and latency-based routing solve real problems
- **NAT Gateway per AZ** — one NAT is a single point of failure for all private subnets
- **Direct Connect for enterprise** — when you need consistent bandwidth and compliance

---

*Found this useful? Follow for more AWS deep-dives — next up: AWS Cost Optimization — how to cut your AWS bill without cutting performance.*
