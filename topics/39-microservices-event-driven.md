# Microservices and Event-Driven Architecture on AWS

## How Netflix, Uber, and Amazon Actually Build Their Systems

---

Every large-scale application you use daily is not one system — it's dozens or hundreds of small, independent services talking to each other. Your Netflix stream involves separate services for authentication, recommendations, streaming, billing, and device management. Each is built, deployed, and scaled independently by separate teams.

This is microservices. And the way these services communicate — without tightly depending on each other — is event-driven architecture.

---

## Monolith vs Microservices

```
MONOLITH:
┌──────────────────────────────────────────┐
│  User Auth + Orders + Payments +         │
│  Inventory + Notifications + Shipping    │
│  — all in one codebase, one deployment   │
└──────────────────────────────────────────┘

Deploy a change to notifications? Redeploy the entire monolith.
One module's bug crashes the entire application.
Scale payments? You scale everything whether it needs it or not.

MICROSERVICES:
┌──────────┐  ┌──────────┐  ┌──────────┐
│ Auth     │  │ Orders   │  │ Payments │
│ Service  │  │ Service  │  │ Service  │
└──────────┘  └──────────┘  └──────────┘
┌──────────┐  ┌──────────┐  ┌──────────┐
│Inventory │  │ Notify   │  │ Shipping │
│ Service  │  │ Service  │  │ Service  │
└──────────┘  └──────────┘  └──────────┘

Each service: independent codebase, deployment, scaling, and team ownership.
```

---

## The Problem with Direct Service-to-Service Calls

In a microservices world, when Order Service needs to trigger Payment Service, Inventory Service, and Notification Service — the naive approach is direct HTTP calls:

```
Order Service
     │
     ├──► HTTP → Payment Service     (what if it's down?)
     ├──► HTTP → Inventory Service   (what if it's slow?)
     └──► HTTP → Notification Service (why should order wait for email?)
```

**Problems:**
- Tight coupling — Order Service now depends on 3 other services being healthy
- If Payment Service is slow, Order Service is slow
- If Notification Service is down, order placement fails
- Hard to add a new downstream consumer without changing Order Service code

Event-driven architecture solves all of this.

---

## Event-Driven Architecture — The Solution

Instead of calling services directly, publish an event. Any interested service subscribes and reacts at its own pace:

```
Order Service
     │
     └──► Publishes: "OrderPlaced" event
                          │
              ┌───────────┼───────────┐
              ▼           ▼           ▼
       Payment Svc   Inventory Svc  Notify Svc
       (processes    (updates        (sends email
        payment)      stock)          async)

Order Service doesn't know or care who consumes the event.
Each consumer is independent. One failing doesn't affect others.
```

---

## AWS Services for Event-Driven Architecture

### Amazon SQS — Reliable Async Messaging

Point-to-point async communication. One producer, one consumer pool.

```
Order Service → SQS Queue → Payment Service (Lambda/ECS workers poll the queue)
                    │
               If payment fails: message reappears after visibility timeout
               After 3 failures: message → Dead Letter Queue for investigation
```

### Amazon SNS — Fan-Out to Multiple Consumers

One event, many consumers simultaneously:

```
"OrderPlaced" SNS Topic
         │
    ┌────┼────────────┐
    ▼    ▼            ▼
  SQS  SQS          Lambda
   │    │               │
Payment Inventory  Notification
Service  Service     Service
```

### Amazon EventBridge — Content-Based Routing

Route events based on their content — not just which topic they're on:

```
All events go to EventBridge event bus
         │
    ┌────┼────────────────────┐
    │    │                    │
    ▼    ▼                    ▼
Rule:           Rule:              Rule:
OrderPlaced     OrderValue > 10000  OrderFailed
  → Inventory     → Fraud Check      → Support ticket
  → Payments      → VIP Notify       → Refund Lambda
```

EventBridge also ingests events from 200+ AWS services and SaaS providers (Shopify, Datadog, PagerDuty).

### Amazon Kinesis — Real-Time Data Streaming

For high-volume real-time event streams (millions of events/second):

```
Kinesis Data Streams:
  Clickstream events → Kinesis → Lambda (real-time processing)
                               → Kinesis Firehose → S3 (batch analytics)
                               → Kinesis Analytics → real-time dashboards

Use when: High volume (>10,000 events/sec), ordering matters within a shard,
          replay capability needed (events retained 1–365 days)

Use SQS when: Task queuing, job processing, lower volume, dead letter queuing needed
```

---

## Key Microservices Patterns on AWS

### Pattern 1 — API Gateway + Lambda (Serverless Microservices)

```
Client → API Gateway → Lambda (Auth Service)
Client → API Gateway → Lambda (Order Service)
Client → API Gateway → Lambda (User Service)

Each Lambda = one microservice
Each function deployed, scaled, and monitored independently
```

### Pattern 2 — ECS Services Behind ALB

```
ALB
 │
 ├── /api/orders/*   → ECS Service: Order-Service  (3 tasks)
 ├── /api/payments/* → ECS Service: Payment-Service (2 tasks)
 └── /api/users/*    → ECS Service: User-Service   (5 tasks)

Each ECS service: separate container image, separate auto-scaling policy
```

