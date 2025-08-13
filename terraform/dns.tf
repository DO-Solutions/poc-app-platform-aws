# PoC App Platform AWS Integration - DNS and SSL Certificate Management
# This file defines ACM certificate for CloudFront with DNS validation and CNAME routing

# =============================================================================
# DNS AND SSL CERTIFICATE MANAGEMENT
# =============================================================================

# Data source for existing DigitalOcean domain
# References the pre-existing base domain
data "digitalocean_domain" "main" {
  name = local.base_domain
}

# ACM Certificate for custom domain
# Provides SSL/TLS certificate for CloudFront distribution
# Must be created in us-east-1 region for CloudFront compatibility
resource "aws_acm_certificate" "main" {
  provider = aws.us_east_1
  
  domain_name       = var.custom_domain
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
  name   = trimsuffix(each.value.name, ".${local.base_domain}.")  # Remove domain suffix
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
# Routes traffic from custom domain to CloudFront
resource "digitalocean_record" "cloudfront_cname" {
  domain = data.digitalocean_domain.main.id
  type   = "CNAME"
  name   = trimsuffix(var.custom_domain, ".${local.base_domain}")
  value  = "${aws_cloudfront_distribution.main.domain_name}."
  ttl    = 300                                  # Short TTL for flexibility
}