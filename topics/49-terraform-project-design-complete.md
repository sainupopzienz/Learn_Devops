# Terraform Project Design: From Zero to Production with Security Best Practices

## How Senior Engineers Structure Terraform for Real Projects

---

Most engineers start Terraform by writing everything in one `main.tf` file. It works for a personal project. It falls apart the moment a second person joins, a second environment is needed, or a security audit happens.

This article covers how to design a Terraform project from scratch — folder structure, state management, modules, variable handling, secrets, CI/CD integration, security practices, and the patterns that separate production-grade IaC from a collection of resource blocks.

---

## Part 1 — Project Structure

### The Wrong Way (How Everyone Starts)

```
project/
├── main.tf         # everything dumped here
├── variables.tf
└── outputs.tf
```

This breaks the moment you need dev and prod environments, multiple teams, or any isolation between workloads.

### The Right Way — Environment-Separated Directory Structure

```
terraform/
├── modules/                        # Reusable building blocks
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── eks/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── rds/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── alb/
│   ├── ecs/
│   ├── elasticache/
│   └── security-groups/
│
├── environments/                   # One folder per environment
│   ├── dev/
│   │   ├── main.tf                 # Calls modules with dev values
│   │   ├── variables.tf
│   │   ├── terraform.tfvars        # Dev-specific values (NOT committed if sensitive)
│   │   ├── backend.tf              # Remote state config for dev
│   │   └── outputs.tf
│   ├── staging/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── terraform.tfvars
│   │   ├── backend.tf
│   │   └── outputs.tf
│   └── production/
│       ├── main.tf
│       ├── variables.tf
│       ├── terraform.tfvars
│       ├── backend.tf
│       └── outputs.tf
│
├── global/                         # Shared resources across all environments
│   ├── iam/                        # IAM roles, policies
│   ├── route53/                    # DNS zones
│   └── ecr/                        # Container registries
│
└── .github/
    └── workflows/
        └── terraform.yml           # CI/CD pipeline
```

### Why Separate Directories Over Workspaces

```
Workspaces:
  Same code, different state files
  Good for: identical environments (rare in reality)
  Problem: dev and prod almost always differ in size, config, and features
  Problem: one bad apply on wrong workspace → prod destroyed
  Problem: no natural blast radius — all environments share same backend config

Separate Directories:
  Each environment has its own code, state, and backend
  Dev can use t3.micro, prod uses r6g.2xlarge — different code
  A plan in dev never touches prod state
  Team can apply dev without any risk to prod
  Each directory is independently versioned

Use workspaces only when environments are truly identical (rare)
Use directories for everything else (almost always)
```

---

## Part 2 — Remote State and Locking

### Why Remote State Is Non-Negotiable in Teams

```
Local state (terraform.tfstate on your laptop):
  ✗ Lost if laptop breaks
  ✗ Two engineers apply simultaneously → state corruption
  ✗ No history, no versioning
  ✗ Secrets stored in plain text on local disk

Remote state (S3 + DynamoDB):
  ✓ Shared across the entire team
  ✓ Versioned — every apply creates a new state version
  ✓ Locked — only one apply at a time
  ✓ Encrypted at rest
  ✓ Audit trail of every change
```

### Setting Up the S3 Backend with DynamoDB Locking

**Step 1 — Bootstrap the state bucket (do this once, manually or with a bootstrap script):**

```hcl
# bootstrap/main.tf — run this ONCE before anything else
# This creates the infrastructure that stores all other infrastructure state

resource "aws_s3_bucket" "terraform_state" {
  bucket = "my-company-terraform-state"

  lifecycle {
    prevent_destroy = true    # Never accidentally delete this
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"        # Every state change = new version (rollback possible)
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_lock" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }
}

resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true    # Rotate key annually
}
```

**Step 2 — Configure each environment's backend:**