### Pattern 3 — Saga Pattern for Distributed Transactions

When a business transaction spans multiple services, you can't use a database ACID transaction. Use the Saga pattern:

```
Place Order Saga:
1. Order Service:    Create order (PENDING)
2. Payment Service:  Charge card
3. Inventory Service: Reserve stock
4. Shipping Service: Create shipment
5. Order Service:    Update order (CONFIRMED)

If Step 3 fails (out of stock):
  → Compensating transaction: Refund payment (Step 2 reversal)
  → Compensating transaction: Cancel order (Step 1 reversal)
```

Implement with **AWS Step Functions** — orchestrates the saga and handles compensation:

```
Step Functions State Machine:
CreateOrder → ChargePayment → ReserveInventory → CreateShipment → Confirm
                │                    │
             Failure:             Failure:
           Compensate           Compensate
           (no payment          (refund payment,
            taken yet)           cancel order)
```

### Pattern 4 — CQRS (Command Query Responsibility Segregation)

Separate the write model from the read model:

```
WRITE (Commands):
Client → API → Order Service → RDS (normalized, write-optimized)
                             → Publish "OrderPlaced" event

READ (Queries):
"OrderPlaced" event → Lambda → DynamoDB (denormalized, read-optimized)
Client → API → Query DynamoDB (fast single-table reads)
```

Reads go to a DynamoDB table optimized for the query patterns. Writes go to RDS for consistency. Different scaling, different optimization, same data.

---

## Service Discovery on AWS

When services need to find each other dynamically (as containers scale up and down, IPs change):

**AWS Cloud Map:**
```
Payment Service registers: payment.myapp.internal:8080
Order Service queries Cloud Map: "where is payment service?"
Cloud Map returns: 10.0.2.45:8080, 10.0.2.67:8080 (healthy instances only)
```

**ECS Service Connect (simpler):**
```
Define services in ECS Task Definition
ECS automatically handles service discovery and load balancing between services
No external service registry needed
```

---

## Circuit Breaker Pattern

When a downstream service is failing, stop sending requests immediately — fail fast instead of waiting for timeouts:

```
Normal:   Order → Payment (success, 100ms)
Degraded: Order → Payment (timeout, 30s) — requests pile up
          Order → Payment (timeout, 30s) — thread pool exhausted
          Order → Payment (timeout, 30s) — Order Service crashes too

Circuit Breaker:
  Closed (normal):   All requests pass through
  Open (failing):    Requests fail immediately — don't even try Payment Service
                     Return fallback response ("Payment unavailable, try again soon")
  Half-Open (probe): Send 1 request — if it succeeds, close the circuit
```

Implement with **AWS App Mesh** (service mesh) or within your application code using libraries like Resilience4j (Java) or `opossum` (Node.js).

---

## Observability for Microservices

With 10+ services, finding which one caused a slow request or error requires:

```
Distributed Tracing (X-Ray):
  Request → Service A (50ms) → Service B (800ms) → Service C (20ms)
                                     ↑
                           Bottleneck identified instantly

Correlation IDs:
  Every request gets a unique ID (X-Request-ID header)
  Passed through every service call
  All logs across all services queryable by the same ID

Centralized Logging:
  All services → CloudWatch Logs
  Query with Logs Insights: filter requestId = "abc-123"
  → See every log line from every service for that one request
```

---

## When to Use Microservices — And When Not To

### Use Microservices When:
- **Team size justifies it** — Conway's Law: your architecture mirrors your org chart. 5+ teams working on the same system benefit from service boundaries.
- **Independent scaling needs** — payment processing needs 10x more capacity than notifications
- **Different technology requirements** — ML service in Python, API in Go, frontend in Node
- **Independent deployment velocity** — teams want to deploy without coordinating with each other

### Don't Break Up the Monolith When:
- **Small team (< 10 engineers)** — microservices overhead will slow you down more than the monolith
- **Domain not well understood yet** — getting service boundaries wrong is worse than a monolith
- **Premature optimization** — a monolith can handle millions of users if built well

> The right answer for most startups: start with a well-structured monolith, identify the seams where independent scaling or deployment would add real value, then extract those as services. Never start with microservices.

---

## Key Takeaways

- **Events decouple services** — producers don't know about consumers, consumers are independent
- **SQS for task queues, SNS for fan-out, EventBridge for complex routing, Kinesis for high-volume streams**
- **Saga pattern replaces distributed transactions** — compensating transactions handle failures
- **CQRS separates reads from writes** — optimize each independently
- **Circuit breakers prevent cascade failures** — fail fast, return fallback, protect the system
- **Distributed tracing (X-Ray) is non-negotiable** — without it, debugging microservices is guesswork
- **Start with a monolith** — extract microservices when you have a real reason, not before

---

*Found this useful? Follow for more AWS deep-dives — next up: Data Engineering on AWS — Glue, Athena, Kinesis, and Redshift.*
