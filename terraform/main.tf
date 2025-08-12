terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# AWS Provider for us-east-1 (required for CloudFront WAF)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Owner = "jkeegan"
    }
  }
}

# AWS Provider for us-west-2 (primary region)
provider "aws" {
  region = "us-west-2"
  default_tags {
    tags = {
      Owner = "jkeegan"
    }
  }
}

variable "do_region" {
  description = "DigitalOcean region for deployment"
  type        = string
  default     = "sfo3"
}

variable "do_tags" {
  description = "Tags to apply to DigitalOcean resources"
  type        = list(string)
  default     = ["jkeegan"]
}

variable "do_project_name" {
  description = "DigitalOcean project name for deployment"
  type        = string
  default     = "jkeegan"
}

variable "image_tag" {
  description = "The tag for the container image"
  type        = string
  default     = "latest"
}

variable "aws_access_key_id" {
  description = "AWS Access Key ID for Secrets Manager access"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS Secret Access Key for Secrets Manager access"
  type        = string
  sensitive   = true
}

resource "digitalocean_project" "poc" {
  name        = var.do_project_name
  description = "Project for poc-app-platform-aws resources"
  purpose     = "Web Application"
  environment = "Development"
}


resource "digitalocean_database_cluster" "postgres" {
  name       = "poc-app-platform-aws-postgres-db"
  engine     = "pg"
  version    = "17"
  size       = "db-s-1vcpu-1gb"
  region     = var.do_region
  node_count = 1
  tags       = var.do_tags
  project_id = digitalocean_project.poc.id
}

resource "digitalocean_database_cluster" "valkey" {
  name       = "poc-app-platform-aws-valkey-db"
  engine     = "valkey"
  version    = "8"
  size       = "db-s-1vcpu-1gb"
  region     = var.do_region
  node_count = 1
  tags       = var.do_tags
  project_id = digitalocean_project.poc.id
}

resource "digitalocean_spaces_bucket" "frontend" {
  name   = "poc-app-platform-aws-frontend-space"
  region = var.do_region
  acl    = "public-read"

}

resource "digitalocean_spaces_bucket_cors_configuration" "frontend_cors" {
  bucket = digitalocean_spaces_bucket.frontend.name
  region = var.do_region

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
  }
}

resource "digitalocean_spaces_bucket_object" "index" {
  bucket       = digitalocean_spaces_bucket.frontend.name
  key          = "index.html"
  source       = "../frontend/index.html"
  acl          = "public-read"
  content_type = "text/html"
  region       = var.do_region
  etag         = filemd5("../frontend/index.html")
}

resource "digitalocean_spaces_bucket_object" "styles" {
  bucket       = digitalocean_spaces_bucket.frontend.name
  key          = "styles.css"
  source       = "../frontend/styles.css"
  acl          = "public-read"
  content_type = "text/css"
  region       = var.do_region
  etag         = filemd5("../frontend/styles.css")
}

resource "digitalocean_spaces_bucket_object" "app_js" {
  bucket       = digitalocean_spaces_bucket.frontend.name
  key          = "app.js"
  source       = "../frontend/app.js"
  acl          = "public-read"
  content_type = "application/javascript"
  region       = var.do_region
  etag         = filemd5("../frontend/app.js")
}

resource "digitalocean_project_resources" "poc" {
  project = digitalocean_project.poc.id
  resources = [
    digitalocean_spaces_bucket.frontend.urn
  ]
}


