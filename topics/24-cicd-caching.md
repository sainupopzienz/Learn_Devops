# Making CI/CD Faster with Cache

### Docker Layer Cache — Order Matters
```dockerfile
# GOOD — rarely changing layers first
COPY package.json package-lock.json ./
RUN npm install          # cached if unchanged
COPY . .                 # only this busts cache
RUN npm run build
```

### GitHub Actions Cache
```yaml
- uses: actions/cache@v3
  with:
    path: ~/.npm
    key: npm-${{ hashFiles('package-lock.json') }}

- uses: actions/cache@v3
  with:
    path: ~/.m2              # Maven
    key: maven-${{ hashFiles('pom.xml') }}
```

### Docker BuildKit Registry Cache
```bash
docker buildx build \
  --cache-from type=registry,ref=ecr/myapp:cache \
  --cache-to   type=registry,ref=ecr/myapp:cache,mode=max \
  -t ecr/myapp:$GIT_SHA .
```

### Other Speed Wins
- **Parallel stages** — run test + lint simultaneously
- **Smaller base images** — alpine/distroless pull faster
- **Self-hosted runners** — no cold start time
- **Monorepo path filters** — skip unchanged services
- **Incremental builds** — Nx, Turborepo for JS monorepos
