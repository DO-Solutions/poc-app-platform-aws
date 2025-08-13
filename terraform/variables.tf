# Terraform Variables for PoC App Platform AWS Integration
# These variables configure deployment settings for DigitalOcean and AWS resources

variable "owner" {
  description = "Owner identifier used for resource naming, tagging, and project organization across both DigitalOcean and AWS resources"
  type        = string

  validation {
    condition     = length(var.owner) > 0 && can(regex("^[a-z0-9-]+$", var.owner))
    error_message = "Owner must be a non-empty string containing only lowercase letters, numbers, and hyphens."
  }
}

variable "do_region" {
  description = "DigitalOcean region for all DigitalOcean resources (App Platform, databases, Spaces)"
  type        = string
}

variable "do_tags" {
  description = "List of tags to apply to all DigitalOcean resources for organization and billing tracking"
  type        = list(string)
  
  validation {
    condition     = length(var.do_tags) > 0
    error_message = "At least one tag must be provided."
  }
}

variable "do_project_name" {
  description = "Name of the DigitalOcean project that will contain all resources for this PoC"
  type        = string
  
  validation {
    condition     = length(var.do_project_name) > 0
    error_message = "Project name must be a non-empty string."
  }
}

variable "image_tag" {
  description = "Docker image tag for the application container in DigitalOcean Container Registry (DOCR)"
  type        = string

  validation {
    condition     = length(var.image_tag) > 0
    error_message = "Image tag cannot be empty."
  }
}

variable "secrets_manager_secret_name" {
  description = "Name of the AWS Secrets Manager secret used for integration demonstration"
  type        = string
  default     = "poc-app-platform/test-secret"

  validation {
    condition     = length(var.secrets_manager_secret_name) > 0
    error_message = "Secrets Manager secret name cannot be empty."
  }
}

