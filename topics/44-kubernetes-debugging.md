# Kubernetes Debugging: 8 Real Scenarios Every Engineer Must Know

## From CrashLoopBackOff to PVC Pending — Diagnose and Fix Like a Pro

---

Kubernetes is powerful. It's also remarkably good at showing you cryptic status messages at the worst possible moment — 2 AM, production down, users complaining.

The difference between an engineer who panics and one who methodically resolves Kubernetes issues is a mental model: a repeatable debugging workflow for every failure mode. This article gives you exactly that — 8 real scenarios, step-by-step commands, and the root cause behind each.

> **Malayalam readers:** ഓരോ scenario-യിലും Malayalam summary കൂടി ഉണ്ട് — quick revision-നു് helpful ആകും ✅

---

## The Universal Kubernetes Debug Flow

Before diving into specific scenarios, one principle covers 80% of all Kubernetes issues:

```
kubectl get pods              ← What is the status?
        │
        ▼
kubectl describe pod <name>   ← Why is it in that status? (events, exit codes)
        │
        ▼
kubectl logs <name>           ← What is the application saying?
        │
        ▼
kubectl exec -it <pod> -- sh  ← Can I reproduce it from inside?
        │
        ▼
Fix → Apply → Verify
```

Now let's go scenario by scenario.

---

## Scenario 1 — CrashLoopBackOff (Pod Constantly Restarts)

### What You See

```
NAME        READY   STATUS             RESTARTS   AGE
debug-me    0/1     CrashLoopBackOff   5          3m
```

Kubernetes is starting the container, the container crashes, Kubernetes restarts it, it crashes again — in an exponential backoff loop.

### Step-by-Step Debug

```bash
# Step 1: Confirm the status
kubectl get pods

# Step 2: Check events and exit code
kubectl describe pod debug-me
# Look for:
#   Last State: Terminated  Reason: Error  Exit Code: 1
#   Events: Back-off restarting failed container

# Step 3: Check current logs
kubectl logs debug-me

# Step 4: Check logs from the PREVIOUS (crashed) container — this is the important one
kubectl logs debug-me --previous

# Step 5: Check if resource limits are the issue
kubectl get pod debug-me -o yaml | grep -A5 resources
```

### Exit Code Reference

| Exit Code | Meaning | Fix |
|---|---|---|
| 1 | Application crash, wrong command, missing config | Check `kubectl logs`, fix app or config |
| 127 | Command not found in container | Fix `command:` in pod YAML, check binary path |
| 137 | OOMKilled — memory limit exceeded | Increase `resources.limits.memory` |
| 143 | SIGTERM — graceful shutdown signal received | Usually fine, check if it should be running |

### Common Root Causes

```
Missing environment variable  →  App exits immediately on startup
Wrong entrypoint command      →  127: command not found
Memory limit too tight        →  137: OOMKilled
Application bug               →  Unhandled exception on startup
Missing config file            →  FileNotFoundError, exits with code 1
```

> **Malayalam:** Pod crash ചെയ്യുന്നു എങ്കിൽ — `kubectl describe pod` → events കാണുക, exit code note ചെയ്യുക (1=app crash, 137=memory, 127=command not found), `kubectl logs --previous` → crashed container-ൻ്റെ logs കാണുക, fix ചെയ്ത് redeploy ചെയ്യുക ✅

---

## Scenario 2 — Pod Pending (Not Scheduled)

### What You See

```
NAME        READY   STATUS    RESTARTS   AGE
debug-me    0/1     Pending   0          10m
```

The pod exists in etcd but the scheduler cannot find a node to place it on.

### Step-by-Step Debug

```bash
# Step 1: Confirm status
kubectl get pods

# Step 2: Check scheduler events — this will tell you exactly why
kubectl describe pod debug-me
# Look for Events section:
#   "0/3 nodes are available: 3 Insufficient cpu"
#   "0/3 nodes are available: 1 node(s) had taint, 2 Insufficient memory"
#   "0/3 nodes are available: 3 node(s) didn't match pod's node affinity"

# Step 3: Check node capacity
kubectl get nodes
kubectl describe node <node-name>
# Look for: Allocatable CPU and Memory vs Requests

# Step 4: Check actual resource usage
kubectl top nodes

# Step 5: If pod uses storage, check PVC
kubectl get pvc
kubectl describe pvc <pvc-name>
```

### Common Root Causes

