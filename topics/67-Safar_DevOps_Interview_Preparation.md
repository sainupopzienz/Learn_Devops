# DevOps Interview Preparation Guide
### Sainudeen Safar — AWS SA Pro | CKA | RHCE | 3+ Years Experience

---

## How to use this guide

- Read each question and answer out loud — not in your head
- Time yourself — most answers should be 30–60 seconds
- For Hard questions, prepare a real example from your resume
- Click nothing — just read, practice, repeat

---

## Kubernetes Architecture — Request Flow (Internet → Pod)

> Based on your diagram: Internet → ALB → Ingress → Service (ClusterIP) → kube-proxy (iptables/ipvs) → Pod

### Q: Walk me through how a request travels from the internet to a pod in Kubernetes.

**Answer:**

*"When a request comes from the internet, it first hits the AWS ALB — the Application Load Balancer — which forwards traffic to the Kubernetes Ingress controller. The Ingress reads the routing rules and routes the request to the correct Service based on the host or path. The Service has a stable ClusterIP which acts as a virtual IP for the pods behind it. From there, kube-proxy — which runs on every node and manages iptables or ipvs rules — selects one of the available pods using round-robin load balancing and forwards the request to it. The pod handles the request and responds back. CNI — the Container Network Interface — handles the underlying network communication between pods and nodes throughout this flow."*

---

### Q: What is the role of kube-proxy in Kubernetes?

**Answer:**

*"kube-proxy runs as a DaemonSet on every node. Its job is to maintain network rules — specifically iptables or ipvs rules — that allow traffic to reach the correct pods. When a Service is created, kube-proxy updates these rules so that any traffic hitting the ClusterIP gets forwarded to one of the healthy pods behind the service. It's responsible for the actual load balancing at the network level using round-robin selection."*

---

### Q: What happens if kube-proxy crashes?

**Answer:**

*"If kube-proxy crashes, existing traffic continues flowing because the iptables or ipvs rules it previously wrote are still in place — they don't disappear when kube-proxy dies. So current pods and services keep working. The problem is that updates stop — if a new pod comes up, or a service is created or deleted, kube-proxy can't update the rules. New pods won't receive traffic and removed pods may still receive traffic. That's why kube-proxy is run as a DaemonSet with automatic restart policies — so it recovers quickly."*

---

### Q: What is Ingress and why do we need it when we already have Services?

**Answer:**

*"A Service exposes pods internally or via a NodePort/LoadBalancer, but it doesn't give you smart HTTP routing. Ingress sits in front of Services and gives you host-based and path-based routing, TLS termination, and a single entry point for multiple services. So instead of having 10 LoadBalancers for 10 services — which is expensive — you have one ALB and one Ingress controller that routes to all of them based on rules. It's more efficient and easier to manage."*

---

### Q: What is the difference between ClusterIP, NodePort, and LoadBalancer services?

**Answer:**

*"ClusterIP is the default — it gives the service a stable internal IP accessible only within the cluster. NodePort exposes the service on a static port on every node's IP — useful for external access in non-cloud environments but not production-grade. LoadBalancer provisions an actual cloud load balancer — like an AWS ALB or NLB — and is the standard way to expose services externally in cloud environments. In practice I use ClusterIP for internal service-to-service communication and LoadBalancer or Ingress for external traffic."*

---

### Q: What is CNI and why does Kubernetes need it?

**Answer:**

*"CNI stands for Container Network Interface. Kubernetes itself doesn't handle pod networking — it delegates that to a CNI plugin. The CNI is responsible for assigning IP addresses to pods, setting up network interfaces inside containers, and enabling communication between pods across different nodes. Common CNI plugins include Calico, Flannel, and AWS VPC CNI. In EKS we use the AWS VPC CNI which assigns actual VPC IPs to pods, which makes pod networking integrate natively with AWS security groups and routing."*

---

### Q: How does HPA work and what triggers it?

**Answer:**

*"HPA — Horizontal Pod Autoscaler — monitors resource metrics like CPU and memory through the metrics-server and automatically adjusts the number of pod replicas. When average CPU across pods exceeds the threshold you set — say 70% — HPA scales up by adding more replicas. When it drops below, it scales down after a cooldown period. You can also configure custom metrics through Prometheus adapter for more fine-grained scaling. In my projects at Pixdynamics I used HPA on EKS serving 50K+ daily requests — it handled traffic spikes automatically without manual intervention."*

---

### Q: What is the difference between a Deployment and a StatefulSet?

**Answer:**

