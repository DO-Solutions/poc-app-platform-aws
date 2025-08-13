"""
PoC App Platform AWS Integration - FastAPI Backend Service

This service demonstrates DigitalOcean App Platform integration with AWS services including:
- PostgreSQL and Valkey databases via DigitalOcean DBaaS
- AWS IAM Roles Anywhere for certificate-based authentication
- AWS Secrets Manager for secure secret storage and retrieval
- Real-time timestamp tracking via worker service integration

The application provides REST API endpoints for connectivity testing and status monitoring
of all integrated services, with comprehensive logging for troubleshooting and monitoring.

The service includes timestamp tracking from worker service updates, showing real-time 
data flow across all integrated services.
"""

import os
import logging
import psycopg2
import redis
import base64
import boto3
import tempfile
import subprocess
import json
from datetime import datetime, timezone, timedelta
from fastapi import FastAPI, Response
from fastapi.middleware.cors import CORSMiddleware

from iam_anywhere import get_iam_anywhere_session

# Configure structured logging for PoC monitoring and troubleshooting
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastAPI application for PoC demonstration
app = FastAPI(
    title="PoC App Platform AWS Integration",
    description="Demonstrates DigitalOcean App Platform integration with AWS services",
    version="1.0.0"
)

# CORS configuration for frontend integration
# Allows the static frontend (served from DigitalOcean Spaces) to call API endpoints
origins = os.environ.get('API_CORS_ORIGINS', '').split(',')
logger.info(f"Configuring CORS for origins: {origins}")

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
def startup_event():
    """
    Application startup event handler.
    
    Initializes database schema on application startup:
    1. Connects to PostgreSQL using App Platform environment variables
    2. Creates test_data table for connectivity testing
    3. Creates last_update table for worker timestamp tracking
    
    This ensures the database is ready for both API operations and worker updates.
    """
    logger.info("Starting application initialization...")
    
    try:
        # Connect to PostgreSQL using DigitalOcean DBaaS connection details
        # These environment variables are automatically injected by App Platform
        logger.info("Connecting to PostgreSQL for schema initialization...")
        conn = psycopg2.connect(
            host=os.environ['PGHOST'],
            port=os.environ['PGPORT'],
            dbname=os.environ['PGDATABASE'],
            user=os.environ['PGUSER'],
            password=os.environ['PGPASSWORD'],
            sslmode=os.environ.get('PGSSLMODE', 'require')
        )
        cursor = conn.cursor()
        
        # Create table for API connectivity testing (read/write verification)
        cursor.execute("CREATE TABLE IF NOT EXISTS test_data (id SERIAL PRIMARY KEY, message TEXT NOT NULL);")
        logger.info("test_data table verified/created for connectivity testing")
        
        # Create table for worker timestamp tracking
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS last_update (
                source VARCHAR(50) PRIMARY KEY,
                timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
                metadata JSONB
            )
        """)
        logger.info("last_update table verified/created for worker timestamp tracking")
        
        conn.commit()
        cursor.close()
        conn.close()
        logger.info("Database schema initialization completed successfully")
        
    except Exception as e:
        logger.error(f"Database initialization failed during startup: {e}")
        logger.error("Application may not function properly without database connectivity")

@app.get("/healthz")
def healthz():
    """
    Basic health check endpoint for App Platform monitoring.
    
    Returns:
        dict: Simple status indicator for load balancer health checks
    """
    return {"status": "ok"}

@app.get("/db/status")
def db_status(response: Response):
    """
    Comprehensive database connectivity testing endpoint.
    
    Tests both PostgreSQL and Valkey (Redis) connections with:
    - Connection establishment
    - Read/write operations for PostgreSQL
    - PING and SET/GET operations for Valkey
    - Worker timestamp retrieval
    
    Args:
        response: FastAPI Response object for setting cache headers
        
    Returns:
        dict: Detailed status for both PostgreSQL and Valkey including
              connectivity, operations, hostnames, and latest worker timestamps
    """
    # Prevent browser/proxy caching for real-time status
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    
    # Initialize status tracking for both databases
    pg_status = {
        "connected": False, 
        "writable": False, 
        "readable": False, 
        "host": os.environ.get('PGHOST', 'unknown'), 
        "postgres_last_update": None
    }
    valkey_status = {
        "connected": False, 
        "ping_ok": False, 
        "set_get_ok": False, 
        "host": os.environ.get('VALKEY_HOST', 'unknown'), 
        "valkey_last_update": None
    }

    # PostgreSQL Connectivity and Operations Testing
    logger.info("Starting PostgreSQL connectivity test...")
    try:
        # Establish connection using App Platform environment variables
        conn = psycopg2.connect(
            host=os.environ['PGHOST'],
            port=os.environ['PGPORT'],
            dbname=os.environ['PGDATABASE'],
            user=os.environ['PGUSER'],
            password=os.environ['PGPASSWORD'],
            sslmode=os.environ.get('PGSSLMODE', 'require')
        )
        pg_status["connected"] = True
        logger.info("PostgreSQL connection established successfully")
        cursor = conn.cursor()
        
        # Test write capability with a temporary record
        cursor.execute("INSERT INTO test_data (message) VALUES (%s) RETURNING id;", ('hello',))
        inserted_id = cursor.fetchone()[0]
        conn.commit()
        pg_status["writable"] = True
        logger.info(f"PostgreSQL write test successful (record ID: {inserted_id})")

        # Test read capability by retrieving the inserted record
        cursor.execute("SELECT message FROM test_data WHERE id = %s;", (inserted_id,))
        message = cursor.fetchone()[0]
        if message == 'hello':
            pg_status["readable"] = True
            logger.info("PostgreSQL read test successful")

        # Clean up test data to avoid accumulation
        cursor.execute("DELETE FROM test_data WHERE id = %s;", (inserted_id,))
        conn.commit()
        logger.info("PostgreSQL test data cleanup completed")

        # Retrieve latest worker timestamp from last_update table
        try:
            cursor.execute("SELECT timestamp FROM last_update WHERE source = %s;", ('worker',))
            result = cursor.fetchone()
            if result:
                pg_status["postgres_last_update"] = result[0].isoformat()
                logger.info(f"Retrieved worker timestamp from PostgreSQL: {pg_status['postgres_last_update']}")
            else:
                logger.info("No worker timestamp found in PostgreSQL (worker may not have run yet)")
        except Exception as e:
            logger.debug(f"Could not fetch worker timestamp from PostgreSQL: {e}")

        cursor.close()
        conn.close()
        logger.info("PostgreSQL connectivity test completed successfully")
        
    except Exception as e:
        logger.error(f"PostgreSQL connectivity test failed: {e}")
        logger.error("This may indicate database connectivity issues, credential problems, or network issues")

    # Valkey (Redis) Connectivity and Operations Testing
    logger.info("Starting Valkey connectivity test...")
    try:
        # Connect to Valkey using SSL (required for DigitalOcean DBaaS)
        r = redis.Redis(
            host=os.environ['VALKEY_HOST'],
            port=os.environ['VALKEY_PORT'],
            password=os.environ.get('VALKEY_PASSWORD'),
            ssl=True, 
            ssl_cert_reqs=None
        )
        valkey_status["connected"] = True
        logger.info("Valkey connection established successfully")
        
        # Test basic connectivity with PING command
        if r.ping():
            valkey_status["ping_ok"] = True
            logger.info("Valkey PING test successful")

        # Test SET/GET operations to verify read/write functionality
        r.set('poc-test', 'success')
        if r.get('poc-test').decode('utf-8') == 'success':
            valkey_status["set_get_ok"] = True
            logger.info("Valkey SET/GET test successful")

        # Retrieve latest worker timestamp from Valkey
        try:
            timestamp = r.get('worker:last_update')
            if timestamp:
                valkey_status["valkey_last_update"] = timestamp.decode('utf-8')
                logger.info(f"Retrieved worker timestamp from Valkey: {valkey_status['valkey_last_update']}")
            else:
                logger.info("No worker timestamp found in Valkey (worker may not have run yet)")
        except Exception as e:
            logger.debug(f"Could not fetch worker timestamp from Valkey: {e}")

        logger.info("Valkey connectivity test completed successfully")

    except Exception as e:
        logger.error(f"Valkey connectivity test failed: {e}")
        logger.error("This may indicate database connectivity issues, SSL/TLS problems, or network issues")

    return {"postgres": pg_status, "valkey": valkey_status}

def assume_role_with_certificate():
    """
    Assume IAM role using X.509 certificate via AWS IAM Roles Anywhere.
    
    This function implements the IAM Roles Anywhere authentication flow by:
    1. Loading X.509 client certificates from environment variables
    2. Using the IAM Roles Anywhere CreateSession API to get temporary credentials
    3. Validating the credentials with AWS STS GetCallerIdentity
    4. Returning role assumption details including ARN and session info
    
    Returns:
        dict: Contains success status, role ARN, account ID, and user ID
              or error information if authentication fails
    """
    logger.info("Starting IAM Roles Anywhere authentication process")
    
    try:
        # Get required environment variables for IAM Roles Anywhere
        client_cert_b64 = os.environ.get('IAM_CLIENT_CERT')
        client_key_b64 = os.environ.get('IAM_CLIENT_KEY')
        trust_anchor_arn = os.environ.get('IAM_TRUST_ANCHOR_ARN')
        profile_arn = os.environ.get('IAM_PROFILE_ARN')
        role_arn = os.environ.get('IAM_ROLE_ARN')
        region = os.environ.get('AWS_REGION', 'us-west-2')
        
        logger.info(f"IAM Roles Anywhere configuration - Trust Anchor: {trust_anchor_arn}, Profile: {profile_arn}, Role: {role_arn}, Region: {region}")
        
        if not all([client_cert_b64, client_key_b64, trust_anchor_arn, profile_arn, role_arn]):
            logger.error("Missing required IAM Roles Anywhere environment variables")
            raise ValueError("Missing required IAM environment variables")
        
        # Get AWS session using IAM Roles Anywhere
        logger.info("Getting AWS session using IAM Roles Anywhere credentials")
        session, credentials = get_iam_anywhere_session(
            region=region,
            trust_anchor_arn=trust_anchor_arn,
            profile_arn=profile_arn,
            role_arn=role_arn,
            client_cert_b64=client_cert_b64,
            client_key_b64=client_key_b64
        )
        
        if not session or not credentials:
            logger.error("Failed to obtain IAM Roles Anywhere session")
            return {
                "success": False,
                "error": "Failed to obtain IAM Roles Anywhere credentials"
            }
        
        # Validate credentials with STS GetCallerIdentity
        try:
            logger.info("Validating IAM Roles Anywhere credentials with STS GetCallerIdentity")
            sts_client = session.client('sts')
            response = sts_client.get_caller_identity()
            
            logger.info(f"IAM Roles Anywhere authentication successful - Account: {response.get('Account')}, Assumed Role: {credentials.get('AssumedRoleArn')}")
            
            return {
                "success": True,
                "role_arn": credentials.get('AssumedRoleArn'),
                "account": response.get('Account', 'N/A'),
                "user_id": response.get('UserId', 'N/A'),
                "credentials_expiration": credentials.get('Expiration'),
                "subject_arn": credentials.get('SubjectArn')
            }
            
        except Exception as e:
            logger.error(f"IAM Roles Anywhere credential validation failed - STS GetCallerIdentity error: {e}")
            return {
                "success": False,
                "error": f"AWS credential validation failed: {str(e)}"
            }
        
    except Exception as e:
        logger.error(f"IAM role assumption failed: {e}")
        return {
            "success": False,
            "error": str(e)
        }

def get_secret_from_secrets_manager():
    """
    Retrieve and parse secret from AWS Secrets Manager.
    
    This function demonstrates AWS Secrets Manager integration using IAM Roles Anywhere
    for authentication. It retrieves the test secret and parses JSON content for
    worker timestamp information.
    
    Returns:
        dict: Contains success status, secret value, metadata, and timestamp information
              or error details if the operation fails
    """
    logger.info("Starting AWS Secrets Manager secret retrieval...")
    
    try:
        # AWS configuration
        region = os.environ.get('AWS_REGION', 'us-west-2')
        secret_name = os.environ.get('SECRETS_MANAGER_SECRET_NAME', 'poc-app-platform/test-secret')
        
        logger.info(f"Retrieving secret '{secret_name}' from region '{region}'")
        
        # Verify IAM Roles Anywhere configuration is available
        client_cert_b64 = os.environ.get('IAM_CLIENT_CERT')
        client_key_b64 = os.environ.get('IAM_CLIENT_KEY')
        role_arn = os.environ.get('IAM_ROLE_ARN')
        
        if not all([client_cert_b64, client_key_b64, role_arn]):
            logger.error("Missing IAM Roles Anywhere configuration for Secrets Manager access")
            return {
                "success": False,
                "error": "Missing IAM Roles Anywhere configuration for Secrets Manager access"
            }
        
        # Get AWS session using IAM Roles Anywhere
        logger.info("Getting AWS session using IAM Roles Anywhere for Secrets Manager access")
        trust_anchor_arn = os.environ.get('IAM_TRUST_ANCHOR_ARN')
        profile_arn = os.environ.get('IAM_PROFILE_ARN')
        
        session, credentials = get_iam_anywhere_session(
            region=region,
            trust_anchor_arn=trust_anchor_arn,
            profile_arn=profile_arn,
            role_arn=role_arn,
            client_cert_b64=client_cert_b64,
            client_key_b64=client_key_b64
        )
        
        if not session:
            logger.error("Failed to get IAM Roles Anywhere session for Secrets Manager")
            return {
                "success": False,
                "error": "Failed to obtain IAM Roles Anywhere credentials for Secrets Manager"
            }
        
        try:
            secrets_client = session.client('secretsmanager')
            
            # Actually retrieve the secret from AWS Secrets Manager
            logger.info(f"Retrieving secret {secret_name} from AWS Secrets Manager")
            response = secrets_client.get_secret_value(SecretId=secret_name)
            
            secret_value = response['SecretString']
            secret_arn = response['ARN']
            version_id = response['VersionId']
            
            logger.info(f"Successfully retrieved secret {secret_name}")
            
            return {
                "success": True,
                "secret_value": secret_value,
                "secret_name": secret_name,
                "secret_arn": secret_arn,
                "version_id": version_id
            }
            
        except secrets_client.exceptions.ResourceNotFoundException:
            logger.error(f"Secret {secret_name} not found in AWS Secrets Manager")
            return {
                "success": False,
                "error": f"Secret '{secret_name}' not found"
            }
        except secrets_client.exceptions.InvalidRequestException as e:
            logger.error(f"Invalid request for secret {secret_name}: {e}")
            return {
                "success": False,
                "error": f"Invalid request: {str(e)}"
            }
        except secrets_client.exceptions.InvalidParameterException as e:
            logger.error(f"Invalid parameter for secret {secret_name}: {e}")
            return {
                "success": False,
                "error": f"Invalid parameter: {str(e)}"
            }
        except Exception as e:
            logger.error(f"Failed to retrieve secret {secret_name}: {e}")
            return {
                "success": False,
                "error": f"Failed to retrieve secret: {str(e)}"
            }
    
    except Exception as e:
        logger.error(f"Secrets Manager setup failed: {e}")
        return {
            "success": False,
            "error": f"Setup failed: {str(e)}"
        }

@app.get("/iam/status")
def iam_status(response: Response):
    """Check IAM Roles Anywhere authentication status"""
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    
    result = assume_role_with_certificate()
    
    # Extract real AWS timestamps - REQUIRED for success
    expiry_str = result.get("credentials_expiration")
    if expiry_str and result["success"]:
        try:
            # Parse the AWS-provided expiration timestamp
            expiry_time = datetime.fromisoformat(expiry_str.replace('Z', '+00:00'))
            # Calculate creation time (session duration is 1 hour)
            creation_time = expiry_time - timedelta(hours=1)
            credentials_created = creation_time.isoformat()
            credentials_expiry = expiry_time.isoformat()
        except Exception as e:
            # If we can't parse AWS timestamps, authentication failed
            logger.error(f"Failed to parse AWS credential timestamps: {e}")
            result["success"] = False
            result["error"] = f"Failed to obtain AWS credential timestamps: {str(e)}"
            credentials_created = None
            credentials_expiry = None
    else:
        # No AWS timestamps = authentication failure
        if result["success"]:
            result["success"] = False
            result["error"] = "No AWS credential timestamps received - authentication incomplete"
        credentials_created = None
        credentials_expiry = None
    
    return {
        "ok": result["success"],
        "role_arn": result.get("role_arn"),
        "account": result.get("account"),
        "user_id": result.get("user_id"),
        "credentials_created": credentials_created,
        "credentials_expiry": credentials_expiry,
        "note": result.get("note"),
        "error": result.get("error")
    }

@app.get("/secret/status")
def secret_status(response: Response):
    """Check AWS Secrets Manager connectivity and retrieve test secret"""
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache" 
    response.headers["Expires"] = "0"
    
    result = get_secret_from_secrets_manager()
    
    # Parse timestamp from JSON secret if available
    secret_timestamp = None
    if result.get("success") and result.get("secret_value"):
        try:
            secret_data = json.loads(result["secret_value"])
            secret_timestamp = secret_data.get("updated_at")
        except (json.JSONDecodeError, AttributeError):
            # If secret is not JSON format, that's okay
            pass
    
    return {
        "ok": result["success"],
        "secret_value": result.get("secret_value"),
        "secret_name": result.get("secret_name"),
        "secret_arn": result.get("secret_arn"),
        "version_id": result.get("version_id"),
        "secret_last_update": secret_timestamp,
        "note": result.get("note"),
        "error": result.get("error")
    }

@app.get("/worker/status")
def worker_status(response: Response):
    """Aggregated status of all worker timestamp updates"""
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    
    current_time = datetime.now(timezone.utc)
    stale_threshold = 90  # seconds
    
    # Get data from other endpoints
    db_data = db_status(response)
    secret_data = secret_status(response) 
    iam_data = iam_status(response)
    
    def calculate_age(timestamp_str):
        """Calculate age of timestamp in seconds"""
        if not timestamp_str:
            return None
        try:
            timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
            return (current_time - timestamp).total_seconds()
        except:
            return None
    
    postgres_age = calculate_age(db_data["postgres"].get("postgres_last_update"))
    valkey_age = calculate_age(db_data["valkey"].get("valkey_last_update"))
    secret_age = calculate_age(secret_data.get("secret_last_update"))
    
    return {
        "current_time": current_time.isoformat(),
        "stale_threshold_seconds": stale_threshold,
        "timestamps": {
            "postgres": {
                "last_update": db_data["postgres"].get("postgres_last_update"),
                "age_seconds": postgres_age,
                "is_stale": postgres_age is None or postgres_age > stale_threshold,
                "status": "ok" if db_data["postgres"].get("connected") else "error"
            },
            "valkey": {
                "last_update": db_data["valkey"].get("valkey_last_update"),
                "age_seconds": valkey_age,
                "is_stale": valkey_age is None or valkey_age > stale_threshold,
                "status": "ok" if db_data["valkey"].get("connected") else "error"
            },
            "secrets_manager": {
                "last_update": secret_data.get("secret_last_update"),
                "age_seconds": secret_age,
                "is_stale": secret_age is None or secret_age > stale_threshold,
                "status": "ok" if secret_data.get("ok") else "error"
            }
        },
        "overall_status": "ok" if all([
            db_data["postgres"].get("connected"),
            db_data["valkey"].get("connected"), 
            secret_data.get("ok")
        ]) else "error"
    }
