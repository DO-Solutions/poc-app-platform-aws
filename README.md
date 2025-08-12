# PoC: DigitalOcean App Platform with AWS Integration

This proof-of-concept demonstrates how to integrate DigitalOcean App Platform with selective AWS services while maintaining the core infrastructure on DigitalOcean. The project showcases a complete integration between DigitalOcean's managed services and AWS services like IAM Roles Anywhere, Secrets Manager, and CloudFront with WAF.

## Architecture Overview

The solution implements a hybrid cloud architecture that leverages the strengths of both platforms:

```
                              ┌─────────────────────────────────────┐
                              │               USER                  │
                              └─────────────┬───────────────────────┘
                                           │ HTTPS Request
                                           │ poc-app-platform-aws.digitalocean.solutions
                                           │
                           ┌───────────────▼──────────────────┐
                           │          AWS CLOUD               │
                           │                                  │
                           │  ┌────────────────────────────┐  │
                           │  │      CloudFront + WAF      │  │
                           │  │   (Global CDN & Security)  │  │
                           │  └──────────┬─────────────────┘  │
                           │             │                    │
                           └─────────────┼────────────────────┘
                                         │
                           ┌─────────────▼────────────────────┐
                           │      Request Routing             │
                           └────┬─────────────────────┬───────┘
                                │                     │
                        Static Assets            API Requests
                      (/index.html, etc.)        (/healthz, /db/*, etc.)
                                │                     │
                   ┌────────────▼──────────┐         │
                   │  DIGITALOCEAN CLOUD   │         │
                   │                       │         │
                   │ ┌─────────────────┐   │         │
                   │ │     Spaces      │   │         │
                   │ │  (Frontend)     │   │         │
                   │ │ • index.html    │   │         │
                   │ │ • app.js        │   │         │
                   │ │ • styles.css    │   │         │
                   │ └─────────────────┘   │         │
                   └───────────────────────┘         │
                                                     │
                   ┌─────────────────────────────────▼─────────────────────────────────┐
                   │                    DIGITALOCEAN CLOUD                             │
                   │                                                                   │
                   │  ┌─────────────────────────────────────────────────────────────┐  │
                   │  │                  App Platform                               │  │
                   │  │                                                             │  │
                   │  │  ┌─────────────────┐        ┌─────────────────────────────┐ │  │
                   │  │  │   API Service   │        │      Worker Service         │ │  │
                   │  │  │                 │        │                             │ │  │
                   │  │  │ FastAPI Backend │        │ • Updates timestamps       │ │  │
                   │  │  │ • /healthz      │        │   every 60s                │ │  │
                   │  │  │ • /db/status    │        │ • PostgreSQL updates       │ │  │
                   │  │  │ • /iam/status   │        │ • Valkey updates            │ │  │
                   │  │  │ • /secret/status│        │ • Secrets Manager updates   │ │  │
                   │  │  │ • /worker/status│        │                             │ │  │
                   │  │  └─────────────────┘        └─────────────────────────────┘ │  │
                   │  │              │                            │                  │  │
                   │  └──────────────┼────────────────────────────┼──────────────────┘  │
                   │                 │                            │                     │
                   │         ┌───────▼────────┐          ┌────────▼──────────┐         │
                   │         │   PostgreSQL   │          │      Valkey       │         │
                   │         │                │          │                   │         │
                   │         │ • App data     │          │ • Cache layer     │         │
                   │         │ • Timestamps   │          │ • Worker timestamps│        │
                   │         │ • Read/Write   │          │ • SET/GET ops     │         │
                   │         └────────────────┘          └───────────────────┘         │
                   │                                                                   │
                   └───────────────────────────────────────────────────────────────────┘
                                                     │
                                         ┌───────────▼──────────────┐
                                         │     AWS INTEGRATION      │
                                         │                          │
                                         │ ┌────────────────────┐   │
                                         │ │ IAM Roles Anywhere │   │
                                         │ │                    │   │
                                         │ │ • Trust Anchor     │   │
                                         │ │ • X.509 Certs      │   │ 
                                         │ │ • Role Assumption  │   │
                                         │ └────────┬───────────┘   │
                                         │          │               │
                                         │ ┌────────▼───────────┐   │
                                         │ │  Secrets Manager   │   │
                                         │ │                    │   │
                                         │ │ • Test Secret      │   │
                                         │ │ • JSON Payloads    │   │
                                         │ │ • Worker Updates   │   │
                                         │ └────────────────────┘   │
                                         └──────────────────────────┘

Data Flow:
1. User → CloudFront (AWS) → Spaces (DO) for static assets
2. User → CloudFront (AWS) → App Platform (DO) for API requests  
3. App Platform (DO) → PostgreSQL/Valkey (DO) for database operations
4. App Platform (DO) → IAM Roles Anywhere (AWS) → Secrets Manager (AWS)
5. Worker Service (DO) → Updates all services every 60 seconds
```