| Reason in Events | Cause | Fix |
|---|---|---|
| Insufficient cpu | All nodes' CPU fully requested | Reduce pod `requests.cpu` or add more nodes |
| Insufficient memory | All nodes' memory fully requested | Reduce `requests.memory` or scale cluster |
| node(s) had taint | Node has a taint the pod doesn't tolerate | Add `tolerations` to pod spec |
| didn't match node affinity | nodeSelector / affinity rules don't match any node | Fix `nodeSelector` or add label to a node |
| PVC Pending | StorageClass unavailable or no PV | See Scenario 8 |

### Taint and Toleration Example

```yaml
# Node has taint: kubectl taint nodes node1 env=production:NoSchedule
# Pod must have toleration to be scheduled there:

spec:
  tolerations:
    - key: "env"
      operator: "Equal"
      value: "production"
      effect: "NoSchedule"
```

> **Malayalam:** Pod pending ആണ് എങ്കിൽ — `kubectl describe pod` → Events section-ൽ scheduler message കാണുക ("Insufficient cpu/memory" or "taint mismatch"), `kubectl top nodes` → actual usage കാണുക, request values reduce ചെയ്യുക അല്ലെങ്കിൽ node add ചെയ്യുക ✅

---

## Scenario 3 — Service No Endpoints (Traffic Not Routing)

### What You See

```
NAME         TYPE        CLUSTER-IP      PORT(S)   AGE
my-service   ClusterIP   10.96.100.10   80/TCP    5m

# But no traffic is reaching pods
```

### Step-by-Step Debug

```bash
# Step 1: Check the service exists
kubectl get svc my-service

# Step 2: CHECK ENDPOINTS — this is the most important command
kubectl get endpoints my-service
# Healthy output:  my-service   10.0.0.5:80,10.0.0.6:80   5m
# Broken output:   my-service   <none>                     5m

# Step 3: Check what selector the service is using
kubectl describe svc my-service
# Look for: Selector: app=web

# Step 4: Check if any pods match that selector
kubectl get pods -l app=web
# If empty → selector mismatch is the problem

# Step 5: Check pod readiness (Running but not Ready = not in endpoints)
kubectl get pods -l app=web
# Look at READY column: 0/1 means pod is excluded from endpoints

# Step 6: Verify the targetPort matches the container port
kubectl get svc my-service -o yaml | grep -A5 ports
kubectl get pod <pod-name> -o yaml | grep containerPort

# Step 7: Test from inside a pod
kubectl exec -it <pod-name> -- curl localhost:80
```

### Why Endpoints Stay Empty

```
Service selector:  app=web
Pod label:         app=webapp     ← MISMATCH — pod never enters endpoints

Service targetPort: 8080
Container port:    80              ← MISMATCH — health checks fail, pod not Ready

Pod is Running but Ready: 0/1     ← Readiness probe failing — excluded from endpoints
```

### Fix: Selector Must Exactly Match Pod Labels

```yaml
# Service
spec:
  selector:
    app: web          # Must match exactly

# Pod
metadata:
  labels:
    app: web          # Must match exactly — case sensitive
```

> **Malayalam:** Service traffic കിട്ടുന്നില്ല എങ്കിൽ — `kubectl get endpoints` → `<none>` ആണോ? `kubectl describe svc` → selector കാണുക, `kubectl get pods -l <selector>` → pods match ചെയ്യുന്നുണ്ടോ? Labels exact ആയി match ചെയ്യണം (case sensitive) ✅

---

## Scenario 4 — OOMKilled (Out of Memory)

### What You See

```
NAME        READY   STATUS    RESTARTS   AGE
debug-me    0/1     Running   5          15m

# kubectl describe shows:
Last State: Terminated   Reason: OOMKilled   Exit Code: 137
```

Kubernetes killed the container because it exceeded its memory limit.

### Step-by-Step Debug

```bash
# Step 1: Confirm OOMKilled
kubectl describe pod debug-me
# Look for: Last State: Terminated  Reason: OOMKilled  Exit Code: 137

# Step 2: Check current memory usage
kubectl top pod debug-me
# Output: debug-me   25m   195Mi
# Compare with limit: memory: 100Mi  ← container needs 195Mi but limit is 100Mi

# Step 3: Check what limits are configured
kubectl get pod debug-me -o yaml | grep -A8 resources

# Step 4: Check node-level memory pressure
kubectl describe node <node-name> | grep -A5 Conditions
# Look for: MemoryPressure: True
```

### Fix: Increase Memory Limit

```yaml
resources:
  requests:
    memory: "128Mi"     # What the pod asks for (used for scheduling)
    cpu: "250m"
  limits:
    memory: "256Mi"     # ← Increase this (was 100Mi)
    cpu: "500m"
```

### OOMKill vs Memory Leak

