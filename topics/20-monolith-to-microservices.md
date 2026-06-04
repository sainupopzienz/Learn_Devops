# Monolithic to Microservices Migration on AWS

**Pattern: Strangler Fig** — gradually replace monolith piece by piece.

### Migration Phases
- **Phase 1 — Analyse:** Identify bounded contexts (auth, orders, payments, users)
- **Phase 2 — Containerize monolith:** Put in Docker → ECS/EKS (no functional change)
- **Phase 3 — Extract one service at a time:** Start with least coupled (e.g. Auth)
- **Phase 4 — API Gateway in front:** /auth → Auth Service, /orders → Orders Service
- **Phase 5 — Event-driven:** Services via SQS/SNS/EventBridge (avoid direct HTTP calls)
- **Phase 6 — Individual DBs:** Each service owns its own DB (no shared DB)

### AWS Services Used

| Purpose | Service |
|---------|---------|
| API Routing | API Gateway, ALB |
| Events | SQS, SNS, EventBridge |
| Compute | EKS, ECS, Lambda |
| Database | RDS, DynamoDB, Aurora |
| Service Mesh | App Mesh, Istio on EKS |

> **Final state:** Monolith retired. All services independent with own CI/CD pipeline.
