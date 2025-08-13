# Deployment Guide

This guide contains all technical details for deploying the PoC App Platform AWS Integration project.

## Prerequisites

1. DigitalOcean account with API token
2. AWS account with programmatic access
3. Access to `digitalocean.solutions` domain for DNS management
4. Terraform >= 1.0
5. Docker for local development (optional)

## Environment Setup

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd poc-app-platform-aws
   ```

2. **Set environment variables** (you can source `scratch/env.sh` for development):
   ```bash
   export DIGITALOCEAN_ACCESS_TOKEN="your-do-token"
   export AWS_ACCESS_KEY_ID="your-aws-key"
   export AWS_SECRET_ACCESS_KEY="your-aws-secret"
   export SPACES_ACCESS_KEY_ID="your-spaces-key"
   export SPACES_SECRET_ACCESS_KEY="your-spaces-secret"
   ```

## Deployment Commands

The project uses Make for all deployment operations:

1. **Full Deployment Pipeline**:
   ```bash
   make deploy
   ```
   This command:
   - Authenticates with DigitalOcean Container Registry
   - Builds the application container with timestamp tag
   - Pushes the image to DOCR
   - Runs `terraform apply` to deploy all infrastructure

2. **Individual Operations**:
   ```bash
   # Build container image
   make build
   
   # Push to container registry
   make push
   
   # Plan infrastructure changes
   make plan
   
   # Apply infrastructure changes
   make apply
   
   # Destroy all resources (use with caution)
   make destroy
   ```

## Deployment Process

The deployment creates the following resources:

**DigitalOcean Resources**:
- Project: `jkeegan` (resource organization)
- PostgreSQL cluster: `poc-app-platform-aws-postgres-db`
- Valkey cluster: `poc-app-platform-aws-valkey-db`
- Spaces bucket: `poc-app-platform-aws-frontend-space`
- App Platform app: `poc-app-platform-aws`

**AWS Resources**:
- CloudFront distribution with custom domain
- WAF WebACL with rate limiting
- ACM certificate for SSL/TLS
- IAM Roles Anywhere trust anchor, profile, and role
- Secrets Manager secret: `poc-app-platform/test-secret`

**DNS Configuration**:
- CNAME: `poc-app-platform-aws.digitalocean.solutions` → CloudFront
- Certificate validation records

## Validation Guide

### 1. Infrastructure Validation

After deployment, verify all resources are created:

```bash
# Check Terraform state
terraform show

# Verify DigitalOcean resources
doctl projects resources list --project-id <project-id>
doctl apps list
doctl databases list

# Verify AWS resources
aws cloudfront list-distributions
aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1
aws rolesanywhere list-trust-anchors
aws secretsmanager list-secrets
```

### 2. Application Health Validation

Access the application at `https://poc-app-platform-aws.digitalocean.solutions`

The dashboard should display:
- **PostgreSQL Status**: Green with recent timestamp
- **Valkey Status**: Green with recent timestamp
- **IAM Roles Anywhere**: Green with assumed role ARN
- **AWS Secrets Manager**: Green with secret content and timestamp

### 3. API Endpoint Testing

Test individual endpoints directly:

```bash
# Basic health check
curl https://poc-app-platform-aws.digitalocean.solutions/healthz

# Database connectivity
curl https://poc-app-platform-aws.digitalocean.solutions/db/status

# IAM authentication status
curl https://poc-app-platform-aws.digitalocean.solutions/iam/status

# Secrets Manager connectivity
curl https://poc-app-platform-aws.digitalocean.solutions/secret/status

# Worker service status
curl https://poc-app-platform-aws.digitalocean.solutions/worker/status
```

### 4. Real-time Integration Validation

The worker service updates timestamps every 60 seconds. To validate:

1. **Check Initial State**: Note timestamps in the dashboard
2. **Wait 60+ Seconds**: Refresh the page
3. **Verify Updates**: All timestamps should be updated
4. **Check Logs**: View App Platform logs for worker activity

### 5. Security and WAF Testing

Test CloudFront and WAF protection:

```bash
# Test rate limiting (should be blocked after 100 requests)
./test-waf.sh

# Or run with custom number of requests:
./test-waf.sh -n 150
```

### 6. Certificate and IAM Validation

Verify X.509 certificate authentication:

```bash
# Check certificate validity
curl -vI https://poc-app-platform-aws.digitalocean.solutions 2>&1 | grep -E "(certificate|SSL)"

# Verify IAM role assumption
curl https://poc-app-platform-aws.digitalocean.solutions/iam/status | jq '.role_arn'
```

## Development and Local Testing

### Local Development

```bash
# Run the API locally
cd app
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8080

# Run the worker locally (in separate terminal)
python worker.py
```

### Container Testing

```bash
# Build and test container locally
make build
docker run -p 8080:8080 --env-file .env registry.digitalocean.com/do-solutions-sfo3/poc-app-platform-aws:latest
```

## Troubleshooting

### Common Issues

1. **Database Connection Errors**:
   - Verify environment variables are set correctly
   - Check database cluster status in DigitalOcean console
   - Ensure App Platform has database attachments

2. **IAM Roles Anywhere Authentication Failures**:
   - Verify certificates are valid and properly base64 encoded
   - Check trust anchor and profile configuration
   - Ensure role permissions include required actions

3. **Frontend Not Loading**:
   - Verify Spaces bucket objects are uploaded
   - Check CloudFront distribution status
   - Validate DNS resolution for custom domain

4. **Worker Service Not Updating Timestamps**:
   - Check App Platform worker logs
   - Verify database permissions for UPSERT operations
   - Ensure AWS credentials are valid for Secrets Manager

### Log Analysis

View logs for debugging:

```bash
# App Platform logs
doctl apps logs <app-id> --component api-svc --follow
doctl apps logs <app-id> --component timestamp-worker --follow

# CloudFront access logs (if enabled)
aws logs describe-log-groups --log-group-name-prefix /aws/cloudfront
```

## Cost Optimization

The deployment is configured for minimal cost:
- Single-node database clusters
- Minimal App Platform instance sizes
- CloudFront uses SNI-only SSL (cost-effective)
- No reserved capacity or premium features

## Cleanup

To destroy all resources:
```bash
make destroy
```

**Warning**: This will permanently delete all resources. Ensure you have backups if needed.

## Security Considerations

- All database connections use SSL/TLS encryption
- AWS authentication uses X.509 certificates (no static credentials)
- Secrets are stored in AWS Secrets Manager, not environment variables
- CloudFront provides DDoS protection and rate limiting
- CORS is configured to only allow requests from the custom domain
- All HTTP traffic is redirected to HTTPS

## Certificate Management

**Important**: The X.509 certificates used in this PoC are self-signed and generated by Terraform for demonstration purposes only. In a production environment, you should:

1. Use a proper Certificate Authority (CA) infrastructure
2. Implement proper certificate lifecycle management
3. Use hardware security modules (HSMs) for private key storage
4. Follow your organization's PKI policies and procedures

The self-signed certificate approach is acceptable for proof-of-concept and development environments but should never be used in production.