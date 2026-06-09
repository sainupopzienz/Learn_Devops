# AWS Transit Gateway, Cross-Account Access & GPU Workloads in Kubernetes
### Complete Interview Notes & Production Guide

---

## Table of Contents

1. [AWS Transit Gateway](#transit-gateway)
2. [Cross-Account Communication](#cross-account)
3. [GPU Workloads in Kubernetes](#gpu-kubernetes)

---

## AWS Transit Gateway

### What is AWS Transit Gateway?

AWS Transit Gateway (TGW) is a fully managed network hub that connects multiple VPCs, AWS accounts, and on-premises networks through a single central gateway.

```
Without Transit Gateway:
  VPC-A <──> VPC-B
  VPC-A <──> VPC-C
  VPC-B <──> VPC-C
  (N*(N-1)/2 peerings needed)
  For 10 VPCs = 45 peering connections

With Transit Gateway:
          TGW
        /  |  \
  VPC-A  VPC-B  VPC-C
  (N attachments only)
  For 10 VPCs = 10 attachments
```

### Why Use Transit Gateway?

Real scenario — company has:

```
Production VPC    (10.0.0.0/16)
Development VPC   (10.1.0.0/16)
Shared Services   (10.2.0.0/16)
  (monitoring, logging, AD)
Security VPC      (10.3.0.0/16)
  (firewalls, inspection)
On-premises DC    (192.168.0.0/16)
```

Without TGW this requires complex peering mesh.
With TGW everything connects through one hub.

### Transit Gateway vs VPC Peering

| Feature | VPC Peering | Transit Gateway |
|---------|------------|-----------------|
| Scalability | Poor — O(N²) | Excellent — O(N) |
| Central Routing | No | Yes |
| Multi-account | Limited | Easy |
| On-premises Integration | Complex | Easy via VPN/DX |
| Route Management | Per-VPC tables | Centralized TGW route table |
| Transitive Routing | No | Yes |
| Cost | Free | Per attachment + data transfer |
| Max Connections | 125 per VPC | 5000 attachments |
| Setup Complexity | Simple for 2-3 VPCs | Better for 4+ VPCs |

### Create Transit Gateway — Step by Step

#### Step 1 — Create the Transit Gateway

```bash
# Via CLI
aws ec2 create-transit-gateway \
  --description "Production Transit Gateway" \
  --options "AmazonSideAsn=64512,AutoAcceptSharedAttachments=enable,DefaultRouteTableAssociation=enable,DefaultRouteTablePropagation=enable,VpnEcmpSupport=enable,DnsSupport=enable"

# Note the TransitGatewayId from output
# e.g. tgw-0abc123def456
```

#### Step 2 — Attach VPCs

```bash
# Attach VPC-A
aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id tgw-0abc123def456 \
  --vpc-id vpc-aaa111 \
  --subnet-ids subnet-aaa111 subnet-aaa222

# Attach VPC-B
aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id tgw-0abc123def456 \
  --vpc-id vpc-bbb222 \
  --subnet-ids subnet-bbb111 subnet-bbb222

# Attach VPC-C
aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id tgw-0abc123def456 \
  --vpc-id vpc-ccc333 \
  --subnet-ids subnet-ccc111 subnet-ccc222
```

#### Step 3 — Update VPC Route Tables

```bash
# VPC-A route table — add routes to VPC-B and VPC-C via TGW
aws ec2 create-route \
  --route-table-id rtb-aaa111 \
  --destination-cidr-block 10.1.0.0/16 \
  --transit-gateway-id tgw-0abc123def456

aws ec2 create-route \
  --route-table-id rtb-aaa111 \
  --destination-cidr-block 10.2.0.0/16 \
  --transit-gateway-id tgw-0abc123def456
```

Via Terraform:

```hcl
resource "aws_ec2_transit_gateway" "main" {
  description                     = "Production Transit Gateway"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = {
    Name        = "production-tgw"
    Environment = "production"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc_a" {
  subnet_ids         = var.vpc_a_private_subnets
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = var.vpc_a_id

  tags = { Name = "vpc-a-attachment" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc_b" {
  subnet_ids         = var.vpc_b_private_subnets
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = var.vpc_b_id

  tags = { Name = "vpc-b-attachment" }
}

# Route in VPC-A pointing to TGW for VPC-B traffic
resource "aws_route" "vpc_a_to_vpc_b" {
  route_table_id         = var.vpc_a_route_table_id
  destination_cidr_block = var.vpc_b_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}
```

#### Result

```
VPC-A (10.0.0.0/16) ↔ VPC-B (10.1.0.0/16)
VPC-A (10.0.0.0/16) ↔ VPC-C (10.2.0.0/16)
VPC-B (10.1.0.0/16) ↔ VPC-C (10.2.0.0/16)

All through single Transit Gateway hub
```

### TGW Route Tables — Traffic Segmentation

```
Use case: Dev VPCs cannot reach Prod VPCs
but both can reach Shared Services

TGW Route Table 1 (Production):
  Associate: Prod VPC
  Propagate from: Prod VPC, Shared Services VPC

TGW Route Table 2 (Development):
  Associate: Dev VPC
  Propagate from: Dev VPC, Shared Services VPC

Result:
  Prod ↔ Shared Services ✅
  Dev ↔ Shared Services ✅
  Prod ↔ Dev ❌ (no route)
```

### Interview Answer — TGW

*"Transit Gateway provides centralized routing, better scalability, simpler route management, multi-account support, and easier hybrid connectivity compared to VPC peering. VPC peering requires N*(N-1)/2 connections for N VPCs — for 10 VPCs that is 45 peering connections. TGW needs only 10 attachments. TGW also supports transitive routing which VPC peering does not, and integrates easily with VPN and Direct Connect for hybrid connectivity."*

---

## Cross-Account Communication

### Scenario

```
Account-A (123456789012)
  EC2 instance running application

Account-B (987654321098)
  S3 bucket with data
  ec2 in Account-A needs to read this bucket
```

### Solution 1 — IAM Role + S3 Bucket Policy (Recommended)

#### Step 1 — Create IAM Role in Account-A

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::account-b-bucket",
        "arn:aws:s3:::account-b-bucket/*"
      ]
    }
  ]
}
```

Attach to EC2 instance profile.

#### Step 2 — Bucket Policy in Account-B

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAccountARole",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:role/EC2AppRole"
      },
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::account-b-bucket",
        "arn:aws:s3:::account-b-bucket/*"
      ]
    }
  ]
}
```

