import os
import logging
import psycopg2
import redis
from fastapi import FastAPI
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
def db_status():
    pg_status = {"connected": False, "writable": False, "readable": False}
    valkey_status = {"connected": False, "ping_ok": False, "set_get_ok": False}

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
