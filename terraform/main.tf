terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

variable "do_region" {
  description = "DigitalOcean region for deployment"
  type        = string
  default     = "sfo3"
}

variable "do_tags" {
  description = "Tags to apply to DigitalOcean resources"
  type        = list(string)
  default     = ["jkeegan"]
}

variable "do_project_name" {
  description = "DigitalOcean project name for deployment"
  type        = string
  default     = "jkeegan"
}

variable "image_tag" {
  description = "The tag for the container image"
  type        = string
  default     = "latest"
}

resource "digitalocean_project" "poc" {
  name        = var.do_project_name
  description = "Project for poc-app-platform-aws resources"
  purpose     = "Web Application"
  environment = "Development"
}


resource "digitalocean_database_cluster" "postgres" {
  name       = "poc-app-platform-aws-postgres-db"
  engine     = "pg"
  version    = "17"
  size       = "db-s-1vcpu-1gb"
  region     = var.do_region
  node_count = 1
  tags       = var.do_tags
  project_id = digitalocean_project.poc.id
}

resource "digitalocean_database_cluster" "valkey" {
  name       = "poc-app-platform-aws-valkey-db"
  engine     = "valkey"
  version    = "8"
  size       = "db-s-1vcpu-1gb"
  region     = var.do_region
  node_count = 1
  tags       = var.do_tags
  project_id = digitalocean_project.poc.id
}

resource "digitalocean_spaces_bucket" "frontend" {
  name   = "poc-app-platform-aws-frontend-space"
  region = var.do_region
  acl    = "public-read"

}

resource "digitalocean_spaces_bucket_cors_configuration" "frontend_cors" {
  bucket = digitalocean_spaces_bucket.frontend.name
  region = var.do_region

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
  }
}

resource "digitalocean_spaces_bucket_object" "index" {
  bucket       = digitalocean_spaces_bucket.frontend.name
  key          = "index.html"
  source       = "../frontend/index.html"
  acl          = "public-read"
  content_type = "text/html"
  region       = var.do_region
}

resource "digitalocean_spaces_bucket_object" "styles" {
  bucket       = digitalocean_spaces_bucket.frontend.name
  key          = "styles.css"
  source       = "../frontend/styles.css"
  acl          = "public-read"
  content_type = "text/css"
  region       = var.do_region
}

resource "digitalocean_spaces_bucket_object" "app_js" {
  bucket       = digitalocean_spaces_bucket.frontend.name
  key          = "app.js"
  source       = "../frontend/app.js"
  acl          = "public-read"
  content_type = "application/javascript"
  region       = var.do_region
}

resource "digitalocean_project_resources" "poc" {
  project = digitalocean_project.poc.id
  resources = [
    digitalocean_spaces_bucket.frontend.urn
  ]
}


resource "digitalocean_app" "poc_app" {
  project_id = digitalocean_project.poc.id
  spec {
    name   = "poc-app-platform-aws"
    region = var.do_region

    service {
      name               = "api-svc"
      instance_count     = 1
      instance_size_slug = "apps-s-1vcpu-1gb"

      image {
        registry_type = "DOCR"
        repository    = "poc-app-platform-aws"
        tag           = var.image_tag
      }

      http_port = 8080

      health_check {
        http_path = "/healthz"
        port      = 8080
      }

      # Environment variables are derived from the attached databases
      # and the frontend Spaces bucket.
      env {
        key   = "API_CORS_ORIGINS"
        value = "https://${digitalocean_spaces_bucket.frontend.bucket_domain_name}"
        scope = "RUN_TIME"
        type  = "GENERAL"
      }
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
    }

    ingress {
      rule {
        match {
          path {
            prefix = "/"
          }
        }
        component {
          name = "api-svc"
        }
      }
    }

    database {
      name         = "postgres"
      cluster_name = digitalocean_database_cluster.postgres.name
      engine       = "PG"
      production   = true
    }

    database {
      name         = "valkey"
      cluster_name = digitalocean_database_cluster.valkey.name
      engine       = "VALKEY"
      production   = true
    }
  }
}

output "app_url" {
  description = "The live URL of the deployed application"
  value       = digitalocean_app.poc_app.live_url
}

output "frontend_url" {
  description = "The public URL of the frontend"
  value       = "https://${digitalocean_spaces_bucket.frontend.bucket_domain_name}/index.html"
}

output "frontend_bucket_name" {
  description = "The name of the frontend Spaces bucket"
  value       = digitalocean_spaces_bucket.frontend.name
}
