# CI/CD Pipelines on AWS: Automate Everything from Code to Production

## How Modern Teams Ship Software Without Fear

---

Most engineering teams start the same way: a developer writes code, SSHes into a server, copies files over, restarts the application, and hopes nothing breaks. It works — until the team grows, the codebase gets complex, and that manual process becomes a source of fear instead of confidence.

CI/CD pipelines replace that fear with a system. Code goes in, tested and deployed software comes out — automatically, consistently, and safely every single time.

---

## What is CI/CD?

**CI — Continuous Integration** is the practice of automatically building and testing code every time a developer pushes a change. It catches bugs before they reach production.

**CD — Continuous Delivery/Deployment** is the practice of automatically releasing tested code to production (or staging) without manual intervention.

```
Developer pushes code
         │
         ▼
CI: Build → Test → Static Analysis → Security Scan
         │
    All checks pass?
         │
    YES  │  NO
         │   └──► Notify developer, block merge
         ▼
CD: Deploy to Staging → Integration Tests → Deploy to Production
         │
         ▼
Users get new features — automatically
```

### CI vs CD — The Difference

| Term | What it means | Outcome |
|---|---|---|
| Continuous Integration | Auto build + test on every commit | Bugs caught early |
| Continuous Delivery | Auto deploy to staging, manual approval to prod | One-click to production |
| Continuous Deployment | Auto deploy all the way to production | Zero manual steps |

Most teams start with Continuous Delivery — auto to staging, one human approval to production. Continuous Deployment comes later, when test coverage is high enough to trust fully.

---

## The AWS Native CI/CD Stack

AWS provides a complete set of native CI/CD services:

```
CodeCommit  →  CodeBuild  →  CodeDeploy  →  Production
(source)       (build+test)   (deploy)

All orchestrated by: CodePipeline
```

### AWS CodeCommit

A **managed Git repository** hosted on AWS — like GitHub but inside your AWS account. Integrated with IAM for access control, no external service dependency.

> Honest note: Most teams use **GitHub** or **GitLab** instead of CodeCommit, even on AWS. CodeCommit is less feature-rich and has a smaller community. CodeBuild, CodeDeploy, and CodePipeline all integrate with GitHub just as well.

### AWS CodeBuild

A **fully managed build service** that compiles code, runs tests, and produces deployment artifacts. You define build steps in a `buildspec.yml` file:

```yaml
# buildspec.yml
version: 0.2

phases:
  install:
    runtime-versions:
      nodejs: 18
    commands:
      - npm install

  pre_build:
    commands:
      - echo "Running tests..."
      - npm test
      - echo "Logging in to ECR..."
      - aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_URI

  build:
    commands:
      - echo "Building Docker image..."
      - docker build -t $IMAGE_NAME:$CODEBUILD_RESOLVED_SOURCE_VERSION .
      - docker tag $IMAGE_NAME:$CODEBUILD_RESOLVED_SOURCE_VERSION $ECR_URI:latest

  post_build:
    commands:
      - docker push $ECR_URI:latest
      - echo "Writing image definitions..."
      - printf '[{"name":"web","imageUri":"%s"}]' $ECR_URI:latest > imagedefinitions.json

artifacts:
  files:
    - imagedefinitions.json
```

CodeBuild spins up a clean environment, runs your build, and tears it down. You pay only per build minute — no idle servers.

### AWS CodeDeploy

A **managed deployment service** that automates application deployments to EC2, ECS, Lambda, or on-premises servers.

**Deployment Strategies:**

**In-Place (Rolling):**
```
Server 1: Deploy new version → health check → ✅
Server 2: Deploy new version → health check → ✅
Server 3: Deploy new version → health check → ✅
(Takes servers offline one at a time — reduced capacity during deploy)
```

**Blue/Green:**
```
Blue (current production):   v1 — 100% traffic
Green (new version):         v2 — 0% traffic, fully deployed and tested

Switch:  Blue 0% ←──────────────────────── 100% Green
         (Instant traffic shift, instant rollback if issues found)
```

Blue/Green is the gold standard for production deployments — zero downtime, instant rollback.

### AWS CodePipeline

The **orchestrator** that connects everything together into a pipeline:

```
Source Stage:      GitHub push to main branch
        │
        ▼
Build Stage:       CodeBuild runs tests + builds Docker image
        │
        ▼
Staging Stage:     CodeDeploy deploys to staging ECS cluster
        │
        ▼
Approval Stage:    Manual approval gate (human reviews staging)
        │
        ▼
Production Stage:  CodeDeploy deploys to production ECS cluster
```

---

## GitHub Actions — The Industry Standard

While AWS's native tools are solid, **GitHub Actions** has become the most widely used CI/CD system across the industry. If you're using GitHub (which most teams are), GitHub Actions is often the better choice.

### A Complete GitHub Actions Pipeline

```yaml
# .github/workflows/deploy.yml
name: Build and Deploy to AWS

on:
  push:
    branches: [main]

env:
  AWS_REGION: ap-south-1
  ECR_REPOSITORY: my-app
  ECS_SERVICE: my-app-service
  ECS_CLUSTER: production

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test

      - name: Run security audit
        run: npm audit --audit-level=high

  build-and-deploy:
    needs: test   # Only runs if tests pass
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1

      - name: Build, tag, and push image to ECR
        id: build-image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          echo "image=$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG" >> $GITHUB_OUTPUT

      - name: Deploy to ECS
        uses: aws-actions/amazon-ecs-deploy-task-definition@v1
        with:
          task-definition: task-definition.json
          service: ${{ env.ECS_SERVICE }}
          cluster: ${{ env.ECS_CLUSTER }}
          wait-for-service-stability: true
```

