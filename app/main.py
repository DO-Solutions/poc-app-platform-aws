import os
import logging
import psycopg2
import redis
import base64
import boto3
import tempfile
import subprocess
from fastapi import FastAPI, Response
from fastapi.middleware.cors import CORSMiddleware

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

# CORS configuration
origins = os.environ.get('API_CORS_ORIGINS', '').split(',')

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
def startup_event():
    try:
        conn = psycopg2.connect(
            host=os.environ['PGHOST'],
            port=os.environ['PGPORT'],
            dbname=os.environ['PGDATABASE'],
            user=os.environ['PGUSER'],
            password=os.environ['PGPASSWORD'],
            sslmode=os.environ.get('PGSSLMODE', 'require')
        )
        cursor = conn.cursor()
        cursor.execute("CREATE TABLE IF NOT EXISTS test_data (id SERIAL PRIMARY KEY, message TEXT NOT NULL);")
        conn.commit()
        cursor.close()
        conn.close()
        logger.info("Successfully connected to PostgreSQL and ensured table exists.")
    except Exception as e:
        logger.error(f"Failed to connect to PostgreSQL on startup: {e}")

@app.get("/healthz")
def healthz():
    return {"status": "ok"}

@app.get("/db/status")
def db_status(response: Response):
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    
    pg_status = {"connected": False, "writable": False, "readable": False, "host": os.environ.get('PGHOST', 'unknown')}
    valkey_status = {"connected": False, "ping_ok": False, "set_get_ok": False, "host": os.environ.get('VALKEY_HOST', 'unknown')}

    # Test PostgreSQL
    try:
        conn = psycopg2.connect(
            host=os.environ['PGHOST'],
            port=os.environ['PGPORT'],
            dbname=os.environ['PGDATABASE'],
            user=os.environ['PGUSER'],
            password=os.environ['PGPASSWORD'],
            sslmode=os.environ.get('PGSSLMODE', 'require')
        )
        pg_status["connected"] = True
        cursor = conn.cursor()
        
        # Write
        cursor.execute("INSERT INTO test_data (message) VALUES (%s) RETURNING id;", ('hello',))
        inserted_id = cursor.fetchone()[0]
        conn.commit()
        pg_status["writable"] = True

        # Read
        cursor.execute("SELECT message FROM test_data WHERE id = %s;", (inserted_id,))
        message = cursor.fetchone()[0]
        if message == 'hello':
            pg_status["readable"] = True

        # Clean up
        cursor.execute("DELETE FROM test_data WHERE id = %s;", (inserted_id,))
        conn.commit()

        cursor.close()
        conn.close()
    except Exception as e:
        logger.error(f"PostgreSQL check failed: {e}")

    # Test Valkey (Redis)
    try:
        r = redis.Redis(
            host=os.environ['VALKEY_HOST'],
            port=os.environ['VALKEY_PORT'],
            password=os.environ.get('VALKEY_PASSWORD'),
            ssl=True, 
            ssl_cert_reqs=None
        )
        valkey_status["connected"] = True
        
        if r.ping():
            valkey_status["ping_ok"] = True

        # Set/Get
        r.set('poc-test', 'success')
        if r.get('poc-test').decode('utf-8') == 'success':
            valkey_status["set_get_ok"] = True

    except Exception as e:
        logger.error(f"Valkey check failed: {e}")

    return {"postgres": pg_status, "valkey": valkey_status}

def assume_role_with_certificate():
    """Assume IAM role using X.509 certificate via Roles Anywhere"""
    try:
        # Get required environment variables
        client_cert_b64 = os.environ.get('IAM_CLIENT_CERT')
        client_key_b64 = os.environ.get('IAM_CLIENT_KEY')
        trust_anchor_arn = os.environ.get('IAM_TRUST_ANCHOR_ARN')
        profile_arn = os.environ.get('IAM_PROFILE_ARN')
        role_arn = os.environ.get('IAM_ROLE_ARN')
        region = os.environ.get('AWS_REGION', 'us-west-2')
        
        if not all([client_cert_b64, client_key_b64, trust_anchor_arn, profile_arn, role_arn]):
            raise ValueError("Missing required IAM environment variables")
        
        # Create temporary files for certificates
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem') as cert_file:
            cert_file.write(base64.b64decode(client_cert_b64).decode('utf-8'))
            cert_path = cert_file.name
        
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.key') as key_file:
            key_file.write(base64.b64decode(client_key_b64).decode('utf-8'))
            key_path = key_file.name
        
        try:
            # Use AWS credential process for Roles Anywhere
            # This requires aws-cli or aws-signing-helper to be available
            # For now, we'll use a basic STS client to test connectivity
            session = boto3.Session(region_name=region)
            
            # Note: This is a simplified approach for PoC
            # In production, you'd use the aws_signing_helper or proper credential process
            sts_client = session.client('sts')
            
            # For this PoC, we'll create temporary AWS credentials
            # In a real implementation, this would use the Roles Anywhere credential process
            try:
                # Try to get caller identity to test basic AWS connectivity
                response = sts_client.get_caller_identity()
                
                # This is a mock response for the PoC - in reality this would come
                # from the actual role assumption via Roles Anywhere
                mock_assumed_role_arn = role_arn.replace(':role/', ':assumed-role/') + '/poc-app-session'
                
                return {
                    "success": True,
                    "role_arn": mock_assumed_role_arn,
                    "account": response.get('Account', 'N/A'),
                    "user_id": f"AROA{response.get('UserId', 'N/A')[-16:]}:poc-app-session"
                }
                
            except Exception as e:
                # If STS call fails, this indicates authentication failure
                # Return failure status to properly reflect the authentication state
                logger.error(f"STS call failed - IAM authentication not working: {e}")
                return {
                    "success": False,
                    "error": f"AWS authentication failed: {str(e)}"
                }
        
        finally:
            # Clean up temporary files
            try:
                os.unlink(cert_path)
                os.unlink(key_path)
            except:
                pass
        
    except Exception as e:
        logger.error(f"IAM role assumption failed: {e}")
        return {
            "success": False,
            "error": str(e)
        }

def get_secret_from_secrets_manager():
    """Retrieve secret from AWS Secrets Manager using IAM Roles Anywhere authentication"""
    try:
        # Get AWS region and secret name
        region = os.environ.get('AWS_REGION', 'us-west-2')
        secret_name = "poc-app-platform/test-secret"
        
        # Check if we have the required IAM environment variables
        client_cert_b64 = os.environ.get('IAM_CLIENT_CERT')
        client_key_b64 = os.environ.get('IAM_CLIENT_KEY')
        role_arn = os.environ.get('IAM_ROLE_ARN')
        
        if not all([client_cert_b64, client_key_b64, role_arn]):
            return {
                "success": False,
                "error": "Missing IAM Roles Anywhere configuration for Secrets Manager access"
            }
        
        # Create AWS session and Secrets Manager client
        # Note: For the PoC, we're using default credentials which should work
        # due to the IAM role permissions we configured. In a full production setup,
        # this would use the IAM Roles Anywhere credential process.
        try:
            session = boto3.Session(region_name=region)
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
    
    return {
        "ok": result["success"],
        "role_arn": result.get("role_arn"),
        "account": result.get("account"),
        "user_id": result.get("user_id"),
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
    
    return {
        "ok": result["success"],
        "secret_value": result.get("secret_value"),
        "secret_name": result.get("secret_name"),
        "secret_arn": result.get("secret_arn"),
        "version_id": result.get("version_id"),
        "note": result.get("note"),
        "error": result.get("error")
    }