```
OOMKill on startup:
  App always needs more than the limit allows
  Fix: Increase the limit

OOMKill after running for hours (gradual):
  Likely a memory leak in the application
  Fix: Profile the app + fix the leak + add HPA for temporary relief

OOMKill during traffic spikes:
  App uses more memory under load
  Fix: Increase limit + add Horizontal Pod Autoscaler (HPA)
```

> **Malayalam:** Exit code 137 = OOMKilled, `kubectl top pod` → actual memory usage കാണുക, `resources.limits.memory` increase ചെയ്യുക (100Mi → 256Mi), gradual increase ആണ് എങ്കിൽ memory leak app-ൽ check ചെയ്യുക ✅

---

## Scenario 5 — ImagePullBackOff (Can't Pull Container Image)

### What You See

```
NAME        READY   STATUS             RESTARTS   AGE
debug-me    0/1     ImagePullBackOff   0          2m
```

Kubernetes cannot pull the container image from the registry.

### Step-by-Step Debug

```bash
# Step 1: Confirm status
kubectl get pods

# Step 2: Check the exact error
kubectl describe pod debug-me
# Look for Events:
#   "Failed to pull image: repository does not exist"
#   "Failed to pull image: unauthorized: access denied"
#   "Failed to pull image: no such host"

# Step 3: Verify the exact image name configured
kubectl get pod debug-me -o yaml | grep image:
# Is it nginx:1.25 or nginx:1.52? (typo?)

# Step 4: For private registries, check imagePullSecrets
kubectl get pod debug-me -o yaml | grep imagePullSecret
kubectl get secrets
# Is there a registry secret? Is it referenced in the pod?

# Step 5: Test if the image exists
docker pull <image-name>      # From your local machine
# or
crane ls <registry>/<image>   # List available tags
```

### Common Error Messages

| Error in Events | Meaning | Fix |
|---|---|---|
| `repository does not exist` | Wrong image name or tag | Fix `image:` field in YAML |
| `unauthorized: access denied` | Private registry, no credentials | Add `imagePullSecrets` |
| `no such host` | Cannot reach registry (DNS/network issue) | Check cluster DNS and network |
| `manifest unknown` | Tag doesn't exist | Check available tags, fix tag |

### Adding imagePullSecrets for Private Registries

```bash
# Create the secret
kubectl create secret docker-registry my-registry-secret \
  --docker-server=registry.example.com \
  --docker-username=myuser \
  --docker-password=mypassword

# Reference it in pod spec:
spec:
  imagePullSecrets:
    - name: my-registry-secret
  containers:
    - name: app
      image: registry.example.com/myapp:1.0
```

> **Malayalam:** `kubectl describe pod` → Events-ൽ error message കാണുക, "repository not found" = image name/tag wrong, "unauthorized" = private registry-ൽ secret ഇല്ല, `imagePullSecrets` add ചെയ്യുക ✅

---

## Scenario 6 — Readiness Probe Failed (Pod Not Ready)

### What You See

```
NAME        READY   STATUS    RESTARTS   AGE
debug-me    0/1     Running   0          5m
```

Pod is Running (container is alive) but READY shows 0/1 — meaning Kubernetes has excluded this pod from all Service endpoints. No traffic reaches it.

### Step-by-Step Debug

```bash
# Step 1: Confirm pod is running but not ready
kubectl get pods
# READY: 0/1 with STATUS: Running

# Step 2: Check probe failure events
kubectl describe pod debug-me
# Look for:
#   Readiness probe failed: HTTP probe failed with statuscode: 404
#   Readiness probe failed: Get "http://localhost:8080/health": connection refused

# Step 3: Check application logs — did the app start?
kubectl logs debug-me
# Is the app listening on the expected port?

# Step 4: Test the health endpoint manually from inside the pod
kubectl exec -it debug-me -- curl -v localhost:80/health
# What does the health endpoint return?

# Step 5: Check the probe configuration
kubectl get pod debug-me -o yaml | grep -A15 readinessProbe
```

### Common Probe Mistakes

```yaml
# ❌ WRONG — health endpoint is at /api/health, probe checks /health
readinessProbe:
  httpGet:
    path: /health        # Returns 404
    port: 8080

# ✅ CORRECT
readinessProbe:
  httpGet:
    path: /api/health    # Correct path
    port: 8080
  initialDelaySeconds: 15  # Give app time to start before first check
  periodSeconds: 10
  failureThreshold: 3      # Allow 3 failures before marking not ready
```

### Liveness vs Readiness vs Startup Probes

