# Terraform Pipeline — Dev & Production

### Folder Structure
```
environments/
  dev/
    main.tf
    variables.tf
    terraform.tfvars
    backend.tf
  staging/
  prod/
    main.tf
    terraform.tfvars
    backend.tf
modules/
  vpc/, eks/, rds/, alb/
```

### Pipeline Flow
```
PR Raised
  → terraform fmt --check
  → terraform validate
  → terraform plan  (posted as PR comment)
PR Approved + Merged
  → terraform apply
```

### Rules
- **Dev pipeline:** plan + auto apply on merge
- **Prod pipeline:** plan → manual approval gate → apply
- State: Separate S3 bucket + DynamoDB lock per environment
- Tools: GitHub Actions / GitLab CI + S3 backend
