# Phase 4: AWS IAM Roles Anywhere Integration

## Overview

Phase 4 implements AWS IAM Roles Anywhere integration to enable the DigitalOcean App Platform application to authenticate to AWS services using X.509 certificates instead of long-term credentials. This demonstrates a secure method for workloads running outside of AWS to assume IAM roles for accessing AWS services.

## Current Project State

Based on the existing codebase:
- **Terraform Infrastructure**: AWS providers configured for us-east-1 and us-west-2, CloudFront/WAF integration complete
- **Backend Application**: FastAPI service with `/healthz` and `/db/status` endpoints
- **Frontend**: Static JavaScript application displaying database connectivity status
- **Database Integration**: PostgreSQL and Valkey connectivity implemented via DigitalOcean DBaaS

## Phase 4 Implementation Plan

### 1. Certificate Infrastructure (Terraform)

**Objective**: Create a self-signed certificate authority and client certificates using the `hashicorp/tls` Terraform provider.

**Tasks**:
- Add `tls` provider to the existing Terraform configuration
- Generate a self-signed CA certificate with appropriate key usage extensions
- Create a client certificate signed by the CA for the application to use
- Store certificates securely as App Platform environment variables

**Implementation Details**:
```hcl
# tls provider for certificate generation
provider "tls" {}

# CA private key
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Self-signed CA certificate
resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem
  
  subject {
    common_name  = "PoC App Platform AWS CA"
    organization = "DigitalOcean Solutions"
  }
  
  validity_period_hours = 8760 # 1 year
  is_ca_certificate     = true
  
  allowed_uses = [
    "cert_signing",
    "key_encipherment",
    "digital_signature",
  ]
}

# Client private key
resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Client certificate request
resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem
  
  subject {
    common_name  = "poc-app-platform-aws-client"
    organization = "DigitalOcean Solutions"
  }
}

# Client certificate signed by CA
resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem
  
  validity_period_hours = 8760 # 1 year
  
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",
  ]
}
```

### 2. AWS IAM Roles Anywhere Setup (Terraform)

**Objective**: Configure AWS IAM Roles Anywhere trust anchor, role, and profile to enable certificate-based authentication.

**Tasks**:
- Create IAM Roles Anywhere trust anchor using the CA certificate
- Define IAM role with minimal permissions (sts:GetCallerIdentity)
- Create IAM Roles Anywhere profile linking trust anchor to role
- Configure trust relationship for certificate-based authentication

**Implementation Details**:
```hcl
# IAM Roles Anywhere trust anchor
resource "aws_rolesanywhere_trust_anchor" "main" {
  name = "poc-app-platform-aws-trust-anchor"
  
  source {
    source_data = base64encode(tls_self_signed_cert.ca.cert_pem)
    source_type = "CERTIFICATE_BUNDLE"
  }
}

# IAM role for the application
resource "aws_iam_role" "app_role" {
  name = "poc-app-platform-aws-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "rolesanywhere.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:PrincipalTag/x509Subject/CN" = "poc-app-platform-aws-client"
          }
        }
      }
    ]
  })
}

# IAM policy for minimal permissions
resource "aws_iam_role_policy" "app_policy" {
  name = "poc-app-platform-aws-policy"
  role = aws_iam_role.app_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Roles Anywhere profile
resource "aws_rolesanywhere_profile" "main" {
  name = "poc-app-platform-aws-profile"
  
  role_arns = [aws_iam_role.app_role.arn]
  
  session_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}
```

### 3. Application Environment Variables (Terraform)

**Objective**: Securely pass certificate data to the App Platform application via environment variables.

**Tasks**:
- Add certificate-related environment variables to the App Platform service
- Use SECRET scope for private key material
- Provide IAM Roles Anywhere configuration parameters

**Implementation Details**:
```hcl
# Additional environment variables for IAM Roles Anywhere
env {
  key   = "IAM_CLIENT_CERT"
  value = base64encode(tls_locally_signed_cert.client.cert_pem)
  scope = "RUN_TIME"
  type  = "SECRET"
}

env {
  key   = "IAM_CLIENT_KEY"
  value = base64encode(tls_private_key.client.private_key_pem)
  scope = "RUN_TIME"
  type  = "SECRET"
}

env {
  key   = "IAM_TRUST_ANCHOR_ARN"
  value = aws_rolesanywhere_trust_anchor.main.arn
  scope = "RUN_TIME"
  type  = "GENERAL"
}

env {
  key   = "IAM_PROFILE_ARN"
  value = aws_rolesanywhere_profile.main.arn
  scope = "RUN_TIME"
  type  = "GENERAL"
}

env {
  key   = "IAM_ROLE_ARN"
  value = aws_iam_role.app_role.arn
  scope = "RUN_TIME"
  type  = "GENERAL"
}

env {
  key   = "AWS_REGION"
  value = "us-west-2"
  scope = "RUN_TIME"
  type  = "GENERAL"
}
```

### 4. Backend Application Updates (FastAPI)

**Objective**: Implement IAM Roles Anywhere authentication and expose status endpoint.

**Tasks**:
- Add AWS SDK dependencies (`boto3`, `botocore`)
- Implement certificate loading and IAM role assumption
- Create `/iam/status` endpoint with role assumption verification
- Add structured error handling and logging

**Implementation Details**:

New dependencies in `requirements.txt`:
```
boto3>=1.34.0
botocore>=1.34.0
cryptography>=41.0.0
```

