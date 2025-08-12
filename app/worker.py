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

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class WorkerService:
    def __init__(self):
        self.running = True
        self.update_interval = 60  # seconds
        
    def signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        logger.info(f"Received signal {signum}. Initiating graceful shutdown...")
        self.running = False

    async def update_postgres(self) -> Dict[str, Any]:
        """Update PostgreSQL last_update table with current timestamp"""
        try:
            timestamp = datetime.now(timezone.utc)
            conn = psycopg2.connect(
                host=os.environ['PGHOST'],
                port=os.environ['PGPORT'],
                dbname=os.environ['PGDATABASE'],
                user=os.environ['PGUSER'],
                password=os.environ['PGPASSWORD'],
                sslmode=os.environ.get('PGSSLMODE', 'require')
            )
            
            cursor = conn.cursor()
            # Use UPSERT (INSERT ... ON CONFLICT) to update or insert
            cursor.execute("""
                INSERT INTO last_update (source, timestamp, metadata) 
                VALUES (%s, %s, %s)
                ON CONFLICT (source) 
                DO UPDATE SET 
                    timestamp = EXCLUDED.timestamp,
                    metadata = EXCLUDED.metadata
            """, ('worker', timestamp, json.dumps({'updated_by': 'worker_service'})))
            
            conn.commit()
            cursor.close()
            conn.close()
            
            logger.info(f"Successfully updated PostgreSQL timestamp: {timestamp}")
            return {"success": True, "timestamp": timestamp.isoformat()}
            
        except Exception as e:
            logger.error(f"Failed to update PostgreSQL: {e}")
            return {"success": False, "error": str(e)}

    async def update_valkey(self) -> Dict[str, Any]:
        """Update Valkey with worker timestamp"""
        try:
            timestamp = datetime.now(timezone.utc)
            r = redis.Redis(
                host=os.environ['VALKEY_HOST'],
                port=os.environ['VALKEY_PORT'],
                password=os.environ.get('VALKEY_PASSWORD'),
                ssl=True, 
                ssl_cert_reqs=None
            )
            
            # Set worker timestamp key
            r.set('worker:last_update', timestamp.isoformat())
            
            logger.info(f"Successfully updated Valkey timestamp: {timestamp}")
            return {"success": True, "timestamp": timestamp.isoformat()}
            
        except Exception as e:
            logger.error(f"Failed to update Valkey: {e}")
            return {"success": False, "error": str(e)}

    async def update_secrets_manager(self) -> Dict[str, Any]:
        """Update AWS Secrets Manager with current timestamp"""
        try:
            timestamp = datetime.now(timezone.utc)
            
            # Check if we have the required IAM environment variables
            client_cert_b64 = os.environ.get('IAM_CLIENT_CERT')
            client_key_b64 = os.environ.get('IAM_CLIENT_KEY')
            role_arn = os.environ.get('IAM_ROLE_ARN')
            region = os.environ.get('AWS_REGION', 'us-west-2')
            secret_name = "poc-app-platform/test-secret"
            
            if not all([client_cert_b64, client_key_b64, role_arn]):
                raise ValueError("Missing IAM Roles Anywhere configuration")
            
            # Create AWS session and Secrets Manager client
            session = boto3.Session(region_name=region)
            secrets_client = session.client('secretsmanager')
            
            # Create JSON payload with timestamp
            secret_payload = {
                "test_value": "This is a test secret from worker",
                "updated_at": timestamp.isoformat(),
                "updated_by": "worker_service"
            }
            
            # Update the secret
            secrets_client.update_secret(
                SecretId=secret_name,
                SecretString=json.dumps(secret_payload)
            )
            
            logger.info(f"Successfully updated Secrets Manager timestamp: {timestamp}")
            return {"success": True, "timestamp": timestamp.isoformat()}
            
        except Exception as e:
            logger.error(f"Failed to update Secrets Manager: {e}")
            return {"success": False, "error": str(e)}

    async def run_update_cycle(self):
        """Execute one complete update cycle"""
        logger.info("Starting update cycle...")
        
        # Run all updates concurrently
        results = await asyncio.gather(
            self.update_postgres(),
            self.update_valkey(),
            self.update_secrets_manager(),
            return_exceptions=True
        )
        
        # Log results
        services = ['PostgreSQL', 'Valkey', 'Secrets Manager']
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                logger.error(f"{services[i]} update failed with exception: {result}")
            elif result.get('success'):
                logger.info(f"{services[i]} update completed successfully")
            else:
                logger.error(f"{services[i]} update failed: {result.get('error')}")
        
        successful_updates = sum(1 for r in results if isinstance(r, dict) and r.get('success'))
        logger.info(f"Update cycle completed: {successful_updates}/{len(services)} services updated successfully")

    async def main_loop(self):
        """Main worker loop"""
        logger.info(f"Worker service starting with {self.update_interval}s interval")
        
        while self.running:
            try:
                await self.run_update_cycle()
                
                # Wait for next cycle, checking shutdown signal periodically
                for _ in range(self.update_interval):
                    if not self.running:
                        break
                    await asyncio.sleep(1)
                    
            except Exception as e:
                logger.error(f"Unexpected error in main loop: {e}")
                # Continue running but wait before retrying
                await asyncio.sleep(10)
        
        logger.info("Worker service shutting down...")

async def ensure_database_schema():
    """Ensure the last_update table exists"""
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
        
        logger.info("Database schema verified/created successfully")
        
    except Exception as e:
        logger.error(f"Failed to ensure database schema: {e}")
        raise

async def main():
    """Main entry point"""
    # Ensure database schema exists
    await ensure_database_schema()
    
    # Create and run worker service
    worker = WorkerService()
    
    # Set up signal handlers for graceful shutdown
    signal.signal(signal.SIGINT, worker.signal_handler)
    signal.signal(signal.SIGTERM, worker.signal_handler)
    
    try:
        await worker.main_loop()
    except KeyboardInterrupt:
        logger.info("Received keyboard interrupt, shutting down...")
    except Exception as e:
        logger.error(f"Worker service failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())