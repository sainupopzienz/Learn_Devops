# Auto Scaling Group (ASG)

### What is ASG
- Automatically adds/removes EC2 instances based on demand
- Works with **Launch Templates** (AMI, instance type, user data)
- Scales based on: CPU, memory, custom CloudWatch metrics, schedule
- Always maintains **min / max / desired** instance count
- Works with ALB — new instances auto-register to target group

### Scaling Policies

| Policy | Trigger | Use Case |
|--------|---------|----------|
| Target Tracking | Keep metric at target (e.g. CPU 60%) | General use |
| Step Scaling | Scale based on alarm thresholds | Fine-grained control |
| Scheduled | Scale at specific times | Known traffic patterns |
| Predictive | ML-based forecast | Variable workloads |

### Example Config
```
min_size     = 2
max_size     = 10
desired      = 3
health_check = ELB (use ELB not EC2 for app health)
```
