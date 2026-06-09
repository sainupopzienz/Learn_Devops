# EKS 503: The Complete Troubleshooting Guide

## Why Your Pods Are Running But Users Are Getting Errors

---

There is one concept that causes more midnight incidents than anything else in Kubernetes:

```
Running ≠ Ready
```

A pod that shows `STATUS: Running` is alive. But alive does not mean it can receive traffic. Kubernetes has a completely separate gate — the **readiness check** — that decides whether a pod gets added to a Service's endpoint list. Fail that check, and the pod is invisible to all traffic, no matter how healthy it looks.

When every pod in your deployment fails its readiness check, the Service has zero endpoints. Zero endpoints means every request returns:

```
HTTP 503 Service Unavailable
```

This guide covers every scenario that produces a 503 in EKS, with the exact commands to diagnose each one.

---

## The Request Flow — Where 503 Can Happen

Understanding where to look starts with understanding how a request travels to your pod:

```
User's Browser
      │
      ▼
AWS ALB (Application Load Balancer)
      │  ← ALB health checks target group
      ▼
Kubernetes Ingress / Service
      │  ← Service routes only to Ready=True pods
      ▼
Pod (must be Running AND Ready=True)
      │
      ▼
Your Application
```

A 503 can be generated at two layers:

- **ALB layer** — the target group has no healthy targets (ALB health check failing)
- **Service layer** — the service has no ready endpoints (readiness probe failing)

Both produce 503 from the user's perspective. The diagnosis is different for each.

---

## The Core Concept: Running vs Ready

```
Pod Status: Running   →  Container is alive, process is running
Pod Ready:  True      →  Readiness probe passed, pod receives traffic
Pod Ready:  False     →  Readiness probe failed, pod receives ZERO traffic

Kubernetes Service endpoint logic:
  Pod Running + Ready=True  →  Added to endpoints → receives traffic
  Pod Running + Ready=False →  Removed from endpoints → receives nothing
```

---

## Scenario 1 — One Replica Fails Readiness (No 503)

### What You See

```
Node-1  →  Pod-A  →  Running  Ready=True
Node-2  →  Pod-B  →  Running  Ready=True
Node-3  →  Pod-C  →  Running  Ready=False   ← failing readiness
```

### Service Endpoints

```
kubectl get endpoints my-service
NAME         ENDPOINTS
my-service   10.0.1.5:8080, 10.0.2.7:8080   ← Pod-A and Pod-B only
```

### Traffic Distribution

```
50% → Pod-A (healthy)
50% → Pod-B (healthy)
 0% → Pod-C (excluded from endpoints)
```

### Result

```
No 503. Application continues working normally.
Pod-C is invisible to traffic — Kubernetes protects users automatically.
```

**This is Kubernetes working as designed.** Readiness failures on individual pods do not cause outages as long as at least one healthy endpoint exists.

---

## Scenario 2 — All Replicas Fail Readiness (503)

### What You See

```
Node-1  →  Pod-A  →  Running  Ready=False
Node-2  →  Pod-B  →  Running  Ready=False
Node-3  →  Pod-C  →  Running  Ready=False
```

All pods are alive. None are in the endpoint list.

### Service Endpoints

```
kubectl get endpoints my-service
NAME         ENDPOINTS
my-service   <none>
```

### Traffic Distribution

```
Client → ALB → Service → <none> → 503 Service Unavailable
```

### Result

```
503 for every request.
All pods Running. None receiving traffic. Endpoints are empty.
```

**This is the most confusing 503 scenario** — everything looks fine in `kubectl get pods` but users are getting errors. The key diagnostic is always `kubectl get endpoints`.

---

## Scenario 3 — Readiness Probe Wrong Path or Port

### The Configuration

```yaml
readinessProbe:
  httpGet:
    path: /ready       ← probe checks this path
    port: 8080
```

### The Problem

```
Application serves health at: /healthz    (not /ready)
Probe hits /ready → 404 Not Found
Kubernetes: readiness check failed
Pod: Running, Ready=False
```

### What You See

```bash
kubectl describe pod my-pod
# Events:
#   Readiness probe failed: HTTP probe failed with statuscode: 404
#   GET http://10.0.1.5:8080/ready → 404
```

### Result

```
Pod Running but Ready=False → excluded from endpoints → 503
```

