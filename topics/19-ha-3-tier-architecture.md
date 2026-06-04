# High Availability 3-Tier Architecture on AWS

### Architecture
```
Route 53         (DNS + health check failover)
     ↓
CloudFront       (CDN + WAF)
     ↓
[PUBLIC SUBNETS — AZ-1, AZ-2, AZ-3]
ALB              (Application Load Balancer)
     ↓
[PRIVATE SUBNETS — AZ-1, AZ-2, AZ-3]
Auto Scaling Group (EC2 / EKS / ECS)
     ↓
[DB SUBNETS — AZ-1, AZ-2]
RDS Multi-AZ     (Primary + Standby)
ElastiCache      (Redis cluster mode)
```

### HA Principles
- No single point of failure at any tier
- Minimum 2 AZs everywhere (preferably 3)
- ASG replaces unhealthy instances automatically
- RDS automatic failover (Multi-AZ) in under 60 seconds
- ALB health checks remove unhealthy targets instantly

| Layer | HA Mechanism |
|-------|-------------|
| DNS | Route 53 health checks + failover |
| Web/App | ASG + ALB across multiple AZs |
| Database | RDS Multi-AZ + Read Replicas |
| Cache | ElastiCache cluster mode |
