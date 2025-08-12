# Terraform Outputs for PoC App Platform AWS Integration
# These outputs provide essential URLs and resource identifiers for accessing the deployed infrastructure

# DigitalOcean App Platform Outputs
output "app_url" {
  description = "The live URL of the deployed DigitalOcean App Platform application. Use this to access the API endpoints directly."
  value       = digitalocean_app.poc_app.live_url
}

# DigitalOcean Spaces Outputs  
output "frontend_url" {
  description = "Direct URL to the frontend static files hosted on DigitalOcean Spaces. Provides access to the web interface."
  value       = "https://${digitalocean_spaces_bucket.frontend.bucket_domain_name}/index.html"
}

output "frontend_bucket_name" {
  description = "Name of the DigitalOcean Spaces bucket containing the frontend static assets (HTML, CSS, JavaScript)."
  value       = digitalocean_spaces_bucket.frontend.name
}

# AWS CloudFront Outputs
output "cloudfront_domain_name" {
  description = "The CloudFront distribution domain name (*.cloudfront.net). Used for DNS configuration and direct CDN access."
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "The CloudFront hosted zone ID required for Route 53 alias records and DNS management."
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "custom_domain_url" {
  description = "The custom domain URL for accessing the application through CloudFront with SSL certificate. This is the primary user-facing URL."
  value       = "https://poc-app-platform-aws.digitalocean.solutions"
}

# AWS Security Outputs
output "waf_web_acl_arn" {
  description = "The ARN of the AWS WAF WebACL protecting the CloudFront distribution. Used for security monitoring and rule management."
  value       = aws_wafv2_web_acl.main.arn
}

output "acm_certificate_arn" {
  description = "The ARN of the AWS ACM SSL certificate used by CloudFront for HTTPS termination."
  value       = aws_acm_certificate.main.arn
}

output "certificate_status" {
  description = "The ARN of the validated ACM certificate, confirming successful DNS validation and certificate issuance."
  value       = aws_acm_certificate_validation.main.certificate_arn
}