### Fix

```yaml
readinessProbe:
  httpGet:
    path: /healthz     ← match the actual endpoint your app serves
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 3
```

---

## Scenario 4 — Dependency Failure Cascades to 503

### The Pattern

Many teams build readiness checks that verify all dependencies:

```
readiness check logic:
  → ping database          ← if this fails, pod goes NotReady
  → ping Redis
  → ping external payment API
```

### The Problem

```
Database becomes unavailable (RDS failover, connection limit, network issue)
      │
      ▼
All pods fail their readiness check simultaneously
      │
      ▼
All pods: Running, Ready=False
      │
      ▼
Service: 0 endpoints
      │
      ▼
503 Service Unavailable
```

### What You See

```bash
kubectl describe pod my-pod
# Readiness probe failed: dial tcp 10.0.3.100:5432: connect: connection refused

kubectl get endpoints my-service
# ENDPOINTS   <none>
```

### The Debate — Should Readiness Check Dependencies?

```
Argument for checking dependencies:
  If DB is down, app cannot serve requests anyway
  Better to return 503 cleanly than serve errors from the app

Argument against checking dependencies:
  One shared dependency outage → all pods NotReady → 503
  The dependency might recover but pods take time to return to Ready
  App might handle degraded state gracefully (serve cached data)
  Cascading failure: DB hiccup → all pods 503 → much worse than DB hiccup alone

Production recommendation:
  Liveness probe   → check only if the app process is alive (never check dependencies)
  Readiness probe  → check if app can serve requests (check dependencies only if
                     the app truly cannot function without them at all)
  Startup probe    → check if app finished initializing (for slow-starting apps)
```

---

## Scenario 5 — ALB Health Check Path Mismatch

### The Problem

```
ALB Target Group health check configured: GET /health
Application serves health at:            GET /healthz
```

```
ALB sends: GET /health → 404
ALB marks target: Unhealthy
Healthy targets: 0
Result: 503 from ALB before request even reaches Kubernetes Service
```

### Diagnosis

```
AWS Console → EC2 → Target Groups → your-target-group
→ Targets tab → Status = Unhealthy

Reason: Health checks failed
Description: Request timed out or received non-2xx response
```

### Fix

```
AWS Console → Target Groups → Health checks tab → Edit
  Path: /healthz   ← match what your app actually serves
  Port: 8080
  Success codes: 200

OR in Terraform:
resource "aws_lb_target_group" "app" {
  health_check {
    path    = "/healthz"    ← must match your app
    port    = "8080"
    matcher = "200"
  }
}
```

---

## Scenario 6 — Service Selector Mismatch

### The Problem

```yaml
# Service — looking for pods with label app=api
spec:
  selector:
    app: api
```

```yaml
# Pod — has label app=backend (not api)
metadata:
  labels:
    app: backend
```

```
Service selector: app=api
Pod labels:       app=backend
Match:            NO MATCH → 0 endpoints → 503
```

### Diagnosis

```bash
# Check what selector the service uses
kubectl describe service my-service
# Selector: app=api

# Check what labels the pods actually have
kubectl get pods --show-labels
# NAME      LABELS
# api-1     app=backend   ← does NOT match service selector

# Confirm endpoints are empty
kubectl get endpoints my-service
# ENDPOINTS   <none>
```

### Fix

```yaml
# Option A: Fix the Service selector to match pod labels
spec:
  selector:
    app: backend    ← match what pods actually have

# Option B: Fix the pod labels to match the Service
metadata:
  labels:
    app: api        ← match what Service expects
```

---

## Scenario 7 — Application Startup Delay

### The Problem

```
Application startup time:    120 seconds (Spring Boot, JVM warmup, etc.)
Readiness probe starts at:   10 seconds (initialDelaySeconds: 10)
Probe result at 10s:         FAIL (app not ready yet)
Probe result at 20s:         FAIL
...
Probe result at 100s:        FAIL
Pod status during this time: Running, Ready=False

If failureThreshold is reached: pod enters NotReady and stays there
If all replicas start simultaneously: 503 during the entire startup window
```

### Fix — Use a Startup Probe

