# Infrastructure as Code: Terraform & CloudFormation Explained

## Stop Clicking. Start Coding Your Infrastructure.

---

Every cloud engineer reaches a moment where they've built something beautiful in AWS — the perfect VPC, the right subnets, a load balancer wired exactly right — and then realize they have no idea how to recreate it. No documentation. No repeatability. Just memory and screenshots.

That moment is when Infrastructure as Code (IaC) stops being a buzzword and starts being a necessity.

This article walks you through what IaC is, why it matters, and how the two most popular tools — **Terraform** and **AWS CloudFormation** — work in practice.

---

## What is Infrastructure as Code?

Infrastructure as Code means you define your cloud resources — servers, networks, databases, security groups — in **code files**, the same way a developer writes application logic. You commit that code to Git, review it, version it, and apply it.

```
WITHOUT IaC:
Developer → AWS Console → Click → Click → Click → Infrastructure exists
(No record. No repeatability. No rollback.)

WITH IaC:
Developer → Write code → git commit → terraform apply → Infrastructure exists
(Versioned. Repeatable. Reviewable. Reversible.)
```

### Why This Matters

- **Repeatability** — deploy the exact same infrastructure to dev, staging, and production with one command
- **Version control** — every infrastructure change is a Git commit with a message, author, and timestamp
- **Disaster recovery** — if a region goes down, re-create your entire infrastructure in minutes
- **Team collaboration** — infrastructure changes go through pull requests, just like application code
- **Cost control** — destroy environments when not in use, recreate them when needed

---

## The Two Major Players

| Feature | Terraform | AWS CloudFormation |
|---|---|---|
| Made by | HashiCorp (open source) | AWS (native) |
| Language | HCL (HashiCorp Configuration Language) | JSON or YAML |
| Multi-cloud | ✅ AWS, Azure, GCP, and 1000+ providers | ❌ AWS only |
| State management | Terraform state file (local or remote) | Managed by AWS |
| Community | Massive — largest IaC ecosystem | AWS-specific community |
| Free | ✅ Open source core | ✅ Free (pay for what you deploy) |
| Best for | Multi-cloud or AWS-heavy teams | Pure AWS shops |

---

## Terraform — How It Works

Terraform uses a simple loop:

```
Write (.tf files)  →  Plan (preview changes)  →  Apply (create resources)  →  Destroy (tear down)
```

### Your First Terraform File

Here's what creating an AWS EC2 instance looks like in Terraform:

```hcl
# main.tf

provider "aws" {
  region = "ap-south-1"   # Mumbai
}

resource "aws_instance" "web_server" {
  ami           = "ami-0c55b159cbfafe1f0"   # Amazon Linux 2
  instance_type = "t3.micro"

  tags = {
    Name        = "MyWebServer"
    Environment = "Production"
  }
}
```

Three commands to go from code to running server:

```bash
terraform init      # Download AWS provider plugin
terraform plan      # Preview: "will create 1 EC2 instance"
terraform apply     # Actually create it
```

That's it. No console. No clicking.

---

### Terraform State — The Most Important Concept

Terraform keeps a **state file** (`terraform.tfstate`) that tracks every resource it has created. This is how Terraform knows what exists and what needs to change.

```
Your .tf files  ──►  Terraform compares with  ──►  terraform.tfstate
(desired state)                                      (current state)
                              │
                              ▼
                    Shows you the DIFF (terraform plan)
                    Then applies only the changes needed
```

**For teams, always use remote state** — store it in S3 with DynamoDB locking:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-lock"   # Prevents two people applying at once
  }
}
```

---

### Terraform Modules — Reusable Infrastructure

Instead of copy-pasting the same VPC code for every project, wrap it in a **module**:

```hcl
# Using a VPC module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "production-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-south-1a", "ap-south-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway = true
}
```

One module call. Entire VPC with subnets, route tables, and NAT Gateway — created automatically.

---

### Deploying the Full 3-Tier Architecture with Terraform

```hcl
# VPC
module "vpc" { ... }

# ALB
resource "aws_lb" "main" {
  name               = "production-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.alb.id]
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app" {
  min_size         = 2
  max_size         = 10
  desired_capacity = 2
  vpc_zone_identifier = module.vpc.private_subnets
}

# RDS Multi-AZ
resource "aws_db_instance" "main" {
  engine               = "mysql"
  instance_class       = "db.t3.medium"
  multi_az             = true
  db_subnet_group_name = aws_db_subnet_group.main.name
}
```

The entire architecture from the previous article — deployed with code.

---

## AWS CloudFormation — How It Works

CloudFormation uses **templates** (JSON or YAML files) that describe your desired infrastructure. You upload the template to AWS, and CloudFormation creates a **Stack** — a collection of resources managed together.

```
Template (YAML/JSON)  →  Upload to CloudFormation  →  Stack Created
                                                        (resources provisioned)
