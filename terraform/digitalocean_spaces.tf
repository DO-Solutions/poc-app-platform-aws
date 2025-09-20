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
  acl    = "public-read"              # Temporarily public for Terraform management
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

# Bucket Policy for CloudFront-Only Access or via authenticated users.
resource "digitalocean_spaces_bucket_policy" "frontend" {
  region = var.do_region
  bucket = digitalocean_spaces_bucket.frontend.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyAnonGetIfNotFromCloudFront"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = "arn:aws:s3:::${digitalocean_spaces_bucket.frontend.name}/*"
        Condition = {
          StringEquals = {
            "aws:PrincipalType" = "Anonymous"
          }
          NotIpAddress = {
            "aws:SourceIp" = [
              # CloudFront IP ranges
              "205.251.200.0/21",
              "205.251.208.0/20",
              "204.246.172.0/23",
              "204.246.164.0/22",
              "13.32.0.0/15",
              "13.35.0.0/16",
              "52.46.0.0/18",
              "52.84.0.0/15",
              "52.124.128.0/17",
              "54.192.0.0/16",
              "54.230.0.0/16",
              "54.239.128.0/18",
              "54.239.192.0/19",
              "71.152.0.0/17",
              "120.52.22.96/27",
              "130.176.0.0/16",
              "144.220.0.0/16",
              "205.251.249.0/24"
            ]
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
            "aws:SourceIp" = [
              "13.32.0.0/15",
              "13.35.0.0/16",
              "13.224.0.0/14",
              "13.249.0.0/16",
              "15.158.0.0/16",
              "18.64.0.0/14",
              "18.68.0.0/16",
              "18.154.0.0/15",
              "18.160.0.0/15",
              "18.164.0.0/15",
              "18.172.0.0/15",
              "18.238.0.0/15",
              "18.244.0.0/15",
              "23.91.0.0/19",
              "52.84.0.0/15",
              "54.182.0.0/16",
              "54.192.0.0/16",
              "54.230.0.0/17",
              "54.230.128.0/18",
              "54.239.128.0/18",
              "54.239.192.0/19",
              "54.240.128.0/18",
              "99.84.0.0/16",
              "99.86.0.0/16",
              "108.156.0.0/14",
              "130.176.0.0/17",
              "143.204.0.0/16",
              "144.220.0.0/16",
              "204.246.164.0/22",
              "204.246.168.0/22",
              "204.246.172.0/24",
              "204.246.173.0/24",
              "204.246.174.0/23",
              "204.246.176.0/20",
              "205.251.202.0/23",
              "205.251.204.0/23",
              "205.251.206.0/23",
              "205.251.208.0/20",
              "205.251.249.0/24",
              "205.251.250.0/23",
              "205.251.252.0/23",
              "205.251.254.0/24"
            ]
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
# Links the Spaces bucket to the DigitalOcean project for organization
resource "digitalocean_project_resources" "poc" {
  project = digitalocean_project.poc.id
  resources = [
    digitalocean_spaces_bucket.frontend.urn
  ]
}