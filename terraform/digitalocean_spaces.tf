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