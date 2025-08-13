# PoC App Platform AWS Integration - DigitalOcean Core Infrastructure
# This file defines the core DigitalOcean infrastructure including project organization and common values

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
  
  # Base domain extracted from custom domain
  # Used for DNS validation and record management
  base_domain = join(".", slice(split(".", var.custom_domain), 1, length(split(".", var.custom_domain))))
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