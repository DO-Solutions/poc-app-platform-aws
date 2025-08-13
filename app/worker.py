"""
PoC App Platform AWS Integration - Worker Service

This worker service runs continuously alongside the main API service and provides:
- Automated timestamp updates every 60 seconds to all integrated services
- PostgreSQL last_update table maintenance for API timestamp retrieval
- Valkey worker:last_update key management for real-time monitoring
- AWS Secrets Manager secret updates with JSON timestamp payloads
- Comprehensive logging for monitoring and troubleshooting
- Graceful shutdown handling for production deployment

The worker demonstrates real-time data flow across the entire PoC infrastructure,
showing continuous integration between DigitalOcean services and AWS services
through automated background operations.

Architecture:
- Runs as separate App Platform worker component
- Shares same container image and environment variables as API
- Operates independently from API service lifecycle
- Provides observable proof of system integration health
"""

import os
import asyncio
import json
import logging
import signal
import sys
from datetime import datetime, timezone
from typing import Dict, Any

import psycopg2
import redis
import boto3
import base64
import tempfile

from iam_anywhere import get_iam_anywhere_session

# Configure structured logging for production monitoring
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class WorkerService:
    """
    Main worker service class for continuous timestamp updates.
    
    This class orchestrates the continuous update cycle that:
    1. Updates PostgreSQL last_update table every 60 seconds
    2. Updates Valkey worker:last_update key for real-time monitoring
    3. Updates AWS Secrets Manager secret with JSON timestamp payload
    4. Handles graceful shutdown for production deployment
    5. Provides comprehensive error handling and logging
    
    Attributes:
        running (bool): Controls the main event loop for graceful shutdown
        update_interval (int): Seconds between update cycles (60s)
    """
    
    def __init__(self):
        """Initialize worker service with default configuration."""
        self.running = True
        self.update_interval = 60  # seconds - configurable for different environments
        logger.info(f"WorkerService initialized with {self.update_interval}s update interval")
        
    def signal_handler(self, signum, frame):
        """
        Handle shutdown signals gracefully for production deployment.
        
        Args:
            signum (int): Signal number (SIGINT, SIGTERM, etc.)
            frame: Current stack frame (unused)
        """
        logger.info(f"Received signal {signum}. Initiating graceful shutdown...")
        self.running = False

    async def update_postgres(self) -> Dict[str, Any]:
        """
        Update PostgreSQL last_update table with current UTC timestamp.
        
        This function:
        1. Generates current UTC timestamp for consistency across services
        2. Connects to PostgreSQL using App Platform environment variables
        3. Uses UPSERT operation to insert or update worker timestamp record
        4. Includes metadata JSON for debugging and audit purposes
        5. Provides error handling with detailed logging
        
        Returns:
            Dict[str, Any]: Success status and timestamp, or error information
        """
        try:
            timestamp = datetime.now(timezone.utc)
            logger.info(f"Updating PostgreSQL with timestamp: {timestamp}")
            
            # Connect using the same environment variables as the API service
            conn = psycopg2.connect(
                host=os.environ['PGHOST'],
                port=os.environ['PGPORT'],
                dbname=os.environ['PGDATABASE'],
                user=os.environ['PGUSER'],
                password=os.environ['PGPASSWORD'],
                sslmode=os.environ.get('PGSSLMODE', 'require')
            )
            
            cursor = conn.cursor()
            # Use UPSERT (INSERT ... ON CONFLICT) to atomically update or insert
            # This ensures the worker timestamp is always current without duplicates
            cursor.execute("""
                INSERT INTO last_update (source, timestamp, metadata) 
                VALUES (%s, %s, %s)
                ON CONFLICT (source) 
                DO UPDATE SET 
                    timestamp = EXCLUDED.timestamp,
                    metadata = EXCLUDED.metadata
            """, ('worker', timestamp, json.dumps({'updated_by': 'worker_service', 'cycle': 'automated'})))
            
            conn.commit()
            cursor.close()
            conn.close()
            
            logger.info(f"PostgreSQL timestamp update successful: {timestamp}")
            return {"success": True, "timestamp": timestamp.isoformat()}
            
        except Exception as e:
            logger.error(f"PostgreSQL timestamp update failed: {e}")
            logger.error("This may indicate database connectivity issues or permission problems")
            return {"success": False, "error": str(e)}

    async def update_valkey(self) -> Dict[str, Any]:
        """
        Update Valkey with worker timestamp for real-time monitoring.
        
        This function:
        1. Generates current UTC timestamp matching PostgreSQL updates
        2. Connects to Valkey using SSL (required for DigitalOcean DBaaS)
        3. Sets worker:last_update key with ISO format timestamp
        4. Provides immediate retrieval capability for API /db/status endpoint
        5. Handles connection errors with detailed logging
        
        Returns:
            Dict[str, Any]: Success status and timestamp, or error information
        """
        try:
            timestamp = datetime.now(timezone.utc)
            logger.info(f"Updating Valkey with timestamp: {timestamp}")
            
            # Connect to Valkey using SSL configuration for DigitalOcean DBaaS
            r = redis.Redis(
                host=os.environ['VALKEY_HOST'],
                port=os.environ['VALKEY_PORT'],
                password=os.environ.get('VALKEY_PASSWORD'),
                ssl=True, 
                ssl_cert_reqs=None
            )
            
            # Set worker timestamp key for API monitoring
            # Uses consistent naming pattern for easy identification
            r.set('worker:last_update', timestamp.isoformat())
            
            logger.info(f"Valkey timestamp update successful: {timestamp}")
            return {"success": True, "timestamp": timestamp.isoformat()}
            
        except Exception as e:
            logger.error(f"Valkey timestamp update failed: {e}")
            logger.error("This may indicate database connectivity, SSL, or authentication issues")
            return {"success": False, "error": str(e)}

    async def update_secrets_manager(self) -> Dict[str, Any]:
        """
        Update AWS Secrets Manager secret with current timestamp payload.
        
        This function:
        1. Creates JSON payload containing timestamp and metadata
        2. Authenticates to AWS using IAM Roles Anywhere credentials
        3. Updates the test secret with new JSON content
        4. Demonstrates AWS integration from DigitalOcean App Platform
        5. Provides comprehensive error handling and logging
        
        Returns:
            Dict[str, Any]: Success status and timestamp, or error information
        """
        try:
            timestamp = datetime.now(timezone.utc)
            logger.info(f"Updating AWS Secrets Manager with timestamp: {timestamp}")
            
            # Verify IAM Roles Anywhere configuration for AWS access
            client_cert_b64 = os.environ.get('IAM_CLIENT_CERT')
            client_key_b64 = os.environ.get('IAM_CLIENT_KEY')
            role_arn = os.environ.get('IAM_ROLE_ARN')
            region = os.environ.get('AWS_REGION', 'us-west-2')
            secret_name = os.environ.get('SECRETS_MANAGER_SECRET_NAME', 'poc-app-platform/test-secret')
            
            if not all([client_cert_b64, client_key_b64, role_arn]):
                logger.error("Missing IAM Roles Anywhere configuration for AWS Secrets Manager")
                raise ValueError("Missing IAM Roles Anywhere configuration")
            
            logger.info(f"Connecting to AWS Secrets Manager in region {region}")
            
            # Get AWS session using IAM Roles Anywhere
            logger.info("Getting AWS session using IAM Roles Anywhere for Secrets Manager")
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
                raise ValueError("Failed to obtain IAM Roles Anywhere credentials")
            
            secrets_client = session.client('secretsmanager')
            
            # Create structured JSON payload for secret content
            # This demonstrates both timestamp tracking and AWS integration
            secret_payload = {
                "test_value": "This is a test secret from worker",
                "updated_at": timestamp.isoformat(),
                "updated_by": "worker_service",
                "metadata": {
                    "region": region,
                    "role_arn": role_arn,
                    "update_cycle": "automated_60s"
                }
            }
            
            logger.info(f"Updating secret '{secret_name}' with new JSON payload")
            
            # Update the secret with new JSON content
            # This triggers new version creation in Secrets Manager
            secrets_client.update_secret(
                SecretId=secret_name,
                SecretString=json.dumps(secret_payload)
            )
            
            logger.info(f"AWS Secrets Manager timestamp update successful: {timestamp}")
            return {"success": True, "timestamp": timestamp.isoformat()}
            
        except Exception as e:
            logger.error(f"AWS Secrets Manager timestamp update failed: {e}")
            logger.error("This may indicate AWS connectivity, authentication, or permission issues")
            return {"success": False, "error": str(e)}

    async def run_update_cycle(self):
        """
        Execute one complete update cycle across all integrated services.
        
        This function:
        1. Runs all three update operations concurrently for efficiency
        2. Handles partial failures gracefully (some services may fail)
        3. Logs detailed results for each service update
        4. Provides summary statistics for monitoring
        5. Continues operating even if individual services fail
        
        The concurrent execution ensures timestamps are as close as possible
        across all services, demonstrating real-time integration.
        """
        logger.info("=== Starting comprehensive update cycle ===")
        cycle_start = datetime.now(timezone.utc)
        
        # Execute all updates concurrently for minimal timestamp drift
        # Uses asyncio.gather with return_exceptions=True to handle partial failures
        logger.info("Executing concurrent updates to PostgreSQL, Valkey, and AWS Secrets Manager...")
        results = await asyncio.gather(
            self.update_postgres(),
            self.update_valkey(),
            self.update_secrets_manager(),
            return_exceptions=True
        )
        
        # Analyze and log results for monitoring and troubleshooting
        services = ['PostgreSQL', 'Valkey', 'AWS Secrets Manager']
        successful_updates = 0
        
        for i, result in enumerate(results):
            service_name = services[i]
            
            if isinstance(result, Exception):
                logger.error(f"{service_name} update failed with exception: {result}")
            elif isinstance(result, dict) and result.get('success'):
                logger.info(f"{service_name} update completed successfully")
                successful_updates += 1
            else:
                error_msg = result.get('error', 'Unknown error') if isinstance(result, dict) else str(result)
                logger.error(f"{service_name} update failed: {error_msg}")
        
        cycle_duration = (datetime.now(timezone.utc) - cycle_start).total_seconds()
        logger.info(f"=== Update cycle completed in {cycle_duration:.2f}s: {successful_updates}/{len(services)} services updated successfully ===")
        
        # Log health status for monitoring
        if successful_updates == len(services):
            logger.info("All services updated successfully - system healthy")
        elif successful_updates > 0:
            logger.warning(f"Partial success - {len(services) - successful_updates} services failed")
        else:
            logger.error("All service updates failed - system may have connectivity issues")

    async def main_loop(self):
        """
        Main worker event loop for continuous operation.
        
        This function:
        1. Runs continuously until shutdown signal received
        2. Executes update cycles at configured intervals (60s)
        3. Handles unexpected errors gracefully with recovery
        4. Provides responsive shutdown for production deployment
        5. Logs operational status for monitoring
        
        The loop design ensures reliable operation in production with
        proper error recovery and graceful shutdown capabilities.
        """
        logger.info(f"🚀 Worker service starting with {self.update_interval}s update interval")
        logger.info("Service will update PostgreSQL, Valkey, and AWS Secrets Manager continuously")
        
        cycle_count = 0
        
        while self.running:
            try:
                cycle_count += 1
                logger.info(f"--- Cycle #{cycle_count} starting ---")
                
                # Execute the update cycle across all services
                await self.run_update_cycle()
                
                # Wait for next cycle with responsive shutdown checking
                # Checks for shutdown signal every second during the interval
                logger.info(f"Waiting {self.update_interval}s for next cycle (cycle #{cycle_count} complete)")
                for second in range(self.update_interval):
                    if not self.running:
                        logger.info(f"Shutdown signal received during wait period (after {second}s)")
                        break
                    await asyncio.sleep(1)
                    
            except Exception as e:
                logger.error(f"Unexpected error in main loop (cycle #{cycle_count}): {e}")
                logger.error("Worker will attempt recovery after 10-second delay")
                # Continue running but wait before retrying to avoid tight error loops
                await asyncio.sleep(10)
        
        logger.info(f"🛑 Worker service shutting down after {cycle_count} completed cycles")
        logger.info("All update operations have been stopped gracefully")

