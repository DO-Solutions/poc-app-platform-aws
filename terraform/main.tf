# PoC App Platform AWS Integration - Main Infrastructure
# This file defines the core infrastructure resources for demonstrating
# DigitalOcean App Platform integration with AWS services

# =============================================================================
# LOCAL VALUES FOR CONSISTENT CONFIGURATION
# =============================================================================

# Local values for consistent resource configuration
# This ensures standardized naming and tagging across all resources
locals {
  # Common tags for AWS resources
  aws_tags = {
    Owner = var.owner
  }
}

# =============================================================================
# DIGITALOCEAN CORE INFRASTRUCTURE
# =============================================================================

# DigitalOcean Project - Logical container for all PoC resources
# Provides resource organization, team access control, and billing separation
resource "digitalocean_project" "poc" {
  name        = var.do_project_name
  description = "Project for poc-app-platform-aws resources"
  purpose     = "Web Application"
  environment = "Development"
}

# =============================================================================
# DIGITALOCEAN MANAGED DATABASES
# =============================================================================

# PostgreSQL Database Cluster
# Provides relational database services with automated backups, monitoring, and SSL
# Used for application data storage and demonstrating database connectivity testing
resource "digitalocean_database_cluster" "postgres" {
  name       = "poc-app-platform-aws-postgres-db"
  engine     = "pg"
  version    = "17"                    # Latest PostgreSQL version for performance and features
  size       = "db-s-1vcpu-1gb"       # Minimal size for PoC cost optimization
  region     = var.do_region
  node_count = 1                      # Single node for development/testing
  tags       = var.do_tags
  project_id = digitalocean_project.poc.id
}

# Valkey Database Cluster (Redis-compatible)
# Provides in-memory caching and real-time data storage
# Used for worker timestamp tracking and demonstrating Redis protocol compatibility
resource "digitalocean_database_cluster" "valkey" {
  name       = "poc-app-platform-aws-valkey-db"
  engine     = "valkey"
  version    = "8"                    # Latest Valkey version for Redis compatibility
  size       = "db-s-1vcpu-1gb"      # Minimal size for PoC cost optimization
  region     = var.do_region
  node_count = 1                     # Single node for development/testing
  tags       = var.do_tags
  project_id = digitalocean_project.poc.id
}

# =============================================================================
# DIGITALOCEAN DATABASE FIREWALLS
# =============================================================================

# PostgreSQL Database Firewall
# Restricts database access to only the App Platform service
# Blocks all other inbound connections for security
resource "digitalocean_database_firewall" "postgres" {
  cluster_id = digitalocean_database_cluster.postgres.id

  rule {
    type  = "app"
    value = digitalocean_app.poc_app.id
  }
}

# Valkey Database Firewall  
# Restricts database access to only the App Platform service
# Blocks all other inbound connections for security
resource "digitalocean_database_firewall" "valkey" {
  cluster_id = digitalocean_database_cluster.valkey.id

  rule {
    type  = "app"
    value = digitalocean_app.poc_app.id
  }
}

# =============================================================================
# DIGITALOCEAN SPACES (OBJECT STORAGE)
# =============================================================================

# Spaces Bucket for Frontend Static Assets
# Provides S3-compatible object storage for HTML, CSS, and JavaScript files
# Configured with public-read ACL for direct web access
resource "digitalocean_spaces_bucket" "frontend" {
  name   = "poc-app-platform-aws-frontend-space"
  region = var.do_region
  acl    = "public-read"              # Enables direct public access to frontend files
}

# CORS Configuration for Frontend Bucket
# Enables cross-origin requests from the custom domain to the Spaces-hosted frontend
# Required for API calls from the frontend to the App Platform backend
resource "digitalocean_spaces_bucket_cors_configuration" "frontend_cors" {
  bucket = digitalocean_spaces_bucket.frontend.name
  region = var.do_region

  cors_rule {
    allowed_headers = ["*"]           # Accept all headers for flexibility
    allowed_methods = ["GET"]         # Only GET requests needed for static assets
    allowed_origins = ["*"]           # Allow all origins for public frontend
  }
}

# Frontend Static Files Upload
# Automatically uploads and manages frontend assets with proper MIME types
# Uses file MD5 hashes to trigger updates only when content changes

