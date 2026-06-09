# Terraform Security — Complete Guide
### tfsec, Checkov, Sentinel & Secure IaC Practices

---

## Table of Contents

1. [Introduction](#introduction)
2. [Common Terraform Security Mistakes](#common-terraform-security-mistakes)
3. [tfsec — Static Analysis](#tfsec)
4. [Checkov — Policy as Code](#checkov)
5. [Sentinel — Policy as Code (Terraform Cloud)](#sentinel)
6. [Secure Terraform Patterns](#secure-terraform-patterns)
7. [State File Security](#state-file-security)
8. [Secrets Management in Terraform](#secrets-management)
9. [CI/CD Security Integration](#cicd-security-integration)
10. [Best Practices](#best-practices)

---

## Introduction

Terraform defines your entire infrastructure as code. A misconfigured Terraform file can create publicly exposed S3 buckets, unencrypted databases, or overpermissioned IAM roles — at scale, automatically, across all environments.

Security scanning of Terraform code must happen BEFORE infrastructure is created — not after.

```
Security shift-left for IaC:

Developer writes .tf file
        │
        ▼
tfsec / Checkov scan locally
        │
        ▼
PR opened → CI pipeline runs scans
        │
        ▼
PR blocked if HIGH severity found
        │
        ▼
Terraform plan reviewed
        │
        ▼
Sentinel policy check (Terraform Cloud)
        │
        ▼
terraform apply
        │
        ▼
Infrastructure created securely ✅
```

---

## Common Terraform Security Mistakes

```
Mistake 1 — Public S3 bucket
resource "aws_s3_bucket" "data" {
  bucket = "company-data"
  acl    = "public-read"  ← exposed to internet ❌
}

Mistake 2 — Unencrypted RDS
resource "aws_db_instance" "main" {
  storage_encrypted = false  ← unencrypted ❌
}

Mistake 3 — Open security group
resource "aws_security_group_rule" "ssh" {
  cidr_blocks = ["0.0.0.0/0"]  ← SSH open to world ❌
  from_port   = 22
  to_port     = 22
}

Mistake 4 — Hardcoded secret
resource "aws_db_instance" "main" {
  password = "mysecret123"  ← in version control ❌
}

Mistake 5 — Overpermissioned IAM
resource "aws_iam_policy" "app" {
  policy = jsonencode({
    Statement = [{
      Action   = ["*"]          ← everything allowed ❌
      Resource = ["*"]
      Effect   = "Allow"
    }]
  })
}

Mistake 6 — No MFA Delete on state bucket
resource "aws_s3_bucket_versioning" "state" {
  versioning_configuration {
    status = "Enabled"
    # mfa_delete missing ❌
  }
}
```

---

## tfsec — Static Analysis

tfsec is a static analysis tool for Terraform code. It scans your `.tf` files without running them and identifies security misconfigurations.

### Installation

```bash
# macOS
brew install tfsec

# Linux
curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash

# Go install
go install github.com/aquasecurity/tfsec/cmd/tfsec@latest

# Docker
docker pull aquasec/tfsec:latest

# Verify
tfsec --version
```

### Basic Usage

```bash
# Scan current directory
tfsec .

# Scan specific directory
tfsec ./infrastructure/prod

# Scan with specific severity
tfsec . --minimum-severity HIGH

# Output as JSON
tfsec . --format json --out tfsec-report.json

# Output as JUnit XML (for CI)
tfsec . --format junit --out tfsec-junit.xml

# Show all checks available
tfsec --list-all-checks
```

### Sample tfsec Output

```
Result #1 HIGH

  [aws-s3-enable-bucket-encryption]
  Bucket does not have encryption enabled

  /infrastructure/s3.tf:5-12
  ─────────────────────────────────
    5  resource "aws_s3_bucket" "data" {
    6    bucket = "company-data"
    7  }
  ─────────────────────────────────

  See https://aquasecurity.github.io/tfsec/latest/checks/aws/s3/enable-bucket-encryption/

Result #2 HIGH

  [aws-rds-encrypt-instance-storage-data]
  Instance does not have storage encryption enabled

  /infrastructure/rds.tf:3-15
  ─────────────────────────────────
    3  resource "aws_db_instance" "main" {
    4    engine         = "postgres"
   10    storage_encrypted = false
  ─────────────────────────────────

  Passed: 12  Failed: 2  Ignored: 0
```

### tfsec Configuration File

```yaml
# .tfsec/config.yml
minimum_severity: MEDIUM

exclude:
  - aws-s3-enable-bucket-logging  # excluded — we use CloudTrail

custom_checks:
  - name: Require environment tag
    short_code: require-environment-tag
    description: All resources must have an Environment tag
    severity: MEDIUM
    match_spec:
      action: not_contains
      attribute: tags
      value: Environment
    resource_types:
      - aws_instance
      - aws_s3_bucket
      - aws_db_instance
    error_message: "Resource must have an 'Environment' tag"
    link: https://wiki.company.com/tagging-policy
```

### tfsec in Pre-commit Hook

```yaml
# .pre-commit-config.yaml
repos:
- repo: https://github.com/aquasecurity/tfsec
  rev: v1.28.1
  hooks:
  - id: tfsec
    args:
    - --minimum-severity=HIGH
    - --format=lovely
```

---

## Checkov — Policy as Code

Checkov is a broader IaC security scanner that supports Terraform, CloudFormation, Kubernetes, Dockerfiles, and more. It has 1000+ built-in policies.

### Installation

```bash
# pip
pip install checkov

# Homebrew
brew install checkov

# Docker
docker pull bridgecrew/checkov

# Verify
checkov --version
```

### Basic Usage

```bash
# Scan Terraform directory
checkov -d ./infrastructure

# Scan specific file
checkov -f main.tf

# Run specific checks only
checkov -d . --check CKV_AWS_20,CKV_AWS_21

# Skip specific checks
checkov -d . --skip-check CKV_AWS_18

# Output JSON report
checkov -d . -o json > checkov-report.json

# Output JUnit for CI
checkov -d . -o junitxml > checkov-junit.xml

# Compact output
checkov -d . --compact
```

### Sample Checkov Output

```
Check: CKV_AWS_18: "Ensure the S3 bucket has access logging enabled"
  FAILED for resource: aws_s3_bucket.data
  File: /infrastructure/s3.tf:1-8

Check: CKV_AWS_21: "Ensure all data stored in the S3 bucket have versioning enabled"
  FAILED for resource: aws_s3_bucket.data
  File: /infrastructure/s3.tf:1-8

Check: CKV_AWS_16: "Ensure that RDS DB is not marked as publicly accessible"
  PASSED for resource: aws_db_instance.main

Passed checks: 45, Failed checks: 2, Skipped checks: 0
```

### Custom Checkov Policy

```python
# custom_policies/check_tags.py
from checkov.common.models.enums import CheckResult, CheckCategories
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck

class CheckRequiredTags(BaseResourceCheck):
    def __init__(self):
        name = "Ensure required tags are set on all resources"
        id = "CKV_CUSTOM_1"
        supported_resources = [
            "aws_instance",
            "aws_s3_bucket",
            "aws_db_instance"
        ]
        categories = [CheckCategories.GENERAL_SECURITY]
        super().__init__(name=name, id=id,
                         categories=categories,
                         supported_resources=supported_resources)

    def scan_resource_conf(self, conf):
        required_tags = ["Environment", "Project", "Owner"]
        tags = conf.get("tags", [{}])
        if isinstance(tags, list):
            tags = tags[0] if tags else {}

        for tag in required_tags:
            if tag not in tags:
                return CheckResult.FAILED
        return CheckResult.PASSED

scanner = CheckRequiredTags()
```

```bash
# Run with custom policy
checkov -d . --external-checks-dir ./custom_policies
```

### Checkov Configuration File

```yaml
# .checkov.yml
directory:
  - ./infrastructure

skip-check:
  - CKV_AWS_18  # S3 access logging — using CloudTrail instead

check:
  - CKV_AWS_20  # S3 bucket ACL
  - CKV_AWS_21  # S3 versioning

hard-fail-on:
  - CKV_AWS_8   # IMDSv2 required
  - CKV2_AWS_6  # S3 public access block

output: json
output-file-path: ./reports
```

---

## Sentinel — Policy as Code (Terraform Cloud)

Sentinel is HashiCorp's policy-as-code framework built into Terraform Cloud and Terraform Enterprise. Policies run AFTER `terraform plan` but BEFORE `terraform apply`.

### Sentinel Policy Enforcement Levels

```
Advisory:   Policy violation → warning only
            Apply can proceed
            Good for awareness

Soft Mandatory: Policy violation → blocks apply
                Override possible by admin
                Good for most policies

Hard Mandatory: Policy violation → blocks apply
                NO override possible
                Good for compliance
                (HIPAA, PCI DSS, SOC2)
```

### Example Sentinel Policies

```hcl
# policy/require-encryption.sentinel
# Ensure all RDS instances have encryption enabled

import "tfplan/v2" as tfplan

# Get all RDS instances from the plan
rds_instances = filter tfplan.resource_changes as _, resource {
  resource.type is "aws_db_instance" and
  resource.change.actions is not ["delete"]
}

# Check each instance has encryption
encryption_enabled = rule {
  all rds_instances as _, instance {
    instance.change.after.storage_encrypted is true
  }
}

# Main rule
main = rule {
  encryption_enabled
}
```

```hcl
# policy/no-public-s3.sentinel
# Prevent S3 buckets from being publicly accessible

import "tfplan/v2" as tfplan

s3_buckets = filter tfplan.resource_changes as _, resource {
  resource.type is "aws_s3_bucket_public_access_block"
}

no_public_access = rule {
  all s3_buckets as _, bucket {
    bucket.change.after.block_public_acls is true and
    bucket.change.after.block_public_policy is true and
    bucket.change.after.ignore_public_acls is true and
    bucket.change.after.restrict_public_buckets is true
  }
}

main = rule {
  no_public_access
}
```

```hcl
# policy/require-tags.sentinel
# All resources must have required tags

import "tfplan/v2" as tfplan

required_tags = ["Environment", "Project", "Owner", "ManagedBy"]

resources_with_tags = filter tfplan.resource_changes as _, resource {
  resource.change.after.tags is defined
}

all_have_required_tags = rule {
  all resources_with_tags as _, resource {
    all required_tags as tag {
      tag in keys(resource.change.after.tags)
    }
  }
}

main = rule {
  all_have_required_tags
}
```

---

## Secure Terraform Patterns

### Secure S3 Bucket

```hcl
resource "aws_s3_bucket" "secure" {
  bucket = "company-secure-data"
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "secure" {
  bucket = aws_s3_bucket.secure.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning
resource "aws_s3_bucket_versioning" "secure" {
  bucket = aws_s3_bucket.secure.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption with KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "secure" {
  bucket = aws_s3_bucket.secure.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

# Enable access logging
resource "aws_s3_bucket_logging" "secure" {
  bucket        = aws_s3_bucket.secure.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access-logs/"
}
```

### Secure RDS

```hcl
resource "aws_db_instance" "secure" {
  identifier        = "prod-database"
  engine            = "postgres"
  engine_version    = "14.9"
  instance_class    = "db.t3.medium"
  db_name           = "appdb"

  # Security settings
  storage_encrypted         = true            # ✅ encrypted
  kms_key_id               = aws_kms_key.rds.arn
  publicly_accessible       = false           # ✅ not public
  deletion_protection       = true            # ✅ prevent accidental deletion
  skip_final_snapshot       = false           # ✅ keep final snapshot
  final_snapshot_identifier = "prod-db-final-snapshot"
  backup_retention_period   = 7              # ✅ 7 days backup
  multi_az                  = true           # ✅ high availability
  auto_minor_version_upgrade = true          # ✅ security patches

  # No hardcoded password
  username = var.db_username
  password = data.aws_secretsmanager_secret_version.db_password.secret_string

  # Network isolation
  db_subnet_group_name   = aws_db_subnet_group.private.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Logging
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = local.common_tags
}
```

### Secure IAM Role

```hcl
# Least privilege IAM role for ECS task
resource "aws_iam_role" "app" {
  name = "${var.environment}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      # Require MFA and specific VPC condition
      Condition = {
        StringEquals = {
          "aws:RequestedRegion" = "ap-south-1"
        }
      }
    }]
  })

  tags = local.common_tags
}

# Specific policy — not wildcard
resource "aws_iam_policy" "app" {
  name = "${var.environment}-app-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Only specific S3 bucket
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.app.arn}/*"
        ]
      },
      {
        # Only specific secret
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.app.arn
        ]
      }
    ]
  })
}
```

---

## State File Security

```hcl
# Secure remote backend
terraform {
  backend "s3" {
    bucket         = "company-terraform-state"
    key            = "${var.environment}/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:ap-south-1:123:key/abc"
    dynamodb_table = "terraform-state-lock"
  }
}

# State bucket with all protections
resource "aws_s3_bucket" "state" {
  bucket = "company-terraform-state"
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

---

## Secrets Management

```hcl
# WRONG — never do this
variable "db_password" {
  default = "hardcoded_password"  ❌
}

# RIGHT — fetch from Secrets Manager at plan time
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "prod/database/password"
}

resource "aws_db_instance" "main" {
  password = data.aws_secretsmanager_secret_version.db_password.secret_string
}

# RIGHT — sensitive variable (not shown in logs)
variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true  # ← masked in plan output
}
```

---

## CI/CD Security Integration

### GitHub Actions — Full Security Pipeline

```yaml
name: Terraform Security Scan

on:
  pull_request:
    paths:
      - '**.tf'
      - '**.tfvars'

jobs:
  terraform-security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.5.7

      - name: Terraform Format Check
        run: terraform fmt -check -recursive

      - name: Terraform Init
        run: terraform init -backend=false

      - name: Terraform Validate
        run: terraform validate

      - name: Run tfsec
        uses: aquasecurity/tfsec-action@v1.0.0
        with:
          minimum_severity: HIGH
          format: sarif
          out: tfsec.sarif

      - name: Run Checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: .
          framework: terraform
          output_format: sarif
          output_file_path: checkov.sarif
          soft_fail: false

      - name: Upload SARIF results
        uses: github/codeql-action/upload-sarif@v2
        if: always()
        with:
          sarif_file: tfsec.sarif
```

---

## Best Practices

```
Code Security:
  ✅ Never hardcode secrets in .tf files
  ✅ Use sensitive = true for secret variables
  ✅ Fetch secrets from Secrets Manager at runtime
  ✅ Use data sources for existing resources
  ✅ Pin provider versions exactly
  ✅ Use required_version constraint

Scanning:
  ✅ Run tfsec locally before committing
  ✅ Run Checkov in CI on every PR
  ✅ Block merges on HIGH severity findings
  ✅ Use Sentinel for enterprise policy enforcement
  ✅ Review and update policies quarterly

State Security:
  ✅ Remote state in S3 with encryption
  ✅ DynamoDB state locking
  ✅ S3 versioning on state bucket
  ✅ Restrict state bucket access via IAM
  ✅ Never commit state files to Git
  ✅ Add *.tfstate to .gitignore

Resource Security:
  ✅ Encrypt all storage at rest
  ✅ Block public access on all S3 buckets
  ✅ No 0.0.0.0/0 in security groups
  ✅ Use least privilege IAM policies
  ✅ Enable deletion protection on databases
  ✅ Tag all resources with Environment and Owner
```

---

*References: tfsec Documentation | Checkov Documentation | HashiCorp Sentinel | CIS AWS Terraform Benchmark*