#### Step 3 — Test from EC2

```bash
# No credentials needed — uses instance role automatically
aws s3 ls s3://account-b-bucket
aws s3 cp s3://account-b-bucket/data.csv .
```

### Solution 2 — Cross-Account AssumeRole

Used when you need more granular control or when the source is not EC2.

```
Account-A EC2
    │
    │ sts:AssumeRole
    ▼
Account-B IAM Role
    │
    ▼
S3 Bucket in Account-B
```

#### Step 1 — Create Role in Account-B with Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "unique-external-id-abc123"
        }
      }
    }
  ]
}
```

#### Step 2 — Assume the Role from Account-A

```python
# Python application in Account-A
import boto3

sts_client = boto3.client('sts')

# Assume role in Account-B
response = sts_client.assume_role(
    RoleArn='arn:aws:iam::987654321098:role/CrossAccountS3Role',
    RoleSessionName='AppSession',
    ExternalId='unique-external-id-abc123',
    DurationSeconds=3600
)

# Use temporary credentials
credentials = response['Credentials']
s3_client = boto3.client(
    's3',
    aws_access_key_id=credentials['AccessKeyId'],
    aws_secret_access_key=credentials['SecretAccessKey'],
    aws_session_token=credentials['SessionToken']
)

# Now access Account-B's S3
response = s3_client.list_objects_v2(Bucket='account-b-bucket')
```

#### Terraform Cross-Account Role

```hcl
# In Account-B
resource "aws_iam_role" "cross_account" {
  name = "CrossAccountS3Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        AWS = "arn:aws:iam::123456789012:root"
      }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = var.external_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "cross_account_s3" {
  name = "CrossAccountS3Policy"
  role = aws_iam_role.cross_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.data.arn,
        "${aws_s3_bucket.data.arn}/*"
      ]
    }]
  })
}
```

### Terraform Cross-Account Deployment

```hcl
# Deploy into customer AWS account using AssumeRole
provider "aws" {
  alias  = "customer"
  region = "ap-south-1"

  assume_role {
    role_arn     = "arn:aws:iam::CUSTOMER-ACCOUNT-ID:role/TerraformDeployRole"
    session_name = "TerraformDeployment"
    external_id  = var.external_id
  }
}