Push to `main` → tests run → image built → deployed to ECS. Automatically. Every time.

---

## The Complete CI/CD Flow for 3-Tier Architecture

```
Developer laptop
      │
      │  git push origin main
      ▼
GitHub Repository
      │
      │  Triggers GitHub Actions workflow
      ▼
┌─────────────────────────────────────────┐
│           CI Stage                      │
│  ✓ Install dependencies                 │
│  ✓ Run unit tests                       │
│  ✓ Run integration tests                │
│  ✓ Static code analysis (ESLint/SonarQ) │
│  ✓ Security scan (npm audit / Snyk)     │
│  ✓ Build Docker image                   │
│  ✓ Scan image for CVEs (ECR)            │
└─────────────────┬───────────────────────┘
                  │ All checks green
                  ▼
┌─────────────────────────────────────────┐
│           CD Stage — Staging            │
│  ✓ Push image to ECR                    │
│  ✓ Deploy new Task Definition to ECS    │
│  ✓ ECS rolling update on staging        │
│  ✓ Run smoke tests against staging URL  │
└─────────────────┬───────────────────────┘
                  │
                  ▼
         Manual Approval Gate
         (team lead reviews)
                  │
                  ▼
┌─────────────────────────────────────────┐
│        CD Stage — Production            │
│  ✓ Blue/Green deployment via CodeDeploy │
│  ✓ Shift 10% traffic to Green           │
│  ✓ Monitor error rate for 5 minutes     │
│  ✓ Shift 100% traffic to Green          │
│  ✓ Terminate Blue environment           │
└─────────────────────────────────────────┘
```

---

## Deployment Strategies Compared

### Rolling Update
```
Before: [v1] [v1] [v1] [v1]
Step 1: [v2] [v1] [v1] [v1]
Step 2: [v2] [v2] [v1] [v1]
Step 3: [v2] [v2] [v2] [v1]
After:  [v2] [v2] [v2] [v2]

✅ No extra infrastructure cost
❌ Brief mixed-version state — v1 and v2 serve traffic simultaneously
❌ Rollback requires another rolling update
```

### Blue/Green
```
Blue:  [v1] [v1] [v1]  ←── 100% traffic
Green: [v2] [v2] [v2]  ←── 0% traffic (deployed and tested)

Switch: instantly move 100% traffic to Green
        Blue kept alive for instant rollback

✅ Zero downtime
✅ Instant rollback (just flip traffic back to Blue)
❌ Double infrastructure cost during deployment window
```

### Canary Release
```
Step 1:  [v2] → 5% traffic,   [v1] → 95% traffic
Step 2:  [v2] → 25% traffic,  [v1] → 75% traffic
Step 3:  [v2] → 50% traffic,  [v1] → 50% traffic
Step 4:  [v2] → 100% traffic, [v1] → retired

✅ Gradual rollout — real user traffic tests new version safely
✅ Automatic rollback if error rate spikes
❌ More complex to implement
Best for: High-risk changes, major feature releases
```

---

## Pipeline Security Best Practices

### Never Store Secrets in Pipeline Code
```yaml
# ❌ WRONG
env:
  DB_PASSWORD: "mysecretpassword"

# ✅ RIGHT — use GitHub Secrets or AWS Secrets Manager
env:
  DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
```

### Use OIDC Instead of Long-Term Access Keys
GitHub Actions supports OpenID Connect (OIDC) to authenticate with AWS without storing access keys:

```yaml
- name: Configure AWS credentials via OIDC
  uses: aws-actions/configure-aws-credentials@v2
  with:
    role-to-assume: arn:aws:iam::123456789:role/GitHubActionsRole
    aws-region: ap-south-1
    # No access key or secret needed — temporary credentials via OIDC
```

### Pin Action Versions
```yaml
# ❌ WRONG — uses latest, could break silently
uses: actions/checkout@main

# ✅ RIGHT — pinned to exact version
uses: actions/checkout@v3.5.2
```

### Require Tests to Pass Before Merge
Enforce branch protection rules on `main`:
- Require status checks to pass before merging
- Require at least 1 review approval
- Prevent direct pushes to main

---

## Key Takeaways

- **CI/CD is how modern teams ship confidently** — manual deployments are a liability, not a process
- **GitHub Actions is the industry standard** — most teams use it regardless of where they deploy
- **AWS CodePipeline + CodeBuild + CodeDeploy** is the AWS-native alternative — solid for AWS-only shops
- **Blue/Green is the gold standard** for production deployments — zero downtime, instant rollback
- **Canary releases** reduce risk on major changes — test with 5% of real traffic before going 100%
- **Secrets in pipelines must be managed carefully** — use OIDC, not long-term access keys
- **Automate everything** — if you're doing it manually more than twice, put it in the pipeline

---

*Found this useful? Follow for more AWS deep-dives — next up: AWS Observability — CloudWatch, X-Ray, and how to actually understand what your production system is doing.*
