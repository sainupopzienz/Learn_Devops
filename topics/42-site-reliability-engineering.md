# Site Reliability Engineering: SLIs, SLOs, Error Budgets, and Running Production Like Google

## The Discipline That Turns On-Call from Chaos into Science

---

Google invented SRE. The story is simple: in 2003, Ben Treynor was given a software team and told to run production. He approached operations the way a software engineer would — with measurement, automation, and engineering rigor. The result was Site Reliability Engineering.

Today SRE is the standard at every serious tech company. It answers the question every engineering team eventually faces: how do you balance shipping new features with keeping the lights on?

---

## The Core Problem SRE Solves

Development teams want to move fast — push features, iterate, break things and fix them.
Operations teams want stability — nothing changes, nothing breaks, users are happy.

These goals are in direct conflict. SRE resolves the conflict with a contractual framework:

```
"You can move as fast as your reliability allows."
```

Measure reliability. Define acceptable risk. When you stay within that risk budget, ship freely. When you've consumed your risk budget, stop and fix things.

---

## SLI — Service Level Indicator

An SLI is a **quantitative measure** of some aspect of service reliability. It's the metric you actually measure.

```
Common SLIs:
──────────────────────────────────────────
Availability:    % of requests that succeed
Latency:         % of requests served within Xms (e.g., 99% under 200ms)
Error rate:      % of requests that return errors
Throughput:      Requests per second the system handles
Durability:      % of data that is retained without corruption (storage systems)
```

### Good SLIs vs Bad SLIs

```
Bad SLI:  "CPU utilization < 80%"
Why:      CPU is an implementation detail. Users don't feel CPU.
          High CPU might be fine. Low CPU might have 100% error rate.

Good SLI: "% of API requests that return 2xx in < 300ms"
Why:      This is what users actually experience.
          If this is high, users are happy. If it drops, users suffer.
```

Always measure SLIs from the **user's perspective**.

---

## SLO — Service Level Objective

An SLO is the **target** for your SLI. It defines what "good enough" means.

```
SLI:  % of requests returning 2xx within 300ms
SLO:  99.9% of requests over a rolling 30-day window

Translation: We promise that at least 999 out of every 1,000 requests
             succeed within 300ms, measured monthly.
```

### Setting the Right SLO

```
Too high (99.999%):
  Near-impossible to achieve. Every deployment becomes terrifying.
  Engineers burn out maintaining it. Costs are massive.

Too low (90%):
  Users are suffering. Business is affected. Trust is lost.

Right (99.5% - 99.9% for most APIs):
  Achievable with good engineering practices.
  Allows for deployments, experiments, and occasional failures.
  Users notice failures but don't churn because of them.
```

### The 9s — What They Actually Mean

```
Availability  Downtime per year    Downtime per month
──────────────────────────────────────────────────────
99%           87.6 hours           7.2 hours
99.5%         43.8 hours           3.6 hours
99.9%         8.7 hours            43 minutes
99.95%        4.4 hours            21 minutes
99.99%        52 minutes           4.4 minutes
99.999%       5.2 minutes          26 seconds
```

Pick your SLO based on what your business requires, what users expect, and what you can realistically achieve.

---

## Error Budget — The Innovation License

The error budget is the **allowed unreliability** derived from your SLO.

```
SLO:          99.9% availability over 30 days
Total minutes: 30 days × 24 hrs × 60 min = 43,200 minutes
Allowed downtime (error budget): 0.1% × 43,200 = 43.2 minutes/month

You can have 43.2 minutes of downtime this month.
That's your budget. Spend it wisely.
```

### How Error Budgets Change Team Behavior

**Budget is healthy (most remains):**
```
→ Development team: "We have budget. Let's ship that risky feature."
→ Operations team:  "We have budget. Let's do that infrastructure upgrade."
Both teams aligned — move fast with awareness of remaining safety margin.
```

**Budget is nearly exhausted:**
```
→ Development team: "We need to slow down. No risky releases."
→ Operations team:  "We need to improve reliability before the next release."
Both teams aligned — reliability work takes priority over features.
```

**Budget exhausted before month end:**
```
→ Feature releases freeze until next month's budget resets.
→ Engineering focuses 100% on reliability improvement.
This is the forcing function. No argument. The math decides.
```

---

## SLA — Service Level Agreement

An SLA is a **contractual promise** to customers — backed by financial consequences if violated.

```
SLI:  What you measure
SLO:  What you target internally
SLA:  What you promise customers (and pay penalties for breaking)

Typical SLA structure:
  "99.9% monthly uptime guaranteed.
   Credits if violated:
     < 99.9%:  10% of monthly bill refunded
     < 99%:    25% refunded
     < 95%:    50% refunded"
```

SLAs should always be **lower than your SLOs**:
```
Internal SLO: 99.95%  (what you aim for)
External SLA: 99.9%   (what you promise — buffer for unexpected events)
```

---

## Toil — The Enemy of SRE

Toil is manual, repetitive, operational work that is:
- **Manual** — human clicks or commands, not code
- **Repetitive** — done over and over, same steps
- **Automatable** — a machine could do this
- **Reactive** — triggered by an external event, not proactive
- **Tactical** — no lasting value; doing it again next time