resource "digitalocean_app" "poc_app" {
  project_id = digitalocean_project.poc.id
  spec {
    name   = "poc-app-platform-aws"
    region = var.do_region

    service {
      name               = "api-svc"
      instance_count     = 1
      instance_size_slug = "apps-s-1vcpu-1gb"

      image {
        registry_type = "DOCR"
        repository    = "poc-app-platform-aws"
        tag           = var.image_tag
      }

      http_port = 8080

      health_check {
        http_path = "/healthz"
        port      = 8080
      }

      # Environment variables are derived from the attached databases
      # and the frontend Spaces bucket.
      env {
        key   = "API_CORS_ORIGINS"
        value = "https://${digitalocean_spaces_bucket.frontend.bucket_domain_name},https://poc-app-platform-aws.digitalocean.solutions"
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
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

      # Phase 4: IAM Roles Anywhere environment variables
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
        key   = "AWS_ACCESS_KEY_ID"
        value = var.aws_access_key_id
        scope = "RUN_TIME"
        type  = "SECRET"
      }

      env {
        key   = "AWS_SECRET_ACCESS_KEY"
        value = var.aws_secret_access_key
        scope = "RUN_TIME"
        type  = "SECRET"
      }
    }

    # Phase 6: Worker service for continuous data updates
    worker {
      name               = "timestamp-worker"
      instance_count     = 1
      instance_size_slug = "apps-s-1vcpu-0.5gb"

      image {
        registry_type = "DOCR"
        repository    = "poc-app-platform-aws"
        tag           = var.image_tag
      }

      run_command = "python worker.py"

      # Share same environment variables as main service
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
        key   = "AWS_ACCESS_KEY_ID"
        value = var.aws_access_key_id
        scope = "RUN_TIME"
        type  = "SECRET"
      }
      env {
        key   = "AWS_SECRET_ACCESS_KEY"
        value = var.aws_secret_access_key
        scope = "RUN_TIME"
        type  = "SECRET"
      }
    }

    ingress {
      rule {
        match {
          path {
            prefix = "/"
          }
        }
        component {
          name = "api-svc"
        }
      }
    }

    database {
      name         = "postgres"
      cluster_name = digitalocean_database_cluster.postgres.name
      engine       = "PG"
      production   = true
    }

    database {
      name         = "valkey"
      cluster_name = digitalocean_database_cluster.valkey.name
      engine       = "VALKEY"
      production   = true
    }
  }
}

output "app_url" {
  description = "The live URL of the deployed application"
  value       = digitalocean_app.poc_app.live_url
}

output "frontend_url" {
  description = "The public URL of the frontend"
  value       = "https://${digitalocean_spaces_bucket.frontend.bucket_domain_name}/index.html"
}

output "frontend_bucket_name" {
  description = "The name of the frontend Spaces bucket"
  value       = digitalocean_spaces_bucket.frontend.name
}

# AWS WAF WebACL (must be in us-east-1 for CloudFront)
resource "aws_wafv2_web_acl" "main" {
  provider = aws.us_east_1
  
  name  = "poc-app-platform-aws-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rate limiting rule
  rule {
    name     = "RateLimitRule"
    priority = 1

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                 = "RateLimitRule"
      sampled_requests_enabled    = true
    }

    action {
      block {}
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                 = "poc-app-platform-aws-waf"
    sampled_requests_enabled    = true
  }

  tags = {
    Name  = "poc-app-platform-aws-waf"
    Owner = "jkeegan"
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "main" {
  provider = aws.us_east_1
  
  # App Platform API origin
  origin {
    domain_name = "poc-app-platform-aws-defua.ondigitalocean.app"
    origin_id   = "app-platform-api"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Spaces bucket origin
  origin {
    domain_name = digitalocean_spaces_bucket.frontend.bucket_domain_name
    origin_id   = "spaces-bucket"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  web_acl_id          = aws_wafv2_web_acl.main.arn

  # Default behavior - serve static assets from Spaces
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "spaces-bucket"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # API behavior - proxy to App Platform
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "app-platform-api"

    forwarded_values {
      query_string = true
      headers      = ["*"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  # Health check behavior - proxy to App Platform
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
    default_ttl            = 0
    max_ttl                = 0
  }

  # DB status behavior - proxy to App Platform (no caching)
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
    default_ttl            = 0
    max_ttl                = 0
  }

  # IAM status behavior - proxy to App Platform (no caching)
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
    default_ttl            = 0
    max_ttl                = 0
  }

  # Secrets Manager status behavior - proxy to App Platform (no caching)
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
    default_ttl            = 0
    max_ttl                = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  aliases = ["poc-app-platform-aws.digitalocean.solutions"]

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.main.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name  = "poc-app-platform-aws-cloudfront"
    Owner = "jkeegan"
  }
}

# Data source for DigitalOcean domain
data "digitalocean_domain" "main" {
  name = "digitalocean.solutions"
}

# ACM Certificate for custom domain (must be in us-east-1 for CloudFront)
resource "aws_acm_certificate" "main" {
  provider = aws.us_east_1
  
  domain_name       = "poc-app-platform-aws.digitalocean.solutions"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name  = "poc-app-platform-aws-cert"
    Owner = "jkeegan"
  }
}

# DNS validation records for ACM certificate
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
  name   = trimsuffix(each.value.name, ".digitalocean.solutions.")
  value  = each.value.record
  ttl    = 300
}

