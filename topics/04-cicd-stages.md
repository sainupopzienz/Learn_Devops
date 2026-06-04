# CI/CD Stages

### Full Pipeline
```
1.  Code Commit / PR
2.  Lint & Static Analysis   (ESLint, SonarQube)
3.  Unit Tests
4.  Build                    (Docker image / JAR)
5.  Image Scan               (Trivy / Snyk)
6.  Push to Registry         (ECR / DockerHub)
7.  Deploy to Dev            (auto)
8.  Integration / Smoke Tests
9.  Deploy to Staging        (auto or manual)
10. E2E Tests
11. Manual Approval Gate     (for prod)
12. Deploy to Production     (Blue/Green or Rolling)
13. Post-deploy health checks
```

### Tools

| Stage | Tool Options |
|-------|-------------|
| CI Runner | GitHub Actions, GitLab CI, Jenkins |
| Image Scan | Trivy, Snyk, Grype |
| Registry | ECR, DockerHub, GHCR |
| Deploy | ArgoCD, Helm, kubectl |
| Notify | Slack, PagerDuty |
