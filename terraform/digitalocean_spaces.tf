# PoC App Platform AWS Integration - DigitalOcean Spaces (Object Storage)
# This file defines Spaces bucket for frontend static assets with CORS configuration

# =============================================================================
# DIGITALOCEAN SPACES (OBJECT STORAGE)
# =============================================================================

# Spaces Bucket for Frontend Static Assets
# Provides S3-compatible object storage for HTML, CSS, and JavaScript files
# Configured with public-read ACL for direct web access
resource "digitalocean_spaces_bucket" "frontend" {
  name   = "poc-app-platform-aws-frontend-space"
  region = var.do_region
  # acl    = "public-read"              # Temporarily public for Terraform management
}

# Spaces Bucket for Access Logs
# Dedicated bucket for storing access logs from the frontend bucket
resource "digitalocean_spaces_bucket" "logs" {
  name   = "poc-app-platform-aws-logs-space"
  region = var.do_region
  acl    = "private"                  # Keep logs private
}

# Bucket Logging Configuration
# Enables access logging for the frontend bucket, storing logs in the dedicated logs bucket
resource "digitalocean_spaces_bucket_logging" "frontend_logging" {
  bucket = digitalocean_spaces_bucket.frontend.name
  region = var.do_region

  target_bucket = digitalocean_spaces_bucket.logs.name
  target_prefix = "frontend-logs/"
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
  acl          = "private"
  content_type = "text/html"          # Ensures browsers render as HTML
  region       = var.do_region
  etag         = filemd5("../frontend/index.html")  # Triggers update on file changes
}

resource "digitalocean_spaces_bucket_object" "styles" {
  bucket       = digitalocean_spaces_bucket.frontend.name
  key          = "styles.css"
  source       = "../frontend/styles.css"
  acl          = "private"
  content_type = "text/css"           # Enables proper CSS rendering
  region       = var.do_region
  etag         = filemd5("../frontend/styles.css")
}

resource "digitalocean_spaces_bucket_object" "app_js" {
  bucket       = digitalocean_spaces_bucket.frontend.name
  key          = "app.js"
  source       = "../frontend/app.js"
  acl          = "private"
  content_type = "application/javascript"  # Enables JavaScript execution
  region       = var.do_region
  etag         = filemd5("../frontend/app.js")
}

# Pull the master AWS IP ranges JSON
data "http" "aws_ipranges" {
  url = "https://ip-ranges.amazonaws.com/ip-ranges.json"
  request_headers = { Accept = "application/json" }
}

locals {
  ipranges      = jsondecode(data.http.aws_ipranges.response_body)
  # IPv4 only, CloudFront service
  cf_ipv4_cidrs_full = sort(distinct([
    for p in local.ipranges.prefixes : p.ip_prefix
    if try(p.service, "") == "CLOUDFRONT"
  ]))
}

# Bucket Policy for CloudFront-Only Access or via authenticated users.
resource "digitalocean_spaces_bucket_policy" "frontend" {
  region = var.do_region
  bucket = digitalocean_spaces_bucket.frontend.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyAnonGetIfNotFromCloudFront1"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = "arn:aws:s3:::${digitalocean_spaces_bucket.frontend.name}/*"
        Condition = {
          StringEquals = {
            "aws:PrincipalType" = "Anonymous"
          }
          NotIpAddress = {
            "aws:SourceIp" = local.cf_ipv4_cidrs_full
          }
        }
      },
      {
        Sid       = "DenyAnonGetIfBadReferer"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = "arn:aws:s3:::${digitalocean_spaces_bucket.frontend.name}/*"
        Condition = {
          StringEquals = {
            "aws:PrincipalType" = "Anonymous"
          }
          StringNotEquals = {
            "aws:Referer" = digitalocean_spaces_bucket.frontend.name
          }
        }
      },
      {
        Sid       = "AllowCloudFrontRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = "arn:aws:s3:::${digitalocean_spaces_bucket.frontend.name}/*"
        Condition = {
          IpAddress = {
            "aws:SourceIp" = local.cf_ipv4_cidrs_full
          }
          StringEquals = {
            "aws:Referer" = digitalocean_spaces_bucket.frontend.name
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [
          "arn:aws:s3:::${digitalocean_spaces_bucket.frontend.name}",
          "arn:aws:s3:::${digitalocean_spaces_bucket.frontend.name}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Project Resource Association
# Links the Spaces buckets to the DigitalOcean project for organization
resource "digitalocean_project_resources" "poc" {
  project = digitalocean_project.poc.id
  resources = [
    digitalocean_spaces_bucket.frontend.urn,
    digitalocean_spaces_bucket.logs.urn
  ]
}