```
Examples of toil:
  Manually restarting a service when it crashes (instead of auto-restart)
  Running a script to rotate access keys every 90 days
  Answering "is the system up?" questions that a dashboard should answer
  Manually approving low-risk deployments that should auto-deploy
  Checking a log file every morning for errors (instead of alerts)
```

SRE teams have a rule: **toil should not exceed 50% of working time**. The other 50% must go to engineering work that eliminates toil.

```
This week: Manually restarted the database 3 times
Next sprint: Automate database restart with CloudWatch alarm + Lambda
Result: 0 minutes of that toil next month
```

---

## Incident Management

When things go wrong — and they will — the SRE process defines exactly what happens:

### Incident Severity Levels

```
SEV-1 (Critical):
  Complete outage. All users affected. Business-critical data at risk.
  Response: Immediate. All hands. CEO notified.
  Resolution target: < 30 minutes

SEV-2 (Major):
  Significant degradation. Large % of users affected. Core features broken.
  Response: Within 15 minutes. On-call engineer + team lead.
  Resolution target: < 2 hours

SEV-3 (Minor):
  Partial degradation. Small % of users affected. Non-core features broken.
  Response: Within 1 hour during business hours.
  Resolution target: < 24 hours

SEV-4 (Low):
  Cosmetic issue. No user impact. Detected proactively.
  Response: Next business day.
```

### The Incident Process

```
1. DETECT:    Alert fires (CloudWatch alarm, PagerDuty, user report)
2. TRIAGE:    On-call assesses severity, declares incident if needed
3. RESPOND:   Incident Commander assigned, stakeholders notified
4. MITIGATE:  Restore service — rollback, failover, scale up, hotfix
              (Mitigation ≠ Root Cause Fix — get users back first)
5. RESOLVE:   Service restored, monitoring confirmed stable
6. POSTMORTEM: Document timeline, root cause, contributing factors, action items
```

### Blameless Postmortem

The postmortem is not about finding who made a mistake. Systems fail because processes allow humans to make mistakes — not because humans are incompetent.

```
Blameless postmortem asks:
  "What in the system allowed this to happen?"
  "What monitoring failed to catch this earlier?"
  "What process change prevents this class of failure?"
  NOT: "Who pushed the bad change?"

Output:
  - Timeline of events
  - Root cause analysis (5 Whys)
  - Contributing factors
  - Action items with owners and due dates
  - What went well (seriously — document the wins too)
```

---

## On-Call Best Practices

### On-Call Should Not Be Miserable

```
Signs of a broken on-call culture:
  ❌ Pages at 3 AM for non-urgent issues
  ❌ Same person on-call for months
  ❌ No runbooks — engineer has to figure it out from scratch each time
  ❌ Alerts that fire but require no action (alert fatigue)
  ❌ More than 2 incidents per on-call shift

Signs of healthy on-call:
  ✅ Pages only for actionable, urgent issues
  ✅ Runbooks for every common alert
  ✅ Rotation shared across the team
  ✅ Compensation for on-call hours
  ✅ Post-incident: eliminate the root cause so it doesn't page again
```

### AWS Tools for On-Call

```
PagerDuty / OpsGenie:  Alert routing, on-call schedules, escalation policies
CloudWatch Alarms:     Triggers alerts based on metric thresholds
CloudWatch Composite:  Combine alarms to reduce noise
SNS → PagerDuty:       CloudWatch alarm → SNS → PagerDuty → engineer's phone
Systems Manager:       Runbooks as automation — fix common issues automatically
```

---

## Chaos Engineering — Test Your Reliability

Don't assume your DR plan works. Test it.

```
Chaos Principles:
1. Build a hypothesis: "If the database fails, the app serves cached data for 5 minutes"
2. Define the blast radius: Test in staging or a limited prod scope
3. Introduce the failure: Kill the DB, terminate instances, block network
4. Observe: Does the system behave as expected?
5. Fix: If not, fix the gap. If yes, try harder.

Tools on AWS:
  AWS Fault Injection Simulator (FIS) — managed chaos engineering
  Experiments: terminate EC2, inject latency, throttle API calls, fail AZ
```

```python
# AWS FIS experiment — terminate 25% of EC2 instances in production
{
  "targets": {
    "ec2-instances": {
      "resourceType": "aws:ec2:instance",
      "filters": [{"path": "tags.Environment", "values": ["production"]}],
      "selectionMode": "PERCENT(25)"    # 25% of instances
    }
  },
  "actions": {
    "terminate-instances": {
      "actionId": "aws:ec2:terminate-instances",
      "targets": {"Instances": "ec2-instances"}
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:alarm:ErrorRateTooHigh"  # Auto-stop if errors spike
    }
  ]
}
```

---

## Key Takeaways

- **SLI is what you measure, SLO is what you target, SLA is what you promise** — know the difference
- **Error budgets turn reliability into a shared team decision** — development AND operations aligned on the same math
- **Toil is the enemy** — every hour of toil is an hour not spent on engineering that eliminates toil
- **Incidents are not failures — they're information** — blameless postmortems extract that information
- **On-call should be sustainable** — rotation, runbooks, alert quality, and compensation matter
- **Chaos engineering proves your reliability** — assumptions tested are more valuable than assumptions stated
- **SRE is a mindset** — treat reliability as a software problem, solve it with engineering

---

*Found this useful? Follow for more deep-dives — next up: MLOps and AIOps on AWS — building, deploying, and operating machine learning systems in production.*
