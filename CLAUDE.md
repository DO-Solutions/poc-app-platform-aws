# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a hybrid cloud PoC demonstrating DigitalOcean App Platform integration with AWS services. It showcases cost-effective architecture using DigitalOcean for core infrastructure (databases, compute) while leveraging specific AWS services (CloudFront, IAM Roles Anywhere, Secrets Manager) for enhanced security and global CDN.

## Architecture

**Core Stack:**
- **DigitalOcean**: App Platform (containerized FastAPI app), PostgreSQL, Valkey (Redis-compatible), Spaces (object storage)
- **AWS**: CloudFront + WAF (global CDN with DDoS protection), IAM Roles Anywhere (certificate-based auth), Secrets Manager
- **Infrastructure**: Terraform for Infrastructure as Code
- **Application**: Python FastAPI with worker service for real-time monitoring
- **Live Demo**: https://poc-app-platform-aws.digitalocean.solutions

**Key Integration Pattern:**
- X.509 certificate-based authentication to AWS (no API keys stored)
- Hybrid deployment where core infrastructure stays on DO, selective AWS services for specialized capabilities
- Real-time status dashboard showing all service integrations

## Development Commands
### Deployment Pipeline
```bash
# Full deployment (login, build, push, apply)
make deploy

# Individual steps
make docr-login    # Login to DigitalOcean Container Registry
make build         # Build Docker image with timestamp tag
make push          # Push to DOCR
make plan          # Terraform plan
make apply         # Terraform apply
make destroy       # Destroy all resources (use with caution)
```

### Local Development
```bash
# Run API locally
cd app
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8080

# Run worker service locally (separate terminal)
python worker.py

# Test container locally
make build
docker run -p 8080:8080 --env-file .env registry.digitalocean.com/do-solutions-sfo3/poc-app-platform-aws:latest
```

### Testing and Validation
```bash
# Test WAF rate limiting (sends parallel requests until blocked - shows 403 errors)
./test-waf.sh

# Test WAF with help
./test-waf.sh -h

# Manual API testing
curl https://poc-app-platform-aws.digitalocean.solutions/healthz
curl https://poc-app-platform-aws.digitalocean.solutions/db/status
curl https://poc-app-platform-aws.digitalocean.solutions/iam/status
curl https://poc-app-platform-aws.digitalocean.solutions/secret/status
curl https://poc-app-platform-aws.digitalocean.solutions/worker/status
```

### Infrastructure Management
```bash
# Check Terraform state
terraform -chdir=terraform show

# Verify DigitalOcean resources
doctl projects resources list --project-id <project-id>
doctl apps list
doctl databases list
doctl apps logs <app-id> --component api-svc --follow
doctl apps logs <app-id> --component timestamp-worker --follow

# Verify AWS resources
aws cloudfront list-distributions
aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1
aws rolesanywhere list-trust-anchors
aws secretsmanager list-secrets
```

### Infrastructure-Only Updates (without rebuilding Docker image)

When making changes to Spaces, CloudFront, or other infrastructure without code changes, you can run terraform operations using the current deployed image tag:

```bash
# Get the current image tag from the running app
CURRENT_TAG=$(doctl app spec get <app-id> | jq -r '.services[0].image.tag')

# Run terraform apply with current image (no rebuild needed)
export AWS_ACCESS_KEY_ID=$SPACES_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$SPACES_SECRET_ACCESS_KEY
terraform -chdir=terraform apply -var="image_tag=$CURRENT_TAG" -var="aws_access_key_id=$AWS_REAL_ACCESS_KEY_ID" -var="aws_secret_access_key=$AWS_REAL_SECRET_ACCESS_KEY"

# Or using make with current tag
make apply IMAGE_TAG=$CURRENT_TAG

# Get app ID if needed
doctl apps list  # Find your app ID from the output
```

**Use Cases:**
- Updating CloudFront distribution settings
- Modifying Spaces bucket configuration
- Changing WAF rules or rate limits
- Adding/removing AWS resources
- Any Terraform changes that don't require new application code

## Environment Variables

