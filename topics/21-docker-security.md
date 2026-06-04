# Securing Docker Deployments

### 10 Security Practices

| # | Practice | Details |
|---|---------|---------|
| 1 | Minimal base images | alpine or distroless — smaller attack surface |
| 2 | Non-root user | `USER appuser` in Dockerfile |
| 3 | No secrets in image | Use Secrets Manager at runtime |
| 4 | Image scanning | Trivy/Snyk in CI — fail on CRITICAL |
| 5 | Read-only filesystem | `readOnlyRootFilesystem: true` |
| 6 | Drop capabilities | `capabilities: drop: ["ALL"]` |
| 7 | No privileged | `privileged: false` always |
| 8 | Specific tags | Never `latest` in prod — use git SHA |
| 9 | Sign images | cosign (sigstore) for integrity |
| 10 | Private registry | ECR with IAM — not public Docker Hub |

### Dockerfile Example
```dockerfile
FROM node:20-alpine
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
USER app
EXPOSE 3000
CMD ["node", "server.js"]
```