async def ensure_database_schema():
    """
    Ensure PostgreSQL schema is ready for worker operations.
    
    This function verifies that the last_update table exists and creates it
    if necessary. This is essential for the worker's PostgreSQL update
    operations and API timestamp retrieval functionality.
    
    The table schema supports:
    - source: Identifies the data source (always 'worker' for this service)
    - timestamp: UTC timestamp with timezone information
    - metadata: JSON blob for debugging and audit information
    
    Raises:
        Exception: If database connection or schema creation fails
    """
    logger.info("Verifying PostgreSQL schema for worker operations...")
    
    try:
        # Connect using same configuration as worker update operations
        conn = psycopg2.connect(
            host=os.environ['PGHOST'],
            port=os.environ['PGPORT'],
            dbname=os.environ['PGDATABASE'],
            user=os.environ['PGUSER'],
            password=os.environ['PGPASSWORD'],
            sslmode=os.environ.get('PGSSLMODE', 'require')
        )
        
        cursor = conn.cursor()
        # Create table with appropriate schema for timestamp tracking
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS last_update (
                source VARCHAR(50) PRIMARY KEY,
                timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
                metadata JSONB
            )
        """)
        conn.commit()
        cursor.close()
        conn.close()
        
        logger.info("PostgreSQL schema verified/created successfully for worker operations")
        
    except Exception as e:
        logger.error(f"Failed to ensure PostgreSQL schema: {e}")
        logger.error("Worker cannot operate without proper database schema")
        raise

async def main():
    """
    Main entry point for the worker service.
    
    This function:
    1. Verifies database schema is ready for operations
    2. Initializes the WorkerService with proper configuration
    3. Sets up signal handlers for graceful shutdown
    4. Starts the main worker loop
    5. Handles errors and provides clean exit codes
    
    The function ensures proper initialization order and error handling
    for production deployment in App Platform.
    """
    logger.info("🌟 PoC App Platform AWS Integration - Worker Service Starting")
    logger.info("Continuous timestamp updates across integrated services")
    
    try:
        # Verify database readiness before starting operations
        await ensure_database_schema()
        
        # Initialize worker service with configuration
        worker = WorkerService()
        
        # Set up signal handlers for graceful shutdown in production
        signal.signal(signal.SIGINT, worker.signal_handler)
        signal.signal(signal.SIGTERM, worker.signal_handler)
        
        logger.info("Worker service initialized - starting continuous update loop")
        
        # Start the main operational loop
        await worker.main_loop()
        
    except KeyboardInterrupt:
        logger.info("Received keyboard interrupt (Ctrl+C) - shutting down gracefully")
    except Exception as e:
        logger.error(f"Worker service initialization or operation failed: {e}")
        logger.error("Check database connectivity, AWS credentials, and environment configuration")
        sys.exit(1)
    
    logger.info("✅ Worker service stopped - all operations completed gracefully")

if __name__ == "__main__":
    asyncio.run(main())