# MinIO Object Storage

## Overview

MinIO is a high-performance, S3-compatible object storage server designed for cloud-native workloads. It can run on-premises, in containers, or alongside Kubernetes.

---

## Installation

### Docker (Quickstart)

```bash
docker run -d \
  -p 9000:9000 \
  -p 9001:9001 \
  --name minio \
  -e "MINIO_ROOT_USER=admin" \
  -e "MINIO_ROOT_PASSWORD=password123" \
  -v /data/minio:/data \
  quay.io/minio/minio server /data --console-address ":9001"
```

- API endpoint: `http://localhost:9000`
- Web Console: `http://localhost:9001`

### Binary (Linux)

```bash
wget https://dl.min.io/server/minio/release/linux-amd64/minio
chmod +x minio
export MINIO_ROOT_USER=admin
export MINIO_ROOT_PASSWORD=password123
./minio server /data --console-address ":9001"
```

---

## MinIO Client (`mc`)

### Install

```bash
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/
```

### Configure an Alias

```bash
mc alias set local http://localhost:9000 admin password123
```

### Common Commands

| Command | Description |
|---|---|
| `mc mb local/mybucket` | Create a bucket |
| `mc ls local/` | List buckets |
| `mc cp file.txt local/mybucket/` | Upload a file |
| `mc cp local/mybucket/file.txt .` | Download a file |
| `mc rm local/mybucket/file.txt` | Delete a file |
| `mc mirror ./folder local/mybucket` | Sync a directory |
| `mc admin info local` | Server info |

---

## Bucket Policies

### Make a Bucket Public (read-only)

```bash
mc anonymous set download local/mybucket
```

### Custom Policy (JSON)

```bash
mc anonymous set-json policy.json local/mybucket
```

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": ["s3:GetObject"],
      "Resource": ["arn:aws:s3:::mybucket/*"]
    }
  ]
}
```

---

## Python SDK (boto3)

MinIO is S3-compatible, so `boto3` works out of the box.

```python
import boto3

s3 = boto3.client(
    "s3",
    endpoint_url="http://localhost:9000",
    aws_access_key_id="admin",
    aws_secret_access_key="password123",
)

# Create bucket
s3.create_bucket(Bucket="mybucket")

# Upload
s3.upload_file("file.txt", "mybucket", "file.txt")

# Download
s3.download_file("mybucket", "file.txt", "downloaded.txt")

# List objects
for obj in s3.list_objects(Bucket="mybucket").get("Contents", []):
    print(obj["Key"])
```

---

## Python SDK (minio-py)

```bash
pip install minio
```

```python
from minio import Minio

client = Minio(
    "localhost:9000",
    access_key="admin",
    secret_key="password123",
    secure=False,
)

# Upload
client.fput_object("mybucket", "file.txt", "/local/path/file.txt")

# Download
client.fget_object("mybucket", "file.txt", "/local/path/downloaded.txt")

# Generate presigned URL (1 hour)
url = client.presigned_get_object("mybucket", "file.txt", expires=3600)
print(url)
```

---

## Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: quay.io/minio/minio:latest
        args: ["server", "/data", "--console-address", ":9001"]
        env:
        - name: MINIO_ROOT_USER
          value: "admin"
        - name: MINIO_ROOT_PASSWORD
          value: "password123"
        ports:
        - containerPort: 9000
        - containerPort: 9001
        volumeMounts:
        - mountPath: /data
          name: storage
      volumes:
      - name: storage
        emptyDir: {}
```

---

## Environment Variables

| Variable | Description |
|---|---|
| `MINIO_ROOT_USER` | Root access key (min 3 chars) |
| `MINIO_ROOT_PASSWORD` | Root secret key (min 8 chars) |
| `MINIO_VOLUMES` | Storage path(s) |
| `MINIO_SITE_NAME` | Human-readable site name |
| `MINIO_BROWSER` | Enable/disable web console (`on`/`off`) |
| `MINIO_DOMAIN` | Enable virtual-hosted-style buckets |

---

## TLS / HTTPS

Place your certs at:

```
~/.minio/certs/
  public.crt
  private.key
```

Or set via flags:

```bash
./minio server /data \
  --certs-dir /etc/minio/certs \
  --console-address ":9001"
```

---

## Versioning

```bash
# Enable versioning on a bucket
mc version enable local/mybucket

# List all versions of an object
mc ls --versions local/mybucket/file.txt
```

---

## Useful Ports

| Port | Purpose |
|---|---|
| `9000` | S3 API |
| `9001` | Web Console (default) |

---

## Tips

- MinIO is fully S3-compatible — any AWS SDK works by pointing `endpoint_url` to your MinIO host.
- For distributed/HA setups, use **MinIO Operator** on Kubernetes or run 4+ nodes with erasure coding.
- Presigned URLs let you share objects securely without exposing credentials.
- Use `mc mirror` for efficient bucket-to-bucket or local-to-bucket syncs.
