# AWS Security Hardening — Complete Guide
### IAM, Network, Data, Monitoring & Compliance

---

## Table of Contents

1. [AWS Shared Responsibility Model](#shared-responsibility)
2. [IAM Hardening](#iam-hardening)
3. [Network Security](#network-security)
4. [Data Protection](#data-protection)
5. [Logging and Monitoring](#logging-and-monitoring)
6. [Threat Detection](#threat-detection)
7. [Compliance Services](#compliance-services)
8. [Service-Specific Hardening](#service-specific-hardening)
9. [Security Automation](#security-automation)
10. [CIS AWS Benchmark Checklist](#cis-checklist)

---

## Shared Responsibility Model

```
AWS Responsible For:              You Responsible For:
──────────────────────────────    ──────────────────────────────
Physical datacenters              IAM users, roles, policies
Hardware                          Data encryption
Hypervisor                        Security group rules
Global infrastructure             OS patching on EC2
Managed service security          Application security
  (RDS patches, Lambda runtime)   Data classification
Network infrastructure            Network configuration
                                  Compliance configuration
```

---

## IAM Hardening

### Root Account Protection

```bash
# 1 — Enable MFA on root immediately
# Console → account menu → Security Credentials → MFA

# 2 — Delete root access keys
aws iam delete-access-key \
  --user-name root \
  --access-key-id AKIAIOSFODNN7EXAMPLE

# 3 — Verify root has no access keys
aws iam list-access-keys --user-name root

# 4 — Set strong password policy
aws iam update-account-password-policy \
  --minimum-password-length 14 \
  --require-symbols \
  --require-numbers \
  --require-uppercase-characters \
  --require-lowercase-characters \
  --allow-users-to-change-password \
  --max-password-age 90 \
  --password-reuse-prevention 24 \
  --hard-expiry
```

### IAM Password Policy via Terraform

```hcl
resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_numbers                = true
  require_uppercase_characters   = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
  hard_expiry                    = true
}
```

### Enforce MFA for All Console Users

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyWithoutMFA",
      "Effect": "Deny",
      "NotAction": [
        "iam:CreateVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:ListMFADevices",
        "iam:ListVirtualMFADevices",
        "iam:ResyncMFADevice",
        "sts:GetSessionToken"
      ],
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {
          "aws:MultiFactorAuthPresent": "false"
        }
      }
    }
  ]
}
```

### Use IAM Identity Center (SSO)

```
Instead of creating individual IAM users:

Active Directory / Google Workspace / Okta
              │
              ▼
       IAM Identity Center
              │
    ┌─────────┼─────────┐
    ▼         ▼         ▼
  Dev Acc  Staging    Prod Acc
  (ReadOnly) (Developer) (ReadOnly)

Benefits:
  Single login for all accounts
  No long-term access keys
  Temporary credentials only
  Centralized access management
  Easy offboarding
```

### Service Control Policies (SCPs)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyNonApprovedRegions",
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:RequestedRegion": [
            "ap-south-1",
            "us-east-1"
          ]
        }
      }
    },
    {
      "Sid": "PreventDisablingSecurityServices",
      "Effect": "Deny",
      "Action": [
        "guardduty:DeleteDetector",
        "guardduty:DisassociateFromMasterAccount",
        "cloudtrail:DeleteTrail",
        "cloudtrail:StopLogging",
        "config:DeleteConfigRule",
        "securityhub:DisableSecurityHub"
      ],
      "Resource": "*"
    },
    {
      "Sid": "RequireIMDSv2",
      "Effect": "Deny",
      "Action": "ec2:RunInstances",
      "Resource": "arn:aws:ec2:*:*:instance/*",
      "Condition": {
        "StringNotEquals": {
          "ec2:MetadataHttpTokens": "required"
        }
      }
    }
  ]
}
```

### Access Analyzer — Find Overpermissioned Resources

```bash
# Create Access Analyzer
aws accessanalyzer create-analyzer \
  --analyzer-name production-analyzer \
  --type ACCOUNT

# List findings
aws accessanalyzer list-findings \
  --analyzer-arn arn:aws:access-analyzer:ap-south-1:123:analyzer/production-analyzer

# Get specific finding details
aws accessanalyzer get-finding \
  --analyzer-arn arn:aws:access-analyzer:ap-south-1:123:analyzer/production-analyzer \
  --id finding-id-here
```

---

## Network Security

### VPC Security Architecture

```
Internet
    │
    ▼
CloudFront + WAF          ← DDoS protection, WAF rules
    │
    ▼
Internet Gateway
    │
    ▼
Public Subnet              ← ALB only
  [ALB]
    │
    ▼
Private Subnet (App)       ← EC2/ECS/EKS
  [Application servers]
    │
    ▼
Private Subnet (Data)      ← RDS, ElastiCache
  [Databases]
    │
    ▼
VPC Endpoints              ← S3, DynamoDB, Secrets Manager
(no internet needed)
```

### Security Group Best Practices

```hcl
# ALB security group — public facing
resource "aws_security_group" "alb" {
  name   = "alb-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # HTTPS from anywhere
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # HTTP — redirect to HTTPS
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# App security group — only from ALB
resource "aws_security_group" "app" {
  name   = "app-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]  # ALB only
    # NOT 0.0.0.0/0
  }

  # NO SSH from anywhere — use SSM Session Manager
}

# RDS security group — only from app
resource "aws_security_group" "rds" {
  name   = "rds-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]  # app only
  }
}
```

### AWS WAF Configuration

```hcl
resource "aws_wafv2_web_acl" "main" {
  name  = "production-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # AWS Managed Rules — Core Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action { none {} }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSCommonRules"
      sampled_requests_enabled   = true
    }
  }

  # Rate limiting
  rule {
    name     = "RateLimitRule"
    priority = 2

    action { block {} }

    statement {
      rate_based_statement {
        limit              = 2000  # 2000 requests per 5 minutes
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # SQL injection protection
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3

    override_action { none {} }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLiRules"
      sampled_requests_enabled   = true
    }
  }
}
```

### VPC Flow Logs

```hcl
resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"  # ACCEPT, REJECT, or ALL
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc/flowlogs"
  retention_in_days = 90
}
```

---

## Data Protection

### KMS Key Management

```hcl
# Customer managed KMS key
resource "aws_kms_key" "main" {
  description             = "Main encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true  # rotate annually

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow app service role"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.app.arn
        }
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/production-main"
  target_key_id = aws_kms_key.main.key_id
}
```

### S3 Security Hardening

```hcl
# Block public access at account level
resource "aws_s3_account_public_access_block" "main" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable S3 server access logging
resource "aws_s3_bucket_logging" "app" {
  bucket        = aws_s3_bucket.app.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "s3-access-logs/"
}

# Force SSL on S3 bucket
resource "aws_s3_bucket_policy" "force_ssl" {
  bucket = aws_s3_bucket.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [
          aws_s3_bucket.app.arn,
          "${aws_s3_bucket.app.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
```

### Secrets Manager — Auto Rotation

```hcl
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "prod/database/password"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 30

  rotation_rules {
    automatically_after_days = 30
  }
}

# Enable rotation with Lambda
resource "aws_secretsmanager_secret_rotation" "db_password" {
  secret_id           = aws_secretsmanager_secret.db_password.id
  rotation_lambda_arn = aws_lambda_function.secret_rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}
```

---

## Logging and Monitoring

### CloudTrail — All Region Trail

```hcl
resource "aws_cloudtrail" "main" {
  name                          = "production-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true  # all regions
  enable_log_file_validation    = true  # detect tampering

  kms_key_id = aws_kms_key.main.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    # Log S3 data events
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }

    # Log Lambda data events
    data_resource {
      type   = "AWS::Lambda::Function"
      values = ["arn:aws:lambda"]
    }
  }

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail.arn
}
```

### CloudWatch Alarms for Security Events

```hcl
# Alarm on root account usage
resource "aws_cloudwatch_metric_alarm" "root_usage" {
  alarm_name          = "root-account-usage"
  alarm_description   = "Root account was used"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "RootAccountUsage"
  namespace           = "CloudTrailMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

# Alarm on unauthorized API calls
resource "aws_cloudwatch_metric_alarm" "unauthorized_api" {
  alarm_name          = "unauthorized-api-calls"
  alarm_description   = "Unauthorized API calls detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnauthorizedAPICalls"
  namespace           = "CloudTrailMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

# Alarm on Security Group changes
resource "aws_cloudwatch_metric_alarm" "sg_changes" {
  alarm_name          = "security-group-changes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "SecurityGroupChanges"
  namespace           = "CloudTrailMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}
```

---

## Threat Detection

### Enable GuardDuty

```hcl
# Enable in all regions
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }
}

# Alert on GuardDuty findings
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "guardduty-high-findings"
  description = "Alert on HIGH/CRITICAL GuardDuty findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]  # HIGH and CRITICAL
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts.arn
}
```

### Enable Security Hub

```hcl
resource "aws_securityhub_account" "main" {}

# Enable CIS AWS Foundations standard
resource "aws_securityhub_standards_subscription" "cis" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
}

# Enable AWS Foundational Security Best Practices
resource "aws_securityhub_standards_subscription" "aws_best_practices" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:ap-south-1::standards/aws-foundational-security-best-practices/v/1.0.0"
}
```

### Enable Macie for S3 Data Discovery

```hcl
resource "aws_macie2_account" "main" {
  finding_publishing_frequency = "FIFTEEN_MINUTES"
  status                       = "ENABLED"
}

# Enable Macie on specific S3 bucket
resource "aws_macie2_classification_job" "s3_scan" {
  job_type = "SCHEDULED"
  name     = "production-s3-scan"

  schedule_frequency {
    weekly_schedule = "MONDAY"
  }

  s3_job_definition {
    bucket_definitions {
      account_id = data.aws_caller_identity.current.account_id
      buckets    = [aws_s3_bucket.app.bucket]
    }
  }
}
```

---

## Service-Specific Hardening

### EC2 Hardening

```hcl
# Require IMDSv2 for all new instances
resource "aws_ec2_instance_metadata_defaults" "main" {
  http_tokens                 = "required"   # force IMDSv2
  http_put_response_hop_limit = 1
}

# EC2 with IMDSv2 and SSM access
resource "aws_instance" "secure" {
  ami                  = data.aws_ami.amazon_linux.id
  instance_type        = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ssm.name

  # IMDSv2 required
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2
    http_put_response_hop_limit = 1
  }

  # Encrypted root volume
  root_block_device {
    encrypted   = true
    kms_key_id  = aws_kms_key.main.arn
    volume_type = "gp3"
  }

  # No public IP
  associate_public_ip_address = false

  tags = merge(local.common_tags, {
    Name = "secure-instance"
  })
}
```

### EKS Hardening

```hcl
resource "aws_eks_cluster" "main" {
  name     = "production-cluster"
  role_arn = aws_iam_role.eks.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false  # no public API server
    public_access_cidrs     = []
  }

  # Enable secrets encryption
  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  # Enable all logging
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
}
```

---

## Security Automation

### Auto-Remediate Public S3 Buckets

```python
# Lambda function — auto-remediate public S3
import boto3

def handler(event, context):
    s3 = boto3.client('s3')

    # Get bucket name from Config event
    bucket_name = event['detail']['resourceId']

    # Block all public access
    s3.put_public_access_block(
        Bucket=bucket_name,
        PublicAccessBlockConfiguration={
            'BlockPublicAcls': True,
            'IgnorePublicAcls': True,
            'BlockPublicPolicy': True,
            'RestrictPublicBuckets': True
        }
    )

    print(f"Remediated public S3 bucket: {bucket_name}")
    return {'statusCode': 200}
```

```hcl
# Config rule + automatic remediation
resource "aws_config_config_rule" "s3_public_access" {
  name = "s3-bucket-public-read-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
}

resource "aws_config_remediation_configuration" "s3_public_access" {
  config_rule_name = aws_config_config_rule.s3_public_access.name
  target_type      = "SSM_DOCUMENT"
  target_id        = "AWS-DisableS3BucketPublicReadWrite"
  automatic        = true
  maximum_automatic_attempts = 3
}
```

---

## CIS Checklist

```
CIS AWS Foundations Benchmark v1.5

Identity and Access Management:
  □ Root account MFA enabled
  □ Root account has no access keys
  □ MFA required for all IAM users
  □ Password policy configured
  □ Access keys rotated within 90 days
  □ Unused credentials disabled
  □ IAM policies attached to groups not users
  □ Access Analyzer enabled

Logging:
  □ CloudTrail enabled in all regions
  □ CloudTrail log file validation enabled
  □ CloudTrail integrated with CloudWatch
  □ S3 bucket access logging enabled
  □ VPC Flow Logs enabled
  □ Config enabled in all regions

Monitoring:
  □ Alarm for root account usage
  □ Alarm for unauthorized API calls
  □ Alarm for MFA console sign-in without MFA
  □ Alarm for IAM policy changes
  □ Alarm for CloudTrail config changes
  □ Alarm for S3 bucket policy changes
  □ Alarm for Security Group changes
  □ Alarm for VPC changes
  □ Alarm for Network Gateway changes

Networking:
  □ No security groups with 0.0.0.0/0 on port 22
  □ No security groups with 0.0.0.0/0 on port 3389
  □ Default VPC deleted or locked down
  □ VPC flow logging enabled
  □ No unrestricted outbound security groups

Additional:
  □ GuardDuty enabled in all regions
  □ Security Hub enabled
  □ Macie enabled
  □ Inspector enabled
  □ All EBS volumes encrypted
  □ All RDS instances encrypted
  □ Secrets Manager used for credentials
  □ IMDSv2 required on all EC2 instances
```

---

*References: CIS AWS Foundations Benchmark | AWS Security Best Practices | NIST Cybersecurity Framework | AWS Well-Architected Security Pillar*
