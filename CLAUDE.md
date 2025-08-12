# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a proof-of-concept project demonstrating DigitalOcean App Platform integration with AWS services. The architecture consists of:

- **FastAPI backend** (`app/main.py`) running on DigitalOcean App Platform
- **Static JavaScript frontend** (`frontend/`) hosted on DigitalOcean Spaces
- **PostgreSQL and Valkey databases** via DigitalOcean DBaaS
- **Terraform infrastructure** (`terraform/main.tf`) for deployment
- **Docker containerization** for the FastAPI application

The project follows a phased implementation approach as outlined in `dev/project.md`, integrating DigitalOcean services with AWS services including CloudFront with WAF, IAM Roles Anywhere for certificate-based authentication, Secrets Manager, and a worker service for continuous data updates.

## Development Commands

### Container Operations
- `make build` - Build Docker image with timestamped tag
- `make push` - Push image to DigitalOcean Container Registry
- `make docr-login` - Authenticate with DO Container Registry

### Infrastructure Management
- `make plan` - Run Terraform plan with current image tag
- `make apply` - Deploy infrastructure via Terraform
- `make destroy` - Destroy all Terraform-managed resources
- `make deploy` - Full deployment pipeline (login, build, push, apply)

### Credentials
This is a development environment, so its OK to use the make commands to make anything except destroy. The credentials needed to interact with the dev environment can be found in scratch/env.sh.

### Running the Application Locally
```bash
cd app
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8080
```

## Architecture Details

### Application Structure
- **Backend**: FastAPI service with health checks and database connectivity endpoints
  - `/healthz` - Basic liveness check
  - `/db/status` - PostgreSQL and Valkey connection status with read/write tests and timestamps
  - `/iam/status` - AWS IAM Roles Anywhere authentication status and role information
  - `/secret/status` - AWS Secrets Manager connectivity and secret retrieval
  - `/worker/status` - Aggregated timestamp status from worker service updates
- **Worker Service**: Continuous data update service that updates timestamps every minute across all integrated services
- **Frontend**: Vanilla JavaScript SPA that calls backend APIs and displays real-time status of all integrated services
- **Databases**: PostgreSQL for relational data, Valkey (Redis-compatible) for caching

### Environment Configuration
The App Platform service receives database connection details via environment variables automatically injected from the attached DigitalOcean database clusters:
- PostgreSQL: `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`, `PGSSLMODE`
- Valkey: `VALKEY_HOST`, `VALKEY_PORT`, `VALKEY_PASSWORD`
- CORS: `API_CORS_ORIGINS` (set to CloudFront distribution URL)
- AWS IAM Roles Anywhere: `IAM_CA_CERT`, `IAM_CLIENT_CERT`, `IAM_CLIENT_KEY`, `IAM_TRUST_ANCHOR_ARN`, `IAM_PROFILE_ARN`, `IAM_ROLE_ARN`
- AWS Configuration: `AWS_REGION`, `SECRETS_MANAGER_SECRET_NAME`

### Infrastructure as Code
All resources are managed via Terraform in `terraform/main.tf`:
- DigitalOcean Project (`jkeegan`) contains all resources
- App Platform service with API and worker components from DO Container Registry
- PostgreSQL and Valkey database clusters
- Spaces bucket for frontend static assets
- CloudFront distribution with custom domain (`poc-app-platform-aws.digitalocean.solutions`)
- AWS WAF Web ACL integrated with CloudFront
- AWS IAM Roles Anywhere infrastructure (trust anchor, profile, role)
- AWS Secrets Manager secret for demonstration
- X.509 certificates for IAM Roles Anywhere authentication
- All resources tagged with `jkeegan` and deployed to `sfo3` (DO) and `us-west-2` (AWS) regions

### Container Registry
Uses DigitalOcean Container Registry (`do-solutions-sfo3`) with automatic timestamped image tags in format `v1.YYYYMMDD.HHMMSS`.

## Project Guidelines

### Deployment Workflow
1. All deployments use Terraform for reproducibility
2. Container images are built and pushed to DOCR before infrastructure deployment
3. Frontend assets are uploaded to Spaces bucket as Terraform objects
4. Database credentials are injected as environment variables, not hardcoded
5. X.509 certificates for AWS IAM Roles Anywhere are generated via Terraform
6. Worker service runs continuously to update timestamps across all integrated services

### Development Standards
- Follow the phased implementation approach outlined in `dev/project.md`
- Use the `sfo3` region for DigitalOcean resources and `us-west-2` for AWS resources
- Tag all resources with `jkeegan` 
- Maintain infrastructure idempotency
- Database connection testing includes write/read verification for PostgreSQL and SET/GET for Valkey
- Real-time timestamp tracking demonstrates continuous data flow across all services
- Certificate-based authentication for AWS services via IAM Roles Anywhere

### Implementation Status
The project has completed all 6 phases as outlined in `dev/project.md`:
- **Phase 1**: Foundation DigitalOcean infrastructure ✅
- **Phase 2**: FastAPI backend with database connectivity ✅
- **Phase 3**: AWS WAF integration via CloudFront ✅
- **Phase 4**: AWS IAM Roles Anywhere authentication ✅
- **Phase 5**: AWS Secrets Manager integration ✅
- **Phase 6**: Worker service for continuous data updates ✅

The project demonstrates a complete integration between DigitalOcean App Platform and selective AWS services while maintaining the core infrastructure on DigitalOcean.