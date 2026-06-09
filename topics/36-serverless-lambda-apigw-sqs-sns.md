# Serverless on AWS: Lambda, API Gateway, SQS, and SNS

## Build Applications Without Managing a Single Server

---

Imagine deploying a backend that scales from zero to a million requests without you touching a single server, writing a single auto-scaling policy, or paying a cent when nobody is using it.

That's serverless. Not "no servers" — there are servers, you just don't see them, manage them, or pay for idle time on them. AWS handles everything below your code.

This article covers the core serverless building blocks on AWS: **Lambda, API Gateway, SQS, SNS, and EventBridge** — and how to wire them into real production systems.

---

## AWS Lambda — The Core of Serverless

Lambda runs your code in response to events. You upload a function, define what triggers it, and Lambda handles execution, scaling, and availability automatically.

```
Traditional Server:                Lambda:
─────────────────────              ──────────────────────
Server running 24/7                Function runs only when triggered
You pay always                     You pay only per invocation
You manage patching                AWS patches everything
You configure scaling              AWS scales automatically (to 1000 concurrent)
Minimum cost: ~$10-20/month        Minimum cost: $0 (free tier: 1M invocations/month)
```

### Your First Lambda Function

```python
import json

def handler(event, context):
    # 'event' contains the trigger data
    # 'context' contains runtime information

    name = event.get('name', 'World')

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Hello, {name}!'
        })
    }
```

Deploy it, trigger it, done. No server setup, no nginx, no systemd.

### Lambda Triggers — What Can Invoke a Function

Lambda integrates with almost every AWS service as a trigger:

```
HTTP requests          → API Gateway / ALB
File uploads           → S3 (s3:ObjectCreated)
Database changes       → DynamoDB Streams, RDS Proxy
Messages               → SQS, SNS, EventBridge
Scheduled jobs         → CloudWatch Events (cron)
Auth flows             → Cognito (pre/post signup hooks)
IoT events             → AWS IoT Core
Email received         → SES
Stream processing      → Kinesis Data Streams
```

### Lambda Execution Model

```
Trigger arrives
      │
      ▼
Is a warm container available?
      │
  YES │  NO
      │   └──► Cold start: download code, start runtime (~100ms-1s)
      │
      ▼
Execute function
      │
      ▼
Return response
      │
      ▼
Container stays warm for ~15 minutes (ready for next invocation)
```

**Cold start** is the main Lambda gotcha — the first invocation after a period of inactivity takes longer. Mitigate it with:
- **Provisioned Concurrency** — pre-warm N containers always
- **Keep functions small** — less code = faster cold start
- **Use Lambda Layers** for shared dependencies — don't bundle them per function

### Lambda Limits to Know

```
Maximum execution time:  15 minutes (not for long-running jobs)
Maximum memory:          10 GB
Maximum deployment size: 50 MB (zipped), 250 MB (unzipped)
Maximum concurrency:     1,000 per region (can be increased)
Maximum /tmp storage:    10 GB (ephemeral — wiped between invocations)
```

Lambda is not for everything. Long-running processes (>15 min), stateful workloads, or anything needing persistent local storage belongs on EC2 or ECS.

---

## API Gateway — HTTP Front Door for Lambda

API Gateway is a fully managed service that creates, publishes, and secures **HTTP APIs** that sit in front of Lambda functions (or any HTTP backend).

```
Client (browser/mobile)
         │
         │  HTTPS request
         ▼
   API Gateway
   - SSL termination
   - Authentication (JWT, API key, IAM)
   - Rate limiting (throttling)
   - Request/response transformation
   - Caching
         │
         ▼
   Lambda Function
         │
         ▼
   Response back to client
```

### REST API vs HTTP API vs WebSocket API

| Type | Use case | Cost |
|---|---|---|
| REST API | Full features — auth, caching, request validation, usage plans | Higher |
| HTTP API | Simple HTTP proxy to Lambda or HTTP backends — 70% cheaper | Lower |
| WebSocket API | Real-time two-way communication — chat, live dashboards | Per message |