resource "digitalocean_spaces_bucket_object" "index" {
  bucket       = digitalocean_spaces_bucket.frontend.name
  key          = "index.html"
  source       = "../frontend/index.html"
  acl          = "public-read"
  content_type = "text/html"          # Ensures browsers render as HTML
  region       = var.do_region
  etag         = filemd5("../frontend/index.html")  # Triggers update on file changes
}

resource "digitalocean_spaces_bucket_object" "styles" {
  bucket       = digitalocean_spaces_bucket.frontend.name
  key          = "styles.css"
  source       = "../frontend/styles.css"
  acl          = "public-read"
  content_type = "text/css"           # Enables proper CSS rendering
  region       = var.do_region
  etag         = filemd5("../frontend/styles.css")
}

resource "digitalocean_spaces_bucket_object" "app_js" {
  bucket       = digitalocean_spaces_bucket.frontend.name
  key          = "app.js"
  source       = "../frontend/app.js"
  acl          = "public-read"
  content_type = "application/javascript"  # Enables JavaScript execution
  region       = var.do_region
  etag         = filemd5("../frontend/app.js")
}

# Project Resource Association
# Links the Spaces bucket to the DigitalOcean project for organization
resource "digitalocean_project_resources" "poc" {
  project = digitalocean_project.poc.id
  resources = [
    digitalocean_spaces_bucket.frontend.urn
  ]
}

# =============================================================================
# DIGITALOCEAN APP PLATFORM
# =============================================================================

