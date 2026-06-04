# Real Problems Faced on AWS Projects

### Issues & Solutions

- **VPC peering routing wrong** — Services couldn't talk across VPCs. Fixed by correcting route tables + security groups.
- **RDS connection pool exhaustion** — Lambda functions opening too many connections. Fixed using RDS Proxy.
- **S3 bucket policy vs IAM conflict** — Access denied despite correct IAM. Fixed by aligning both policies.
- **NAT Gateway cost spike** — All traffic going through NAT. Fixed using VPC endpoints for S3/ECR.
- **EKS can't pull ECR images** — Node IAM role missing ecr:GetAuthorizationToken. Added policy.
- **ALB 504 timeout** — Task taking too long. Increased ALB idle timeout + optimized app.
- **CloudWatch log retention not set** — Logs growing indefinitely. Added 30/90 day retention policy.
- **IAM role permission boundary** — Cross-account role not working. Fixed trust policy + boundary.

> **Lesson:** Always check Security Groups, Route Tables, and IAM policies together — most AWS issues are one of these three.