```
Startup Probe:    Is the app done initializing?
                  Blocks liveness + readiness probes until it passes
                  Use for slow-starting apps (Spring Boot, JVM warmup)

Readiness Probe:  Is the app ready to receive traffic?
                  Failure → removed from Service endpoints (no traffic)
                  Passes → included in Service endpoints (traffic routed here)

Liveness Probe:   Is the app still alive and not deadlocked?
                  Failure → container restarted
```

> **Malayalam:** Pod running but ready 0/1 — traffic ഒന്നും കിട്ടുന്നില്ല, `kubectl describe pod` → "readiness probe failed" കാണുക, `kubectl exec` → inside pod-ൽ curl test ചെയ്യുക, probe-ൻ്റെ path, port, initialDelaySeconds correct ആണോ? ✅

---

## Scenario 7 — Network Issue (Pod Can't Reach Service)

### What You See

```
# From inside a pod:
curl my-service:80
# curl: (6) Could not resolve host: my-service
# OR
# curl: (7) Failed to connect: Connection refused
# OR
# Request timeout after 30s
```

### Step-by-Step Debug

```bash
# Step 1: Exec into the source pod
kubectl exec -it <pod-name> -- /bin/sh

# Step 2: Test DNS resolution first
nslookup my-service
nslookup my-service.my-namespace.svc.cluster.local
# If this fails → DNS / CoreDNS issue

# Step 3: Test direct IP (bypass DNS)
kubectl get svc my-service   # Get ClusterIP
curl 10.96.100.10:80         # Use the ClusterIP directly
# If this works but DNS fails → CoreDNS problem
# If this also fails → Network or Service issue

# Step 4: Check if CoreDNS is running
kubectl get pods -n kube-system | grep coredns
# All CoreDNS pods should be Running

# Step 5: Check NetworkPolicy
kubectl get networkpolicy -n <namespace>
kubectl describe networkpolicy <name>
# Is there a policy blocking ingress or egress?

# Step 6: Check CNI plugin health
kubectl get pods -n kube-system | grep -E "calico|flannel|weave|cilium"
# CNI pod down = cluster-wide network broken
```

### DNS Resolution Rules in Kubernetes

```
Within same namespace:
  curl my-service               ← Short name works

Cross namespace:
  curl my-service               ← FAILS
  curl my-service.other-ns      ← Works
  curl my-service.other-ns.svc.cluster.local  ← Full FQDN, always works

Always works from anywhere:
  curl <service-name>.<namespace>.svc.cluster.local
```

### NetworkPolicy — Check If Traffic Is Blocked

```yaml
# This NetworkPolicy blocks ALL ingress to pods with label app=backend
# unless the source pod has label app=frontend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
spec:
  podSelector:
    matchLabels:
      app: backend
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend    # Only frontend can talk to backend
```

If your pod is blocked by a NetworkPolicy, either add the correct label or update the policy rules.

> **Malayalam:** Pod-ൽ നിന്ന് service reach ചെയ്യാൻ കഴിയുന്നില്ല — `nslookup` → DNS resolve ആകുന്നുണ്ടോ? CoreDNS running ആണോ? NetworkPolicy block ചെയ്യുന്നുണ്ടോ? Cross-namespace ആണ് എങ്കിൽ full FQDN ഉപയോഗിക്കുക (`service.namespace.svc.cluster.local`) ✅

---

## Scenario 8 — PVC Pending (Storage Not Bound)

### What You See

```
NAME     STATUS    VOLUME   CAPACITY   STORAGECLASS   AGE
my-pvc   Pending                       fast           5m
```

The PersistentVolumeClaim is not bound, which means any pod waiting for it is also stuck in Pending.

### Step-by-Step Debug

```bash
# Step 1: Check PVC status
kubectl get pvc

# Step 2: Check exactly why it's pending
kubectl describe pvc my-pvc
# Look for:
#   "storageclass.storage.k8s.io \"fast\" not found"
#   "no persistent volumes available for this claim"
#   "waiting for first consumer to be created before binding" (WaitForFirstConsumer mode)

# Step 3: List available StorageClasses
kubectl get storageclass
# Is "fast" in the list? What's the default StorageClass?

# Step 4: Check existing PersistentVolumes
kubectl get pv
# Are there unbound PVs that match this PVC?

# Step 5: Check namespace resource quota
kubectl describe resourcequota -n <namespace>
# Is storage quota exhausted?
```

### Static vs Dynamic Provisioning

```
Static Provisioning:
  Admin manually creates PV (with specific size, access mode, storageClass)
  PVC must match PV's storageClass, size, and accessMode
  If no PV matches → PVC stays Pending

Dynamic Provisioning:
  StorageClass has a provisioner (AWS EBS, GCP PD, Azure Disk)
  PVC request → StorageClass automatically creates a PV
  If StorageClass doesn't exist or provisioner is down → PVC stays Pending
```

