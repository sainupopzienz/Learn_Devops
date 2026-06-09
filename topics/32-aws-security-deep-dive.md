# AWS Security Deep Dive: From IAM to GuardDuty

## The Complete Guide to Securing Your AWS Infrastructure

---

Security is not a feature you add at the end. It's the foundation everything else sits on. Yet most engineers treat AWS security as an afterthought — they build the architecture first, then scramble to lock things down before going live.

This article walks you through AWS security from the ground up — IAM, encryption, secrets management, and threat detection — the same stack used to protect production systems handling millions of users and sensitive data.

---

## The AWS Shared Responsibility Model — Know Your Boundaries

Before writing a single IAM policy, understand one thing: **AWS and you share security responsibility**.

```
AWS is responsible for:                    You are responsible for:
───────────────────────────────────        ────────────────────────────────
Physical data center security              IAM users, roles, and policies
Hardware maintenance                       Data encryption
Network infrastructure                     Security group rules
Hypervisor security                        OS patching on EC2
Global infrastructure                      Application security
                                           Data classification
```

AWS secures **the cloud**. You secure **what's in the cloud**. Confusing these two is the root cause of most AWS security incidents.

---

## Layer 1 — IAM: Identity and Access Management

IAM is the master control plane of AWS security. Every API call made to AWS — whether from a developer, an EC2 instance, or a Lambda function — is authenticated and authorized through IAM.

### The Core IAM Concepts

**Users** — represent a person or application with long-term credentials (access keys or passwords). Avoid creating users for applications — use roles instead.

**Groups** — collections of users that share the same permissions. Assign policies to groups, not individual users.

**Roles** — temporary identity assumed by AWS services, applications, or federated users. An EC2 instance assumes a role to access S3. A Lambda function assumes a role to write to DynamoDB.