For most new APIs, use **HTTP API** — it's simpler, faster, and significantly cheaper. Use REST API only when you need request validation, response mapping, or API keys with usage plans.

### Building a Simple REST API

```
GET  /users          → Lambda: listUsers
POST /users          → Lambda: createUser
GET  /users/{id}     → Lambda: getUser
PUT  /users/{id}     → Lambda: updateUser
DELETE /users/{id}   → Lambda: deleteUser
```

Each route maps to a Lambda function. API Gateway handles routing, SSL, and authentication. Lambda handles business logic.

### API Gateway — Authorization

**Lambda Authorizer** (most flexible):
```
Request → API Gateway → Lambda Authorizer (validates JWT/API key)
                              │
                    ✅ Valid  │  ❌ Invalid
                              │
                    Forward to backend  Return 401
```

**JWT Authorizer** (simplest for modern apps):
```yaml
# Built-in JWT validation — no custom Lambda needed
auth:
  issuer: https://cognito-idp.ap-south-1.amazonaws.com/ap-south-1_XXXXX
  audience:
    - my-app-client-id
```

**IAM Authorization** (for service-to-service calls):
```
Service A signs request with AWS Signature V4
API Gateway validates the IAM identity and checks permissions
```

---

## Amazon SQS — Message Queuing

SQS is a **fully managed message queue**. It decouples your services — instead of Service A calling Service B directly, A puts a message in a queue and B processes it whenever it's ready.

```
WITHOUT SQS (tight coupling):
OrderService → PaymentService
               (if PaymentService is down, orders fail)

WITH SQS (loose coupling):
OrderService → SQS Queue → PaymentService
               (if PaymentService is down, messages wait safely in queue)
```

### SQS Queue Types

**Standard Queue:**
```
✅ Unlimited throughput
✅ At-least-once delivery (message delivered at least once, possibly more)
❌ Message order not guaranteed
Best for: High throughput, order doesn't matter (email sending, log processing)
```

**FIFO Queue:**
```
✅ Exactly-once processing (no duplicates)
✅ Strict ordering — first in, first out
❌ 3,000 messages/second max throughput
Best for: Order matters — financial transactions, inventory updates
```

### SQS + Lambda — The Pattern

```
Producer (API, EC2, etc.) → SQS Queue → Lambda (consumer)
                                │
                                │  Lambda polls the queue automatically
                                │  Scales up/down with queue depth
                                │  Failed messages go to DLQ after N retries
                                ▼
                           Dead Letter Queue (DLQ)
                           (failed messages waiting for investigation)
```

Always configure a **Dead Letter Queue (DLQ)** — when message processing fails repeatedly, the message moves to DLQ instead of disappearing. You can then investigate what went wrong and reprocess.

### SQS Visibility Timeout

When a consumer picks up a message, it becomes **invisible** to other consumers for the visibility timeout period. If the consumer crashes before deleting the message, it reappears in the queue for another consumer.

```
Message received by Lambda
         │
         ▼
Visibility timeout starts (e.g., 30 seconds)
Message invisible to other consumers
         │
  Lambda succeeds → Deletes message from queue ✅
         │
  Lambda fails → Visibility timeout expires → Message reappears → Retried
```

Set visibility timeout to at least 6× your Lambda function's average execution time.

---

## Amazon SNS — Pub/Sub Messaging

SNS is a **publish/subscribe** messaging service. One message published to an SNS topic can be delivered to **multiple subscribers simultaneously**.

```
SQS:  One producer → Queue → One consumer reads each message

SNS:  One publisher → Topic → Multiple subscribers receive the same message
                               ├── SQS Queue (for async processing)
                               ├── Lambda function (for immediate action)
                               ├── Email (notify administrators)
                               ├── SMS (alert on-call engineer)
                               └── HTTP endpoint (webhook)
```

### SNS Fan-Out Pattern

The most powerful pattern: publish once, fan out to multiple SQS queues:

```
Order Placed Event
         │
         ▼
    SNS Topic: "order-placed"
         │
    ┌────┼────┬────┐
    ▼    ▼    ▼    ▼
  SQS  SQS  SQS  Lambda
   │    │    │       │
Notify  │  Update  Send
 user   │  inventory confirmation
        │    email
     Charge
     payment
```

