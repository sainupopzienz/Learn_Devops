# VPC & IAM Setup in Existing Projects

### VPC Architecture
```
VPC (10.0.0.0/16)
├── Public Subnets   → ALB, NAT Gateway, Bastion
├── Private Subnets  → EKS Nodes, ECS, App Servers
└── DB Subnets       → RDS, ElastiCache (no internet)

Internet Gateway  → attached to VPC
NAT Gateway       → public subnet, routes private subnets
VPC Endpoints     → S3, ECR, Secrets Manager (no NAT cost)
Security Groups   → per layer — least privilege
```

### IAM Setup
- No root account usage — IAM users with MFA only
- Roles for EC2/EKS nodes (instance profiles)
- **IRSA** (IAM Roles for Service Accounts) in EKS — pod-level IAM
- Separate roles per environment (dev-role, prod-role)
- Permission boundaries to prevent privilege escalation
- **SCPs** at AWS Org level to restrict regions/services
