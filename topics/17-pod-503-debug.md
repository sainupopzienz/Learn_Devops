# Pod Running but App Showing 503 Error

**503 = Service Unavailable** — pod is up but can't serve traffic.

### Checklist
- **Readiness probe failing?** — `kubectl describe pod` → check Readiness status
- **App crashed inside container?** — `kubectl logs <pod>` → check for errors
- **Service selector wrong?** — selector must match pod labels exactly
- **Ingress/ALB misconfigured?** — check ALB target group health in AWS Console
- **Wrong port?** — Service port vs containerPort mismatch
- **DB not reachable?** — app starts but can't connect → returns 503
- **CPU throttling?** — limit too low → slow → timeout → 503

### Debug Flow
```bash
kubectl get pods
kubectl describe pod <pod-name>
kubectl logs <pod-name> --previous
kubectl describe svc <service-name>
kubectl get endpoints <service-name>   # must show pod IPs
```