```yaml
startupProbe:
  httpGet:
    path: /health
    port: 8080
  failureThreshold: 30        # Allow up to 30 × 10s = 5 minutes for startup
  periodSeconds: 10
  # Startup probe must pass BEFORE readiness probe begins checking

readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 0      # Startup probe already handled the delay
  periodSeconds: 5
  failureThreshold: 3

livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 0
  periodSeconds: 10
  failureThreshold: 3
```

```
With startup probe:
  Kubernetes waits for startupProbe to pass (up to 5 minutes here)
  Only AFTER startupProbe passes → readinessProbe begins
  Only AFTER startupProbe passes → livenessProbe begins
  Slow-starting app gets the time it needs
  No false readiness failures during startup
```

---

## Scenario 8 — Rolling Deployment Causes Temporary 503

### The Problem

```
Current deployment: 3 pods running (v1)
Rolling update begins: replace pods one at a time

Moment 1: Pod-A terminated (old v1), Pod-D starting (new v2)
          Endpoints: Pod-B, Pod-C (2 healthy)   → No 503

Moment 2: Pod-B terminated, Pod-E starting
          Endpoints: Pod-C (1 healthy)           → No 503 but reduced capacity

Moment 3: Pod-C terminated, Pod-F starting
          ALL old pods gone, ALL new pods starting up
          Endpoints: <none>                      → 503!

This happens when:
  maxUnavailable is too high
  New pods take too long to become Ready
  New pods are failing their readiness probe (bad deployment)
```

### Fix — Rolling Update Strategy

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0    # Never remove an old pod until new pod is Ready
      maxSurge: 1          # Create one extra pod above desired count during update

# With maxUnavailable=0:
  Old pod is only terminated AFTER new pod passes readiness check
  At least desired-count healthy pods always exist
  Zero-downtime guaranteed if new pods can become Ready
  If new pods fail readiness → rollout pauses → old pods stay → no 503
```

---

## Diagnostic Commands — In Order of Use

### Step 1 — Check Pod Status and Readiness

```bash
kubectl get pods -n <namespace>

# Good output (all ready):
# NAME      READY   STATUS    RESTARTS   AGE
# api-1     1/1     Running   0          5m
# api-2     1/1     Running   0          5m

# Problem output (not ready):
# NAME      READY   STATUS    RESTARTS   AGE
# api-1     0/1     Running   0          5m    ← 0/1 = container running but not ready
# api-2     0/1     Running   0          5m
```

### Step 2 — Find the Readiness Failure Reason

```bash
kubectl describe pod <pod-name> -n <namespace>

# Look for Events section at the bottom:
# Events:
#   Warning  Unhealthy  readiness probe failed: HTTP probe failed
#            with statuscode: 404
#   Warning  Unhealthy  readiness probe failed: dial tcp: connect refused
#   Warning  Unhealthy  readiness probe failed: context deadline exceeded
```

### Step 3 — Check Service Endpoints (Most Important)

```bash
kubectl get endpoints <service-name> -n <namespace>

# Healthy:
# NAME         ENDPOINTS
# my-service   10.0.1.5:8080, 10.0.2.7:8080

# Problem — this is your 503 confirmation:
# NAME         ENDPOINTS
# my-service   <none>
```

### Step 4 — Check Service Selector vs Pod Labels

```bash
# What does the service expect?
kubectl describe service <service-name> -n <namespace>
# Selector: app=api

# What labels do pods actually have?
kubectl get pods -n <namespace> --show-labels
# NAME    LABELS
# api-1   app=backend   ← mismatch!
```

### Step 5 — Test the Health Endpoint From Inside the Pod

```bash
kubectl exec -it <pod-name> -n <namespace> -- \
  curl -v localhost:8080/health

# 200 OK → app is healthy, probe config is wrong (wrong path or port)
# 404    → wrong health endpoint path configured in probe
# Connection refused → app not listening on that port
# Timeout → app is overloaded or deadlocked
```

### Step 6 — Check ALB Target Health (if using AWS ALB)

```bash
# Get target group ARN
aws elbv2 describe-target-groups \
  --query 'TargetGroups[?TargetGroupName==`my-target-group`].TargetGroupArn' \
  --output text

# Check health of targets
aws elbv2 describe-target-health \
  --target-group-arn <arn>

