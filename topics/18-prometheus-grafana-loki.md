# Prometheus + Grafana + Loki Setup

### Step 1: Install kube-prometheus-stack
```bash
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm install monitoring \
  prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace
# Installs: Prometheus, Grafana, Alertmanager, node-exporter
```

### Step 2: Install Loki + Promtail
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack \
  -n monitoring --set promtail.enabled=true
# Promtail = DaemonSet that collects logs → ships to Loki
```

### Step 3: Configure
- Add Loki data source: Grafana → Data Sources → Loki → `http://loki:3100`
- Import dashboards: ID **15661** (K8s cluster), ID **13639** (node-exporter)
- Alertmanager → Slack/PagerDuty for pod crash, high CPU, OOM

### Step 4: App Custom Metrics
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
spec:
  endpoints:
  - port: http
    path: /metrics
```

### Log Retention
- Dev: 30 days | Prod: 90 days
- Logs stored on **S3** — S3 lifecycle policies auto-delete
