#
#
#                         *** SECURITY WARNING ***
#
#     THE SELF-SIGNED CERTIFICATES GENERATED HERE ARE FOR PROOF-OF-CONCEPT ONLY
#
#     ❌ DO NOT USE IN PRODUCTION ENVIRONMENTS
#     ❌ DO NOT USE WITH SENSITIVE DATA
#     ❌ DO NOT USE IN CUSTOMER-FACING APPLICATIONS
#
#     For production deployments, you MUST:
#     ✅ Use a proper Certificate Authority (CA) infrastructure
#     ✅ Implement proper certificate lifecycle management
#     ✅ Use hardware security modules (HSMs) for private key storage
#     ✅ Follow your organization's PKI policies and procedures
#     ✅ Implement certificate rotation and renewal processes
#
#     This self-signed approach is acceptable ONLY for:
#     • Proof-of-concept demonstrations
#     • Development and testing environments
#     • Learning and educational purposes
#
#

# PoC App Platform AWS Integration - X.509 Certificate Infrastructure
# This file defines self-signed certificates for IAM Roles Anywhere authentication

# =============================================================================
# AWS IAM ROLES ANYWHERE - X.509 CERTIFICATE INFRASTRUCTURE
# =============================================================================

# Certificate Authority (CA) Private Key
# Root private key for signing client certificates
# Used to establish trust chain for IAM Roles Anywhere
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048                              # Secure key length
}

# Self-signed CA Certificate
# Root certificate for the certificate authority
# Establishes the trust anchor for IAM Roles Anywhere
resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem
  
  subject {
    common_name  = "PoC App Platform AWS CA"
    organization = "DigitalOcean Solutions"
  }
  
  validity_period_hours = 8760                  # Valid for 1 year
  is_ca_certificate     = true                  # Marks as CA certificate
  
  allowed_uses = [
    "cert_signing",                             # Can sign other certificates
    "key_encipherment",
    "digital_signature",
  ]
}

# Client Private Key
# Private key for the application's client certificate
resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Client Certificate Request
# Certificate signing request for the application
resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem
  
  subject {
    common_name  = "poc-app-platform-aws-client"  # Must match IAM role condition
    organization = "DigitalOcean Solutions"
  }
}

# Client Certificate signed by CA
# Final client certificate for IAM Roles Anywhere authentication
resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem
  
  validity_period_hours = 8760                  # Valid for 1 year
  
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",                              # Enables client authentication
  ]
}