*"A Deployment is for stateless applications — pods are interchangeable, they can be created and destroyed in any order, and they don't have persistent identity. A StatefulSet is for stateful applications like databases — each pod gets a stable hostname, stable storage, and pods are created and deleted in order. StatefulSets are used for things like MySQL, PostgreSQL, Kafka, or Redis clusters where pod identity and ordered startup/shutdown matters."*

---

## Section 1 — Incident & Production Issues

### Q: Production is down at 2am. Walk me through exactly what you do in the first 10 minutes.

**Answer:**

*"First thing — don't panic, follow the process. I immediately check my monitoring dashboards — CloudWatch and Grafana — to understand the scope. Is it one service or everything? I check for recent deployments or config changes in the last hour — that's the most common cause. I look at error rates, latency spikes, and pod health in Kubernetes. While I'm doing this I post in the incident Slack channel so the team knows I'm on it — communication is as important as the fix. If I identify the cause quickly, I act — rollback, scale up, restart pods. If I can't find it in 5 minutes I escalate and pull in the right people. I never stay silent and solo-debug a production outage for 30 minutes. First 10 minutes is about: assess scope, check recent changes, communicate, act or escalate."*

---

### Q: A deployment just broke production. How do you rollback and what's your communication plan?

**Answer:**

*"Immediate action — rollback using `kubectl rollout undo deployment/<name>`. This reverts to the previous ReplicaSet instantly. While that's running I post in the incident channel: 'Production issue identified, rolling back deployment X, ETA to recovery 5 minutes.' I confirm the rollback worked by checking pod status and error rates in monitoring. Once stable I do a post-mortem — what was in the deployment, why did it pass staging, what gate failed. Going forward I'd add a smoke test or canary stage to the pipeline so a bad deployment catches in canary before it hits 100% of traffic. The communication plan matters as much as the technical fix — stakeholders need to know what happened and when it will be resolved."*

---

### Q: Your monitoring shows CPU at 100% on 3 nodes. What's your immediate response?

**Answer:**

*"I first check which pods are consuming the most CPU using `kubectl top pods` — identify the culprit. Then I check if it's a legitimate traffic spike or a runaway process. If it's traffic, I check if HPA is working and if not, I manually scale the deployment up. If it's a runaway process I check the pod logs for errors or infinite loops. If the nodes themselves are overwhelmed I can cordon the affected nodes to stop new pod scheduling and let the cluster autoscaler add capacity. I also check CloudWatch metrics to see if this is gradual or sudden — sudden usually means a bad deployment or a traffic spike, gradual means a resource leak. I set a CloudWatch alarm for this exact threshold in my projects so I'm notified before it reaches 100%."*

---

### Q: A pod keeps crashing with OOMKilled. How do you diagnose and fix it?

**Answer:**

*"OOMKilled means the pod exceeded its memory limit and the kernel killed it. First I check `kubectl describe pod <name>` to confirm it's OOMKilled and see the last exit code — 137 confirms it. Then I check `kubectl logs <pod> --previous` to see what it was doing before it died. The fix depends on the cause — if the app genuinely needs more memory I increase the memory limit in the deployment spec. If it's a memory leak in the application I flag it to the dev team. If the limit was set too low initially I adjust it based on actual observed usage from metrics. I also set memory requests and limits properly — requests for scheduling, limits for enforcement — and I use Prometheus to track memory trends so I can right-size before it becomes an incident."*

---

### Q: Users are reporting intermittent 502 errors. How do you track down the root cause?

**Answer:**

*"502 means the load balancer got a bad response from the backend. I start at the ALB access logs — check which target group is returning errors and what percentage. Then I check pod health — are pods crashing and restarting? A pod that's restarting during a request will cause a 502. I check readiness probes — if they're misconfigured, pods get traffic before they're ready. I check for timeouts — if the app takes longer than the ALB timeout setting to respond, it returns a 502. I look at application logs for errors during the same time window. In most cases it's either pods restarting during deployment, readiness probes not configured correctly, or the app timing out under load. I correlate the 502 timestamps in ALB logs with pod restart events in Kubernetes events to pinpoint it."*

---

### Q: Database connections are maxing out. What are your steps?

**Answer:**

*"First I check RDS CloudWatch metrics — DatabaseConnections, CPUUtilization, FreeableMemory — to understand the severity. Then I identify which application is opening the most connections using RDS Performance Insights or pg_stat_activity for PostgreSQL. The most common cause is connection pooling not being configured — applications opening a new connection per request instead of reusing a pool. The fix is to implement a connection pooler like PgBouncer in front of RDS, or configure the application's connection pool size properly. If it's an immediate emergency I can temporarily scale up the RDS instance class to support more connections while the fix is being applied. Long term I set a CloudWatch alarm on DatabaseConnections at 80% of max to catch this early."*