# App Platform Application
# Deploys containerized application with both API service and worker components
# Automatically connects to managed databases and configures environment variables
resource "digitalocean_app" "poc_app" {
  project_id = digitalocean_project.poc.id
  
  spec {
    name   = "poc-app-platform-aws"
    region = var.do_region

    # Main API Service
    # Runs the FastAPI application serving REST endpoints
    # Configured with health checks and automatic database connections
    service {
      name               = "api-svc"
      instance_count     = 1                    # Single instance for PoC
      instance_size_slug = "apps-s-1vcpu-1gb"  # Minimal size for cost optimization

      # Container image configuration
      image {
        registry_type = "DOCR"                  # DigitalOcean Container Registry
        repository    = "poc-app-platform-aws"
        tag           = var.image_tag           # Allows dynamic image updates
      }

      http_port = 8080                          # Port exposed by FastAPI application

      # Health check configuration for load balancer
      health_check {
        http_path = "/healthz"                  # Endpoint implemented in FastAPI
        port      = 8080
      }

      # CORS Configuration
      # Allows frontend hosted on Spaces to call API endpoints
      env {
        key   = "API_CORS_ORIGINS"
        value = "https://${digitalocean_spaces_bucket.frontend.bucket_domain_name},https://poc-app-platform-aws.digitalocean.solutions"
        scope = "RUN_TIME"
        type  = "GENERAL"
      }

      # PostgreSQL Database Connection Variables
      # Automatically injected by App Platform when database is attached
      env {
        key   = "PGHOST"
        value = digitalocean_database_cluster.postgres.host
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGPORT"
        value = digitalocean_database_cluster.postgres.port
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGDATABASE"
        value = digitalocean_database_cluster.postgres.database
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGUSER"
        value = digitalocean_database_cluster.postgres.user
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGPASSWORD"
        value = digitalocean_database_cluster.postgres.password
        scope = "RUN_TIME"
        type  = "SECRET"                        # Encrypted in App Platform
      }
      env {
        key   = "PGSSLMODE"
        value = "require"                       # Enforces SSL connection
        scope = "RUN_TIME"
        type  = "GENERAL"
      }

      # Valkey Database Connection Variables
      # Provides Redis-compatible caching layer
      env {
        key   = "VALKEY_HOST"
        value = digitalocean_database_cluster.valkey.host
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "VALKEY_PORT"
        value = digitalocean_database_cluster.valkey.port
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "VALKEY_PASSWORD"
        value = digitalocean_database_cluster.valkey.password
        scope = "RUN_TIME"
        type  = "SECRET"
      }

      # AWS IAM Roles Anywhere Configuration
      # Provides certificate-based AWS authentication
      env {
        key   = "IAM_CLIENT_CERT"
        value = base64encode(tls_locally_signed_cert.client.cert_pem)
        scope = "RUN_TIME"
        type  = "SECRET"                        # X.509 client certificate
      }
      env {
        key   = "IAM_CLIENT_KEY"
        value = base64encode(tls_private_key.client.private_key_pem)
        scope = "RUN_TIME"
        type  = "SECRET"                        # Private key for client certificate
      }
      env {
        key   = "IAM_TRUST_ANCHOR_ARN"
        value = aws_rolesanywhere_trust_anchor.main.arn
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "IAM_PROFILE_ARN"
        value = aws_rolesanywhere_profile.main.arn
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "IAM_ROLE_ARN"
        value = aws_iam_role.app_role.arn
        scope = "RUN_TIME"
        type  = "GENERAL"
      }

      # AWS Service Configuration
      env {
        key   = "AWS_REGION"
        value = "us-west-2"                     # Primary AWS region for services
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "SECRETS_MANAGER_SECRET_NAME"
        value = var.secrets_manager_secret_name # Name of the AWS Secrets Manager secret
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
    }

    # Worker Service for Continuous Data Updates
    # Runs background timestamp updates every 60 seconds
    # Demonstrates real-time integration across all services
    worker {
      name               = "timestamp-worker"
      instance_count     = 1                    # Single worker instance
      instance_size_slug = "apps-s-1vcpu-0.5gb" # Smaller size for background task

      # Uses same container image with different command
      image {
        registry_type = "DOCR"
        repository    = "poc-app-platform-aws"
        tag           = var.image_tag
      }

      run_command = "python worker.py"          # Starts worker instead of API

      # Worker Environment Variables
      # Shares same database and AWS configuration as API service
      # This ensures consistent connectivity across both components

      # PostgreSQL connection for timestamp tracking
      env {
        key   = "PGHOST"
        value = digitalocean_database_cluster.postgres.host
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGPORT"
        value = digitalocean_database_cluster.postgres.port
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGDATABASE"
        value = digitalocean_database_cluster.postgres.database
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGUSER"
        value = digitalocean_database_cluster.postgres.user
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGPASSWORD"
        value = digitalocean_database_cluster.postgres.password
        scope = "RUN_TIME"
        type  = "SECRET"
      }
      env {
        key   = "PGSSLMODE"
        value = "require"
        scope = "RUN_TIME"
        type  = "GENERAL"
      }

      # Valkey connection for real-time timestamp updates
      env {
        key   = "VALKEY_HOST"
        value = digitalocean_database_cluster.valkey.host
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "VALKEY_PORT"
        value = digitalocean_database_cluster.valkey.port
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "VALKEY_PASSWORD"
        value = digitalocean_database_cluster.valkey.password
        scope = "RUN_TIME"
        type  = "SECRET"
      }

      # AWS authentication for Secrets Manager updates
      env {
        key   = "IAM_CLIENT_CERT"
        value = base64encode(tls_locally_signed_cert.client.cert_pem)
        scope = "RUN_TIME"
        type  = "SECRET"
      }
      env {
        key   = "IAM_CLIENT_KEY"
        value = base64encode(tls_private_key.client.private_key_pem)
        scope = "RUN_TIME"
        type  = "SECRET"
      }
      env {
        key   = "IAM_TRUST_ANCHOR_ARN"
        value = aws_rolesanywhere_trust_anchor.main.arn
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "IAM_PROFILE_ARN"
        value = aws_rolesanywhere_profile.main.arn
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "IAM_ROLE_ARN"
        value = aws_iam_role.app_role.arn
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "AWS_REGION"
        value = "us-west-2"
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "SECRETS_MANAGER_SECRET_NAME"
        value = var.secrets_manager_secret_name
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
    }

    # Ingress Configuration
    # Routes all HTTP traffic to the API service
    ingress {
      rule {
        match {
          path {
            prefix = "/"                        # Catches all paths
          }
        }
        component {
          name = "api-svc"                      # Routes to main API service
        }
      }
    }

    # Database Attachments
    # Automatically configures connection pooling and environment variables
    
    database {
      name         = "postgres"
      cluster_name = digitalocean_database_cluster.postgres.name
      engine       = "PG"
      production   = true                       # Enables connection pooling
    }

    database {
      name         = "valkey"
      cluster_name = digitalocean_database_cluster.valkey.name
      engine       = "VALKEY"
      production   = true                       # Enables connection pooling
    }
  }
}

# =============================================================================
# AWS CLOUDFRONT AND WAF (CONTENT DELIVERY AND SECURITY)
# =============================================================================

# AWS WAF WebACL for CloudFront Protection
# Provides DDoS protection and rate limiting for the application
# Must be created in us-east-1 region for CloudFront compatibility
resource "aws_wafv2_web_acl" "main" {
  provider = aws.us_east_1
  
  name  = "poc-app-platform-aws-waf"
  scope = "CLOUDFRONT"                          # Specifically for CloudFront distributions

  # Default action allows all traffic not matched by rules
  default_action {
    allow {}
  }

  # Rate limiting rule to prevent abuse
  # Blocks IPs making more than 2000 requests in 5-minute window
  rule {
    name     = "RateLimitRule"
    priority = 1

    statement {
      rate_based_statement {
        limit              = 2000               # Requests per 5-minute window
        aggregate_key_type = "IP"              # Rate limit per source IP
      }
    }

    # CloudWatch integration for monitoring
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                 = "RateLimitRule"
      sampled_requests_enabled    = true
    }

    action {
      block {}                                  # Block excessive requests
    }
  }

  # WAF-wide visibility configuration
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                 = "poc-app-platform-aws-waf"
    sampled_requests_enabled    = true
  }

  tags = merge(local.aws_tags, {
    Name = "poc-app-platform-aws-waf"
  })
}