# Use provider alias for customer resources
resource "aws_s3_bucket" "customer_bucket" {
  provider = aws.customer
  bucket   = "customer-app-data"
}
```

### Interview Answer — Cross-Account

*"For EC2 in Account-A to access S3 in Account-B, I use two pieces — an IAM role attached to the EC2 instance with permission to access S3, and an S3 bucket policy in Account-B that trusts that specific IAM role ARN from Account-A. The SDK automatically picks up the instance role credentials and when it makes an S3 API call, Account-B's bucket policy allows it. For more advanced scenarios like Terraform deployments into customer accounts, I use STS AssumeRole — Account-A assumes a role in Account-B with an ExternalId condition for security, gets temporary credentials, and uses those to deploy resources."*

---

## GPU Workloads in Kubernetes

### Scenario

```
Existing cluster:
  Container-A → CPU node
  Container-B → CPU node
  Container-C → CPU node

New requirement:
  Container-D → GPU node
  (without disrupting existing CPU workloads)
```

### Step 1 — Create GPU Node Group

```bash
# EKS — add GPU node group
aws eks create-nodegroup \
  --cluster-name production-eks \
  --nodegroup-name gpu-nodes \
  --node-role arn:aws:iam::123:role/EKSNodeRole \
  --ami-type AL2_x86_64_GPU \
  --instance-types g5.xlarge g4dn.xlarge \
  --scaling-config minSize=0,maxSize=5,desiredSize=1 \
  --labels '{"workload-type":"gpu"}'
```

Terraform:

```hcl
resource "aws_eks_node_group" "gpu" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "gpu-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  ami_type       = "AL2_x86_64_GPU"
  instance_types = ["g5.xlarge"]

  scaling_config {
    min_size     = 0
    max_size     = 5
    desired_size = 1
  }

  labels = {
    "workload-type" = "gpu"
  }

  taint {
    key    = "nvidia.com/gpu"
    value  = "present"
    effect = "NO_SCHEDULE"
  }
}
```

### Step 2 — Install NVIDIA Device Plugin

```bash
# Install device plugin
kubectl apply -f \
  https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/master/nvidia-device-plugin.yml

# Verify plugin is running on GPU nodes
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds

# Check GPU resource is exposed
kubectl describe node gpu-node-1 | grep -A 5 "Capacity"
# Capacity:
#   cpu: 4
#   memory: 16Gi
#   nvidia.com/gpu: 1   ← GPU exposed ✅
```

### Step 3 — Label GPU Nodes

```bash
# Label GPU nodes
kubectl label nodes gpu-node-1 accelerator=nvidia-gpu
kubectl label nodes gpu-node-2 accelerator=nvidia-gpu