---

## Section 2 — Kubernetes & Containers

### Q: A Kubernetes node is NotReady. How do you investigate and recover?

**Answer:**

*"First I run `kubectl describe node <node-name>` to see the conditions and events. NotReady usually means the kubelet stopped communicating with the API server. I SSH into the node and check kubelet status — `systemctl status kubelet`. If kubelet is down I restart it. I check system resources — disk pressure, memory pressure, PID pressure — these are common reasons for NotReady. I check `/var/log/kubelet.log` for errors. If the node is genuinely unhealthy — hardware issue or unrecoverable state — I cordon it to prevent new scheduling, drain it to move pods to healthy nodes, then terminate it and let the autoscaling group replace it. In EKS this is straightforward — I terminate the EC2 instance and ASG launches a new one automatically."*

---

### Q: Pods are in Pending state and not scheduling. What do you check?

**Answer:**

*"Pending means the scheduler can't find a suitable node. I run `kubectl describe pod <name>` and look at the Events section — it tells you exactly why. The most common reasons are: insufficient CPU or memory on nodes — no node has enough resources for the pod's request. Taints and tolerations mismatch — the pod doesn't tolerate the node's taint. Node selector or affinity rules that no node matches. PVC not bound — if the pod needs persistent storage that isn't available. I check `kubectl get nodes` to see node capacity and `kubectl describe nodes` to see allocatable resources. If it's a resource issue, the cluster autoscaler should add a node — if it's not doing that, I check the autoscaler logs."*

---

### Q: How would you design a zero-downtime deployment strategy in Kubernetes?

**Answer:**

*"I use a combination of rolling updates, readiness probes, and PodDisruptionBudgets. Rolling update strategy ensures pods are replaced gradually — I set maxUnavailable to 0 and maxSurge to 1 so new pods come up before old ones go down. Readiness probes ensure the load balancer only sends traffic to pods that are actually ready to serve — this is critical, without it you get 502s during deployment. PodDisruptionBudgets ensure a minimum number of pods are always available during voluntary disruptions. For higher-risk deployments I use canary — deploy to 10% of traffic first, monitor error rates and latency for 10 minutes, then proceed or rollback. In my projects at Pixdynamics I achieved zero-downtime deployments for 15+ microservices using this approach."*

---

### Q: Your HPA is not scaling even though CPU is high. Why could this happen?

**Answer:**

*"Several possible reasons. First — metrics-server not installed or not working. HPA gets metrics from metrics-server and if it's down, HPA can't act. I check `kubectl top pods` — if that doesn't work, metrics-server is the issue. Second — resource requests not set on the pod. HPA calculates CPU utilization as a percentage of the requested CPU — if no request is set, HPA has no baseline to calculate against and won't scale. Third — HPA already at maxReplicas. If you've hit the max, it can't scale further. Fourth — cooldown period. HPA has a scale-up cooldown to prevent thrashing — it won't scale again immediately after a recent scale event. I check `kubectl describe hpa <name>` to see the current status and any conditions that explain why it's not acting."*

---

### Q: How do you manage secrets securely in a Kubernetes environment?

**Answer:**

*"I don't store secrets in plain Kubernetes Secrets if I can avoid it — by default they're just base64 encoded, not encrypted. My preferred approach is AWS Secrets Manager integrated with Kubernetes using the Secrets Store CSI Driver or External Secrets Operator. Secrets are stored and rotated in AWS Secrets Manager and synced into pods as environment variables or mounted volumes. This gives you rotation, audit logging, and IAM-based access control. For less sensitive configuration I use SSM Parameter Store. I also enable envelope encryption on the Kubernetes secrets using KMS keys so secrets at rest in etcd are actually encrypted. RBAC is essential too — only the service accounts that need a secret should have access to it."*

---

### Q: Walk me through how you would upgrade an EKS cluster with zero downtime.

**Answer:**

*"EKS upgrade is a multi-step process. First I upgrade the control plane — in EKS this is done through the console or CLI and AWS manages the master nodes. I upgrade one minor version at a time — you can't skip versions. Once the control plane is updated, I upgrade the node groups — I create a new node group with the new version, cordon the old nodes to stop new pod scheduling, then drain them one by one to move pods to the new nodes. PodDisruptionBudgets ensure pods are moved gracefully without dropping below minimum availability. After all pods are on new nodes I terminate the old node group. I also update add-ons — kube-proxy, CoreDNS, VPC CNI — to versions compatible with the new Kubernetes version. I always test the upgrade in staging first and I schedule it during low-traffic windows even though it should be zero-downtime."*

---

## Section 3 — AWS & Cloud Infrastructure