### Core Infrastructure (DigitalOcean)
- **App Platform**: Hosts the containerized FastAPI application with both API and worker services
- **PostgreSQL Database**: Managed database for application data and timestamp tracking
- **Valkey Database**: Redis-compatible in-memory store for caching and real-time data
- **Spaces**: Object storage hosting the static frontend (HTML, CSS, JavaScript)
- **Container Registry**: Stores the application container images

### AWS Integration Layer
- **CloudFront + WAF**: Global CDN with DDoS protection and rate limiting
- **IAM Roles Anywhere**: Certificate-based authentication for secure AWS service access
- **Secrets Manager**: Secure storage and retrieval of application secrets
- **ACM Certificate**: SSL/TLS certificate for the custom domain

### Application Components
- **FastAPI Backend**: REST API with endpoints for health checks, database status, IAM authentication, and secrets management
- **Worker Service**: Background service that updates timestamps across all integrated services every 60 seconds
- **Static Frontend**: JavaScript-based dashboard displaying real-time status of all services

## How It Works

### Authentication Flow
1. X.509 certificates are generated via Terraform and stored as environment variables
2. The application uses IAM Roles Anywhere to assume AWS roles using these certificates
3. Temporary AWS credentials are used to access Secrets Manager and other AWS services

### Data Flow
1. **Frontend Request**: User accesses `https://poc-app-platform-aws.digitalocean.solutions`
2. **CloudFront Routing**: AWS CloudFront serves static assets from DigitalOcean Spaces and proxies API calls to App Platform
3. **API Processing**: App Platform handles API requests, connecting to databases and AWS services
4. **Background Updates**: Worker service continuously updates timestamps across all services

### Monitoring and Validation
The application provides real-time status monitoring through several endpoints:
- `/healthz`: Basic health check
- `/db/status`: PostgreSQL and Valkey connectivity with read/write tests
- `/iam/status`: AWS IAM Roles Anywhere authentication status
- `/secret/status`: AWS Secrets Manager connectivity and secret retrieval
- `/worker/status`: Aggregated timestamp status showing real-time data flow

## Deployment Guide

### Prerequisites
1. DigitalOcean account with API token
2. AWS account with programmatic access
3. Access to `digitalocean.solutions` domain for DNS management
4. Terraform >= 1.0
5. Docker for local development (optional)

### Environment Setup
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

### Deployment Commands

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

### Deployment Process
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
# Test rate limiting (should be blocked after 2000 requests)
for i in {1..2010}; do
  curl -s https://poc-app-platform-aws.digitalocean.solutions/healthz > /dev/null
  echo "Request $i completed"
done
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

## Security Considerations

- All database connections use SSL/TLS encryption
- AWS authentication uses X.509 certificates (no static credentials)
- Secrets are stored in AWS Secrets Manager, not environment variables
- CloudFront provides DDoS protection and rate limiting
- CORS is configured to only allow requests from the custom domain
- All HTTP traffic is redirected to HTTPS

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

## Architecture Benefits

This hybrid architecture provides:
- **Cost Efficiency**: Core infrastructure on DigitalOcean with selective AWS services
- **Global Performance**: CloudFront CDN for worldwide content delivery
- **Security**: AWS WAF protection and certificate-based authentication
- **Scalability**: App Platform auto-scaling with managed databases
- **Observability**: Real-time monitoring across all integrated services
- **Flexibility**: Easy to extend with additional AWS or DigitalOcean services

The proof-of-concept successfully demonstrates that organizations can leverage both platforms effectively, using each for their respective strengths while maintaining seamless integration.