### Common Fixes

```bash
# Fix 1: StorageClass name typo — check what's available
kubectl get storageclass
# Use the correct name in PVC

# Fix 2: Create PVC with default StorageClass (remove storageClassName)
spec:
  storageClassName: ""   # Uses cluster default

# Fix 3: For WaitForFirstConsumer mode, the PV is only created when
# a pod actually tries to use the PVC — this is normal behavior
# Just deploy the pod and PVC will bind

# Fix 4: Check cloud provider health
# AWS: Check EBS service status in your region
# GCP: Check GCP status page for Persistent Disk
```

> **Malayalam:** `kubectl describe pvc` → "storageclass not found" = StorageClass name wrong, "no PV available" = static provisioning-ൽ matching PV ഇല്ല, `kubectl get storageclass` → correct name use ചെയ്യുക, dynamic provisioning ആണ് എങ്കിൽ cloud provider status check ചെയ്യുക ✅

---

## Quick Debug Cheatsheet — All 10 Commands You Need

```bash
# 1. What is happening?
kubectl get pods -A                          # All pods in all namespaces

# 2. Why is this pod in that state?
kubectl describe pod <name>                  # Events, exit codes, probe status

# 3. What is the app saying?
kubectl logs <pod>                           # Current logs
kubectl logs <pod> --previous                # Logs from crashed container
kubectl logs <pod> -c <container>            # Specific container in multi-container pod

# 4. How much resource is it using?
kubectl top pod <name>                       # CPU and memory usage

# 5. Is the service reachable?
kubectl get endpoints <service-name>         # Empty = selector mismatch or pods not ready

# 6. Can I test from inside?
kubectl exec -it <pod> -- /bin/sh            # Shell into the pod
kubectl exec -it <pod> -- curl localhost:80  # Quick connectivity test

# 7. What does the full YAML look like?
kubectl get pod <name> -o yaml              # Full spec with all applied defaults

# 8. Is storage bound?
kubectl get pvc                              # PVC status

# 9. Any cluster-wide issues?
kubectl get events --sort-by='.lastTimestamp' # Most recent events first

# 10. Are system components healthy?
kubectl get pods -n kube-system              # CoreDNS, CNI, scheduler, controller-manager
```

---

## Scenario Summary Table

| Scenario | First Command | Key Symptom to Look For | Most Common Fix |
|---|---|---|---|
| CrashLoopBackOff | `kubectl logs --previous` | Exit Code 1/127/137 | Fix app config or increase memory |
| Pod Pending | `kubectl describe pod` | "Insufficient cpu/memory" in events | Reduce requests or scale cluster |
| No Endpoints | `kubectl get endpoints` | `<none>` in endpoint list | Fix label selector on Service |
| OOMKilled | `kubectl top pod` | Exit Code 137, OOMKilled reason | Increase `limits.memory` |
| ImagePullBackOff | `kubectl describe pod` | "unauthorized" or "not found" | Fix image name or add imagePullSecret |
| Not Ready | `kubectl describe pod` | "Readiness probe failed" | Fix probe path/port/initialDelay |
| Network Issue | `kubectl exec` + `nslookup` | DNS failure or connection refused | Fix CoreDNS, NetworkPolicy, or FQDN |
| PVC Pending | `kubectl describe pvc` | "storageclass not found" | Fix StorageClass name in PVC |

---

## Key Takeaways

- **`kubectl describe` is your best friend** — the Events section tells you exactly what Kubernetes tried and why it failed
- **`kubectl logs --previous`** is the command most engineers forget — the crashed container's logs are more useful than the current logs
- **Empty endpoints = selector mismatch** — always check `kubectl get endpoints` when traffic isn't routing
- **Exit Code 137 = OOMKilled** — the container didn't crash, Kubernetes killed it for exceeding its memory limit
- **Ready 0/1 ≠ Crashed** — pod can be Running but excluded from Service due to failing readiness probe
- **DNS uses FQDN for cross-namespace** — `service.namespace.svc.cluster.local` always works regardless of where you call from
- **NetworkPolicy is stateless by default** — if you add an ingress rule, you may need to explicitly allow egress too
- **PVC pending blocks pod scheduling** — always check PVC before debugging the pod when it's Pending

---

*Found this useful? Follow for more Kubernetes and AWS deep-dives — next up: Kubernetes Production Best Practices — resource management, security contexts, pod disruption budgets, and more.*
