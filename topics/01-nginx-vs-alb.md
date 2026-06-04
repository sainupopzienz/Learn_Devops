# NGINX vs Load Balancer (ALB)

### NGINX
- Web server + reverse proxy + Layer 7 load balancer
- Runs **inside your infrastructure** (on EC2, pod, container)
- Handles: serving static files, SSL termination, rate limiting, routing to upstream services
- You manage it, you maintain it

### ALB (Application Load Balancer)
- AWS **managed** load balancer — Layer 7
- Sits **in front** of your infrastructure
- Features: path-based routing, host-based routing, sticky sessions, WAF integration

### Comparison

| Feature | NGINX | ALB |
|---------|-------|-----|
| Managed by | You | AWS |
| Layer | L4 + L7 | L7 |
| Location | Inside infra | In front of infra |
| Cost | Free (self-hosted) | Pay per use |
| Use case | Internal routing, API gateway | Entry point to AWS infra |

> **Typical combo:** ALB → NGINX (inside cluster) → App
