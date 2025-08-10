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

provider "digitalocean" {}

resource "digitalocean_project" "poc" {
  name        = var.do_project_name
  description = "Project for jkeegan's resources"
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

variable "image_tag" {
  description = "The tag for the container image"
  type        = string
  default     = "latest"
}

resource "digitalocean_app" "poc_app" {
  project_id = digitalocean_project.poc.id
  spec {
    name   = "poc-app-platform-aws"
    region = var.do_region

    service {
      name               = "hello-world-svc"
      instance_count     = 1
      instance_size_slug = "apps-s-1vcpu-1gb"

      image {
        registry_type = "DOCR"
        repository    = "poc-app-platform-aws"
        tag           = var.image_tag
      }

      http_port = 80
    }

    ingress {
      rule {
        match {
          path {
            prefix = "/"
          }
        }
        component {
          name = "hello-world-svc"
        }
      }
    }

    database {
      name       = "postgres"
      cluster_name = digitalocean_database_cluster.postgres.name
      engine     = "PG"
      production = true
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
