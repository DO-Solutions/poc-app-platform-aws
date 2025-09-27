# Terraform configuration block defining required providers and versions
# This file specifies the core Terraform and provider requirements for the PoC

terraform {
  required_providers {
    # DigitalOcean provider for App Platform, Spaces, and managed databases
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }

    # AWS provider for CloudFront, WAF, IAM Roles Anywhere, and Secrets Manager
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # TLS provider for X.509 certificate generation for IAM Roles Anywhere
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # Used to get CloudFront IP Addresses
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }

  backend "s3" {
    endpoints = {
      s3 = "https://sfo3.digitaloceanspaces.com"
    }

    bucket               = "poc-app-platform-aws-tfstate"
    key                  = "terraform.tfstate"
    workspace_key_prefix = ""

    # Disable AWS-specific checks
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    region                      = "us-east-1"
  }
}

# AWS Provider for us-east-1 region
# Required for CloudFront distribution and WAF WebACL resources
# CloudFront distributions must use certificates and WAF rules in us-east-1
provider "aws" {
  alias               = "us_east_1"
  region              = "us-east-1"
  access_key          = var.aws_access_key_id
  secret_key          = var.aws_secret_access_key
  default_tags {
    tags = {
      Owner = var.owner
    }
  }
}

# AWS Provider for us-west-2 region (primary)
# Used for IAM Roles Anywhere, Secrets Manager, and other general AWS resources
# This region aligns with DigitalOcean's SFO3 region for optimal latency
provider "aws" {
  region              = var.aws_region
  access_key          = var.aws_access_key_id
  secret_key          = var.aws_secret_access_key
  default_tags {
    tags = {
      Owner = var.owner
    }
  }
}