```hcl
# environments/production/backend.tf
terraform {
  backend "s3" {
    bucket         = "my-company-terraform-state"
    key            = "production/terraform.tfstate"   # Unique path per environment
    region         = "ap-south-1"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:ap-south-1:123456789:key/xxxx"
    dynamodb_table = "terraform-state-lock"
  }
}

# environments/staging/backend.tf
terraform {
  backend "s3" {
    bucket         = "my-company-terraform-state"
    key            = "staging/terraform.tfstate"      # Different key = isolated state
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

### State Locking in Practice

```
Engineer A runs: terraform apply (production)
  → DynamoDB acquires lock: LockID = "production/terraform.tfstate"
  → Apply runs

Engineer B runs: terraform apply (production) simultaneously
  → DynamoDB: lock already held
  → Error: "Error acquiring the state lock"
  → Engineer B waits or tries again after Engineer A finishes

This prevents concurrent applies from corrupting state.
Without DynamoDB: both engineers apply → state file overwritten → resources orphaned
```

---

## Part 3 — Modules

### What Makes a Good Module

A module is reusable infrastructure code. It takes inputs, creates resources, and produces outputs. The quality of a module determines how easily it can be reused across 10 projects without modification.

```hcl
# modules/rds/variables.tf — every input documented
variable "identifier" {
  description = "Unique identifier for this RDS instance"
  type        = string
}

variable "engine" {
  description = "Database engine (mysql, postgres, aurora-mysql)"
  type        = string
  default     = "postgres"
}

variable "instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.medium"
}

variable "allocated_storage" {
  description = "Initial storage in GB"
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Enable Multi-AZ for high availability"
  type        = bool
  default     = true   # Default ON — production safe
}

variable "backup_retention_period" {
  description = "Days to retain backups (0 disables backups)"
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Prevent accidental deletion"
  type        = bool
  default     = true   # Default ON — safety first
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
```

```hcl
# modules/rds/main.tf
resource "aws_db_instance" "this" {
  identifier              = var.identifier
  engine                  = var.engine
  instance_class          = var.instance_class
  allocated_storage       = var.allocated_storage
  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  deletion_protection     = var.deletion_protection
  storage_encrypted       = true               # Always encrypted
  skip_final_snapshot     = false              # Always take snapshot on delete
  copy_tags_to_snapshot   = true

  # Password from Secrets Manager — never hardcoded
  password = data.aws_secretsmanager_secret_version.db_password.secret_string
  username = var.db_username

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]

  tags = merge(var.tags, {
    ManagedBy = "Terraform"
  })
}
```

```hcl
# modules/rds/outputs.tf — expose what callers need
output "endpoint" {
  description = "RDS connection endpoint"
  value       = aws_db_instance.this.endpoint
}

output "port" {
  description = "RDS port"
  value       = aws_db_instance.this.port
}

output "arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.this.arn
}
```

### Calling a Module from an Environment

```hcl
# environments/production/main.tf

module "vpc" {
  source = "../../modules/vpc"

  cidr               = "10.0.0.0/16"
  availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
  private_subnets    = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = false    # One NAT per AZ — HA

  tags = local.common_tags
}

module "rds" {
  source = "../../modules/rds"

  identifier              = "prod-myapp-db"
  engine                  = "postgres"
  instance_class          = "db.r6g.large"
  allocated_storage       = 100
  multi_az                = true
  backup_retention_period = 14
  deletion_protection     = true
  db_username             = "myapp"
  security_group_id       = module.security_groups.rds_sg_id

  tags = local.common_tags
}
```

### Module Versioning

```hcl
# Pin module versions when using remote modules (Terraform Registry or Git)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"    # Always pin — never use latest or ~> without review

  # Without pinning: module updates automatically on next terraform init
  # A breaking change in the module → your infra changes unexpectedly
}

# For internal modules in the same repo: use relative paths
module "rds" {
  source = "../../modules/rds"    # No version needed — same repo, same commit
}
```

---

## Part 4 — Variable Management

### Variable Types and Where They Live

```
Three categories of variables:

1. Non-sensitive configuration → terraform.tfvars (committed to Git)
   Examples: region, instance types, CIDR blocks, replica counts

2. Sensitive values → environment variables or CI/CD secrets (never committed)
   Examples: database passwords, API keys, account IDs