### Q: Your AWS bill doubled this month. How do you find and fix the cause?

**Answer:**

*"I go to AWS Cost Explorer first — filter by service and sort by cost to identify what spiked. Then I filter by linked account and region to narrow it down further. Common culprits are EC2 instances that were scaled up and not scaled back down, NAT Gateway data transfer charges which get expensive fast, RDS storage autoscaling that increased, or someone leaving a large EC2 instance running. I check CloudTrail for recent API calls — if someone launched expensive instance types I'll see it there. For the fix I right-size instances, set up AWS Budgets with alerts so I'm notified before costs double next time, and implement auto-shutdown for non-production environments. At Pixdynamics I reduced AWS costs by 15% — about $12K/year — through rightsizing and Reserved Instance planning."*

---

### Q: Design a highly available, multi-AZ architecture for a web application on AWS.

**Answer:**

*"I'd design it across at least 2 AZs — ideally 3. The entry point is Route 53 with health checks for DNS failover. Behind that, an ALB spread across AZs distributes traffic. The application tier runs on ECS or EKS with tasks/pods spread across AZs using topology spread constraints. For the database tier I use RDS Multi-AZ — primary in one AZ, synchronous standby replica in another — automatic failover in under 2 minutes if primary fails. Static assets go to S3 with CloudFront in front for caching and global distribution. Secrets go to Secrets Manager, configuration to SSM Parameter Store. All resources live in private subnets — only the ALB is in public subnets. NAT Gateway in each AZ for outbound internet from private subnets. VPC endpoints for S3 and other AWS services to avoid NAT costs."*

---

### Q: An EC2 instance is unreachable via SSH. What are your troubleshooting steps?

**Answer:**

*"I work through the layers systematically. First — check the instance state in the console, is it running? Check system status checks and instance status checks — if either is failing there's a hardware or OS issue. Second — check Security Groups — is port 22 open from my IP? Third — check NACLs — are they blocking the traffic? Fourth — check the route table — does the subnet have a route to the internet gateway if it's a public subnet? Fifth — check if the key pair is correct. If all of that looks fine I use EC2 Serial Console or SSM Session Manager to get in without SSH — SSM is actually my preferred method now because it doesn't require SSH at all, just SSM agent running on the instance and the right IAM permissions."*

---

### Q: How would you migrate 20 on-premise applications to AWS with minimal downtime?

**Answer:**

*"I follow a phased approach. First — discovery and assessment. Understand each application's dependencies, data, and uptime requirements. Categorize them by migration strategy — rehost, replatform, or refactor. Second — set up the AWS environment — VPC, subnets, security groups, IAM, Direct Connect or VPN for hybrid connectivity during migration. Third — migrate in waves, starting with the least critical applications to learn and refine the process. For databases I use AWS DMS for live replication so the source stays running while data syncs to RDS. I do a cutover during a maintenance window — update DNS, switch traffic, monitor. For stateless applications I containerize and run on ECS or EKS. At Pixdynamics I migrated 20+ applications to EKS with less than 2 hours total downtime by using this phased approach with DMS for database replication."*

---

### Q: S3 bucket data was accidentally deleted. What do you do?

**Answer:**

*"First question — is versioning enabled? If yes, deleted objects have a delete marker that can be removed to restore them — I use the S3 console or CLI to remove delete markers. If versioning isn't enabled, recovery depends on whether there's a backup — I check AWS Backup or any cross-region replication. If neither — the data may be unrecoverable, which is why I always enable versioning and cross-region replication on critical buckets. Going forward I enable MFA Delete on the bucket so deletions require MFA confirmation — prevents accidental or malicious deletion. I also set S3 Object Lock for compliance-sensitive data. This incident becomes a post-mortem and a reason to add S3 versioning and backup verification to the infrastructure checklist."*

---

## Section 4 — CI/CD & Automation

### Q: Your CI/CD pipeline is taking 45 minutes. How do you optimize it?

**Answer:**

*"I start by profiling — identify which stages take the most time. Common culprits are test suites, Docker builds, and dependency installation. For tests I parallelize them across multiple agents and run unit tests separately from integration tests — fail fast on unit tests before running slower integration tests. For Docker builds I optimize the Dockerfile — put rarely-changing layers first so Docker cache is used effectively. I use a Docker registry cache and multi-stage builds to reduce image size. For dependencies I cache node_modules or pip packages between runs — most CI systems support this. I also look at whether all stages need to run on every commit — maybe integration tests only run on PR merge. In my projects I got pipelines from weekly batch to 20+ daily releases by restructuring the pipeline and adding parallelism."*

---

### Q: A developer pushed directly to main and broke the build. How do you prevent this?

