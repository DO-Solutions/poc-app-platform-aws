# PoC App Platform AWS Integration - DigitalOcean App Platform Configuration
# This file defines the App Platform application with both API service and worker components

# =============================================================================
# DIGITALOCEAN APP PLATFORM
# =============================================================================

# App Platform Application
# Deploys containerized application with both API service and worker components
# Automatically connects to managed databases and configures environment variables
resource "digitalocean_app" "poc_app" {
  project_id = digitalocean_project.poc.id
  
  spec {
    name   = "poc-app-platform-aws"
    region = substr(var.do_region, 0, 3)

    # Main API Service
    # Runs the FastAPI application serving REST endpoints
    # Configured with health checks and automatic database connections
    service {
      name               = "api-svc"
      instance_count     = 1                    # Single instance for PoC
      instance_size_slug = "apps-s-1vcpu-1gb"  # Minimal size for cost optimization

      # Container image configuration
      image {
        registry_type = "DOCR"                  # DigitalOcean Container Registry
        registry = "do-solutions-sfo3"
        repository    = "poc-app-platform-aws"
        tag           = var.image_tag           # Allows dynamic image updates
      }

      http_port = 8080                          # Port exposed by FastAPI application

      # Health check configuration for load balancer
      health_check {
        http_path = "/healthz"                  # Endpoint implemented in FastAPI
        port      = 8080
      }

      # CORS Configuration
      # Allows frontend hosted on Spaces to call API endpoints
      env {
        key   = "API_CORS_ORIGINS"
        value = "https://${digitalocean_spaces_bucket.frontend.bucket_domain_name},https://${var.custom_domain}"
        scope = "RUN_TIME"
        type  = "GENERAL"
      }

      # PostgreSQL Database Connection Variables
      # Automatically injected by App Platform when database is attached
      env {
        key   = "PGHOST"
        value = digitalocean_database_cluster.postgres.host
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGPORT"
        value = digitalocean_database_cluster.postgres.port
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGDATABASE"
        value = digitalocean_database_cluster.postgres.database
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGUSER"
        value = digitalocean_database_cluster.postgres.user
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGPASSWORD"
        value = digitalocean_database_cluster.postgres.password
        scope = "RUN_TIME"
        type  = "SECRET"                        # Encrypted in App Platform
      }
      env {
        key   = "PGSSLMODE"
        value = "require"                       # Enforces SSL connection
        scope = "RUN_TIME"
        type  = "GENERAL"
      }

      # Valkey Database Connection Variables
      # Provides Redis-compatible caching layer
      env {
        key   = "VALKEY_HOST"
        value = digitalocean_database_cluster.valkey.host
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "VALKEY_PORT"
        value = digitalocean_database_cluster.valkey.port
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "VALKEY_PASSWORD"
        value = digitalocean_database_cluster.valkey.password
        scope = "RUN_TIME"
        type  = "SECRET"
      }

      # AWS IAM Roles Anywhere Configuration
      # Provides certificate-based AWS authentication
      env {
        key   = "IAM_CLIENT_CERT"
        value = base64encode(tls_locally_signed_cert.client.cert_pem)
        scope = "RUN_TIME"
        type  = "SECRET"                        # X.509 client certificate
      }
      env {
        key   = "IAM_CLIENT_KEY"
        value = base64encode(tls_private_key.client.private_key_pem)
        scope = "RUN_TIME"
        type  = "SECRET"                        # Private key for client certificate
      }
      env {
        key   = "IAM_TRUST_ANCHOR_ARN"
        value = aws_rolesanywhere_trust_anchor.main.arn
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "IAM_PROFILE_ARN"
        value = aws_rolesanywhere_profile.main.arn
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "IAM_ROLE_ARN"
        value = aws_iam_role.app_role.arn
        scope = "RUN_TIME"
        type  = "GENERAL"
      }

      # AWS Service Configuration
      env {
        key   = "AWS_REGION"
        value = var.aws_region                  # Primary AWS region for services
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "SECRETS_MANAGER_SECRET_NAME"
        value = var.secrets_manager_secret_name # Name of the AWS Secrets Manager secret
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
    }

    # Worker Service for Continuous Data Updates
    # Runs background timestamp updates every 60 seconds
    # Demonstrates real-time integration across all services
    worker {
      name               = "timestamp-worker"
      instance_count     = 1                    # Single worker instance
      instance_size_slug = "apps-s-1vcpu-0.5gb" # Smaller size for background task

      # Uses same container image with different command
      image {
        registry_type = "DOCR"
        registry = "do-solutions-sfo3"
        repository    = "poc-app-platform-aws"
        tag           = var.image_tag
      }

      run_command = "python worker.py"          # Starts worker instead of API

      # Worker Environment Variables
      # Shares same database and AWS configuration as API service
      # This ensures consistent connectivity across both components

      # PostgreSQL connection for timestamp tracking
      env {
        key   = "PGHOST"
        value = digitalocean_database_cluster.postgres.host
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGPORT"
        value = digitalocean_database_cluster.postgres.port
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGDATABASE"
        value = digitalocean_database_cluster.postgres.database
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGUSER"
        value = digitalocean_database_cluster.postgres.user
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "PGPASSWORD"
        value = digitalocean_database_cluster.postgres.password
        scope = "RUN_TIME"
        type  = "SECRET"
      }
      env {
        key   = "PGSSLMODE"
        value = "require"
        scope = "RUN_TIME"
        type  = "GENERAL"
      }

      # Valkey connection for real-time timestamp updates
      env {
        key   = "VALKEY_HOST"
        value = digitalocean_database_cluster.valkey.host
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "VALKEY_PORT"
        value = digitalocean_database_cluster.valkey.port
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "VALKEY_PASSWORD"
        value = digitalocean_database_cluster.valkey.password
        scope = "RUN_TIME"
        type  = "SECRET"
      }

      # AWS authentication for Secrets Manager updates
      env {
        key   = "IAM_CLIENT_CERT"
        value = base64encode(tls_locally_signed_cert.client.cert_pem)
        scope = "RUN_TIME"
        type  = "SECRET"
      }
      env {
        key   = "IAM_CLIENT_KEY"
        value = base64encode(tls_private_key.client.private_key_pem)
        scope = "RUN_TIME"
        type  = "SECRET"
      }
      env {
        key   = "IAM_TRUST_ANCHOR_ARN"
        value = aws_rolesanywhere_trust_anchor.main.arn
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "IAM_PROFILE_ARN"
        value = aws_rolesanywhere_profile.main.arn
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "IAM_ROLE_ARN"
        value = aws_iam_role.app_role.arn
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "AWS_REGION"
        value = var.aws_region
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
      env {
        key   = "SECRETS_MANAGER_SECRET_NAME"
        value = var.secrets_manager_secret_name
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
    }

    # Ingress Configuration
    # Routes all HTTP traffic to the API service
    ingress {
      rule {
        match {
          path {
            prefix = "/"                        # Catches all paths
          }
        }
        component {
          name = "api-svc"                      # Routes to main API service
        }
      }
    }

    # Database Attachments
    # Automatically configures connection pooling and environment variables
    
    database {
      name         = "postgres"
      cluster_name = digitalocean_database_cluster.postgres.name
      engine       = "PG"
      production   = true                       # Enables connection pooling
    }

    database {
      name         = "valkey"
      cluster_name = digitalocean_database_cluster.valkey.name
      engine       = "VALKEY"
      production   = true                       # Enables connection pooling
    }
  }
}