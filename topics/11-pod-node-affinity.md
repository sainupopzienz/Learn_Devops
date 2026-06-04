# Pod & Node Affinity / Anti-Affinity

### Types

| Type | Purpose | Use Case |
|------|---------|----------|
| Node Affinity | Schedule pod ON specific nodes | Run only on prod/GPU nodes |
| Node Anti-Affinity | Avoid certain nodes | Keep off spot instances |
| Pod Affinity | Schedule pod NEAR another pod | Low-latency co-location |
| Pod Anti-Affinity | Spread pods AWAY | HA — no 2 replicas on same node |

### Node Affinity Example
```yaml
nodeAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
    - matchExpressions:
      - key: env
        operator: In
        values: [prod]
```

### Pod Anti-Affinity (Most Used)
```yaml
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
  - labelSelector:
      matchLabels:
        app: my-app
    topologyKey: kubernetes.io/hostname
```

> **Real use:** Anti-affinity ensures one node failure won't take down your app.