```

### Your First CloudFormation Template

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Simple EC2 Instance

Resources:
  WebServer:
    Type: AWS::EC2::Instance
    Properties:
      ImageId: ami-0c55b159cbfafe1f0
      InstanceType: t3.micro
      Tags:
        - Key: Name
          Value: MyWebServer
        - Key: Environment
          Value: Production
```

Deploy it:

```bash
aws cloudformation create-stack \
  --stack-name my-web-server \
  --template-body file://template.yaml
```

---

### CloudFormation Key Concepts

**Stacks** — a collection of AWS resources created from one template. Delete the stack → deletes all resources inside it.

**Change Sets** — preview what will change before applying, similar to `terraform plan`:

```bash
aws cloudformation create-change-set \
  --stack-name my-web-server \
  --change-set-name my-update \
  --template-body file://updated-template.yaml

aws cloudformation describe-change-set \
  --stack-name my-web-server \
  --change-set-name my-update
# Shows exactly what will be added, modified, or deleted
```

**Outputs** — export values from one stack to use in another:

```yaml
Outputs:
  VpcId:
    Value: !Ref MyVPC
    Export:
      Name: ProductionVpcId   # Other stacks can import this
```

**Parameters** — make templates reusable across environments:

```yaml
Parameters:
  Environment:
    Type: String
    AllowedValues: [dev, staging, production]

Resources:
  WebServer:
    Type: AWS::EC2::Instance
    Properties:
      InstanceType: !If [IsProduction, t3.large, t3.micro]
```

---

## Terraform vs CloudFormation — When to Use Which

### Choose Terraform when:
- Your company uses **multiple cloud providers** (AWS + Azure or AWS + GCP)
- You want the **largest community** and most modules available
- You prefer a **cleaner, more readable syntax** (HCL vs YAML)
- You're working in a **DevOps/platform engineering** role

### Choose CloudFormation when:
- Your team is **100% AWS** and never plans to change
- You want **zero additional tooling** — it's built into AWS
- You need **deep AWS service integration** — some newer AWS services support CloudFormation before Terraform
- You're already using **AWS CDK** (Cloud Development Kit) — CDK compiles to CloudFormation under the hood

---

## IaC Best Practices

### 1. Always Use Remote State (Terraform)
Never store `terraform.tfstate` locally on your laptop. Use S3 + DynamoDB as shown above.

### 2. Never Hardcode Secrets
```hcl
# ❌ WRONG — never do this
resource "aws_db_instance" "main" {
  password = "mysecretpassword123"
}

# ✅ RIGHT — use AWS Secrets Manager or environment variables
resource "aws_db_instance" "main" {
  password = var.db_password   # Passed via environment variable or secrets vault
}
```

### 3. Use Workspaces / Separate State per Environment
```bash
terraform workspace new production
terraform workspace new staging
# Each workspace has its own state file — no risk of dev changes hitting prod
```

### 4. Always Run Plan Before Apply
```bash
terraform plan -out=tfplan    # Save the plan
terraform apply tfplan        # Apply exactly that plan — no surprises
```

### 5. Tag Everything
```hcl
locals {
  common_tags = {
    Project     = "MyApp"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "platform-team"
  }
}
```

Tags make cost allocation and resource identification infinitely easier at scale.

---

## The IaC Workflow in a Real Team

```
Developer writes .tf file
         │
         ▼
    git push → Pull Request opened
         │
         ▼
    CI pipeline runs:
    - terraform fmt (format check)
    - terraform validate (syntax check)
    - terraform plan (preview posted as PR comment)
         │
         ▼
    Team reviews the plan in the PR
         │
         ▼
    PR merged → CD pipeline runs:
    - terraform apply (resources created/updated)
         │
         ▼
    Infrastructure live in production
```

This is how senior DevOps teams operate — infrastructure changes are as disciplined as application code changes.

---

## Key Takeaways

- **IaC is not optional in production** — it's the difference between infrastructure you control and infrastructure that controls you
- **Terraform is the industry standard** for multi-cloud and most modern DevOps roles
- **CloudFormation is AWS-native and zero-setup** — a solid choice for pure AWS shops
- **Remote state is non-negotiable** in a team — local state files cause disasters
- **Never hardcode secrets** in IaC files — use Secrets Manager or environment variables
- **Plan before apply, always** — the preview is the safety net

---

## What to Learn Next

Once you're comfortable with Terraform basics, the natural progression is:

1. **Terraform modules** — build reusable infrastructure components
2. **Terragrunt** — DRY wrapper for Terraform at scale
3. **AWS CDK** — define CloudFormation with real programming languages (Python, TypeScript)
4. **Pulumi** — IaC with full programming languages (Go, Python, TypeScript)
5. **CI/CD for IaC** — automate `terraform apply` via GitHub Actions or AWS CodePipeline

---

*Found this useful? Follow for more AWS deep-dives — next up: AWS Security from IAM to GuardDuty, the complete guide.*
