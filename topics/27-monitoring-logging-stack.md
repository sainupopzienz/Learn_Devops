# Monitoring & Logging Stack — Prometheus, Grafana, Loki, S3

### Architecture Overview

5 EC2 instances + 1 Monitoring Server running Prometheus, Grafana, Loki. Logs archived to S3.

```
                   +------------------+
                   |     Grafana      |
                   +--------+---------+
                            |
                +-----------+-----------+
                |                       |
         Metrics Query           Log Query
                |                       |
         +------+-----+           +-----+------+
         | Prometheus |           |    Loki    |
         +------+-----+           +-----+------+
                |                       |
      --------------------         Fluent Bit
      |        |        |               |
 +--------+ +--------+ +--------+  App Logs
 | EC2-1  | | EC2-2  | | EC2-5  |
 +--------+ +--------+ +--------+
 |NodeExp | |NodeExp | |NodeExp |
 |cAdvisor| |cAdvisor| |cAdvisor|
 +--------+ +--------+ +--------+
                                       |
                                       v
                                  Amazon S3
                               (Log Retention)
```

---

### What is Prometheus?

- Open-source monitoring system — collects and stores time-series metrics
- **Pull-based** — Prometheus scrapes targets over HTTP (not push)
- Periodically hits exporters and stores metrics in its own time-series DB

```
Prometheus
      |
      +--> Node Exporter  (host metrics)
      |
      +--> cAdvisor       (container metrics)
```

---

### Node Exporter — Host Metrics

Collects **OS and host-level** metrics from each EC2 instance.

| Metric | What it Tracks |
|--------|---------------|
| CPU | Utilization per core |
| Memory | Usage, available, cached |
| Disk | Read/write IOPS, space used |
| Network | Bytes in/out, errors |
| Load | System load average |

**Use cases:**
- Detect high CPU / memory pressure
- Track disk space before it fills
- Analyze network throughput

---

### cAdvisor — Container Metrics

Collects **Docker container-level** metrics running on each EC2.

| Metric | What it Tracks |
|--------|---------------|
| CPU | Per-container usage |
| Memory | Container memory consumption |
| Network | Container network activity |
| Filesystem | Container disk usage |
| Lifecycle | Restarts, uptime |

**Use cases:**
- Identify containers consuming excessive memory
- Detect CPU spikes in specific containers
- Track container resource allocation

---

### Node Exporter vs cAdvisor — Key Difference

| Component | Purpose | Scope |
|-----------|---------|-------|
| Node Exporter | Host / OS metrics | The EC2 machine itself |
| cAdvisor | Container metrics | Docker containers on the machine |
| Prometheus | Stores all metrics | Time-series database |
| Grafana | Visualizes everything | Dashboards |

> Both are **exporters** — they expose HTTP endpoints that Prometheus scrapes. Neither handles logs.

---

### Grafana Dashboards

**Infrastructure Dashboard**
- CPU Utilization, Memory Usage, Disk Usage, Network Throughput

**Container Dashboard**
- Container CPU/Memory, Restart count, Network activity

**Application Dashboard**
- Request rate, Response time, Error rate, Throughput

---

### Centralized Logging with Loki

**Without Loki** — engineer must SSH into each server individually:
```
EC2-1 Logs  ← SSH
EC2-2 Logs  ← SSH
EC2-3 Logs  ← SSH
EC2-4 Logs  ← SSH
EC2-5 Logs  ← SSH
```

**With Loki** — all logs searchable from one Grafana interface:
```
EC2 Servers → Fluent Bit → Loki → Grafana
```

- Metrics tell you **something is wrong**
- Logs tell you **why**

---

### Fluent Bit — Log Collector

Lightweight agent running on each EC2 that ships logs to Loki.

```
Application Logs → Fluent Bit → Loki
```

**Why Fluent Bit over Promtail?**
- Extremely lightweight — low CPU and memory footprint
- Cloud-native and Kubernetes-friendly
- Broader ecosystem support (supports multiple outputs: Loki, S3, Elasticsearch)
- Promtail still works but newer architectures favor Fluent Bit or Grafana Alloy

---

### Long-Term Log Retention with Amazon S3

```
App Logs → Fluent Bit → Loki → Amazon S3
```

| Storage Tier | Retention | Purpose |
|-------------|-----------|---------|
| Loki Local Storage | 7 Days | Fast recent queries |
| Amazon S3 | 1 Year+ | Archive, compliance, audits |

**Benefits:**
- Cost-effective vs keeping everything in Loki
- Highly durable (99.999999999%)
- Virtually unlimited scale
- S3 Lifecycle policies auto-archive or delete old chunks

---

### Alerting with Alertmanager

**Infrastructure Alerts**
- CPU > 80%
- Memory > 90%
- Disk space < 15%

**Container Alerts**
- Container restart count increased
- Container memory usage high
- Container marked unhealthy

**Application Alerts**
- High error rate
- Increased response time
- Service down

**Alert destinations via Alertmanager:**
- Slack, Email, PagerDuty, Microsoft Teams

---

### Full Stack Summary

| Component | Role |
|-----------|------|
| Node Exporter | Collects host/OS metrics from each EC2 |
| cAdvisor | Collects Docker container metrics |
| Prometheus | Scrapes and stores all metrics |
| Grafana | Visualizes metrics + logs in dashboards |
| Fluent Bit | Collects logs from apps and ships to Loki |
| Loki | Aggregates and indexes logs |
| Alertmanager | Routes alerts to Slack/PagerDuty/Email |
| Amazon S3 | Long-term log archive (cost-effective) |