**Answer:**

*"I implement branch protection rules on main — require pull requests, require at least one code review approval, require all CI checks to pass before merge, and disable force pushes. In GitHub/GitLab this is a settings configuration. I also add a pre-commit hook that runs linting locally before the code even gets pushed. For the pipeline itself I add a build validation step that runs on every PR so issues are caught before merge. Going forward I communicate the new process to the team — not as a punishment but as a quality gate that protects everyone. I document it in the team's contributing guide."*

---

### Q: How would you design a GitOps workflow using ArgoCD for a microservices application?

**Answer:**

*"In GitOps, Git is the single source of truth for infrastructure and application state. I'd have two repositories — one for application code and one for Kubernetes manifests. When a developer merges code, the CI pipeline builds the image, pushes to ECR, and updates the image tag in the manifests repo. ArgoCD watches the manifests repo and automatically syncs any changes to the cluster — if the desired state in Git differs from the actual state in the cluster, ArgoCD reconciles it. For multiple environments — dev, staging, prod — I use separate folders or branches in the manifests repo with Kustomize overlays for environment-specific values. Rollback is as simple as reverting a commit in Git — ArgoCD picks it up and reverts the cluster. This approach gives you full auditability, easy rollback, and prevents configuration drift."*

---

### Q: How do you handle secrets in a CI/CD pipeline securely?

**Answer:**

*"I never store secrets in the repository — not even encrypted ones if I can avoid it. I use the CI system's native secret storage — Jenkins credentials store, GitLab CI variables, or GitHub Actions secrets — for secrets needed during the pipeline. For secrets that need to reach the application at runtime, I use AWS Secrets Manager and the application fetches them at startup using IAM roles — no secrets are ever injected through environment variables in the pipeline itself. I also scan the repository with tools like git-secrets or truffleHog to detect accidentally committed secrets. For Kubernetes, the External Secrets Operator syncs from AWS Secrets Manager into Kubernetes secrets automatically."*

---

### Q: Describe blue-green vs canary deployment. When would you use each?

**Answer:**

*"Blue-green means you have two identical environments — blue is live, green is the new version. You deploy to green, test it, then switch all traffic from blue to green at once. Rollback is instant — just switch back to blue. The downside is cost — you need double the infrastructure. I use blue-green for major releases where I want the ability to instantly rollback and where brief traffic switch is acceptable. Canary is more gradual — you send a small percentage of traffic — say 5% or 10% — to the new version and monitor metrics. If everything looks good you gradually increase. If something is wrong, only a small percentage of users were affected. I use canary for high-risk changes where I want real production validation with limited blast radius. In Kubernetes I implement canary using weighted routing in the Ingress or with a service mesh like Istio."*

---

## Section 5 — Monitoring & Observability

### Q: How did you reduce MTTR from 4 hours to 12 minutes? Walk through your exact approach.

**Answer:**

*"The 4-hour MTTR was because we were detecting incidents from user reports — by the time someone complained, triaged it, found the on-call person, and they started investigating, hours had passed. I built a proactive observability stack using Prometheus for metrics, Grafana for dashboards, Loki for log aggregation, and CloudWatch for AWS-level metrics. I created custom dashboards with the 4 golden signals — latency, traffic, errors, saturation — for every service. I set up PagerDuty-style alerts with clear runbooks so when an alert fires, the on-call engineer immediately knows what to check. I also wrote automated remediation for the most common incidents — pod restarts, disk full — so they self-heal before a human even needs to get involved. The result was we were detecting and resolving issues in 12 minutes on average instead of 4 hours."*

---

### Q: What's the difference between metrics, logs, and traces? How do you use all three together?

**Answer:**

*"Metrics are numerical time-series data — CPU usage, request rate, error rate. They tell you that something is wrong. Logs are timestamped text records of events — they tell you what happened. Traces are records of a request's journey across multiple services — they tell you where in the system something went wrong. In practice I use them together in layers. An alert fires on a metric — error rate is above 1%. I go to Grafana, look at the dashboard, and see the error started at 14:23. I go to Loki and filter logs for that time window to find the error messages. If it's a distributed system, I use distributed tracing — Jaeger or X-Ray — to find which service in the chain is failing. Metrics → Logs → Traces is the investigation flow."*

---

### Q: How do you set up alerting that avoids alert fatigue?

**Answer:**

