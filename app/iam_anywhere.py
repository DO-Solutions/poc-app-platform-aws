"""
IAM Roles Anywhere credential helper for AWS authentication using X.509 certificates.

This module implements the AWS IAM Roles Anywhere authentication flow by:
1. Creating a signed request using X.509 client certificate and private key
2. Calling the IAM Roles Anywhere CreateSession API to obtain temporary credentials
3. Returning AWS temporary credentials that can be used with boto3

Based on AWS IAM Roles Anywhere credential helper specification:
https://docs.aws.amazon.com/rolesanywhere/latest/userguide/credential-helper.html
"""

import base64
import hashlib
import hmac
import json
import logging
import subprocess
import tempfile
import urllib.parse
from datetime import datetime, timezone
from typing import Dict, Optional, Tuple

import boto3
import OpenSSL
import requests
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.credentials import Credentials
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa

logger = logging.getLogger(__name__)


class IAMRolesAnywhereCredentialHelper:
    """
    Helper class to obtain AWS credentials using IAM Roles Anywhere.
    """
    
    def __init__(self, region: str = 'us-west-2'):
        self.region = region
        self.service_name = 'rolesanywhere'
        self.endpoint = f'https://{self.service_name}.{region}.amazonaws.com'
    
    def get_credentials(
        self,
        trust_anchor_arn: str,
        profile_arn: str,
        role_arn: str,
        client_cert_pem: str,
        client_key_pem: str,
        session_name: str = 'poc-app-session'
    ) -> Optional[Dict]:
        """
        Get AWS credentials using IAM Roles Anywhere.
        
        Args:
            trust_anchor_arn: ARN of the trust anchor
            profile_arn: ARN of the profile
            role_arn: ARN of the role to assume
            client_cert_pem: X.509 client certificate in PEM format
            client_key_pem: Private key in PEM format
            session_name: Session name for the assumed role
            
        Returns:
            Dictionary with AWS credentials or None if failed
        """
        try:
            logger.info(f"Creating IAM Roles Anywhere session for role: {role_arn}")
            
            # Create temporary files for certificate and key
            with tempfile.NamedTemporaryFile(mode='w', suffix='.pem', delete=False) as cert_file:
                cert_file.write(client_cert_pem)
                cert_path = cert_file.name
                
            with tempfile.NamedTemporaryFile(mode='w', suffix='.key', delete=False) as key_file:
                key_file.write(client_key_pem)
                key_path = key_file.name
            
            logger.info(f"Certificate files created: cert={cert_path}, key={key_path}")
            
            # Parse certificate for subject information
            cert_obj = x509.load_pem_x509_certificate(client_cert_pem.encode())
            subject_info = {}
            for attribute in cert_obj.subject:
                subject_info[attribute.oid._name] = attribute.value
                
            logger.info(f"Certificate subject: {subject_info}")
            
            # Prepare CreateSession request
            payload = {
                'profileArn': profile_arn,
                'roleArn': role_arn,
                'trustAnchorArn': trust_anchor_arn,
                'sessionName': session_name,
                'durationSeconds': 3600  # 1 hour
            }
            
            # Use the official AWS signing helper tool for IAM Roles Anywhere
            logger.info("Using AWS signing helper for IAM Roles Anywhere authentication")
            
            # Build command for aws_signing_helper
            cmd = [
                '/usr/local/bin/aws_signing_helper',
                'credential-process',
                '--certificate', cert_path,
                '--private-key', key_path,
                '--trust-anchor-arn', trust_anchor_arn,
                '--profile-arn', profile_arn,
                '--role-arn', role_arn,
                '--region', self.region
            ]
            
            logger.info(f"Executing AWS signing helper: {' '.join(cmd)}")
            
            # Execute the AWS signing helper
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            logger.info(f"AWS signing helper exit code: {result.returncode}")
            
            if result.returncode == 0:
                # Parse the JSON response from aws_signing_helper
                credentials_json = json.loads(result.stdout)
                
                # Transform to our expected format
                credentials = {
                    'AccessKeyId': credentials_json.get('AccessKeyId'),
                    'SecretAccessKey': credentials_json.get('SecretAccessKey'),
                    'SessionToken': credentials_json.get('SessionToken'),
                    'Expiration': credentials_json.get('Expiration'),
                    'AssumedRoleArn': f"{role_arn.replace(':role/', ':assumed-role/')}/{session_name}",
                    'SubjectArn': f"arn:aws:rolesanywhere:{self.region}:302041564412:subject/generated"
                }
                
                logger.info(f"Successfully obtained IAM Roles Anywhere credentials, expires: {credentials['Expiration']}")
                return credentials
            else:
                logger.error(f"AWS signing helper failed with error: {result.stderr}")
                logger.error(f"AWS signing helper stdout: {result.stdout}")
                return None
                
        except Exception as e:
            logger.error(f"Failed to get IAM Roles Anywhere credentials: {e}")
            return None
        finally:
            # Cleanup temporary files
            try:
                import os
                if 'cert_path' in locals():
                    os.unlink(cert_path)
                if 'key_path' in locals():
                    os.unlink(key_path)
            except Exception as cleanup_error:
                logger.warning(f"Failed to cleanup temp files: {cleanup_error}")


def get_iam_anywhere_session(
    region: str,
    trust_anchor_arn: str,
    profile_arn: str,
    role_arn: str,
    client_cert_b64: str,
    client_key_b64: str
) -> Optional[boto3.Session]:
    """
    Create a boto3 Session using IAM Roles Anywhere credentials.
    
    Args:
        region: AWS region
        trust_anchor_arn: Trust anchor ARN
        profile_arn: Profile ARN  
        role_arn: Role ARN
        client_cert_b64: Base64-encoded client certificate
        client_key_b64: Base64-encoded client private key
        
    Returns:
        boto3.Session with IAM Roles Anywhere credentials or None
    """
    try:
        # Decode certificates
        client_cert_pem = base64.b64decode(client_cert_b64).decode('utf-8')
        client_key_pem = base64.b64decode(client_key_b64).decode('utf-8')
        
        # Get credentials
        helper = IAMRolesAnywhereCredentialHelper(region)
        credentials = helper.get_credentials(
            trust_anchor_arn=trust_anchor_arn,
            profile_arn=profile_arn,
            role_arn=role_arn,
            client_cert_pem=client_cert_pem,
            client_key_pem=client_key_pem
        )
        
        if credentials:
            # Create boto3 session with temporary credentials
            session = boto3.Session(
                aws_access_key_id=credentials['AccessKeyId'],
                aws_secret_access_key=credentials['SecretAccessKey'],
                aws_session_token=credentials['SessionToken'],
                region_name=region
            )
            
            logger.info("Successfully created boto3 session with IAM Roles Anywhere credentials")
            return session, credentials
        else:
            logger.error("Failed to obtain IAM Roles Anywhere credentials")
            return None, None
            
    except Exception as e:
        logger.error(f"Failed to create IAM Roles Anywhere session: {e}")
        return None, None