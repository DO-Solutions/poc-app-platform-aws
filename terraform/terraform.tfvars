# Default Terraform Variables for PoC App Platform AWS Integration
# This file contains the default configuration values for the PoC deployment

# Owner identifier for resource naming and tagging
# Used across all DigitalOcean and AWS resources
owner = "jkeegan"

# AWS deployment region
# SFO3 chosen for optimal latency with AWS us-west-2
aws_region = "us-west-2"

# DigitalOcean deployment region
# SFO3 chosen for optimal latency with AWS us-west-2
do_region = "sfo3"

# DigitalOcean project name
# Uses owner name for project organization
do_project_name = "jkeegan"

# DigitalOcean resource tags
# Applied to all DigitalOcean resources for billing and organization
do_tags = ["jkeegan"]

# Custom domain for the application
# This will be the primary user-facing URL through CloudFront
custom_domain = "poc-app-platform-aws.digitalocean.solutions"

# Note that secrets are just marked for deletion,
# so if you need to destroy and apply you will need to change the secret name.
secrets_manager_secret_name = "poc-app-platform/test-secret2"