*"Alert fatigue happens when you get too many alerts that aren't actionable. My approach is to alert on symptoms not causes — alert when users are affected, not every time a low-level metric twitches. I use multi-window alerts in Prometheus — a short window catches fast incidents, a longer window catches slow burns. I set severity levels — P1 for immediate action, P2 for business hours, P3 for informational. I regularly review and tune alerts — if an alert fires and the on-call engineer ignores it because it's a false positive, it gets tuned or removed. I also use alert grouping and inhibition — if a node is down, suppress all the pod alerts that result from it, because they're all caused by the same thing. The goal is every alert is actionable and meaningful."*

---

### Q: Design a complete observability stack for a microservices application from scratch.

**Answer:**

*"I'd build it in layers. For metrics — Prometheus scrapes all services and Kubernetes components, with AlertManager for alerting and PagerDuty integration for on-call. Grafana for visualization with dashboards per service and an overall SLA dashboard. For logs — Fluent Bit as a DaemonSet on every node to collect container logs and ship to Loki or CloudWatch Logs. Grafana queries Loki directly so metrics and logs are in the same tool. For traces — Jaeger or AWS X-Ray with OpenTelemetry SDK instrumentation in the applications. For AWS-level monitoring — CloudWatch for EC2, RDS, ALB metrics, and CloudTrail for API audit logging. For uptime — synthetic monitoring using CloudWatch Synthetics or Blackbox Exporter. The entire stack is deployed as Helm charts and managed with Terraform so it's reproducible and version-controlled."*

---

## Section 6 — Terraform & IaC

### Q: Someone manually changed an AWS resource managed by Terraform. What happens and what do you do?

**Answer:**

*"This is called configuration drift — the actual state in AWS no longer matches what's in the Terraform state file. If someone runs terraform plan next time, it will show that change as a diff and terraform apply will revert it — which could cause an outage if the manual change was intentional and important. My immediate action is to run terraform plan to see what drifted. If the manual change should be kept, I update the Terraform code to reflect it — terraform import if needed — and then apply. If the change was unauthorized, I revert it via terraform apply. Going forward I prevent this with IAM policies that restrict direct console changes in production — all changes must go through Terraform. I also run terraform plan in CI on a schedule to detect drift regularly."*

---

### Q: How do you manage Terraform state across multiple teams and environments safely?

**Answer:**

*"I use remote state in S3 with DynamoDB for state locking. Each environment — dev, staging, prod — has its own state file in a separate S3 prefix. State locking with DynamoDB prevents two people running apply at the same time and corrupting the state. I organize code into modules and workspaces — or separate directories — per environment. For teams, I use Terraform Cloud or Atlantis for collaborative workflows — every PR shows a plan, approvals are required before apply, and the apply runs automatically after merge. State files are encrypted at rest using SSM-managed KMS keys. I also enable versioning on the S3 bucket so I can restore a previous state if something goes wrong."*

---

### Q: A terraform apply is going to delete a production database. What do you do?

**Answer:**

*"Stop everything — do not apply. This is a critical situation. First I understand why Terraform wants to delete it — was the resource removed from the code, was the resource identifier changed, was it imported with the wrong name? Most database deletions in Terraform happen because someone renamed a resource or changed a parameter that forces recreation. I add a lifecycle block with `prevent_destroy = true` to the RDS resource immediately — this makes Terraform throw an error instead of deleting. I fix the code to match the actual desired state without deleting. If a rename is needed, I use terraform state mv to rename the resource in state without touching the actual infrastructure. I also set RDS deletion protection at the AWS level as a second safety net — even if Terraform tries to delete it, AWS will reject the API call."*

---

### Q: How do you structure Terraform modules for reuse across 10+ projects?

**Answer:**

*"I create a private Terraform module registry — either in a Git repo with versioned tags or using Terraform Cloud's private registry. I build modules for common patterns — a VPC module, an ECS cluster module, an RDS module — each with well-defined input variables and outputs. Modules are versioned with semantic versioning — projects reference a specific version so they're not broken by module updates. I use a consistent variable naming convention and document inputs and outputs with descriptions. For the 10+ projects at Innovature, this approach reduced infrastructure provisioning from 4 hours to 15 minutes — you call the VPC module, the ECS module, the RDS module, pass in environment-specific variables, and the infrastructure is ready. Changes to the module propagate to all projects through version upgrades, not copy-paste."*

---

## Section 7 — Security & Networking

### Q: You discover an S3 bucket in your AWS account is publicly accessible. What do you do?

**Answer:**

*"Immediate response — check what's in the bucket. Is sensitive data exposed? If yes, this is a security incident and I escalate immediately. I block public access on the bucket right away using the S3 Block Public Access setting — this is a one-click fix. I check CloudTrail to see who made it public and when. I check S3 access logs to see if anyone accessed it while it was public. I review all other S3 buckets in the account — if one is misconfigured, others might be too. Long term I enable AWS Config rules for S3 public access — it automatically detects and alerts on public buckets. I also enable S3 Block Public Access at the account level as a blanket prevention measure. This becomes a post-mortem and a review of IAM policies to ensure only the right people can modify bucket policies."*

