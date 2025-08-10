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
* **Stateless re‑targeting:** By updating these secrets (and any provider/account IDs captured as variables) to point at a different **DigitalOcean Team** and **AWS account**, then re-running the deploy workflow, the pipeline should create a **fresh, isolated deployment** in the new environments without modifying the previous one.
* **Inputs over edits:** Environment- and account-specific values should be expressed as Terraform variables or GitHub Actions inputs, not hard-coded in modules or app code.
* **Idempotence:** Terraform plans must be clean on re-runs; CI should fail on drift.
* If the case there does need to be manual interact with GitHub, DigitalOcean or AWS this will be done for you. You are not to use utilities or interact directly with GitHub, DigitalOcean or AWS.
* Make and Makefile should be used for repo actions like building a container, deploying, testing, linting, etc. If a Github action job doesn't use a pre-created action then it should use make to perform the action.
* The DO sfo3 region and the AWS us-west-2 region should be used

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

**Summary:** Integrate AWS WAF with CloudFront and configure Secrets Manager access from App Platform.

### Technical Objectives:

1. **AWS WAF & CloudFront**

    * Provision CloudFront distribution with AWS WAF WebACL.
    * Configure origin to point to the App Platform default URL.
    * Validate that traffic flows from CloudFront → App Platform.
    * A CNAME \`ap-aws-poc.digitailocean.solutions\` should be created for the CloudFront Distribution. The digitailocean.solutions domain is within the Team used for the PoC so creating the CNAME should be done using Terraform with the rest of the stack.

### Success Criteria:

* Requests to CNAME are routed through AWS WAF and reach the App Platform app.

---

## Phase 4: Application Integration with AWS Secrets Manager (Non-DB Secret Demo)

**Summary:** Extend the application to demonstrate AWS Secrets Manager access without using it for database credentials. A dummy secret will be created in Secrets Manager and retrieved by the backend API, which will return it and the IAM Role ARN used to the frontend. The frontend will display this information along with an OK/Fail badge indicating whether AWS Secrets Manager access works.

### Technical Objectives:

1. **Secrets Manager Access**

    * Configure AWS IAM Roles Anywhere.
    * Set up App Platform app to authenticate to AWS via IAM Roles Anywhere.
    * Retrieve test secret from AWS Secrets Manager.

2. **Application Deployment**

    * Modify the FastAPI backend to call AWS Secrets Manager using IAM Roles Anywhere, fetch a specific dummy secret, and determine the ARN of the IAM role used for retrieval.
    * Expose a `/secret/status` API endpoint returning JSON with:

        * `ok`: boolean
        * `secret_value`: string (value of the dummy secret)
        * `role_arn`: string (IAM role ARN used)

3. **Frontend Update**

    * Add a new section in the static JS frontend that calls `/secret/status`.
    * Display OK/Fail status for AWS Secrets Manager connectivity.
    * Show the secret value and IAM Role ARN in a simple, readable format.

### Success Criteria:

* Application retrieves the dummy secret from AWS Secrets Manager at runtime.
* Frontend shows the OK/Fail badge, secret value, and IAM Role ARN.
* All communication paths use secure protocols and least-privilege IAM access.

---

## Deliverables

* Terraform code for all infrastructure.
* Application container code.
* GitHub Actions workflow for CI/CD.
* Documentation for setup, configuration, and testing.