**Policies** — JSON documents that define what actions are allowed or denied on which resources.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::my-app-bucket/*"
    }
  ]
}
```

This policy allows reading and writing objects in one specific S3 bucket — and nothing else.

---

### The Principle of Least Privilege

The single most important IAM rule: **give the minimum permissions needed, nothing more**.

```
❌ BAD — AdministratorAccess on an EC2 instance
(If that instance is compromised, the attacker has full AWS account access)

✅ GOOD — Only the specific S3 bucket and DynamoDB table the app actually needs
(If compromised, the blast radius is limited to those two resources)
```

### IAM Best Practices

**Enable MFA everywhere** — especially on the root account and all IAM users with console access. The root account should have MFA and its access keys should be deleted entirely after initial setup.

**Use IAM Roles for EC2, Lambda, and ECS** — never embed access keys in code or EC2 user data:

```bash
# ❌ WRONG — hardcoded keys in your application
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG

# ✅ RIGHT — attach an IAM role to the EC2 instance
# The SDK automatically picks up credentials from the instance metadata
```

**Use Permission Boundaries** — caps the maximum permissions a role can ever have, even if someone accidentally attaches a broader policy later.

**Rotate access keys regularly** — if you must use access keys, rotate them every 90 days and audit which ones are unused.

---

### IAM Identity Center (SSO)

For teams, never create individual IAM users per person. Use **IAM Identity Center** (formerly AWS SSO):

```
Your corporate identity provider (Google Workspace, Okta, Active Directory)
                          │
                          ▼
                 IAM Identity Center
                          │
              ┌───────────┼───────────┐
              ▼           ▼           ▼
         Dev Account  Staging Acc  Prod Account
         (read-only)  (developer)  (read-only)
```

One login. Multiple AWS accounts. Permissions managed centrally. No long-term access keys.

---

## Layer 2 — Encryption: KMS and Data Protection

### AWS KMS — Key Management Service

KMS manages **encryption keys** — the cryptographic material that protects your data at rest and in transit.

```
Your Data  ──►  KMS encrypts  ──►  Encrypted Data stored in S3/RDS/EBS
                    │
                    │  (only principals with kms:Decrypt permission can read)
                    ▼
Your App   ──►  KMS decrypts  ──►  Plain text data returned to app
```

Every major AWS storage service supports KMS encryption:

| Service | Encryption Option |
|---|---|
| S3 | SSE-S3 (managed), SSE-KMS (your key), SSE-C (customer key) |
| RDS | Enable encryption at creation (cannot add later) |
| EBS | Encrypt volumes at creation or copy |
| DynamoDB | Encryption at rest with KMS |
| Secrets Manager | Encrypted with KMS by default |

> **Critical:** Enable RDS encryption at creation time. You cannot encrypt an existing unencrypted RDS instance — you must take a snapshot, encrypt the snapshot, and restore from it.

### Encryption in Transit

Always enforce HTTPS/TLS:
- ALB: use ACM certificates, redirect HTTP → HTTPS
- RDS: enforce SSL connections via parameter group (`rds.force_ssl = 1`)
- S3: bucket policy to deny HTTP requests
- API Gateway: always HTTPS by default
- Inter-service communication inside VPC: use TLS even on private networks

---

## Layer 3 — Secrets Management

### AWS Secrets Manager vs Parameter Store

Never store database passwords, API keys, or credentials in environment variables hardcoded in code or EC2 user data. Use a secrets service.

| Feature | Secrets Manager | Parameter Store |
|---|---|---|
| Cost | ~$0.40/secret/month | Free (standard tier) |
| Auto rotation | ✅ Built-in for RDS, Redshift, DocumentDB | ❌ Manual only |
| Encryption | ✅ Always KMS encrypted | ✅ SecureString tier |
| Cross-account | ✅ Yes | Limited |
| Best for | Database passwords, API keys, OAuth tokens | Config values, feature flags, non-sensitive config |

### How Your App Retrieves a Secret

```python
import boto3
import json

def get_db_password():
    client = boto3.client('secretsmanager', region_name='ap-south-1')
    response = client.get_secret_value(SecretId='prod/myapp/db-password')
    secret = json.loads(response['SecretString'])
    return secret['password']
```

Your application retrieves the password at runtime — the secret never lives in your code, config files, or environment variables.

### Secrets Manager Auto-Rotation

```
Secrets Manager rotates the RDS password automatically every 30/60/90 days:

Day 1:   Password = "abc123"  → stored in Secrets Manager
Day 30:  Lambda rotation function runs automatically
         → Creates new password "xyz789" in RDS
         → Updates Secrets Manager with new password
         → Old password invalidated
         Your app fetches fresh secret every time → zero downtime
```

---

## Layer 4 — Network Security

### Security Groups — Stateful Firewall

Security groups are the primary firewall for EC2, RDS, Lambda (in VPC), and ECS:

```
Rule: Allow port 443 inbound from 0.0.0.0/0
→ Response traffic is automatically allowed outbound (stateful)
→ You don't need a separate outbound rule for responses
```

**Key principles:**
- Default: deny all inbound, allow all outbound
- Reference security groups by ID, not IP ranges, for internal traffic
- Keep security groups specific — one per tier, one per service type

### Network ACLs — Stateless Firewall

NACLs operate at the subnet level and are **stateless** (you need explicit inbound AND outbound rules):

```
Security Group  →  Instance-level, stateful,  allow rules only
Network ACL     →  Subnet-level,  stateless,  allow AND deny rules
```

Use NACLs to block specific IP ranges that are attacking you at the subnet level, before traffic even reaches your security groups.

### VPC Flow Logs

Enable **VPC Flow Logs** to capture all network traffic metadata in your VPC:

```
[2024-01-15 10:23:45] 203.0.113.0 → 10.0.1.5:443  ACCEPT  1250 bytes
[2024-01-15 10:23:46] 198.51.100.0 → 10.0.1.5:22   REJECT  0 bytes
```

Flow logs go to CloudWatch Logs or S3 — invaluable for security investigations and compliance audits.

---

## Layer 5 — Threat Detection and Monitoring

### AWS GuardDuty

GuardDuty is a **managed threat detection service** that continuously analyzes:
- CloudTrail logs (API calls)
- VPC Flow Logs (network traffic)
- DNS logs (domain resolution patterns)

It uses machine learning to detect:

```
Suspicious findings GuardDuty catches:
─────────────────────────────────────
✗ EC2 instance communicating with known malware C2 servers
✗ IAM credentials used from an unusual geographic location
✗ Cryptocurrency mining activity detected on EC2
✗ Brute force attacks on RDS or SSH
✗ S3 bucket data exfiltration patterns
✗ Unauthorized API calls from root account
```

Enable GuardDuty in every region, even regions you're not actively using — attackers often spin up resources in quiet regions.

### AWS Security Hub

Security Hub is the **central dashboard** for security findings across your AWS account:

```
GuardDuty findings ──┐
Inspector findings ──┤──► Security Hub ──► Unified dashboard + scoring
Macie findings    ──┤                      + EventBridge alerts
Config findings   ──┘                      + Ticketing integration
```

It scores your account against industry standards — CIS AWS Foundations, PCI DSS, AWS Foundational Best Practices — and shows you exactly where you're failing.

### AWS Inspector

Inspector automatically scans:
- **EC2 instances** — OS vulnerabilities, unpatched CVEs
- **ECR container images** — known vulnerabilities in container layers
- **Lambda functions** — vulnerable dependencies in function packages

```
Inspector scans your EC2 daily:
"Critical: OpenSSL vulnerability CVE-2023-XXXX detected
 on instance i-0abc123, patch available, severity: 9.8/10"
```

### Amazon Macie

Macie uses machine learning to **discover and protect sensitive data in S3**:

```
Macie scans your S3 buckets and finds:
─────────────────────────────────────
⚠ Bucket "user-uploads" contains 1,247 files with credit card numbers
⚠ Bucket "logs" contains files with Indian Aadhaar numbers  
⚠ Bucket "reports" is publicly accessible and contains PII
```

Essential for compliance — GDPR, PCI DSS, HIPAA all require you to know where sensitive data lives.

---

## Layer 6 — Compliance and Auditing

### AWS CloudTrail

CloudTrail records **every API call** made in your AWS account:

```
Who:    arn:aws:iam::123456789:user/john
What:   DeleteSecurityGroup
When:   2024-01-15T14:23:45Z
Where:  ap-south-1
How:    Console / CLI / SDK
Result: Success / AccessDenied
```

Enable CloudTrail in all regions, send logs to a dedicated S3 bucket with MFA delete enabled so logs cannot be tampered with — even by administrators.

### AWS Config

Config tracks the **configuration history** of every AWS resource:

```
"Was this S3 bucket ever made public?" → Config has the answer
"What were the security group rules on this EC2 last Tuesday?" → Config knows
"Which EC2 instances don't have encrypted EBS volumes?" → Config can tell you
```

Create **Config Rules** to enforce compliance automatically:
- `ec2-instance-no-public-ip` — alert on any EC2 with a public IP in private subnets
- `s3-bucket-public-read-prohibited` — alert on any public S3 bucket
- `rds-storage-encrypted` — alert on any unencrypted RDS instance

---

## The AWS Security Checklist

```
IAM
✅ Root account MFA enabled, access keys deleted
✅ All users have MFA
✅ No inline policies — use managed policies only
✅ EC2/Lambda use IAM roles, not access keys
✅ IAM Identity Center for team access

Encryption
✅ All S3 buckets have default encryption enabled
✅ All RDS instances encrypted at creation
✅ All EBS volumes encrypted
✅ KMS CMKs used for sensitive workloads
✅ SSL enforced on all endpoints

Secrets
✅ No secrets in code, config files, or environment variables
✅ All secrets stored in Secrets Manager
✅ Auto-rotation enabled for database credentials

Network
✅ No 0.0.0.0/0 on port 22 or 3389 in any security group
✅ VPC Flow Logs enabled
✅ Private subnets for all databases and app servers
✅ WAF in front of public endpoints

Monitoring
✅ GuardDuty enabled in all regions
✅ Security Hub enabled and configured
✅ CloudTrail enabled in all regions, logs protected
✅ Config rules enforcing compliance
✅ Inspector scanning EC2 and containers
```

---

## Key Takeaways

- **IAM is everything** — a misconfigured IAM policy is the most common cause of AWS breaches
- **Least privilege is not optional** — start with zero permissions and add only what's needed
- **Encrypt everything** — at rest with KMS, in transit with TLS — no exceptions
- **Secrets Manager over environment variables** — always, even for internal tools
- **GuardDuty should always be on** — it's cheap, managed, and catches real attacks
- **CloudTrail is your black box recorder** — you cannot investigate an incident without it

---

*Found this useful? Follow for more AWS deep-dives — next up: Containers on AWS — Docker, ECS, and EKS explained.*