# Certificate validation
resource "aws_acm_certificate_validation" "main" {
  provider = aws.us_east_1
  
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in digitalocean_record.cert_validation : record.fqdn]

  timeouts {
    create = "5m"
  }
}

# CNAME record pointing to CloudFront
resource "digitalocean_record" "cloudfront_cname" {
  domain = data.digitalocean_domain.main.id
  type   = "CNAME"
  name   = "poc-app-platform-aws"
  value  = "${aws_cloudfront_distribution.main.domain_name}."
  ttl    = 300
}

# Output CloudFront information
output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront distribution hosted zone ID"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "custom_domain_url" {
  description = "Custom domain URL for the application"
  value       = "https://poc-app-platform-aws.digitalocean.solutions"
}

output "waf_web_acl_arn" {
  description = "WAF WebACL ARN"
  value       = aws_wafv2_web_acl.main.arn
}

output "acm_certificate_arn" {
  description = "ACM Certificate ARN"
  value       = aws_acm_certificate.main.arn
}

output "certificate_status" {
  description = "ACM Certificate validation status"
  value       = aws_acm_certificate_validation.main.certificate_arn
}

# Phase 4: IAM Roles Anywhere - Certificate Infrastructure

# CA private key
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Self-signed CA certificate
resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem
  
  subject {
    common_name  = "PoC App Platform AWS CA"
    organization = "DigitalOcean Solutions"
  }
  
  validity_period_hours = 8760 # 1 year
  is_ca_certificate     = true
  
  allowed_uses = [
    "cert_signing",
    "key_encipherment",
    "digital_signature",
  ]
}

# Client private key
resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Client certificate request
resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem
  
  subject {
    common_name  = "poc-app-platform-aws-client"
    organization = "DigitalOcean Solutions"
  }
}

# Client certificate signed by CA
resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem
  
  validity_period_hours = 8760 # 1 year
  
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",
  ]
}

# Phase 4: AWS IAM Roles Anywhere Setup

# IAM Roles Anywhere trust anchor
resource "aws_rolesanywhere_trust_anchor" "main" {
  name = "poc-app-platform-aws-trust-anchor"
  
  source {
    source_type = "CERTIFICATE_BUNDLE"
    source_data {
      x509_certificate_data = tls_self_signed_cert.ca.cert_pem
    }
  }
  
  tags = {
    Name  = "poc-app-platform-aws-trust-anchor"
    Owner = "jkeegan"
  }
}

# IAM role for the application
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
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:PrincipalTag/x509Subject/CN" = "poc-app-platform-aws-client"
          }
        }
      }
    ]
  })
  
  tags = {
    Name  = "poc-app-platform-aws-role"
    Owner = "jkeegan"
  }
}

# IAM policy for minimal permissions
resource "aws_iam_role_policy" "app_policy" {
  name = "poc-app-platform-aws-policy"
  role = aws_iam_role.app_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:UpdateSecret"
        ]
        Resource = aws_secretsmanager_secret.test_secret.arn
      }
    ]
  })
}

# IAM Roles Anywhere profile
resource "aws_rolesanywhere_profile" "main" {
  name = "poc-app-platform-aws-profile"
  
  role_arns = [aws_iam_role.app_role.arn]
  
  session_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = {
    Name  = "poc-app-platform-aws-profile"
    Owner = "jkeegan"
  }
}

# Phase 5: AWS Secrets Manager Integration

# AWS Secrets Manager secret
resource "aws_secretsmanager_secret" "test_secret" {
  name        = "poc-app-platform/test-secret"
  description = "Test secret for PoC App Platform AWS integration"
  
  tags = {
    Name  = "poc-app-platform-test-secret"
    Owner = "jkeegan"
  }
}

# Secret version with dummy content
resource "aws_secretsmanager_secret_version" "test_secret" {
  secret_id = aws_secretsmanager_secret.test_secret.id
  secret_string = jsonencode({
    message   = "Hello from AWS Secrets Manager"
    timestamp = "2024-12-12"
    purpose   = "PoC demonstration of Secrets Manager integration"
  })
}