New IAM functionality in `main.py`:
```python
import base64
import boto3
from botocore.credentials import Credentials
from botocore.config import Config
import tempfile
import os

def assume_role_with_certificate():
    """Assume IAM role using X.509 certificate via Roles Anywhere"""
    try:
        # Decode certificates from environment variables
        client_cert_b64 = os.environ.get('IAM_CLIENT_CERT')
        client_key_b64 = os.environ.get('IAM_CLIENT_KEY')
        
        if not client_cert_b64 or not client_key_b64:
            raise ValueError("Certificate or key not found in environment variables")
        
        # Write certificates to temporary files
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pem') as cert_file:
            cert_file.write(base64.b64decode(client_cert_b64).decode('utf-8'))
            cert_path = cert_file.name
        
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.key') as key_file:
            key_file.write(base64.b64decode(client_key_b64).decode('utf-8'))
            key_path = key_file.name
        
        # Configure AWS credentials using IAM Roles Anywhere
        session = boto3.Session(
            region_name=os.environ.get('AWS_REGION', 'us-west-2')
        )
        
        # Use AWS CLI credential process for Roles Anywhere
        sts_client = session.client('sts')
        response = sts_client.get_caller_identity()
        
        return {
            "success": True,
            "role_arn": response.get('Arn'),
            "account": response.get('Account'),
            "user_id": response.get('UserId')
        }
        
    except Exception as e:
        logger.error(f"IAM role assumption failed: {e}")
        return {
            "success": False,
            "error": str(e)
        }
    finally:
        # Clean up temporary files
        try:
            if 'cert_path' in locals():
                os.unlink(cert_path)
            if 'key_path' in locals():
                os.unlink(key_path)
        except:
            pass

@app.get("/iam/status")
def iam_status():
    """Check IAM Roles Anywhere authentication status"""
    result = assume_role_with_certificate()
    
    return {
        "ok": result["success"],
        "role_arn": result.get("role_arn"),
        "error": result.get("error")
    }
```

### 5. Frontend Updates (JavaScript)

**Objective**: Display IAM Roles Anywhere authentication status in the UI.

**Tasks**:
- Add IAM status section to the HTML
- Implement API call to `/iam/status` endpoint
- Display OK/FAIL badge with role ARN when successful
- Maintain visual consistency with existing status badges

**Implementation Details**:

HTML updates in `index.html`:
```html
<div class="status-item">
    <h3>AWS IAM Roles Anywhere</h3>
    <span id="iam-status" class="status-badge">CHECKING...</span>
    <div id="iam-details" class="status-details"></div>
</div>
```

JavaScript updates in `app.js`:
```javascript
// Add IAM status check
fetch(`${API_URL}/iam/status`)
    .then(response => response.json())
    .then(data => {
        const iamStatus = document.getElementById('iam-status');
        const iamDetails = document.getElementById('iam-details');
        
        if (data.ok && data.role_arn) {
            iamStatus.textContent = 'OK';
            iamStatus.classList.add('ok');
            iamDetails.textContent = `Role: ${data.role_arn}`;
        } else {
            iamStatus.textContent = 'FAIL';
            iamStatus.classList.add('fail');
            if (data.error) {
                iamDetails.textContent = `Error: ${data.error}`;
            }
        }
    })
    .catch(error => {
        console.error('Error fetching IAM status:', error);
        document.getElementById('iam-status').textContent = 'FAIL';
        document.getElementById('iam-status').classList.add('fail');
    });
```

### 6. CloudFront Path Configuration

**Objective**: Ensure CloudFront properly routes the new `/iam/status` endpoint.

**Tasks**:
- Add ordered cache behavior for `/iam/status` path
- Configure appropriate caching settings (no caching for dynamic content)
- Ensure proper header forwarding

**Implementation Details**:
```hcl
# IAM status behavior - proxy to App Platform
ordered_cache_behavior {
  path_pattern     = "/iam/status"
  allowed_methods  = ["GET", "HEAD"]
  cached_methods   = ["GET", "HEAD"]
  target_origin_id = "app-platform-api"

  forwarded_values {
    query_string = false

    cookies {
      forward = "none"
    }
  }

  viewer_protocol_policy = "redirect-to-https"
  min_ttl                = 0
  default_ttl            = 0
  max_ttl                = 0
}
```

## Success Criteriyou 

- [ ] All certificates and IAM Roles Anywhere infrastructure created via `terraform apply`
- [ ] Application successfully asWhen Isumes IAM role using X.509 certificate authentication
- [ ] Frontend displays OK badge and the correct IAM Role ARN
- [ ] No manual certificate generation or AWS console configuration required
- [ ] Clean terraform plan on subsequent runs (idempotent)
- [ ] All certificate material stored securely as App Platform secrets
- [ ] Proper error handling and logging for authentication failures
- [ ] Frontend accessible via CloudFront with new IAM status section

## Implementation Order

1. **Terraform Infrastructure**: Add certificate generation and IAM Roles Anywhere resources
2. **Application Dependencies**: Update `requirements.txt` with AWS SDK
3. **Backend Implementation**: Add IAM authentication logic and `/iam/status` endpoint
4. **Frontend Updates**: Implement IAM status UI and API integration
5. **CloudFront Configuration**: Add routing for new endpoint
6. **Testing and Validation**: Verify end-to-end certificate authentication

## Security Considerations

- Certificate private keys stored as App Platform secrets with `SECRET` scope
- IAM role follows least-privilege principle with minimal permissions
- Certificate validity period limited to 1 year
- Temporary files for certificates are securely cleaned up after use
- Trust anchor configured to validate specific certificate subjects
- No long-term AWS credentials stored in the application

## Dependencies

- `hashicorp/tls` Terraform provider for certificate generation
- `boto3` and `botocore` Python libraries for AWS SDK functionality
- `cryptography` library for certificate handling
- AWS IAM Roles Anywhere service availability in us-west-2 region

This ensures that any Phase 4 issues don't impact the working Phase 1-3 functionality.