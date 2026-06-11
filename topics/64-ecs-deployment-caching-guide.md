# Why ECS Deployment Succeeds but Users Still See the Old Version

> A deep-dive into one of the most misunderstood production problems in AWS — with real-world examples, architecture diagrams, and DevOps-ready fixes.

---

## Table of Contents

1. [The Problem Statement](#1-the-problem-statement)
2. [Key Insight: What ECS Success Actually Means](#2-key-insight-what-ecs-success-actually-means)
3. [Full Architecture Overview](#3-full-architecture-overview)
4. [Caching Layers Explained](#4-caching-layers-explained)
5. [Root Causes Deep Dive](#5-root-causes-deep-dive)
6. [The Fix: Content Hashing Strategy](#6-the-fix-content-hashing-strategy)
7. [CloudFront Caching Strategy](#7-cloudfront-caching-strategy)
8. [Correct CI/CD Deployment Flow](#8-correct-cicd-deployment-flow)
9. [DevOps Fix Checklist](#9-devops-fix-checklist)
10. [Real-World Scenario Walkthrough](#10-real-world-scenario-walkthrough)
11. [Invalidation Decision Tree](#11-invalidation-decision-tree)
12. [S3 Cache-Control Headers](#12-s3-cache-control-headers)
13. [ECS Task Definition Versioning](#13-ecs-task-definition-versioning)
14. [Debugging Steps in Production](#14-debugging-steps-in-production)
15. [Interview-Ready Explanation](#15-interview-ready-explanation)

---

## 1. The Problem Statement

You push code. CI/CD pipeline shows **green**. ECS deployment shows **SUCCESS**. No error logs. No 5xx responses from the backend. Yet your users call support saying:

> "The new feature isn't showing up."
> "I'm still seeing the old button."
> "The bug you said you fixed is still happening."

This is one of the most confusing production issues because every AWS dashboard looks healthy.

**Why it confuses engineers:**

```
What you check:          What it shows:
─────────────────────    ─────────────────────
ECS Service Events   →   "Deployment completed"
ECS Tasks            →   All tasks RUNNING (new revision)
ALB Target Group     →   All targets healthy
CloudWatch Logs      →   No errors
RDS                  →   No slow queries
```

Everything is green. But users see the old UI. The bug is **not in your backend** — it is in your **caching architecture**.

---

## 2. Key Insight: What ECS Success Actually Means

```
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║   ECS deployment success = containers replaced           ║
║   ECS deployment success ≠ users see new version         ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
```

ECS manages your **backend API containers**. It has no knowledge of:

- What `index.html` CloudFront is serving
- What JavaScript files are cached in a browser
- What TTL you set on your S3 objects
- What your users' browsers cached 3 days ago

The user experience is the product of **all layers combined**, not just ECS.

---

## 3. Full Architecture Overview

### 3.1 Component Map

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER'S BROWSER                                  │
│                                                                              │
│   Browser Cache: index.html, main.js, chunk.css                              │
│   (Controlled by: Cache-Control response headers)                            │
└────────────────────────────┬────────────────────────────────────────────────┘
                             │  HTTPS Request
                             ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         AMAZON CLOUDFRONT (CDN)                              │
│                                                                              │
│   Edge Locations: 400+ globally (Mumbai, Singapore, Frankfurt, etc.)         │
│   Cache: index.html, *.js, *.css, images                                    │
│   TTL: Controlled per path pattern (your policy)                             │
└──────────────┬──────────────────────────────────────┬───────────────────────┘
               │ Static files                         │ API requests
               │ (Cache HIT = serve from edge)        │ (/api/*)
               ▼                                      ▼
┌──────────────────────────┐              ┌───────────────────────────────────┐
│       AMAZON S3           │              │   APPLICATION LOAD BALANCER       │
│                           │              │                                   │
│  /index.html              │              │  Listener: HTTPS 443              │
│  /static/js/              │              │  Target Group: ECS Tasks          │
│    main.8f3a91.js         │              │  Health Check: /health            │
│    chunk.a3f9bc.js        │              └──────────────────┬────────────────┘
│  /static/css/             │                                 │
│    main.d3a1b2.css        │                                 ▼
│  /assets/                 │              ┌───────────────────────────────────┐
│    logo.png               │              │        ECS CLUSTER                │
└──────────────────────────┘              │                                   │
                                          │  Service: my-api-service          │
                                          │  ┌──────────┐  ┌──────────┐      │
                                          │  │ Task v23 │  │ Task v23 │      │
                                          │  │ api:v2.1 │  │ api:v2.1 │      │
                                          │  └──────────┘  └──────────┘      │
                                          │                                   │
                                          │  (Old tasks v22 drained & stopped)│
                                          └──────────────────┬────────────────┘
                                                             │
                                                             ▼
                                          ┌───────────────────────────────────┐
                                          │       AMAZON RDS / DATABASE        │
                                          │  PostgreSQL Multi-AZ              │
                                          └───────────────────────────────────┘
```

### 3.2 Frontend vs Backend Split

```
Frontend (User's Browser ← CloudFront ← S3):
─────────────────────────────────────────────
React / Vue / Angular SPA
├── index.html         (entry point — loads everything)
├── main.[hash].js     (your application code)
├── chunk.[hash].js    (vendor libraries: React, Axios, etc.)
└── main.[hash].css    (styles)

Backend (User's Browser → ALB → ECS):
──────────────────────────────────────
Node.js / Java / Python API
├── GET  /api/users
├── POST /api/orders
├── PUT  /api/products/:id
└── GET  /api/health
```

**Critical understanding:** Deploying a new ECS task only replaces the **right side** of this diagram. The left side (S3 + CloudFront) is completely separate.

---

## 4. Caching Layers Explained

Each layer below is an independent cache that can independently serve stale content.

```
Request journey from user to server:

USER
 │
 ├──► Layer 1: BROWSER CACHE
 │    Location: User's device (Chrome/Firefox/Safari)
 │    Controlled by: Cache-Control header in HTTP response
 │    TTL: Whatever your S3/CloudFront sends
 │    Problem: If cached, NEVER reaches CloudFront
 │
 │    ↓ (cache miss or expired)
 │
 ├──► Layer 2: CLOUDFRONT EDGE CACHE
 │    Location: Nearest AWS edge location to user
 │    Controlled by: CloudFront Cache Behavior settings
 │    TTL: Your configuration (could be 24hrs, 7 days, 1 year)
 │    Problem: Serves old content to ALL users globally
 │
 │    ↓ (cache miss or invalidated)
 │
 ├──► Layer 3: S3 ORIGIN
 │    Location: Your S3 bucket
 │    Controlled by: Object metadata + Cache-Control headers
 │    Problem: If filename unchanged, serves same old file
 │
 └──► (for API requests only)
      Layer 4: ALB → ECS Task
      This IS updated by your deployment
      This is what "ECS success" actually means
```

**The trap:** Most engineers monitor only Layer 4 (ECS). Layers 1–3 are invisible in the AWS console.

---

## 5. Root Causes Deep Dive

### 5.1 Root Cause A: CloudFront Caches `index.html`

`index.html` is the **master controller** of your frontend. It tells the browser which JavaScript and CSS files to load.

**What index.html looks like:**

```html
<!-- OLD index.html (cached by CloudFront) -->
<!DOCTYPE html>
<html>
  <head>
    <link rel="stylesheet" href="/static/css/main.css">  <!-- ← OLD CSS, no hash -->
  </head>
  <body>
    <div id="root"></div>
    <script src="/static/js/main.js"></script>  <!-- ← OLD JS, no hash -->
  </body>
</html>
```

**Timeline when this goes wrong:**

```
Day 1 - v1 deployed:
  S3: index.html references main.js (v1 code)
  CloudFront: Caches index.html for 24 hours

Day 2 - v2 deployed:
  S3: index.html updated, references main.js (v2 code)
  CloudFront: Still serving yesterday's index.html (cache not expired!)
  Browser: Gets old index.html → loads old main.js → user sees v1

Result:
  ECS: Running v2 API ✓
  CloudFront: Serving v1 index.html ✗
  User: Sees v1 frontend calling v2 API = bugs
```

---

### 5.2 Root Cause B: Non-Hashed JS/CSS Files

```
Bad pattern:
  S3 bucket: /static/js/main.js

Build 1 uploads: main.js (contains old code)
Build 2 uploads: main.js (contains new code, SAME FILENAME)

CloudFront sees: Same filename → assumes same file
Browser sees:    Same URL → serves from cache
User sees:       Old code
```

```
Good pattern:
  Build 1 uploads: main.a1b2c3.js  (hash of file contents)
  Build 2 uploads: main.x9y8z7.js  (different hash = different filename)

CloudFront sees: Different URL → fetches new file
Browser sees:    Unknown URL → must fetch from network
User sees:       New code immediately
```

---

### 5.3 Root Cause C: ECS Updated, Frontend Still Old

This is the most confusing case — your API is v2 but your frontend is still v1.

```
Scenario: You added a new "Export CSV" button in frontend + new API endpoint

ECS deployment: Deploys new API with GET /api/export/csv   ✓
Frontend:       Old bundle without the "Export CSV" button  ✗

Result:
  API: Ready to handle /api/export/csv (v2)
  User's browser: Still has old frontend, button doesn't exist
  User: "The button you promised isn't there"
  You: "But ECS shows deployment successful!"
```

---

### 5.4 Root Cause D: Browser Long-Term Cache

Even if CloudFront is correct, the user's browser may have cached the old file for days.

```
Cache-Control: max-age=86400  (24 hours)

User visits site at 9 AM Monday → browser caches main.js for 24 hours
You deploy at 2 PM Monday
User visits site at 8 PM Monday → browser uses cache (8 PM < 9 AM Tuesday)
User sees old version even though CloudFront is serving new version!

Fix: Use hashed filenames. Browser treats main.x9y8z7.js as a completely new file.
```

---

## 6. The Fix: Content Hashing Strategy

Content hashing is the **single most important fix** for frontend caching problems. It makes cache invalidation nearly automatic.

### 6.1 The Concept

```
Without hashing:           With hashing:
─────────────────          ──────────────────────────────────────
main.js                    main.8f3a91bc.js
chunk.js                   chunk.a92bd7e1.js
styles.css                 styles.d1e2f3a4.css

Same name → cache reuse    New name on any code change → fresh fetch
```

The hash is derived from the **file's actual contents**. If one byte changes, the hash changes, the filename changes, and every cache layer treats it as a completely new file.

### 6.2 Webpack Configuration

```javascript
// webpack.config.js
module.exports = {
  output: {
    path: path.resolve(__dirname, 'build'),
    filename: 'static/js/[name].[contenthash:8].js',     // ← contenthash, not chunkhash
    chunkFilename: 'static/js/[name].[contenthash:8].chunk.js',
    publicPath: '/',
  },
  optimization: {
    splitChunks: {
      chunks: 'all',
      name: false,
    },
    runtimeChunk: {
      name: (entrypoint) => `runtime-${entrypoint.name}`,
    },
  },
};

// CSS (via MiniCssExtractPlugin)
new MiniCssExtractPlugin({
  filename: 'static/css/[name].[contenthash:8].css',
  chunkFilename: 'static/css/[name].[contenthash:8].chunk.css',
}),
```

### 6.3 Vite Configuration

```javascript
// vite.config.js
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: {
      output: {
        entryFileNames: 'assets/[name]-[hash].js',         // ← hash included
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash].[ext]',
      },
    },
  },
});
```

### 6.4 What the Build Generates

```
Before hashing (bad):         After hashing (good):
──────────────────────────    ──────────────────────────────────────────
build/
  index.html                  build/
  static/                       index.html
    js/                         static/
      main.js                     js/
      chunk.js                      main.8f3a91bc.js
    css/                            runtime-main.a1b2c3d4.js
      main.css                      2.chunk.a92bd7e1.js
                                css/
                                  main.d1e2f3a4.css
```

**Auto-generated index.html:**

```html
<!-- index.html — auto-generated by Webpack/Vite -->
<!DOCTYPE html>
<html>
  <head>
    <!-- Build tool injects the correct hashed filename automatically -->
    <link rel="stylesheet" href="/static/css/main.d1e2f3a4.css">
  </head>
  <body>
    <div id="root"></div>
    <script src="/static/js/runtime-main.a1b2c3d4.js"></script>
    <script src="/static/js/2.chunk.a92bd7e1.js"></script>
    <script src="/static/js/main.8f3a91bc.js"></script>
  </body>
</html>
```

You never hand-edit these script tags. The build tool always injects the correct hashed names.

---

## 7. CloudFront Caching Strategy

Different file types need radically different cache lifetimes.

### 7.1 Cache Policy Table

```
File Type            Cache Duration    Reasoning
───────────────────  ────────────────  ─────────────────────────────────────────
index.html           NO-CACHE          Controls which JS/CSS loads.
                                       Must always be fresh.
                                       Short TTL or no-store.

main.[hash].js       1 YEAR            Hash guarantees uniqueness.
chunk.[hash].js      1 YEAR            A new deploy = new hash = new file.
                                       Old hash files are safe to cache forever.

main.[hash].css      1 YEAR            Same as JS — hash ensures freshness.

Images (no hash)     1 WEEK            Rarely change; acceptable staleness.
Images (hashed)      1 YEAR            If hashed, cache aggressively.

favicon.ico          1 DAY             Low-risk, rarely changes.
robots.txt           1 HOUR            Policy files, can change.

/api/* responses     NO-CACHE          Dynamic data, should not be cached
                     or per-endpoint   unless you explicitly want edge caching.
```

### 7.2 CloudFront Behavior Configuration

```
CloudFront Distribution Behaviors (in order of precedence):

Priority 0: /api/*
  ├── Cache: Disabled (or minimal TTL)
  ├── Origin: ALB (backend)
  ├── TTL: 0 seconds
  └── Forward: All headers, cookies, query strings

Priority 1: /static/js/*
  ├── Cache: Maximum (1 year)
  ├── Origin: S3
  ├── TTL: 31,536,000 seconds
  └── Compress: Yes

Priority 2: /static/css/*
  ├── Cache: Maximum (1 year)
  ├── Origin: S3
  ├── TTL: 31,536,000 seconds
  └── Compress: Yes

Priority 3: /assets/*
  ├── Cache: Long (1 week to 1 year depending on hashing)
  ├── Origin: S3
  ├── TTL: 604,800 seconds (1 week, if no hash)
  └── Compress: Yes

Default (*):  → applies to index.html and everything else
  ├── Cache: None or very short
  ├── Origin: S3
  ├── TTL: 0 or 60 seconds
  └── Cache-Control: no-store, must-revalidate
```

### 7.3 Terraform Configuration

```hcl
resource "aws_cloudfront_distribution" "frontend" {
  # ... origin config ...

  # Default behavior → index.html (NO CACHE)
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    # NO CACHE for index.html
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0

    response_headers_policy_id = aws_cloudfront_response_headers_policy.no_cache.id
  }

  # /static/* behavior → hashed assets (LONG CACHE)
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    # 1 YEAR for hashed assets
    min_ttl     = 31536000
    default_ttl = 31536000
    max_ttl     = 31536000
  }
}

resource "aws_cloudfront_response_headers_policy" "no_cache" {
  name = "no-cache-policy"
  custom_headers_config {
    items {
      header   = "Cache-Control"
      value    = "no-store, no-cache, must-revalidate, proxy-revalidate"
      override = true
    }
  }
}
```

---

## 8. Correct CI/CD Deployment Flow

### 8.1 Full Deployment Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DEVELOPER                                    │
│                    git push origin main                              │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   CI/CD PIPELINE (Jenkins / GitHub Actions)          │
│                                                                      │
│  Stage 1: TEST                                                       │
│  ├── Unit tests                                                      │
│  ├── Integration tests                                               │
│  └── Lint + type check                                               │
│                                                                      │
│  Stage 2: FRONTEND BUILD                                             │
│  ├── npm ci                                                          │
│  ├── npm run build (Webpack/Vite with contenthash)                   │
│  ├── Output: build/ with hashed filenames                            │
│  └── Note: index.html is auto-updated with new hashes               │
│                                                                      │
│  Stage 3: BACKEND BUILD                                              │
│  ├── mvn package / gradle build / docker build                       │
│  └── Tag image: 123456789.dkr.ecr.ap-south-1.amazonaws.com/api:git-sha │
│                                                                      │
│  Stage 4: PUSH TO AWS                                                │
│  ├── docker push → ECR (new image tag)                               │
│  ├── aws s3 sync build/ s3://my-frontend-bucket/ --delete            │
│  │   (hashed files: uploaded with 1-year cache headers)             │
│  │   (index.html: uploaded with no-cache headers)                   │
│  └── [OPTIONAL] CloudFront invalidation for index.html              │
│      aws cloudfront create-invalidation --paths "/index.html"       │
│                                                                      │
│  Stage 5: ECS DEPLOYMENT                                             │
│  ├── Register new task definition (new image tag)                    │
│  ├── Update ECS service → rolling deployment                         │
│  └── Wait for service stability                                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │                              │
              ▼                              ▼
┌─────────────────────┐          ┌─────────────────────────────┐
│   S3 + CloudFront   │          │       ECS Cluster           │
│                     │          │                             │
│  index.html (new)   │          │  Task v23 running (new API) │
│  main.x9y8z7.js     │          │  Task v22 drained & stopped │
│  (new hash = new    │          │                             │
│   file to browser)  │          └─────────────────────────────┘
└─────────────────────┘
```

### 8.2 Jenkins Pipeline Script

```groovy
pipeline {
    agent any

    environment {
        AWS_REGION          = 'ap-south-1'
        ECR_REGISTRY        = '123456789.dkr.ecr.ap-south-1.amazonaws.com'
        ECR_REPO            = 'my-api'
        ECS_CLUSTER         = 'production-cluster'
        ECS_SERVICE         = 'my-api-service'
        S3_BUCKET           = 'my-frontend-prod'
        CLOUDFRONT_DIST_ID  = 'E1A2B3C4D5E6F7'
        IMAGE_TAG           = "${env.GIT_COMMIT[0..7]}"
    }

    stages {
        stage('Test') {
            parallel {
                stage('Frontend Tests') {
                    steps {
                        sh 'cd frontend && npm ci && npm test'
                    }
                }
                stage('Backend Tests') {
                    steps {
                        sh 'cd backend && ./gradlew test'
                    }
                }
            }
        }

        stage('Build Frontend') {
            steps {
                sh '''
                    cd frontend
                    npm ci
                    npm run build
                    echo "Build complete. Verifying hash in filenames..."
                    ls build/static/js/  # Should show hashed filenames
                '''
            }
        }

        stage('Deploy Frontend to S3') {
            steps {
                sh '''
                    # Upload hashed assets with long cache headers
                    aws s3 sync frontend/build/static/ s3://${S3_BUCKET}/static/ \
                        --cache-control "public, max-age=31536000, immutable" \
                        --delete \
                        --region ${AWS_REGION}

                    # Upload index.html with NO cache
                    aws s3 cp frontend/build/index.html s3://${S3_BUCKET}/index.html \
                        --cache-control "no-store, no-cache, must-revalidate" \
                        --content-type "text/html" \
                        --region ${AWS_REGION}

                    # Optional: Invalidate CloudFront for index.html
                    # (Only needed if CloudFront TTL is not already 0)
                    aws cloudfront create-invalidation \
                        --distribution-id ${CLOUDFRONT_DIST_ID} \
                        --paths "/index.html" \
                        --region ${AWS_REGION}
                '''
            }
        }

        stage('Build & Push Docker Image') {
            steps {
                sh '''
                    aws ecr get-login-password --region ${AWS_REGION} | \
                        docker login --username AWS --password-stdin ${ECR_REGISTRY}

                    docker build -t ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG} ./backend
                    docker push ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
                '''
            }
        }

        stage('Deploy to ECS') {
            steps {
                sh '''
                    # Register new task definition with new image tag
                    TASK_DEF=$(aws ecs describe-task-definition \
                        --task-definition my-api-task \
                        --query "taskDefinition" \
                        --output json)

                    NEW_TASK_DEF=$(echo $TASK_DEF | jq \
                        --arg IMG "${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}" \
                        '.containerDefinitions[0].image = $IMG |
                         del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)')

                    NEW_REVISION=$(aws ecs register-task-definition \
                        --cli-input-json "$NEW_TASK_DEF" \
                        --query "taskDefinition.taskDefinitionArn" \
                        --output text)

                    # Update service with new task definition
                    aws ecs update-service \
                        --cluster ${ECS_CLUSTER} \
                        --service ${ECS_SERVICE} \
                        --task-definition $NEW_REVISION \
                        --region ${AWS_REGION}

                    # Wait for deployment to complete
                    aws ecs wait services-stable \
                        --cluster ${ECS_CLUSTER} \
                        --services ${ECS_SERVICE} \
                        --region ${AWS_REGION}

                    echo "ECS deployment stable!"
                '''
            }
        }
    }

    post {
        success {
            echo "Deployment successful: Frontend on S3/CloudFront, Backend on ECS"
        }
        failure {
            echo "Deployment failed — check logs above"
        }
    }
}
```

---

## 9. DevOps Fix Checklist

```
MANDATORY (implement these before going to production):
────────────────────────────────────────────────────────
☐ Enable contenthash in Webpack / Vite build config
☐ Verify build output shows hashed filenames (ls build/static/js/)
☐ Set index.html Cache-Control: no-store on S3
☐ Set /static/* Cache-Control: max-age=31536000, immutable on S3
☐ Configure CloudFront behavior: index.html TTL = 0
☐ Configure CloudFront behavior: /static/* TTL = 1 year
☐ Verify CI/CD uploads index.html separately with no-cache header
☐ Test: deploy, check browser network tab, confirm new JS filename loaded

RECOMMENDED (greatly improves reliability):
────────────────────────────────────────────
☐ Add CloudFront invalidation for /index.html in CI/CD pipeline
☐ Use ECS deployment circuit breaker (auto-rollback on failure)
☐ Tag ECS task definitions with git commit SHA
☐ Add deployment verification step: smoke test after ECS stabilizes

ADVANCED (for high-traffic or regulated environments):
──────────────────────────────────────────────────────
☐ Set up CloudFront real-time logs to detect cache anomalies
☐ Implement version endpoint: GET /api/version returns git SHA
☐ Frontend checks version on load, prompts user to refresh if mismatch
☐ Use ECS Blue/Green deployment for zero-downtime rollouts
☐ Set up Canary releases (10% traffic to new version first)
```

---

## 10. Real-World Scenario Walkthrough

**Company:** A Bangalore-based fintech startup running a React + Spring Boot app on AWS.

**Problem:**

> "We deployed the new KYC form on Friday. ECS shows successful deployment. But Monday morning, 40% of users are calling support saying they see the old form."

**Investigation:**

```
Step 1: Check ECS
  ECS Service: ACTIVE, 2/2 tasks running, revision 47
  Result: ✓ New backend is running

Step 2: Check S3
  S3 browser: index.html last modified Friday 6:32 PM
  S3 browser: main.js last modified Friday 6:32 PM  ← SAME FILENAME!
  Result: ✗ Non-hashed JS files

Step 3: Check CloudFront
  CloudFront behavior for /static/*: TTL = 86400 (24 hours)
  Friday 6:32 PM + 24 hours = Saturday 6:32 PM
  Users on Monday: CloudFront served cached old main.js
  Result: ✗ Old JS served for 24+ hours after deployment

Step 4: Check Browser
  Network tab on support user's machine:
  main.js: 304 Not Modified (from browser disk cache)
  Result: ✗ Browser using 3-day-old cached JS
```

**What 100% of users with the problem had in common:** They had visited the site on Friday before the deployment, and their browser had cached the old `main.js`.

**Fix applied:**

1. Webpack updated to use `[contenthash:8]` in filenames
2. S3 upload script updated: hashed assets get `max-age=31536000`, `index.html` gets `no-store`
3. CloudFront behavior updated: `index.html` TTL = 0, `/static/*` TTL = 1 year
4. CloudFront invalidation added to CI/CD pipeline for `/index.html`

**Result:** Next deployment — zero support calls about old UI.

---

## 11. Invalidation Decision Tree

```
Q: Do I need CloudFront invalidation on every deployment?
│
├── Are you using content-hashed filenames for JS/CSS?
│   │
│   ├── YES
│   │   │
│   │   └── Is your index.html CloudFront TTL = 0 or very low?
│   │       │
│   │       ├── YES (TTL = 0 or Cache-Control: no-store on S3)
│   │       │   └── ✓ NO INVALIDATION NEEDED
│   │       │       Users always get fresh index.html
│   │       │       index.html references new hashed JS
│   │       │       Browser fetches new JS (unknown URL)
│   │       │
│   │       └── NO (TTL > 0 on index.html at CloudFront)
│   │           └── ✓ INVALIDATE /index.html ONLY
│   │               Cost: $0.005 per 1000 paths (cheap)
│   │               aws cloudfront create-invalidation --paths "/index.html"
│   │
│   └── NO (non-hashed JS/CSS filenames)
│       │
│       └── ✓ INVALIDATE EVERYTHING (and fix your build!)
│           aws cloudfront create-invalidation --paths "/*"
│           Cost: $0.005 per 1000 paths
│           ⚠ This causes a traffic spike to S3 as edge caches refill
│           ⚠ Users may see slower loads globally for 5-15 minutes
│           ⚠ Fix the root cause: enable content hashing
```

---

## 12. S3 Cache-Control Headers

Setting the right headers per file type is as important as the CloudFront configuration.

### 12.1 AWS CLI Commands

```bash
# Upload index.html with NO cache
aws s3 cp build/index.html s3://my-bucket/index.html \
    --cache-control "no-store, no-cache, must-revalidate, proxy-revalidate" \
    --content-type "text/html; charset=utf-8"

# Upload hashed JS files with LONG cache (1 year, immutable)
aws s3 sync build/static/js/ s3://my-bucket/static/js/ \
    --cache-control "public, max-age=31536000, immutable" \
    --content-type "application/javascript"

# Upload hashed CSS files
aws s3 sync build/static/css/ s3://my-bucket/static/css/ \
    --cache-control "public, max-age=31536000, immutable" \
    --content-type "text/css"

# Upload images (1 week if not hashed, 1 year if hashed)
aws s3 sync build/assets/ s3://my-bucket/assets/ \
    --cache-control "public, max-age=604800"
```

### 12.2 What Users See in Browser Network Tab

**Before fix (problem state):**

```
Request URL: https://app.mycompany.com/static/js/main.js
Status: 304 Not Modified
From: disk cache
Response Headers:
  Cache-Control: public, max-age=86400
  Last-Modified: Fri, 01 Nov 2024 18:32:00 GMT
                                     ↑
                    3-day-old file served from cache!
```

**After fix (correct state):**

```
Request URL: https://app.mycompany.com/static/js/main.8f3a91bc.js
Status: 200 OK
From: network (or CloudFront edge, but not stale)
Response Headers:
  Cache-Control: public, max-age=31536000, immutable
  ETag: "8f3a91bc..."
  ↑
  New hash in URL = browser never had this, fetches fresh copy
```

---

## 13. ECS Task Definition Versioning

ECS task definitions are automatically versioned. Understanding this prevents rollback confusion.

### 13.1 Task Definition Revision Flow

```
Initial state:
  my-api-task:1  (image: api:abc123)   ← deployed 3 months ago
  my-api-task:2  (image: api:def456)   ← deployed 2 months ago
  my-api-task:3  (image: api:ghi789)   ← deployed last week
  my-api-task:4  (image: api:jkl012)   ← CURRENT

ECS Service:
  my-api-service → running task definition: my-api-task:4
```

### 13.2 Deployment Process Inside ECS

```
ECS Rolling Update (default):

Initial state:
  ┌──────────┐  ┌──────────┐
  │ Task v3  │  │ Task v3  │  (old version, serving traffic)
  └──────────┘  └──────────┘

Step 1: Launch new tasks (task definition v4)
  ┌──────────┐  ┌──────────┐
  │ Task v3  │  │ Task v3  │  (still serving)
  │ Task v4  │  │ Task v4  │  (starting up)
  └──────────┘  └──────────┘

Step 2: Health check passes for new tasks
  ALB: New tasks added to target group

Step 3: Drain old tasks
  ┌──────────┐  ┌──────────┐
  │ Task v3  │  │ Task v3  │  (draining — no new connections)
  │ Task v4  │  │ Task v4  │  (serving traffic)
  └──────────┘  └──────────┘

Step 4: Old tasks stopped
  ┌──────────┐  ┌──────────┐
  │ Task v4  │  │ Task v4  │  (only new version running)
  └──────────┘  └──────────┘

ECS console shows: "DEPLOYMENT COMPLETED" ← This is the green tick you see
```

### 13.3 ECS Blue/Green Deployment (Zero Downtime)

For production systems that can't tolerate any downtime or serving mixed versions:

```
Blue/Green with CodeDeploy:

BLUE (current production):         GREEN (new version):
┌──────────────────────┐           ┌──────────────────────┐
│  ECS Task v3 × 4     │           │  ECS Task v4 × 4     │
│  ALB: Production LB  │           │  ALB: Test LB (5%?)  │
└──────────────────────┘           └──────────────────────┘

Phase 1 (shift 10%):   Blue: 90%, Green: 10%
Phase 2 (shift 50%):   Blue: 50%, Green: 50%
Phase 3 (full shift):  Blue: 0%,  Green: 100%
Phase 4 (cleanup):     Blue tasks drained and deleted

If green fails health checks → instant rollback to blue
```

---

## 14. Debugging Steps in Production

When you encounter "deployment succeeded but users see old version":

### Step-by-Step Debug Flow

```
1. Confirm which version the USER's browser is loading:
   ─────────────────────────────────────────────────────
   Open browser DevTools → Network tab → reload page
   Look at index.html response:
     ├── What JS filenames does it reference?
     └── Is the Cache-Control header "no-store" or has a max-age?

2. Confirm what S3 contains:
   ─────────────────────────────────────────────────────
   aws s3 ls s3://my-bucket/static/js/
   ├── Do you see hashed filenames?
   └── What's the Last-Modified timestamp?

3. Confirm what CloudFront is serving:
   ─────────────────────────────────────────────────────
   curl -I https://app.mycompany.com/index.html
   Look at:
     ├── X-Cache: Hit from cloudfront  (cached!) vs  Miss from cloudfront (fresh)
     ├── Age: 3600  (seconds the object has been cached)
     └── Cache-Control header (what your S3 sends)

4. Confirm ECS is running new version:
   ─────────────────────────────────────────────────────
   curl https://app.mycompany.com/api/version
   → {"version": "git-abc12345", "deployedAt": "2024-11-15T18:32:00Z"}

5. Invalidate if stuck:
   ─────────────────────────────────────────────────────
   aws cloudfront create-invalidation \
       --distribution-id E1A2B3C4D5E6F7 \
       --paths "/index.html" "/static/*"
   Wait 2–5 minutes, re-check.
```

### Useful Curl Commands

```bash
# Check what CloudFront is serving for index.html
curl -I https://app.mycompany.com/index.html

# Expected response headers:
# HTTP/2 200
# cache-control: no-store, no-cache        ← Good
# x-cache: Miss from cloudfront            ← Fetched from S3, not cached
# content-type: text/html; charset=utf-8

# Check a hashed JS file
curl -I https://app.mycompany.com/static/js/main.8f3a91bc.js

# Expected:
# HTTP/2 200
# cache-control: public, max-age=31536000, immutable  ← Good
# x-cache: Hit from cloudfront                         ← Cached = fast
```

---

## 15. Interview-Ready Explanation

### Short Answer (30 seconds)

> "ECS deployment success only confirms that backend containers were replaced. If users still see old UI, the issue is almost always in the caching layers — specifically CloudFront serving a cached `index.html` that still references old JS files. The root fix is content hashing: every build produces JS/CSS with unique filenames based on file contents. This means every deploy creates new filenames, and both browser and CDN caches automatically fetch the new files without any invalidation. Additionally, `index.html` must have a zero or no-cache TTL at CloudFront, since it's the entry point that controls which JS version loads."

---

### Full Technical Answer (2 minutes)

> "This is a layered caching problem. When we deploy to ECS, we're only updating the backend API containers. The frontend (React/Vue) is served from S3 via CloudFront and is completely separate from ECS.
>
> There are three common root causes. First, CloudFront may have cached the old `index.html`. Since `index.html` references the JS and CSS files by filename, if it's stale, it loads old code even when S3 has the new version. Second, if JS filenames don't include a content hash — like `main.js` instead of `main.8f3a91bc.js` — both CloudFront and the browser cache the old file and see no reason to fetch again. Third, browsers themselves cache aggressively based on `Cache-Control` headers.
>
> The correct solution has two parts. For assets (JS, CSS, images), we use content hashing in our Webpack or Vite build config. Every file change produces a unique filename, so caches always treat it as a new file — no invalidation needed. For `index.html`, we set `Cache-Control: no-store` on the S3 object and configure CloudFront to never cache it (TTL = 0). With this setup, every user always gets a fresh `index.html` pointing to the latest hashed assets.
>
> In our CI/CD pipeline, we upload hashed assets to S3 with a one-year cache header, upload `index.html` with a no-cache header, and optionally run a CloudFront invalidation for `/index.html` as a safety net. This gives us zero cache-related production issues with no manual intervention."

---

### Key Quote

```
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║  "Production issues are not always deployment failures —             ║
║   most of the time they are caching and architecture                 ║
║   design issues."                                                    ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## Summary: The Three Rules

```
Rule 1: Hash everything (JS, CSS, assets)
        Filename change = automatic cache busting
        No hash = cache never busts automatically

Rule 2: Never cache index.html at CloudFront
        It controls your app version
        One stale index.html = all users see old version

Rule 3: ECS success ≠ user experience success
        Monitor all cache layers, not just ECS
        Add a /api/version endpoint to verify backend version
        Check browser network tab to verify frontend version
```

---

*Last updated: June 2026 | For AWS DevOps and frontend engineering teams*
