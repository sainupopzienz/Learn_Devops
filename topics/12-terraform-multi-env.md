# Managing Multiple Environments in Terraform

### Approach 1 — Workspaces
```bash
terraform workspace new dev
terraform workspace new prod
terraform workspace select prod
terraform apply -var-file=prod.tfvars
```
- Same code, different state files
- Problem: Easy to apply to wrong workspace

### Approach 2 — Separate Folders (Recommended)
```
environments/
  dev/
    main.tf         ← calls shared modules
    terraform.tfvars
    backend.tf      ← S3 key: "dev/terraform.tfstate"
  prod/
    main.tf
    terraform.tfvars
    backend.tf      ← S3 key: "prod/terraform.tfstate"
```
- Completely isolated state per environment
- Safer — can't accidentally run prod plan from dev
- **Standard for production setups**

> **Workspaces:** fine for small projects. **Separate folders:** use for real production.
