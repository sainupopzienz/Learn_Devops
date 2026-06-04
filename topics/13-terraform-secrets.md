# Storing Terraform Secrets in CI/CD

### Rules
- Never hardcode secrets in .tf files or .tfvars committed to git
- Use CI/CD environment variables

### GitHub Actions Example
```yaml
env:
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  TF_VAR_db_password: ${{ secrets.DB_PASSWORD }}
```

### Better — OIDC (No Static Keys)
```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789:role/github-actions
    aws-region: us-east-1
```

### Secrets Manager Data Source
```hcl
data "aws_secretsmanager_secret_version" "db" {
  secret_id = "prod/db/password"
}

resource "aws_db_instance" "main" {
  password = data.aws_secretsmanager_secret_version.db.secret_string
}
```