# Look for:
#   TargetHealth.State: healthy   → ALB can reach the target
#   TargetHealth.State: unhealthy → health check failing
#   TargetHealth.Reason: Target.FailedHealthChecks
```

### Step 7 — Check EndpointSlices (Newer Clusters)

```bash
kubectl get endpointslices -n <namespace>
kubectl describe endpointslice <name> -n <namespace>
# Shows which pods are in the endpoint slice and their ready status
```

### Step 8 — Check Recent Deployments

```bash
# Has something changed recently?
kubectl rollout history deployment/<name> -n <namespace>

# If a recent rollout caused the issue:
kubectl rollout undo deployment/<name> -n <namespace>
kubectl rollout status deployment/<name> -n <namespace> --timeout=300s
```

---

## The 2 AM Checklist — Fastest Path to Root Cause

Run these commands in this exact order. Most 503s are resolved by command 3.

```bash
# ── 1. Pod status ───────────────────────────────────────────────────────
kubectl get pods -n <namespace>
# READY 0/1 on any pod? → continue to 2

# ── 2. Why is pod not ready? ────────────────────────────────────────────
kubectl describe pod <pod-name> -n <namespace> | grep -A20 Events
# Readiness probe failed? → fix probe path/port
# OOMKilled?             → increase memory limit
# CrashLoopBackOff?      → check logs: kubectl logs <pod> --previous

# ── 3. Service has endpoints? ───────────────────────────────────────────
kubectl get endpoints <service-name> -n <namespace>
# <none>? → that IS your 503. Probe or selector issue.

# ── 4. Selector matches pods? ───────────────────────────────────────────
kubectl get pods -n <namespace> --show-labels | grep <expected-label>
# No match? → fix selector in service or labels on pod

# ── 5. App responding inside pod? ───────────────────────────────────────
kubectl exec -it <pod-name> -n <namespace> -- curl -sv localhost:8080/health
# 200? → probe config wrong. 404/refused? → app issue.

# ── 6. ALB targets healthy? ─────────────────────────────────────────────
aws elbv2 describe-target-health --target-group-arn <arn>
# Unhealthy? → ALB health check path mismatch

# ── 7. Recent change caused this? ───────────────────────────────────────
kubectl rollout history deployment/<name> -n <namespace>
# New deployment? → kubectl rollout undo deployment/<name>
```

---

## Root Cause Summary

| Scenario | First Command | Root Cause Indicator | Fix |
|---|---|---|---|
| All pods NotReady | `kubectl get pods` | `READY: 0/1` on all pods | Fix readiness probe |
| Empty endpoints | `kubectl get endpoints` | `<none>` | Probe failure or selector mismatch |
| Wrong probe path | `kubectl describe pod` | `statuscode: 404` in events | Fix probe path |
| Wrong probe port | `kubectl exec -- curl` | `connection refused` | Fix probe port |
| Selector mismatch | `kubectl get pods --show-labels` | Labels don't match service | Fix selector or labels |
| ALB health check | AWS Console / CLI | `Healthy Targets: 0` | Fix ALB health check path |
| DB dependency | `kubectl describe pod` | `connect: connection refused` | Fix DB or remove from readiness |
| Slow startup | `kubectl describe pod` | `context deadline exceeded` | Add startupProbe |
| Bad deployment | `kubectl rollout history` | Recent revision | `kubectl rollout undo` |

---

## Key Takeaways

**The single most important command when investigating a 503:**

```bash
kubectl get endpoints <service-name>
```

If this shows `<none>` — you have found your 503. Everything else is finding out why.

**The mental model to carry:**

```
Running   →  container process is alive
Ready     →  readiness probe passed → pod is in service endpoints → receives traffic

503 = Service has no Ready pods = check endpoints first, probes second
```

**The three probe types and what they do:**

```
startupProbe:   "Has the app finished starting?"
                Failure → pod gets more time (does not kill or exclude)
                Pass    → liveness and readiness probes begin

readinessProbe: "Is the app ready to serve traffic?"
                Failure → pod removed from Service endpoints (no traffic)
                Pass    → pod added to Service endpoints (receives traffic)

livenessProbe:  "Is the app still alive and not deadlocked?"
                Failure → container restarted
                Pass    → container kept running
```

---

*503 errors in Kubernetes are almost always a routing problem, not an application problem. The application is running — Kubernetes is simply not sending it traffic. Follow the request flow, check the endpoints, find the broken gate.*
