# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a proof-of-concept project demonstrating DigitalOcean App Platform integration with AWS services. The architecture consists of:

- **FastAPI backend** (`app/main.py`) running on DigitalOcean App Platform
- **Static JavaScript frontend** (`frontend/`) hosted on DigitalOcean Spaces
- **PostgreSQL and Valkey databases** via DigitalOcean DBaaS
- **Terraform infrastructure** (`terraform/main.tf`) for deployment
- **Docker containerization** for the FastAPI application

The project follows a phased implementation approach as outlined in `DEV.md`, integrating DigitalOcean services with selective AWS services (WAF via CloudFront, Secrets Manager via IAM Roles Anywhere).

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
  - `/db/status` - PostgreSQL and Valkey connection status with read/write tests
- **Frontend**: Vanilla JavaScript SPA that calls backend APIs and displays database status
- **Databases**: PostgreSQL for relational data, Valkey (Redis-compatible) for caching

### Environment Configuration
The App Platform service receives database connection details via environment variables automatically injected from the attached DigitalOcean database clusters:
- PostgreSQL: `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`, `PGSSLMODE`
- Valkey: `VALKEY_HOST`, `VALKEY_PORT`, `VALKEY_PASSWORD`
- CORS: `API_CORS_ORIGINS` (set to Spaces bucket URL)

### Infrastructure as Code
All resources are managed via Terraform in `terraform/main.tf`:
- DigitalOcean Project (`jkeegan`) contains all resources
- App Platform service with container from DO Container Registry
- PostgreSQL and Valkey database clusters
- Spaces bucket for frontend static assets with CORS configuration
- All resources tagged with `jkeegan` and deployed to `sfo3` region

### Container Registry
Uses DigitalOcean Container Registry (`do-solutions-sfo3`) with automatic timestamped image tags in format `v1.YYYYMMDD.HHMMSS`.

## Project Guidelines

### Deployment Workflow
1. All deployments use Terraform for reproducibility
2. Container images are built and pushed to DOCR before infrastructure deployment
3. Frontend assets are uploaded to Spaces bucket as Terraform objects
4. Database credentials are injected as environment variables, not hardcoded

### Development Standards
- Follow the phased approach outlined in `DEV.md`
- Use the `sfo3` region for DigitalOcean resources
- Tag all resources with `jkeegan` 
- Maintain infrastructure idempotency
- Database connection testing includes write/read verification for PostgreSQL and SET/GET for Valkey

### Future Phases
The project is designed to integrate AWS WAF via CloudFront (Phase 3) and AWS Secrets Manager via IAM Roles Anywhere (Phase 4) while maintaining the core DigitalOcean infrastructure.