Required for deployment (see `scratch/env.sh` for development template):
- `DIGITALOCEAN_ACCESS_TOKEN`: DigitalOcean API token
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`: AWS credentials for AWS providers
- `SPACES_ACCESS_KEY_ID`, `SPACES_SECRET_ACCESS_KEY`: DigitalOcean Spaces credentials for terraform backend

**CLI Tools Setup:**
Both `doctl` (DigitalOcean CLI) and `aws` (AWS CLI) are available for troubleshooting and inspection. Before using these tools or running terraform commands, source the environment file:

```bash
# Load all required credentials
source scratch/env.sh

# Use CLI tools for READ-ONLY troubleshooting and inspection
doctl apps list
doctl apps logs <app-id> --component api-svc
aws cloudfront list-distributions
aws s3 ls
terraform -chdir=terraform show
```

**⚠️ IMPORTANT**: CLI tools should **ONLY** be used for reading and understanding current state. **ALL CHANGES** must be made through Terraform to ensure the environment can be reproduced via `make deploy`. Do not use CLI tools to modify resources directly.

**⚠️ SECURITY WARNING**: The `scratch/env.sh` file contains sensitive credentials and should **NEVER** be committed to git. Ensure it's in `.gitignore` and never share its contents.

**Important**: The project uses DigitalOcean Spaces as the Terraform state backend, which creates a complex credential management pattern:

**Credential Separation Pattern:**
- **Terraform Backend (Spaces)**: Uses `SPACES_ACCESS_KEY_ID` and `SPACES_SECRET_ACCESS_KEY` as environment variables
- **AWS Provider**: Uses `aws_access_key_id` and `aws_secret_access_key` as Terraform variables (NOT environment variables)

**Why This Matters:**
The Terraform AWS provider configuration at `terraform/terraform.tf:53-77` shows two AWS providers that get credentials via Terraform variables, while the Spaces backend gets credentials via environment variables. This means:

```bash
# ❌ WRONG - This won't work because AWS credentials would override Spaces backend access
export AWS_ACCESS_KEY_ID="aws-key"
export AWS_SECRET_ACCESS_KEY="aws-secret"
terraform apply

# ✅ CORRECT - Manual terraform commands need this pattern:
export AWS_ACCESS_KEY_ID="spaces-key"
export AWS_SECRET_ACCESS_KEY="spaces-secret"
terraform apply -var="aws_access_key_id=real-aws-key" -var="aws_secret_access_key=real-aws-secret"
```

The Makefile handles this automatically by temporarily setting the environment variables to Spaces credentials for the backend, then passing real AWS credentials as Terraform variables.

## Key Files and Structure

- `/app/`: FastAPI application with main.py (API endpoints), worker.py (background service), iam_anywhere.py (AWS auth)
- `/terraform/`: Infrastructure as Code - separate files for each service layer
- `/frontend/`: Static assets served via Spaces + CloudFront
- `/test-waf.sh`: Script to test AWS WAF rate limiting protection
- `Makefile`: Deployment automation with docker build/push and terraform operations

## Important Implementation Details

**AWS IAM Roles Anywhere Integration:**
- Uses X.509 certificates for AWS authentication (no static credentials)
- Self-signed certificates for PoC (production should use proper CA)
- Certificate-based authentication pattern eliminates credential management

**Worker Service Pattern:**
- Background service updates timestamps every 60 seconds
- Demonstrates continuous integration health monitoring
- Updates PostgreSQL, Valkey, and AWS Secrets Manager timestamps

**Hybrid Cloud Security:**
- All database connections use SSL/TLS
- CloudFront provides DDoS protection and rate limiting (100 requests/5min)
- CORS configured for custom domain only
- All HTTP traffic redirected to HTTPS

## Testing Strategy

The project includes comprehensive validation:
1. **Infrastructure Health**: Terraform state and resource verification
2. **Service Integration**: API endpoint testing for each service
3. **Real-time Monitoring**: Worker service timestamp updates every 60s
4. **Security Testing**: WAF rate limiting with automated test script
5. **Certificate Validation**: X.509 authentication flow testing

**Note**: This is a PoC environment - the self-signed certificates and minimal resource allocation are intentional for demonstration and cost optimization.