# CloudFront Distribution
# Provides global CDN with custom domain, SSL, and routing to both origins
# Routes API calls to App Platform and static assets to Spaces
resource "aws_cloudfront_distribution" "main" {
  provider = aws.us_east_1
  
  # App Platform API origin configuration
  # Proxies dynamic API requests to DigitalOcean App Platform
  origin {
    domain_name = "poc-app-platform-aws-defua.ondigitalocean.app"
    origin_id   = "app-platform-api"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"    # Force HTTPS to App Platform
      origin_ssl_protocols   = ["TLSv1.2"]     # Modern TLS only
    }
  }

  # DigitalOcean Spaces origin configuration
  # Serves static frontend assets directly from object storage
  origin {
    domain_name = digitalocean_spaces_bucket.frontend.bucket_domain_name
    origin_id   = "spaces-bucket"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"    # Force HTTPS to Spaces
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true                    # Support both IPv4 and IPv6
  default_root_object = "index.html"           # Serve index.html for root requests
  web_acl_id          = aws_wafv2_web_acl.main.arn  # Attach WAF protection

  # Default behavior: serve static assets from Spaces
  # This handles the main website content (HTML, CSS, JS)
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]           # Only cache read operations
    target_origin_id = "spaces-bucket"

    forwarded_values {
      query_string = false                      # Don't forward query strings to static assets

      cookies {
        forward = "none"                        # Don't forward cookies to static assets
      }
    }

    viewer_protocol_policy = "redirect-to-https" # Force HTTPS for security
    min_ttl                = 0
    default_ttl            = 3600               # Cache static assets for 1 hour
    max_ttl                = 86400              # Maximum cache time 24 hours
  }

  # API behavior: proxy to App Platform with no caching
  # Handles all /api/* requests with full header forwarding
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "app-platform-api"

    forwarded_values {
      query_string = true                       # Forward query parameters
      headers      = ["*"]                      # Forward all headers

      cookies {
        forward = "all"                         # Forward all cookies
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0                  # No caching for API responses
    max_ttl                = 0
  }

  # Health check behavior: proxy to App Platform
  # Routes health checks directly to the application
  ordered_cache_behavior {
    path_pattern     = "/healthz"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "app-platform-api"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0                  # No caching for health checks
    max_ttl                = 0
  }

  # Database status behavior: proxy to App Platform with no caching
  # Real-time database connectivity information
  ordered_cache_behavior {
    path_pattern     = "/db/status"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "app-platform-api"

    forwarded_values {
      query_string = false
      headers      = ["Cache-Control", "Pragma", "Expires", "Authorization"]

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0                  # Real-time status data
    max_ttl                = 0
  }

  # IAM status behavior: proxy to App Platform with no caching
  # Real-time AWS authentication status
  ordered_cache_behavior {
    path_pattern     = "/iam/status"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "app-platform-api"

    forwarded_values {
      query_string = false
      headers      = ["Cache-Control", "Pragma", "Expires", "Authorization"]

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0                  # Real-time authentication data
    max_ttl                = 0
  }

  # Secrets Manager status behavior: proxy to App Platform with no caching
  # Real-time AWS Secrets Manager connectivity
  ordered_cache_behavior {
    path_pattern     = "/secret/status"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "app-platform-api"

    forwarded_values {
      query_string = false
      headers      = ["Cache-Control", "Pragma", "Expires", "Authorization"]

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0                  # Real-time secrets data
    max_ttl                = 0
  }

  # Geographic restrictions (none for global access)
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Custom domain configuration
  aliases = ["poc-app-platform-aws.digitalocean.solutions"]

  # SSL certificate configuration
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.main.certificate_arn
    ssl_support_method       = "sni-only"      # Server Name Indication for cost optimization
    minimum_protocol_version = "TLSv1.2_2021" # Modern TLS for security
  }

  tags = merge(local.aws_tags, {
    Name = "poc-app-platform-aws-cloudfront"
  })
}

# =============================================================================
# DNS AND SSL CERTIFICATE MANAGEMENT
# =============================================================================

# Data source for existing DigitalOcean domain
# References the pre-existing digitalocean.solutions domain
data "digitalocean_domain" "main" {
  name = "digitalocean.solutions"
}

# ACM Certificate for custom domain
# Provides SSL/TLS certificate for CloudFront distribution
# Must be created in us-east-1 region for CloudFront compatibility
resource "aws_acm_certificate" "main" {
  provider = aws.us_east_1
  
  domain_name       = "poc-app-platform-aws.digitalocean.solutions"
  validation_method = "DNS"                     # DNS validation for automation

  # Ensures certificate is renewed before expiration
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.aws_tags, {
    Name = "poc-app-platform-aws-cert"
  })
}

# DNS validation records for ACM certificate
# Creates DNS records in DigitalOcean to validate certificate ownership
# Uses for_each to handle multiple validation records if needed
resource "digitalocean_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  domain = data.digitalocean_domain.main.id
  type   = each.value.type
  name   = trimsuffix(each.value.name, ".digitalocean.solutions.")  # Remove domain suffix
  value  = each.value.record
  ttl    = 300                                  # Short TTL for validation
}

