# PoC App Platform AWS Integration - DigitalOcean Managed Databases
# This file defines PostgreSQL and Valkey database clusters with security firewall rules

# =============================================================================
# DIGITALOCEAN MANAGED DATABASES
# =============================================================================

# PostgreSQL Database Cluster
# Provides relational database services with automated backups, monitoring, and SSL
# Used for application data storage and demonstrating database connectivity testing
resource "digitalocean_database_cluster" "postgres" {
  name       = "poc-app-platform-aws-postgres-db"
  engine     = "pg"
  version    = "17"                    # Latest PostgreSQL version for performance and features
  size       = "db-s-1vcpu-1gb"       # Minimal size for PoC cost optimization
  region     = var.do_region
  node_count = 1                      # Single node for development/testing
  tags       = var.do_tags
  project_id = digitalocean_project.poc.id
}

# Valkey Database Cluster (Redis-compatible)
# Provides in-memory caching and real-time data storage
# Used for worker timestamp tracking and demonstrating Redis protocol compatibility
resource "digitalocean_database_cluster" "valkey" {
  name       = "poc-app-platform-aws-valkey-db"
  engine     = "valkey"
  version    = "8"                    # Latest Valkey version for Redis compatibility
  size       = "db-s-1vcpu-1gb"      # Minimal size for PoC cost optimization
  region     = var.do_region
  node_count = 1                     # Single node for development/testing
  tags       = var.do_tags
  project_id = digitalocean_project.poc.id
}

# =============================================================================
# DIGITALOCEAN DATABASE FIREWALLS
# =============================================================================

# PostgreSQL Database Firewall
# Restricts database access to only the App Platform service
# Blocks all other inbound connections for security
resource "digitalocean_database_firewall" "postgres" {
  cluster_id = digitalocean_database_cluster.postgres.id

  rule {
    type  = "app"
    value = digitalocean_app.poc_app.id
  }
}

# Valkey Database Firewall  
# Restricts database access to only the App Platform service
# Blocks all other inbound connections for security
resource "digitalocean_database_firewall" "valkey" {
  cluster_id = digitalocean_database_cluster.valkey.id

  rule {
    type  = "app"
    value = digitalocean_app.poc_app.id
  }
}