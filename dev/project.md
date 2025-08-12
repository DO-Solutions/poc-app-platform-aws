# DigitalOcean App Platform Proof of Concept Plan

## Overview

This proof of concept (PoC) will replicate functionality that the customer currently leverages on AWS (ECS, AWS WAF, AWS Secrets Manager) using DigitalOcean's App Platform, DigitalOcean Database-as-a-Service (DBaaS), and selective AWS services where required.

The PoC will be implemented in phases, each with clearly defined technical objectives and success criteria. Terraform will be used for all infrastructure deployment, with code hosted in GitHub. Changes to the repository will trigger container builds and deployments to App Platform. The application will integrate with AWS WAF via CloudFront and AWS Secrets Manager via IAM Roles Anywhere.

## Overall guidance

* **Reproducibility first:** Everything must be deployable and reproducible via **Terraform** with all configuration in versioned files in **GitHub**.
* **Single deployment path:** **All deployments are performed by GitHub Actions**; no manual clicks in consoles for the happy-path flow.
* **GitHub repo secrets:**

    * `DIGITALOCEAN_ACCESS_TOKEN`
    * `AWS_ACCESS_KEY_ID`
    * `AWS_SECRET_ACCESS_KEY`
    * `SPACES_ACCESS_KEY_ID`
    * `SPACES_SECRET_ACCESS_KEY`

    Assume these Env Vars will be set wherever Terrafrom deploy will be run and they do not need to be passed into the terraform command, but will automatically be used by terraform. For your testing you can get set these env vars by sourcing the file `scratch/env.sh`
* **Stateless re‑targeting:** By updating these secrets (and any provider/account IDs captured as variables) to point at a different **DigitalOcean Team** and **AWS account**, then re-running the deploy workflow, the pipeline should create a **fresh, isolated deployment** in the new environments without modifying the previous one.
* **Inputs over edits:** Environment- and account-specific values should be expressed as Terraform variables or GitHub Actions inputs, not hard-coded in modules or app code.
* **Idempotence:** Terraform plans must be clean on re-runs; CI should fail on drift.
* If the case there does need to be manual interact with GitHub, DigitalOcean or AWS this will be done for you. You are not to use utilities or interact directly with GitHub, DigitalOcean or AWS.
* Make and Makefile should be used for repo actions like building a container, deploying, testing, linting, etc. If a Github action job doesn't use a pre-created action then it should use make to perform the action.
* The DO sfo3 region and the AWS us-west-2 region should be used
* Ensure that all resources create by Terraform are tagged with my username jkeegan. For DO this is just the value as a tag, in aws the key should be `Owner` and the value should be `jkeegan`.
* In DO any resource that is created and can be part of a Project should be made part of a `jkeegan` project.

## Phase 1: Foundation Setup

**Summary:** Establish the base infrastructure on DigitalOcean and AWS to enable further integration.

### Technical Objectives:

1. **Repository and CI/CD Setup**

    * Configure GitHub Actions for container image build and deployment to DigitalOcean App Platform.
    * Define Terraform project structure in repo.

2. **DigitalOcean Infrastructure**

    * Create App Platform service to run the containerized application.
    * Provision PostgreSQL and Valkey instances via DigitalOcean DBaaS.

3. **Networking and Access**

    * Ensure secure connectivity from App Platform app to both DBaaS instances (private networking where possible).

### Success Criteria:

* Containerized "hello world" app deployed to App Platform via Terraform. This can be as simple as just running an nginx container.
* PostgreSQL and Valkey provisioned and reachable from the app. Having the app interact with the DBs is done in phase 2, this just ensures interaction is possible.
* GitHub push triggers build and deploy to App Platform.

---

## Phase 2: Application Scaffold with DB Connectivity

**Summary:** Replace the hello-world with a minimal two-tier app: a Python **FastAPI** backend API and a static **JavaScript** frontend. The API connects to PostgreSQL and Valkey using environment variables provided by App Platform and exposes health/status endpoints. The frontend is built as static assets and **uploaded to a DigitalOcean Spaces bucket** (created via Terraform) to display DB connectivity results.

### Technical Objectives:

1. **App Implementation (Backend: FastAPI)**

    * Implement a FastAPI service with routes:

        * `/healthz` (basic liveness)
        * `/db/status` (returns JSON with Postgres and Valkey ping results)
    * Implement simple write+read verification to Postgres and a `PING` then `SET`/`GET` to Valkey.
    * Enable CORS to allow requests from the Spaces-hosted frontend.
    * Structured JSON logging for connection attempts/failures.

2. **App Implementation (Frontend: Static JS in Spaces)**

    * Create a minimal JS/HTML page that calls the API’s `/db/status` and renders **OK/FAIL** badges for Postgres and Valkey.
    * Build artifacts (e.g., `index.html`, `app.js`, `styles.css`) are uploaded to a **DigitalOcean Spaces** bucket.

3. **Infrastructure (Spaces + App Platform via Terraform)**

    * Create a **Spaces bucket** (and optional CDN endpoint) via Terraform.
    * Configure Spaces **CORS rules** to allow the frontend to call the API domain and fetch assets.
    * Upload static artifacts to the bucket during CI (GitHub Actions) or via Terraform object resources.
    * Output the public URL (or CDN URL) of the frontend from Terraform for use in testing.

4. **Configuration via Environment Variables (API)**

    * Define App Platform environment variables for:

        * `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`, `PGSSLMODE`
        * `VALKEY_HOST`, `VALKEY_PORT`, `VALKEY_PASSWORD`
        * `API_CORS_ORIGINS` (comma-separated; include the Spaces/CDN URL of the frontend)
    * Inject these via Terraform `digitalocean_app` resource.

5. **Database Bootstrapping**

    * Add basic schema migration (e.g., a single table) using a migration tool or inline SQL.
    * Provide a simple endpoint or startup hook that ensures schema existence for the demo table.

### Success Criteria:

* New app version (FastAPI API) deployed to App Platform via CI/CD.
* Spaces bucket is created via Terraform and contains the uploaded frontend assets; the frontend is reachable at the Spaces URL.&#x20;
* Since the plan is to use CloudFront the DO CDN should be not be used for either the spaces bucket or the App Platform app itself.
* Visiting the frontend displays connectivity results; calling `/db/status` shows **OK/FAIL** for both PostgreSQL and Valkey.
* A test write/read to Postgres and a `SET`/`GET` in Valkey succeed under normal conditions.
* All API connection details are supplied exclusively via App Platform environment variables.

---

## Phase 3: AWS Service Integration

**Summary:** Integrate AWS WAF with CloudFront with access from App Platform.

### Technical Objectives:

1. **AWS WAF & CloudFront**

    * Provision CloudFront distribution with AWS WAF WebACL.
    * Configure two origins
      * App Platform default URL for API calls
      * Spaces Bucket for static content
    * Validate that traffic flows from CloudFront → App Platform.
    * A CNAME \`poc-app-platform-aws.digitailocean.solutions\` should be created for the CloudFront Distribution. The digitailocean.solutions domain is within the Team used for the PoC so creating the CNAME should be done using Terraform with the rest of the stack.

### Success Criteria:

* Requests to CNAME are routed through AWS WAF and reach the App Platform app.

---

## Phase 4: AWS IAM Roles Anywhere Integration

**Summary:** Configure IAM Roles Anywhere to enable the App Platform application to authenticate to AWS services using X.509 certificates. The application will demonstrate successful authentication by retrieving and displaying the assumed IAM role ARN.

### Technical Objectives:

1. **Certificate Infrastructure (via Terraform)**
   * Use the `hashicorp/tls` provider to create a self-signed CA certificate
   * Generate a client certificate signed by the CA for the application
   * Store certificates as App Platform environment variables or secrets

2. **AWS IAM Roles Anywhere Setup (via Terraform)**
   * Create an IAM Roles Anywhere trust anchor using the CA certificate
   * Create an IAM role with minimal permissions (just `sts:GetCallerIdentity`)
   * Configure an IAM Roles Anywhere profile linking the trust anchor to the role
   * Set up trust relationship allowing assumption via Roles Anywhere

3. **Application Updates**
   * Modify the FastAPI backend to:
      * Load the client certificate and private key from environment variables
      * Use AWS STS with IAM Roles Anywhere to assume the role
      * Call `sts:GetCallerIdentity` to retrieve the assumed role ARN
   * Expose a `/iam/status` API endpoint returning JSON with:
      * `ok`: boolean (true if role assumption succeeded)
      * `role_arn`: string (the assumed IAM role ARN)
      * `error`: string (optional, error message if failed)

4. **Frontend Update**
   * Add a new section in the static JS frontend that calls `/iam/status`
   * Display OK/FAIL badge for IAM Roles Anywhere connectivity
   * Show the assumed IAM Role ARN when successful

### Success Criteria:

* All certificates and IAM Roles Anywhere infrastructure created via `terraform apply`
* Application successfully assumes IAM role using X.509 certificate authentication
* Frontend displays OK badge and the correct IAM Role ARN
* No manual certificate generation or AWS console configuration required
* Clean terraform plan on subsequent runs (idempotent)

---

## Phase 5: AWS Secrets Manager Integration

**Summary:** Extend the application to demonstrate AWS Secrets Manager access using the IAM role established in Phase 4. A dummy secret will be created in Secrets Manager, retrieved by the backend API, and displayed in the frontend.

### Technical Objectives:

1. **Secrets Manager Setup (via Terraform)**
   * Create a dummy secret in AWS Secrets Manager (e.g., `poc-app-platform/test-secret`)
   * Update the IAM role from Phase 4 to include permissions:
      * `secretsmanager:GetSecretValue` for the specific secret
      * `secretsmanager:DescribeSecret` for the specific secret

2. **Application Updates**
   * Extend the FastAPI backend to:
      * Use the existing IAM Roles Anywhere authentication from Phase 4
      * Retrieve the dummy secret from AWS Secrets Manager
      * Handle potential errors gracefully with structured logging
   * Expose a `/secret/status` API endpoint returning JSON with:
      * `ok`: boolean (true if secret retrieval succeeded)
      * `secret_value`: string (value of the dummy secret)
      * `secret_name`: string (name/ARN of the secret)
      * `error`: string (optional, error message if failed)

3. **Frontend Update**
   * Add a new section in the static JS frontend that calls `/secret/status`
   * Display OK/FAIL badge for AWS Secrets Manager connectivity
   * Show the secret value and name in a readable format
   * Maintain visual consistency with other status badges

### Success Criteria:

* Dummy secret created in AWS Secrets Manager via Terraform
* Application retrieves the secret using IAM Roles Anywhere authentication
* Frontend shows OK badge and displays the secret value
* All permissions follow least-privilege principle
* Complete deployment remains achievable with single `terraform apply`
* No hardcoded AWS credentials anywhere in the codebase

## Phase 6: App Platform Worker for Continuous Data Updates

**Summary:** Deploy an App Platform worker service that continuously updates timestamps in PostgreSQL, Valkey, and AWS Secrets Manager every minute. The frontend will display these timestamps alongside connectivity status to demonstrate real-time data flow from all integrated services.

### Technical Objectives:

1. **Worker Service Implementation**
    * Create a Python-based worker service that runs as an App Platform worker component
    * Implement a continuous loop that executes every 60 seconds to:
        * Write current UTC timestamp to a dedicated PostgreSQL table (`last_update` table with columns: `source`, `timestamp`, `metadata`)
        * Set a UTC timestamp in Valkey with key `worker:last_update`
        * Update the AWS Secrets Manager secret with a JSON payload containing the current UTC timestamp
    * Use the same connection patterns and environment variables as the main API
    * Implement structured logging for all update operations
    * Handle failures gracefully with exponential backoff retry logic

2. **API Endpoint Extensions**
    * Modify `/db/status` to include:
        * `postgres_last_update`: UTC timestamp from the `last_update` table
        * `valkey_last_update`: UTC timestamp from the `worker:last_update` key
    * Modify `/secret/status` to parse and return the timestamp from the secret's JSON payload
    * Modify `/iam/status` to include:
        * `credentials_expiry`: expiration time of the assumed role credentials
        * `credentials_created`: when the credentials were obtained
    * Add a new `/worker/status` endpoint that aggregates all timestamps:
        * Returns JSON with all data source timestamps
        * Calculates age of each timestamp
        * Indicates if any source is stale (>90 seconds old)

3. **Infrastructure Updates (via Terraform)**
    * Add worker service definition to the `digitalocean_app` resource:
        * Use same container image as the API but with different run command
        * Configure as `type = "WORKER"`
        * Share database connection environment variables with main service
        * Ensure worker has access to IAM Roles Anywhere certificates
    * Update PostgreSQL schema to include `last_update` table
    * Modify AWS Secrets Manager secret to accept JSON format
    * Ensure IAM role permissions include `secretsmanager:UpdateSecret`

4. **Frontend Enhancements**
    * Add a "Last Updated" column after the "Endpoint / FQDN" column
    * Display timestamps for each service:
        * PostgreSQL: Show last update time and age (e.g., "2024-01-15 14:30:45 UTC (23s ago)")
        * Valkey: Show last update time and age
        * AWS Secrets Manager: Show last update time from secret content
        * IAM Roles Anywhere: Show credential creation time and time until expiry
    * Use color coding for timestamp freshness:
        * Green: <60 seconds old
        * Yellow: 60-90 seconds old
        * Red: >90 seconds old
    * Auto-refresh the page every 30 seconds or provide a manual refresh button
    * Add visual indicator (spinner/badge) showing when data is being refreshed

5. **Worker Lifecycle Management**
    * Implement graceful shutdown handling for the worker
    * Add health check endpoint specific to worker (can be same container, different command)
    * Configure App Platform alerts for worker failures
    * Implement dead letter queue pattern for failed updates

### Implementation Details:

**Worker Service Structure:**
```python
# worker.py
import asyncio
import json
from datetime import datetime, timezone
import os
import logging

