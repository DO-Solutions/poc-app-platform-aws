# PoC App Platform AWS Integration - AWS CloudFront and WAF Configuration
# This file defines CloudFront distribution with WAF protection for global content delivery and security

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
  # Blocks IPs making more than 100 requests in 5-minute window
  rule {
    name     = "RateLimitRule"
    priority = 1

    statement {
      rate_based_statement {
        limit              = 100               # Requests per 5-minute window
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