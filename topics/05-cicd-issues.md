# Issues Faced in CI/CD

### Common Issues & Fixes

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Flaky tests | Intermittent failures | Retries + isolated test envs |
| Docker cache miss | Wrong layer order | Reorder COPY/RUN in Dockerfile |
| Secrets in logs | Hardcoded secrets | Mask in pipeline env vars |
| Long build times | Sequential stages | Parallel stages + caching |
| Race condition | Two pipelines deploying | Pipeline locks |
| Wrong image tag | Using 'latest' | git SHA as image tag |
| Terraform state lock | Failed apply | Manually release DynamoDB lock |
| ECR push failing | Missing IAM permission | Add ecr:PutImage to role |

### Dockerfile Layer Fix
```dockerfile
# GOOD — put rarely changing layers first
COPY package.json package-lock.json ./
RUN npm install          # cached if package.json unchanged
COPY . .                 # only this busts cache on code change
RUN npm run build
```