# Certificate validation resource
# Waits for DNS validation to complete before proceeding
resource "aws_acm_certificate_validation" "main" {
  provider = aws.us_east_1
  
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in digitalocean_record.cert_validation : record.fqdn]

  timeouts {
    create = "5m"                               # Allow up to 5 minutes for validation
  }
}

# CNAME record pointing custom domain to CloudFront
# Routes traffic from poc-app-platform-aws.digitalocean.solutions to CloudFront
resource "digitalocean_record" "cloudfront_cname" {
  domain = data.digitalocean_domain.main.id
  type   = "CNAME"
  name   = "poc-app-platform-aws"
  value  = "${aws_cloudfront_distribution.main.domain_name}."
  ttl    = 300                                  # Short TTL for flexibility
}

# =============================================================================
# AWS IAM ROLES ANYWHERE - X.509 CERTIFICATE INFRASTRUCTURE
# =============================================================================

# Certificate Authority (CA) Private Key
# Root private key for signing client certificates
# Used to establish trust chain for IAM Roles Anywhere
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048                              # Secure key length
}

# Self-signed CA Certificate
# Root certificate for the certificate authority
# Establishes the trust anchor for IAM Roles Anywhere
resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem
  
  subject {
    common_name  = "PoC App Platform AWS CA"
    organization = "DigitalOcean Solutions"
  }
  
  validity_period_hours = 8760                  # Valid for 1 year
  is_ca_certificate     = true                  # Marks as CA certificate
  
  allowed_uses = [
    "cert_signing",                             # Can sign other certificates
    "key_encipherment",
    "digital_signature",
  ]
}