Each downstream service processes the event independently at its own pace. If one fails, others aren't affected.

---

## Amazon EventBridge — Event-Driven Architecture at Scale

EventBridge is the evolution of SNS for complex event-driven systems. It routes events based on **content** — not just which topic they're published to.

```
SNS:         Event → Topic → All subscribers get it
EventBridge: Event → Rules engine → Only matching subscribers get it
```

### EventBridge Rules

```json
// Rule: Route order events only when amount > 10000
{
  "source": ["myapp.orders"],
  "detail-type": ["OrderPlaced"],
  "detail": {
    "amount": [{ "numeric": [">", 10000] }]
  }
}
// Target: Lambda function for high-value order handling
```

### EventBridge Scheduler

Replace cron jobs on EC2 with EventBridge Scheduler — run Lambda functions on a schedule:

```
Every day at midnight IST  →  Lambda: generate daily reports
Every Monday 9 AM         →  Lambda: send weekly digest emails
Every 5 minutes           →  Lambda: health check and alert
First of every month      →  Lambda: generate invoices
```

---

## Building a Real Serverless Architecture

### Serverless E-Commerce Order Processing

```
Customer places order
         │
         ▼
API Gateway (POST /orders)
         │
         ▼
Lambda: ValidateOrder
- Check inventory
- Validate payment details
- Write order to DynamoDB (status: PENDING)
         │
         ▼
Publish to SNS: "order-created"
         │
    ┌────┼────────────┐
    ▼    ▼            ▼
  SQS  SQS          SQS
   │    │             │
Lambda Lambda      Lambda
   │    │             │
Process Send        Update
payment confirm   inventory
       email
         │
         ▼
Payment Lambda → Success:
  Update DynamoDB (status: CONFIRMED)
  Publish SNS: "payment-confirmed"
         │
         ▼
Notification Lambda:
  Send SMS + email to customer
```

Every component scales independently. A spike in orders doesn't crash payment processing. Payment processing failure doesn't affect inventory updates.

### Costs at Scale

```
1,000,000 API requests/month:
  API Gateway HTTP API:  $1.00
  Lambda (128MB, 200ms): $0.42
  DynamoDB:              $1.25
  Total:                ~$2.67/month
```

For a startup, that's essentially free. A comparable EC2 + RDS setup would cost $50–$150/month minimum even with zero traffic.

---

## When Serverless Makes Sense ✅

- **Event-driven workloads** — respond to events (file uploads, API calls, database changes)
- **Variable traffic** — scales to zero when idle, handles spikes automatically
- **Microservices backends** — each function handles one responsibility
- **Scheduled jobs** — replace EC2-based cron jobs
- **Prototypes and MVPs** — zero infrastructure management lets you move fast

## When Serverless is the Wrong Choice ❌

- **Long-running tasks** — Lambda max is 15 minutes; video transcoding, ML training belong on EC2
- **Consistent high traffic** — if you're always at 1M requests/hour, EC2 reserved instances may be cheaper
- **Stateful applications** — Lambda is stateless; use ElastiCache or DynamoDB for state
- **Legacy monoliths** — lifting a monolith into Lambda is an anti-pattern; containerize it instead

---

## Key Takeaways

- **Lambda = functions as a service** — run code without servers, pay per invocation
- **API Gateway = managed HTTP layer** — authentication, rate limiting, routing without writing it yourself
- **SQS = reliable async communication** — decouple services, handle failures gracefully with DLQ
- **SNS = fan-out messaging** — one event, many consumers simultaneously
- **EventBridge = intelligent event routing** — route events based on content, not just topic
- **Serverless is not always cheaper** — it wins at variable load, loses at consistent high throughput
- **The SQS + SNS fan-out pattern** is the backbone of scalable event-driven systems on AWS

---

*Found this useful? Follow for more AWS deep-dives — next up: AWS Networking Deep Dive — VPC, Transit Gateway, PrivateLink, and everything in between.*