async def update_postgres(connection_params):
    # Update or insert timestamp in last_update table
    pass

async def update_valkey(connection_params):
    # SET worker:last_update with current UTC timestamp
    pass

async def update_secrets_manager(iam_client):
    # Update secret with JSON containing timestamp
    pass

async def main():
    while True:
        try:
            timestamp = datetime.now(timezone.utc)
            await asyncio.gather(
                update_postgres(pg_params),
                update_valkey(valkey_params),
                update_secrets_manager(aws_client)
            )
            logging.info(f"Successfully updated all sources at {timestamp}")
        except Exception as e:
            logging.error(f"Update cycle failed: {e}")
        
        await asyncio.sleep(60)
```

**Terraform Worker Configuration:**
```hcl
# In digitalocean_app resource
service {
  name               = "timestamp-worker"
  environment_slug   = "python"
  instance_count     = 1
  instance_size_slug = "apps-s-1vcpu-0.5gb"
  
  image {
    registry_type = "DOCR"
    repository    = var.container_repository
    tag           = var.container_tag
  }
  
  run_command = "python worker.py"
  
  # Share same env vars as main API service
  env {
    key   = "PGHOST"
    value = digitalocean_database_cluster.postgres.host
  }
  # ... additional env vars
}
```

### Success Criteria:

* Worker service successfully deploys as part of `terraform apply`
* All three data sources show timestamps updating every ~60 seconds
* Frontend displays current timestamps with age indicators for all services
* Timestamps remain fresh even during API restarts (worker runs independently)
* No manual intervention required for worker deployment or operation
* Clean separation between API and worker services while sharing same codebase
* Graceful handling of transient failures with automatic recovery
* Frontend clearly shows that data is being actively updated from all integrated services
* Complete system demonstrates end-to-end integration with real-time data flow

### Testing Validation:

* Stop worker service → timestamps should become stale and show red in UI
* Restart worker → timestamps should resume updating within 60 seconds
* Kill database connection → worker should log errors but continue attempting other updates
* Verify timestamp consistency across multiple frontend sessions
* Confirm worker resource usage remains stable over extended runs (no memory leaks)

---

## Deliverables

* Terraform code for all infrastructure.
* Application container code.
* GitHub Actions workflow for CI/CD.
* Documentation for setup, configuration, and testing.
