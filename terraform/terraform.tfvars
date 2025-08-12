# Default Terraform Variables for PoC App Platform AWS Integration
# This file contains the default configuration values for the PoC deployment

# Owner identifier for resource naming and tagging
# Used across all DigitalOcean and AWS resources
owner = "jkeegan"

# DigitalOcean deployment region
# SFO3 chosen for optimal latency with AWS us-west-2
do_region = "sfo3"

# DigitalOcean project name
# Uses owner name for project organization
do_project_name = "jkeegan"

# DigitalOcean resource tags
# Applied to all DigitalOcean resources for billing and organization
do_tags = ["jkeegan"]