3. Environment-specific → terraform.tfvars per environment (committed to Git)
   Examples: instance size is t3.micro in dev, r6g.2xlarge in prod
```

```hcl
# environments/production/variables.tf
variable "region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true    # Terraform redacts this from all output and logs
}
```

```hcl
# environments/production/terraform.tfvars — safe to commit
region         = "ap-south-1"
environment    = "production"
instance_type  = "t3.large"
min_capacity   = 3
max_capacity   = 10
```

```bash
# Sensitive values — passed via environment variables in CI/CD
# Never in terraform.tfvars, never in .tf files
export TF_VAR_db_password="$(aws secretsmanager get-secret-value \
  --secret-id prod/rds/master-password \
  --query SecretString --output text | jq -r .password)"

terraform apply
```

### Local Values — DRY Principle in Terraform

```hcl
# environments/production/main.tf
locals {
  # Common tags applied to every resource — define once, use everywhere
  common_tags = {
    Environment = var.environment
    Project     = "myapp"
    ManagedBy   = "Terraform"
    Owner       = "platform-team"
    CostCenter  = "engineering"
  }

  # Computed values derived from variables
  name_prefix = "${var.project}-${var.environment}"

  # Environment-specific logic
  is_production = var.environment == "production"
}

# Usage:
resource "aws_s3_bucket" "app_assets" {
  bucket = "${local.name_prefix}-assets"
  tags   = local.common_tags
}
```

---

## Part 5 — Security Practices

### Never Store Secrets in Terraform Files

```hcl
# ❌ WRONG — hardcoded password in .tf file
resource "aws_db_instance" "main" {
  password = "mysecretpassword123"   # Stored in state file, Git history, logs
}

# ❌ WRONG — password in terraform.tfvars (committed to Git)
db_password = "mysecretpassword123"

# ✅ RIGHT — read from Secrets Manager at apply time
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "prod/rds/master-password"
}

resource "aws_db_instance" "main" {
  password = jsondecode(
    data.aws_secretsmanager_secret_version.db_password.secret_string
  )["password"]
}

# ✅ RIGHT — pass via environment variable (CI/CD injects it)
variable "db_password" {
  type      = string
  sensitive = true    # Terraform never prints this value
}
# Set via: export TF_VAR_db_password="..." in CI/CD pipeline
```

### Encrypt Everything

```hcl
# S3 bucket — always encrypt
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.this.arn
    }
    bucket_key_enabled = true    # Reduces KMS API calls and costs
  }
}

# RDS — always encrypt
resource "aws_db_instance" "this" {
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn
}

# EBS volumes — always encrypt
resource "aws_ebs_volume" "this" {
  encrypted  = true
  kms_key_id = aws_kms_key.ebs.arn
}

# ElastiCache — always encrypt
resource "aws_elasticache_replication_group" "this" {
  at_rest_encryption_enabled  = true
  transit_encryption_enabled  = true
}
```

### IAM — Least Privilege

```hcl
# ❌ WRONG — wildcard resource
resource "aws_iam_policy" "bad" {
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*"]
      Resource = "*"    # Every S3 bucket in the entire account
    }]
  })
}

