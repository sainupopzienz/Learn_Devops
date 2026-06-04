# EKS — Most Faced Issues & Critical Fixes

### Issue Breakdown

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Pods stuck Pending | No CPU/Memory on nodes | kubectl describe pod → add node group |
| OOMKilled | Memory limit too low | Increase memory limit in deployment |
| ImagePullBackOff | ECR auth expired / wrong tag | Refresh ECR token, check node IAM role |
| CrashLoopBackOff | App crash on startup | kubectl logs + describe pod for exit code |
| CoreDNS failing | DNS broken in cluster | Restart CoreDNS pods, check VPC DNS |
| Node NotReady | Kubelet / disk pressure | SSH to node, journalctl -u kubelet |
| Ingress 502/504 | Target unhealthy | Fix readiness probe, check ALB target group |
| Upgrade broke workloads | Deprecated API versions | Run kubent before upgrade |

### Debug Commands
```bash
kubectl get pods -A
kubectl describe pod <pod-name>
kubectl logs <pod-name> --previous
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl top nodes
kubectl top pods
```