# Client Private Key
# Private key for the application's client certificate
resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Client Certificate Request
# Certificate signing request for the application
resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem
  
  subject {
    common_name  = "poc-app-platform-aws-client"  # Must match IAM role condition
    organization = "DigitalOcean Solutions"
  }
}

# Client Certificate signed by CA
# Final client certificate for IAM Roles Anywhere authentication
resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem
  
  validity_period_hours = 8760                  # Valid for 1 year
  
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",                              # Enables client authentication
  ]
}

# =============================================================================
# AWS IAM ROLES ANYWHERE CONFIGURATION
# =============================================================================

# IAM Roles Anywhere Trust Anchor
# Links the CA certificate to AWS IAM for certificate-based authentication
# Enables App Platform to assume AWS roles using X.509 certificates
resource "aws_rolesanywhere_trust_anchor" "main" {
  name    = "poc-app-platform-aws-trust-anchor"
  enabled = true                                    # Ensure trust anchor is enabled
  
  source {
    source_type = "CERTIFICATE_BUNDLE"
    source_data {
      x509_certificate_data = tls_self_signed_cert.ca.cert_pem
    }
  }
  
  tags = merge(local.aws_tags, {
    Name = "poc-app-platform-aws-trust-anchor"
  })
}

# IAM Role for Application
# Defines the AWS role that the application can assume
# Includes trust policy for IAM Roles Anywhere with certificate validation
resource "aws_iam_role" "app_role" {
  name = "poc-app-platform-aws-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "rolesanywhere.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession",
          "sts:SetSourceIdentity"
        ]
        Condition = {
          StringEquals = {
            # Validates the trust anchor being used
            "aws:SourceArn" = aws_rolesanywhere_trust_anchor.main.arn
          }
        }
      }
    ]
  })
  
  tags = merge(local.aws_tags, {
    Name = "poc-app-platform-aws-role"
  })
}

# IAM Policy for Application Permissions
# Grants minimal required permissions for the PoC
# Includes access to STS and Secrets Manager for demonstration
resource "aws_iam_role_policy" "app_policy" {
  name = "poc-app-platform-aws-policy"
  role = aws_iam_role.app_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"               # For authentication testing
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",      # Read secret content
          "secretsmanager:DescribeSecret",      # Get secret metadata
          "secretsmanager:UpdateSecret"         # Update secret (for worker)
        ]
        Resource = aws_secretsmanager_secret.test_secret.arn
      }
    ]
  })
}

# IAM Roles Anywhere Profile
# Links the IAM role to the trust anchor for role assumption
# Includes session policy for additional access control
resource "aws_rolesanywhere_profile" "main" {
  name    = "poc-app-platform-aws-profile"
  enabled = true                                    # Ensure profile is enabled
  
  role_arns = [aws_iam_role.app_role.arn]
  
  # Session policy provides additional restrictions during role assumption
  session_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"                   # For authentication testing
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",          # Read secret content
          "secretsmanager:DescribeSecret",          # Get secret metadata
          "secretsmanager:UpdateSecret"             # Update secret (for worker)
        ]
        Resource = aws_secretsmanager_secret.test_secret.arn
      }
    ]
  })
  
  tags = merge(local.aws_tags, {
    Name = "poc-app-platform-aws-profile"
  })
}

# =============================================================================
# AWS SECRETS MANAGER
# =============================================================================

# AWS Secrets Manager Secret
# Stores test data for demonstrating secret retrieval and updates
# Used by both API endpoints and worker for timestamp updates
resource "aws_secretsmanager_secret" "test_secret" {
  name        = var.secrets_manager_secret_name
  description = "Test secret for PoC App Platform AWS integration"
  
  tags = merge(local.aws_tags, {
    Name = "poc-app-platform-test-secret"
  })
}

# Initial Secret Content
# Provides baseline secret content with JSON structure
# Will be updated by worker service with timestamps
resource "aws_secretsmanager_secret_version" "test_secret" {
  secret_id = aws_secretsmanager_secret.test_secret.id
  secret_string = jsonencode({
    message   = "Hello from AWS Secrets Manager"
    timestamp = "2024-12-12"
    purpose   = "PoC demonstration of Secrets Manager integration"
  })
}