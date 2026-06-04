# 5 Security Implementations in Projects

### 1. IRSA (IAM Roles for Service Accounts)
Pods get only the IAM they need — not the entire node's role. Prevents lateral movement if a pod is compromised.

### 2. Secrets Manager + External Secrets Operator
Secrets never stored in code or ConfigMaps. ESO automatically syncs from AWS Secrets Manager into K8s secrets.

### 3. Image Scanning with Trivy in CI
Every Docker image scanned before push to ECR. Pipeline hard-fails on CRITICAL vulnerabilities.

### 4. Network Policies in EKS
Restricted pod-to-pod traffic using Kubernetes NetworkPolicy. Default deny all — only explicitly allowed services communicate.

### 5. WAF + ALB
AWS WAF rules on ALB for all public apps: rate limiting, SQL injection protection, XSS filtering, geo-blocking.
