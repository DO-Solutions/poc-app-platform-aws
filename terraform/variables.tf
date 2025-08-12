# Terraform Variables for PoC App Platform AWS Integration
# These variables configure deployment settings for DigitalOcean and AWS resources

variable "owner" {
  description = "Owner identifier used for resource naming, tagging, and project organization across both DigitalOcean and AWS resources"
  type        = string
  default     = "jkeegan"
  
  validation {
    condition     = length(var.owner) > 0 && can(regex("^[a-z0-9-]+$", var.owner))
    error_message = "Owner must be a non-empty string containing only lowercase letters, numbers, and hyphens."
  }
}

variable "do_region" {
  description = "DigitalOcean region for all DigitalOcean resources (App Platform, databases, Spaces)"
  type        = string
  default     = "sfo3"
}

variable "do_tags" {
  description = "List of tags to apply to all DigitalOcean resources for organization and billing tracking"
  type        = list(string)
  default     = null  # Will default to [var.owner] when null
}

variable "do_project_name" {
  description = "Name of the DigitalOcean project that will contain all resources for this PoC"
  type        = string
  default     = null  # Will default to var.owner when null
}

variable "image_tag" {
  description = "Docker image tag for the application container in DigitalOcean Container Registry (DOCR)"
  type        = string

  validation {
    condition     = length(var.image_tag) > 0
    error_message = "Image tag cannot be empty."
  }
}

variable "aws_access_key_id" {
  description = "AWS Access Key ID for authentication to AWS services (Secrets Manager, IAM). Used as fallback credentials alongside IAM Roles Anywhere."
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.aws_access_key_id) > 0
    error_message = "AWS Access Key ID must be provided."
  }
}

variable "aws_secret_access_key" {
  description = "AWS Secret Access Key corresponding to the Access Key ID. Used for AWS service authentication alongside IAM Roles Anywhere setup."
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.aws_secret_access_key) > 0
    error_message = "AWS Secret Access Key must be provided."
  }
}