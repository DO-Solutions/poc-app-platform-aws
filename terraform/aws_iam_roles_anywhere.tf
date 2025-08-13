# PoC App Platform AWS Integration - AWS IAM Roles Anywhere Configuration
# This file defines IAM Roles Anywhere trust anchor, role, and profile for certificate-based authentication

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