# ✅ RIGHT — scoped to specific resources
resource "aws_iam_policy" "app_s3" {
  name = "${local.name_prefix}-s3-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadWriteAppBucket"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.app_assets.arn}/*"    # Only this bucket
      },
      {
        Sid      = "ListAppBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.app_assets.arn
      }
    ]
  })
}
```

### Block Public Access on Every S3 Bucket

```hcl
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Account-level S3 public access block (belt and suspenders)
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

### Prevention with Lifecycle Rules

```hcl
# Prevent accidental deletion of critical resources
resource "aws_db_instance" "production" {
  # ...
  deletion_protection = true      # Cannot delete from AWS console or Terraform
  skip_final_snapshot = false     # Always take snapshot before delete
}

resource "aws_s3_bucket" "terraform_state" {
  # ...
  lifecycle {
    prevent_destroy = true        # Terraform refuses to destroy this resource
  }
}

# Prevent replacement of resources that should be updated in-place
resource "aws_db_instance" "main" {
  lifecycle {
    ignore_changes = [
      password,      # Password managed by Secrets Manager rotation — Terraform ignores drift
    ]
  }
}
```

### Security Group Rules — Explicit Deny by Default

```hcl
# ❌ WRONG — open to internet
resource "aws_security_group_rule" "bad" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]    # Never do this
}

# ✅ RIGHT — reference security groups, not IP ranges
resource "aws_security_group" "app" {
  name   = "${local.name_prefix}-app-sg"
  vpc_id = module.vpc.vpc_id

  # Allow only ALB to reach app
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Allow traffic from ALB only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }
}

resource "aws_security_group" "rds" {
  name   = "${local.name_prefix}-rds-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "Allow only app tier to reach RDS"
  }
}
```

### Enable CloudTrail and AWS Config

```hcl
resource "aws_cloudtrail" "main" {
  name                          = "${local.name_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true    # Capture all regions
  enable_log_file_validation    = true    # Detect tampered logs
  kms_key_id                    = aws_kms_key.cloudtrail.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]    # Log all S3 object-level events
    }
  }
}

resource "aws_config_configuration_recorder" "main" {
  name     = "${local.name_prefix}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

# Enforce no public S3 buckets via Config rule
resource "aws_config_config_rule" "s3_no_public" {
  name = "s3-bucket-public-read-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
}
```

### KMS Key Management

```hcl
resource "aws_kms_key" "main" {
  description             = "Master KMS key for ${var.environment} environment"
  deletion_window_in_days = 30             # 30-day safety window before deletion
  enable_key_rotation     = true           # Auto-rotate annually
  multi_region            = false          # Single region unless DR requires multi

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Terraform role to use the key"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.terraform.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name_prefix}-main"
  target_key_id = aws_kms_key.main.key_id
}
```

---

## Part 6 — State Security

### Who Can Access State?

```hcl
# IAM policy for Terraform execution role — access to state bucket
resource "aws_iam_policy" "terraform_state" {
  name = "TerraformStateAccess"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.terraform_state.arn}/production/*"
        # Scoped to production path — dev team cannot access prod state
      },
      {
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.terraform_lock.arn
      },
      {
        Sid    = "ListStateBucket"
        Effect = "Allow"
        Action = "s3:ListBucket"
        Resource = aws_s3_bucket.terraform_state.arn
      }
    ]
  })
}
```

### State File Contains Sensitive Data — Always Encrypt

```
Terraform state stores:
  - ALL resource attributes including passwords, secrets, keys
  - Even if you use sensitive = true in variables
  - Even if Secrets Manager provides the value

State encryption is not optional.
Always: encrypt = true in backend config + KMS key attached to S3 bucket.

Additionally:
  - Enable S3 versioning → recover from bad applies
  - Enable MFA delete → prevent accidental state deletion
  - Restrict S3 bucket access to Terraform execution role only
  - Never share state files via email or Slack
```

---

## Part 7 — CI/CD Integration

### The Terraform Workflow in a Pipeline

```
Developer pushes code to feature branch
        │
        ▼
Pull Request opened
        │
        ▼
CI Pipeline runs automatically:
  ├── terraform fmt -check     → format check (fail if not formatted)
  ├── terraform validate       → syntax check
  ├── tflint                   → linting (naming conventions, deprecated resources)
  ├── tfsec / checkov          → security scanning
  └── terraform plan           → post plan as PR comment
        │
Team reviews the plan in the PR
"Will create 3 resources, modify 1, destroy 0"
        │
PR merged to main
        │
        ▼
CD Pipeline runs:
  └── terraform apply          → applies changes to the environment
        │
        ▼
Post-apply validation:
  └── smoke tests / health checks
```

### GitHub Actions Pipeline

```yaml
# .github/workflows/terraform.yml
name: Terraform

on:
  pull_request:
    paths: ['terraform/**']
  push:
    branches: [main]
    paths: ['terraform/**']

permissions:
  id-token: write       # For OIDC authentication to AWS
  contents: read
  pull-requests: write  # For posting plan as PR comment

jobs:
  terraform:
    runs-on: ubuntu-latest
    environment: ${{ github.ref == 'refs/heads/main' && 'production' || 'staging' }}

    defaults:
      run:
        working-directory: terraform/environments/production

    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.7.0"    # Always pin Terraform version

      - name: Configure AWS Credentials (OIDC — no long-lived keys)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789:role/GitHubActionsRole
          aws-region: ap-south-1

      - name: Terraform Format Check
        run: terraform fmt -check -recursive
        continue-on-error: false

      - name: Terraform Init
        run: terraform init

      - name: Terraform Validate
        run: terraform validate

      - name: Run tfsec (security scan)
        uses: aquasecurity/tfsec-action@v1.0.3
        with:
          working_directory: terraform/

      - name: Terraform Plan
        id: plan
        run: terraform plan -out=tfplan -no-color
        env:
          TF_VAR_db_password: ${{ secrets.DB_PASSWORD }}

      - name: Post Plan to PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const output = `#### Terraform Plan
            \`\`\`
            ${{ steps.plan.outputs.stdout }}
            \`\`\`
            `;
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            })

      - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply tfplan   # Apply the exact plan that was reviewed
```

### GitHubActionsRole Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::123456789:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub":
          "repo:my-org/my-repo:ref:refs/heads/main"
      }
    }
  }]
}
```

```
Why OIDC for GitHub Actions:
  No long-lived AWS access keys stored in GitHub Secrets
  GitHub generates a short-lived token for each workflow run
  Token is exchanged for temporary AWS credentials (valid 1 hour)
  If GitHub is compromised: no permanent keys to steal
  Condition StringLike limits to specific repo and branch
```

---

## Part 8 — Code Quality and Safety Tools

### Tools Every Terraform Project Should Use

```
terraform fmt:
  Built-in formatter
  Run: terraform fmt -recursive
  Enforced in CI: terraform fmt -check (fails if unformatted)

terraform validate:
  Checks syntax and internal consistency
  Does not check against AWS — purely local

TFLint:
  Linter with provider-specific rules
  Catches: deprecated resource types, invalid instance types,
           missing required tags, naming convention violations
  Install: brew install tflint

tfsec:
  Security scanner for Terraform code
  Finds: unencrypted resources, open security groups, missing MFA,
         public S3 buckets, missing CloudTrail
  Install: brew install tfsec
  Run:     tfsec .

Checkov:
  Policy-as-code scanner
  Broader than tfsec — 1000+ checks across providers
  Run: checkov -d .

Infracost:
  Shows cost estimate for terraform plan output
  PR comment: "This change will increase your bill by $47/month"
  Prevents surprise AWS bills from infrastructure changes

Terragrunt:
  DRY wrapper for Terraform
  Eliminates repeated backend config across environments
  Adds dependency management between modules
  Use when: 10+ environments, repeated boilerplate is painful
```

### .terraform-version File

```
# Always pin Terraform version in the project root
# .terraform-version (used by tfenv)
1.7.0

# Or in required_version block in every environment:
terraform {
  required_version = "~> 1.7.0"    # Allow 1.7.x but not 1.8.x

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"    # Pin provider version too
    }
  }
}
```

---

## Part 9 — Drift Detection

### What Is Drift?

```
Drift = difference between what Terraform expects and what actually exists in AWS

Causes:
  Someone made a manual change in the AWS console
  An AWS service automatically modified a resource
  Another tool modified something Terraform manages

Result:
  terraform plan shows unexpected changes
  Applying "fixes" the drift (manual change overwritten)
  Drift can hide security issues (someone opened port 22 manually)
```

### Detecting Drift

```bash
# See what changed in AWS vs Terraform state (without proposing fixes)
terraform plan -refresh-only

# Output:
# ~ aws_security_group.app (drift detected)
#   + ingress: 0.0.0.0/0:22   ← someone opened SSH manually
#
# This is evidence of unauthorized change

# Schedule drift detection weekly in CI/CD:
# Run terraform plan -refresh-only → if diff exists → alert the team
```

---

## Part 10 — Tagging Strategy

### Tags as the Foundation of Cost and Security Visibility

```hcl
# Define tagging standard as a local in every environment
locals {
  required_tags = {
    Environment   = var.environment          # production / staging / dev
    Project       = var.project_name         # myapp
    Team          = var.team                 # platform / backend / data
    ManagedBy     = "Terraform"              # Identifies IaC-managed resources
    Owner         = var.owner_email          # team-lead@company.com
    CostCenter    = var.cost_center          # engineering / marketing
    DataClass     = var.data_classification  # public / internal / confidential
    TerraformRepo = "github.com/org/infra"  # Traceability to code
  }
}

# Enforce via AWS Config rule — alert on untagged resources
resource "aws_config_config_rule" "required_tags" {
  name = "required-tags"

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  input_parameters = jsonencode({
    tag1Key = "Environment"
    tag2Key = "Project"
    tag3Key = "ManagedBy"
    tag4Key = "Owner"
  })
}
```

---

## Part 11 — The Complete Project Checklist

### Before Writing Any Resource

```
Structure:
  ✓ Separate directories for each environment (not workspaces)
  ✓ Modules for every reusable component
  ✓ Global folder for shared resources (IAM, Route53, ECR)
  ✓ .terraform-version file with pinned version
  ✓ required_version and required_providers pinned in every environment
```

### Remote State

```
  ✓ S3 bucket with versioning enabled
  ✓ S3 bucket encrypted with KMS
  ✓ S3 bucket public access blocked
  ✓ DynamoDB table for state locking
  ✓ Separate state key per environment
  ✓ IAM policy restricting state access per environment
  ✓ prevent_destroy on state bucket
```

### Security

```
  ✓ No secrets in .tf files or terraform.tfvars
  ✓ Sensitive variables marked sensitive = true
  ✓ Secrets read from Secrets Manager at apply time
  ✓ All storage resources encrypted at rest
  ✓ KMS keys with rotation enabled
  ✓ S3 buckets have public access block
  ✓ Security groups reference SG IDs not CIDR ranges
  ✓ Port 22 and 3389 not open to 0.0.0.0/0
  ✓ deletion_protection = true on databases
  ✓ skip_final_snapshot = false on databases
  ✓ CloudTrail enabled multi-region
  ✓ AWS Config enabled with required-tags rule
  ✓ GuardDuty enabled
```

### Code Quality

```
  ✓ terraform fmt -check in CI
  ✓ terraform validate in CI
  ✓ tfsec security scan in CI
  ✓ tflint in CI
  ✓ All variables have description and type
  ✓ All outputs have description
  ✓ All resources have tags via common_tags local
  ✓ Modules have README.md with usage example
```

### CI/CD

```
  ✓ Plan on every PR — posted as comment
  ✓ Apply only on merge to main
  ✓ OIDC authentication — no long-lived access keys
  ✓ Separate pipeline jobs per environment
  ✓ Production requires manual approval gate
  ✓ terraform apply tfplan — applies exact reviewed plan
  ✓ Infracost on PRs showing cost impact
```

---

## The Interview Answer — One Paragraph

> *"When designing a Terraform project I start with environment-separated directories — dev, staging, production each with their own state file in S3 with DynamoDB locking and KMS encryption. Everything reusable lives in modules: VPC, RDS, ECS, security groups. No secrets ever touch a .tf file or tfvars — they come from Secrets Manager at apply time or CI/CD environment variables, always marked sensitive. Every resource gets a common_tags local covering environment, team, managed-by, and owner. Security group rules reference other security group IDs rather than CIDR blocks. Deletion protection and skip_final_snapshot are defaults. CI/CD runs fmt check, validate, tfsec, and tflint on every PR, posts the plan as a PR comment, and applies only on merge to main using OIDC instead of long-lived access keys. Drift detection runs weekly. This is the setup I've used across 10+ projects — it reduces provisioning from hours to 15 minutes per new project and gives any team member enough visibility to review infrastructure changes the same way they review application code."*

---

*Infrastructure as code is only as good as the discipline around it. The tools are simple. The practice — version everything, encrypt everything, least privilege everywhere, automate the review — is what separates a Terraform file from a Terraform system.*