---

### Q: How do you implement least privilege IAM in a large AWS environment?

**Answer:**

*"Least privilege means every IAM entity has exactly the permissions it needs — nothing more. I start by using IAM roles for everything instead of IAM users with access keys — roles are temporary and auto-rotated. For services I use task roles in ECS or pod identity in EKS so each application has its own role with only the permissions for the AWS services it calls. I use AWS-managed policies as a starting point and then restrict further with condition keys — for example, restrict S3 access to a specific bucket. I use IAM Access Analyzer to identify unused permissions and tighten them over time. For humans I use AWS SSO with permission sets tied to Active Directory groups. I avoid wildcard actions like s3:* or iam:* in production. Regular access reviews — at least quarterly — to remove stale permissions."*

---

### Q: A security scan found critical vulnerabilities in a container image in production. What's your response?

**Answer:**

*"First I assess the severity and exploitability — is this vulnerability actually reachable in our environment? A critical CVE in a library we don't call is lower priority than one in an actively used code path. If it's genuinely critical and exploitable, I treat it as an incident — update the base image or affected package, rebuild the image, and redeploy. If it's in the base OS layer I update FROM debian:latest to the patched version. I use ECR image scanning to detect vulnerabilities on push — I configure the pipeline to fail if critical CVEs are found, preventing vulnerable images from reaching production. I implement a regular image rebuild process — even if no code changes, images are rebuilt weekly to pick up OS patch updates. For zero-day type vulnerabilities I check AWS Security Bulletins and EKS release notes proactively."*

---

### Q: How would you design network segmentation in a VPC for a 3-tier application?

**Answer:**

*"I create three subnet tiers across multiple AZs. Public subnets for the load balancer — only the ALB lives here, it's the only thing with a direct internet gateway route. Private application subnets for EC2 instances or ECS tasks — no direct internet access, outbound through NAT Gateway. Private database subnets for RDS — completely isolated, no internet access at all, not even outbound. Security groups enforce the communication rules — ALB security group allows 443 from the internet, application security group allows traffic only from the ALB security group, database security group allows traffic only from the application security group. NACLs add a second layer of defense at the subnet boundary. This means even if one layer is compromised, the attacker can't directly reach the database — they have to go through every layer."*

---

## Section 8 — Behavioural & Situational

### Q: Tell me about a time you caused an outage. What happened and what did you learn?

**Answer:**

*"I'll be honest — every engineer who's worked in production has caused an outage. In my experience at Pixdynamics, I once applied a Terraform change to a security group that accidentally removed an inbound rule, which broke connectivity to several services. I caught it fairly quickly through monitoring — about 8 minutes of degraded service. I immediately rolled back the security group change and service restored. The learning was twofold — first, always run terraform plan and review every single change, especially security group modifications, before applying. Second, I added a mandatory peer review step for all Terraform changes to production — two sets of eyes on every plan. I also wrote a runbook for security group-related incidents so the next person can recover faster. I'm not embarrassed about it — I'm proud that I used it to make the process better."*

---

### Q: A developer keeps deploying bad code that breaks production. How do you handle this?

**Answer:**

*"I approach this as a process problem, not a people problem. The question is — why is bad code reaching production? I look at the CI/CD pipeline — do we have adequate automated tests? Do we have a staging environment that mirrors production? Is there a code review step? My solution is to fix the gates, not blame the developer. I add automated testing stages — unit tests, integration tests, smoke tests — that must pass before deployment. I add a staging environment where every deployment goes first and gets monitored for 10 minutes before promoting to production. I have a conversation with the developer — not accusatory — to understand why it keeps happening and whether they need help. If the gates are solid and it's still happening, that's a different conversation with the team lead. But 90% of the time it's a process gap, not a people problem."*

---

### Q: How do you prioritize when you have 3 critical incidents at the same time?

**Answer:**

*"First — communicate immediately. Post in the incident channel that there are multiple incidents and you're triaging. Quickly assess impact — which incident is affecting the most users or the most revenue? That gets priority. Which one has a quick fix — a simple restart or rollback? Fix that one first to reduce the number of active incidents. For the others, I delegate — pull in team members if available, or escalate to management to get more hands. I don't try to context-switch between three incidents alone — that's the worst outcome. Clear ownership per incident, clear communication channel, regular status updates every 15 minutes. Once the critical incidents are stable, I do a post-mortem on why three things broke at the same time — often they have a common cause."*

---

