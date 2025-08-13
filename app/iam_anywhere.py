"""
IAM Roles Anywhere credential helper for AWS authentication using X.509 certificates.

This module provides a simplified wrapper around the official AWS IAM Roles Anywhere
Session package to obtain temporary AWS credentials using X.509 client certificates.
"""

import base64
import logging
import tempfile
from typing import Dict, Optional, Tuple

import boto3
from iam_rolesanywhere_session import IAMRolesAnywhereSession

logger = logging.getLogger(__name__)


def get_iam_anywhere_session(
    region: str,
    trust_anchor_arn: str,
    profile_arn: str,
    role_arn: str,
    client_cert_b64: str,
    client_key_b64: str
) -> Tuple[Optional[boto3.Session], Optional[Dict]]:
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
        Tuple of (boto3.Session, credentials_dict) or (None, None) on failure
    """
    try:
        logger.info(f"Creating IAM Roles Anywhere session for role: {role_arn}")
        
        # Decode certificates from base64
        client_cert_pem = base64.b64decode(client_cert_b64).decode('utf-8')
        client_key_pem = base64.b64decode(client_key_b64).decode('utf-8')
        
        # Write certificates to temporary files as the AWS package expects file paths
        with tempfile.NamedTemporaryFile(mode='w', suffix='.pem', delete=False) as cert_file:
            cert_file.write(client_cert_pem)
            cert_path = cert_file.name
            
        with tempfile.NamedTemporaryFile(mode='w', suffix='.key', delete=False) as key_file:
            key_file.write(client_key_pem)
            key_path = key_file.name
        
        try:
            # Create IAM Roles Anywhere session using the official AWS package
            roles_anywhere_session = IAMRolesAnywhereSession(
                profile_arn=profile_arn,
                role_arn=role_arn,
                trust_anchor_arn=trust_anchor_arn,
                certificate=cert_path,
                private_key=key_path,
                region=region,
                session_duration=3600  # 1 hour
            )
            
            # Get the boto3 session
            session = roles_anywhere_session.get_session()
            
            # Get credentials for compatibility with existing code
            credentials_obj = session.get_credentials()
            credentials = {
                'AccessKeyId': credentials_obj.access_key,
                'SecretAccessKey': credentials_obj.secret_key,
                'SessionToken': credentials_obj.token,
                'Expiration': None,  # The session handles refresh automatically
                'AssumedRoleArn': f"{role_arn.replace(':role/', ':assumed-role/')}/iam-roles-anywhere-session",
                'SubjectArn': f"arn:aws:rolesanywhere:{region}:302041564412:subject/generated"
            }
            
            logger.info("Successfully created boto3 session with IAM Roles Anywhere credentials")
            return session, credentials
            
        finally:
            # Cleanup temporary files
            import os
            try:
                os.unlink(cert_path)
                os.unlink(key_path)
            except Exception as cleanup_error:
                logger.warning(f"Failed to cleanup temp files: {cleanup_error}")
        
    except Exception as e:
        logger.error(f"Failed to create IAM Roles Anywhere session: {e}")
        return None, None