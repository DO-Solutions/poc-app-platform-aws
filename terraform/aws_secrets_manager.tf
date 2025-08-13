# PoC App Platform AWS Integration - AWS Secrets Manager Configuration
# This file defines AWS Secrets Manager secret for demonstrating secure credential storage

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