### Q: Tell me about a time you reduced infrastructure costs significantly. What was your approach?

**Answer:**

*"At Pixdynamics I reduced AWS costs by 15% — approximately $12,000 per year. My approach was systematic. First I used AWS Cost Explorer and Trusted Advisor to identify where money was going. The biggest wins were three things. First — rightsizing EC2 instances. Several instances were running at 10-15% CPU utilization — we were paying for large instances that weren't needed. I rightsized them and saved significantly. Second — Reserved Instances for stable workloads. We converted our always-on RDS and core EC2 instances from On-Demand to 1-year Reserved Instances — 40% discount. Third — cleaning up orphaned resources — old snapshots, unused EBS volumes, idle load balancers that nobody had noticed. I now run a monthly cost review and have CloudWatch billing alarms to catch unexpected spend before it compounds."*

---

### Q: How do you keep up with new DevOps tools and decide what to adopt?

**Answer:**

*"I follow a few sources consistently — CNCF landscape for cloud-native tools, AWS re:Invent sessions on YouTube, the Kubernetes and Terraform changelogs, and a few engineering blogs from companies like Shopify and Cloudflare that publish their infrastructure war stories. When a new tool appears — say a new observability tool or a new CI system — I don't immediately adopt it. I ask three questions: does it solve a problem I actually have? Is it mature enough for production — what's the community size, is it CNCF-graduated? What's the migration cost from what we use today? I test new tools in a personal lab environment first. For team adoption I do a small proof of concept, document the findings, and present the trade-offs to the team. Tools should solve problems — not be adopted because they're new."*

---

## Quick Reference — Key Numbers from Your Resume

Use these in interviews when asked for specifics:

| Metric | Value | Context |
|--------|-------|---------|
| Availability achieved | 99.95% | ECS deployments at Innovature |
| Deployment speed improvement | 40% faster | ECS with autoscaling |
| Provisioning time reduction | 4 hours → 15 minutes | Terraform modules across 10+ projects |
| Deployment frequency | Weekly → 20+ daily | CI/CD pipeline automation |
| MTTR reduction | 4 hours → 12 minutes | Observability stack implementation |
| Projects delivered on time | 5 major client projects | 100% on-time delivery |
| Microservices with zero-downtime | 15+ | CI/CD pipelines at Pixdynamics |
| Cost savings | 15% / $12K/year | AWS rightsizing and IAM optimization |
| Migration scope | 20+ applications | On-premise to EKS |
| Migration downtime | <2 hours total | Maintained 99.9% SLA |
| Daily requests served | 50K+ | EKS with HPA |
| Cost reduction (Lambda) | 30% | Serverless migration at Giglabz |
| Manual effort eliminated | 60% | Terraform/CloudFormation automation |

---

## Your Certification Talking Points

### AWS Solutions Architect – Professional
*"This is the hardest AWS certification — it covers multi-account architectures, disaster recovery, cost optimization, and migration strategies at enterprise scale. Only around 3% of AWS-certified professionals hold the Professional level. It means I can design systems, not just operate them."*

### Certified Kubernetes Administrator (CKA)
*"CKA is a hands-on, performance-based exam in a live Kubernetes cluster — no multiple choice. You have to actually fix real cluster problems under time pressure. It validates that I can operate Kubernetes in production — cluster upgrades, networking, RBAC, troubleshooting — not just deploy applications to it."*

### Red Hat Certified Engineer (RHCE)
*"RHCE validates Ansible automation expertise — configuring and managing Linux infrastructure at scale using automation. It's a performance-based exam. In a DevOps context it means I can automate server configuration, patch management, and compliance enforcement across hundreds of servers reliably."*

---

## Reason for Change — Final Answer

*"I'm looking for an environment that gives me more challenges — working across diverse projects, solving real infrastructure problems at scale. My current role has become more maintenance-focused and the scope has narrowed. I want to be in a place where I'm constantly pushed to learn, where the work aligns with where I want to go long-term — deeper into cloud-native infrastructure, platform engineering, and reliability at scale. That's what drew me to this opportunity specifically."*

---

## Ownership Answer — Final Answer

*"Ownership to me means being accountable for the full lifecycle — not just building and deploying, but monitoring, fixing when it breaks, and continuously improving. I don't wait for someone to report an issue — I set up the alerts, own the incidents, and drive the post-mortems. For the role I'm looking for — I want an environment where I'm trusted to make decisions end-to-end, not just execute tickets. I'm at a stage where I want to contribute to architectural decisions, reduce toil for the team, and grow toward a senior or lead level."*

---

*Prepared for Sainudeen Safar | June 2026 | AWS SA Pro | CKA | RHCE*