# Taint GPU nodes
# Forces only GPU workloads to schedule on GPU nodes
# CPU pods that don't tolerate the taint won't go here
kubectl taint nodes gpu-node-1 nvidia.com/gpu=present:NoSchedule
kubectl taint nodes gpu-node-2 nvidia.com/gpu=present:NoSchedule
```

### Step 4 — Deploy GPU Workload

```yaml
# gpu-ai-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ai-model
  namespace: production
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ai-model
  template:
    metadata:
      labels:
        app: ai-model
    spec:
      # Schedule only on GPU nodes
      nodeSelector:
        accelerator: nvidia-gpu

      # Tolerate the GPU node taint
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule

      containers:
      - name: ai-model
        image: my-ai-image:1.0
        command: ["python3", "inference.py"]

        resources:
          requests:
            cpu: "2"
            memory: "8Gi"
            nvidia.com/gpu: "1"     # request 1 GPU
          limits:
            cpu: "4"
            memory: "16Gi"
            nvidia.com/gpu: "1"     # limit 1 GPU

        env:
        - name: MODEL_PATH
          value: /models

        volumeMounts:
        - name: model-weights
          mountPath: /models
          readOnly: true

      volumes:
      - name: model-weights
        persistentVolumeClaim:
          claimName: model-weights-pvc
```

```bash
# Deploy
kubectl apply -f gpu-ai-deployment.yaml

# Check pod scheduled on GPU node
kubectl get pods -o wide
# NAME             READY   STATUS    NODE
# ai-model-abc     1/1     Running   gpu-node-1 ← correct node

# Verify GPU inside pod
kubectl exec -it ai-model-abc -- nvidia-smi
```

### Step 5 — CPU Workloads Unchanged

```yaml
# CPU deployment — no GPU config needed
# These pods CANNOT schedule on tainted GPU nodes
# (they don't have the toleration)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
spec:
  template:
    spec:
      # No nodeSelector for GPU
      # No toleration for GPU taint
      # Kubernetes schedules on CPU nodes automatically
      containers:
      - name: api
        image: api-server:1.0
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          # No nvidia.com/gpu
```

### Multiple GPU Containers

```yaml
# Container 1 — GPU 0
resources:
  limits:
    nvidia.com/gpu: 1
# NVIDIA device plugin assigns GPU 0

---
# Container 2 — GPU 1
resources:
  limits:
    nvidia.com/gpu: 1
# NVIDIA device plugin assigns GPU 1

# Kubernetes prevents two pods from using
# the same GPU automatically
```

### GPU Autoscaling

```yaml
# HPA based on custom GPU metric
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ai-model-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ai-model
  minReplicas: 1
  maxReplicas: 4
  metrics:
  - type: External
    external:
      metric:
        name: nvidia_gpu_duty_cycle  # from DCGM Exporter
      target:
        type: AverageValue
        averageValue: "80"           # scale when GPU > 80%
```

### Production Best Practices

```yaml
# Complete production GPU deployment spec
spec:
  template:
    spec:
      nodeSelector:
        accelerator: nvidia-gpu

      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule

      # Init container verifies GPU available
      initContainers:
      - name: check-gpu
        image: nvidia/cuda:12.3.1-base-ubuntu22.04
        command: ["nvidia-smi"]
        resources:
          limits:
            nvidia.com/gpu: "1"

      containers:
      - name: ai-model
        image: my-ai-image:1.0

        resources:
          requests:
            cpu: "2"
            memory: "8Gi"
            nvidia.com/gpu: "1"
          limits:
            cpu: "4"
            memory: "16Gi"
            nvidia.com/gpu: "1"

        # Readiness probe
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10

        # Liveness probe
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
```

### Interview Answer — Kubernetes GPU

*"To deploy a GPU-based AI workload into an existing CPU cluster, I create a dedicated GPU node group using instances like g5.xlarge or g4dn.xlarge. I install the NVIDIA device plugin via kubectl apply which exposes nvidia.com/gpu as a schedulable resource. I taint GPU nodes so only GPU workloads schedule there and CPU workloads are not affected. In the deployment spec I request nvidia.com/gpu: 1 in resource limits, add nodeSelector for the GPU label, and add the corresponding toleration. Kubernetes then schedules the pod exclusively on GPU nodes. CPU containers have no GPU config and cannot tolerate the taint so they stay on CPU nodes. The NVIDIA device plugin ensures no two pods share the same GPU."*

---

*References: AWS Transit Gateway Documentation | AWS IAM Cross-Account Access | NVIDIA Kubernetes Device Plugin | EKS GPU AMI Documentation*
