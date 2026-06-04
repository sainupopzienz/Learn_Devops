# Branching Strategy

### GitFlow (Enterprise / Scheduled Releases)
```
main      ← production code, always deployable
develop   ← integration branch
feature/* ← new features (branch from develop)
release/* ← release prep → main + develop
hotfix/*  ← urgent prod fix → main + develop
```

### Trunk-Based Development (CI/CD Teams)
```
main      ← everyone merges here daily
feature/* ← short-lived, merge within 1-2 days
           ← feature flags for incomplete features
```

### How to Choose

| Team Type | Strategy |
|-----------|---------|
| Large enterprise, scheduled releases | GitFlow |
| Fast CI/CD, frequent deployments | Trunk-based |
| Mid-size teams | Simplified GitFlow |
