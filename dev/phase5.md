# Phase 5: AWS Secrets Manager Integration

## Overview

Phase 5 extends the application to demonstrate AWS Secrets Manager access using the IAM Roles Anywhere authentication established in Phase 4. This phase showcases how DigitalOcean App Platform applications can securely access AWS secrets using X.509 certificate-based authentication without hardcoded credentials.

## Dependencies

**Prerequisites from Phase 4:**
- IAM Roles Anywhere trust anchor and profile configured
- X.509 certificates (CA and client) deployed via environment variables
- IAM role with `sts:GetCallerIdentity` permissions
- Working `/iam/status` endpoint demonstrating role assumption

## Technical Objectives

### 1. AWS Secrets Manager Infrastructure (Terraform)

**Objective:** Create AWS Secrets Manager resources with appropriate IAM permissions

**Tasks:**
- Create a dummy secret in AWS Secrets Manager with name `poc-app-platform/test-secret`
- Store a simple JSON secret value (e.g., `{"message": "Hello from AWS Secrets Manager", "timestamp": "2024-XX-XX"}`)
- Update existing IAM role from Phase 4 to include Secrets Manager permissions:
  - `secretsmanager:GetSecretValue` for the specific secret ARN
  - `secretsmanager:DescribeSecret` for the specific secret ARN
- Apply least-privilege principle (permissions only for the specific secret)

### 2. Backend API Enhancement

**Objective:** Extend FastAPI backend to retrieve and expose AWS secrets

**Tasks:**
- Add AWS Secrets Manager client to existing IAM Roles Anywhere authentication flow
- Implement secret retrieval logic with error handling
- Create new `/secret/status` API endpoint with JSON response:
  ```json
  {
    "ok": boolean,
    "secret_value": string,
    "secret_name": string,
    "error": string (optional)
  }
  ```
- Add structured logging for secret retrieval operations
- Integrate with existing AWS session from Phase 4 (reuse authentication)

### 3. Frontend Integration

**Objective:** Display AWS Secrets Manager connectivity status in the web interface

**Tasks:**
- Add new section to index.html for Secrets Manager status
- Implement JavaScript function to call `/secret/status` endpoint
- Display OK/FAIL badge consistent with existing database and IAM status badges
- Show retrieved secret value and name in readable format
- Handle error states gracefully with user-friendly messages
- Maintain visual consistency with existing status sections

### 4. Testing and Validation

**Objective:** Ensure end-to-end functionality and error handling

**Tasks:**
- Test successful secret retrieval through full authentication chain
- Validate error handling for various failure scenarios:
  - IAM authentication failures
  - Secret not found
  - Insufficient permissions
  - Network connectivity issues
- Verify frontend displays correct status and error messages
- Confirm all operations work through CloudFront distribution

## Implementation Todo List

### Phase 5A: Infrastructure Setup
- [ ] **Task 5.1:** Add AWS Secrets Manager secret to `terraform/main.tf`
  - [ ] Create `aws_secretsmanager_secret` resource with name `poc-app-platform/test-secret`
  - [ ] Create `aws_secretsmanager_secret_version` with dummy JSON content
  - [ ] Tag with `Owner: jkeegan`

- [ ] **Task 5.2:** Update IAM role permissions
  - [ ] Modify existing IAM role policy from Phase 4
  - [ ] Add `secretsmanager:GetSecretValue` permission for specific secret ARN
  - [ ] Add `secretsmanager:DescribeSecret` permission for specific secret ARN
  - [ ] Ensure least-privilege access (no wildcard permissions)

- [ ] **Task 5.3:** Apply infrastructure changes
  - [ ] Run `make plan` to verify Terraform changes
  - [ ] Run `make apply` to deploy Secrets Manager resources
  - [ ] Verify secret creation in AWS console (manual verification only)

### Phase 5B: Backend Development
- [ ] **Task 5.4:** Extend AWS integration in `app/main.py`
  - [ ] Import `boto3.client('secretsmanager')`
  - [ ] Create reusable function to get Secrets Manager client using existing AWS session
  - [ ] Implement `retrieve_secret()` function with error handling

- [ ] **Task 5.5:** Create `/secret/status` endpoint
  - [ ] Add new FastAPI route handler
  - [ ] Implement secret retrieval using IAM Roles Anywhere credentials
  - [ ] Return structured JSON response with all required fields
  - [ ] Add comprehensive error handling and logging

- [ ] **Task 5.6:** Test backend integration
  - [ ] Verify endpoint works locally with test credentials
  - [ ] Test error scenarios (missing secret, wrong permissions)
  - [ ] Validate JSON response structure matches specification

### Phase 5C: Frontend Development
- [ ] **Task 5.7:** Update `frontend/index.html`
  - [ ] Add new section for "AWS Secrets Manager" status
  - [ ] Include placeholder elements for status badge and secret display
  - [ ] Maintain consistent styling with existing sections

- [ ] **Task 5.8:** Extend `frontend/app.js`
  - [ ] Add `checkSecretStatus()` function to call `/secret/status`
  - [ ] Implement UI update logic for success/failure states
  - [ ] Display secret value and name in user-friendly format
  - [ ] Add error message display for failure scenarios

- [ ] **Task 5.9:** Update `frontend/styles.css`
  - [ ] Add styles for new Secrets Manager section
  - [ ] Ensure visual consistency with existing status badges
  - [ ] Style secret value display (consider monospace font)

### Phase 5D: Integration Testing
- [ ] **Task 5.10:** Local testing
  - [ ] Build and test container locally
  - [ ] Verify all endpoints work correctly
  - [ ] Test frontend displays all status sections properly

- [ ] **Task 5.11:** Deployment testing
  - [ ] Deploy via `make deploy`
  - [ ] Test application through CloudFront distribution
  - [ ] Verify end-to-end functionality from browser to AWS Secrets Manager
  - [ ] Validate all status badges show correct states

- [ ] **Task 5.12:** Error scenario testing
  - [ ] Test with temporarily removed IAM permissions
  - [ ] Test with non-existent secret name
  - [ ] Verify graceful degradation and error reporting

## Success Criteria

### Functional Requirements
- [ ] Dummy secret successfully created in AWS Secrets Manager via Terraform
- [ ] Application retrieves secret using IAM Roles Anywhere authentication from Phase 4
- [ ] `/secret/status` endpoint returns correct JSON with secret value
- [ ] Frontend displays OK badge and secret information
- [ ] All error scenarios handled gracefully with appropriate user feedback

### Infrastructure Requirements
- [ ] Complete deployment achievable with single `terraform apply`
- [ ] No hardcoded AWS credentials anywhere in codebase
- [ ] IAM permissions follow least-privilege principle
- [ ] Clean terraform plan on subsequent runs (idempotent)

### Integration Requirements
- [ ] Works through existing CloudFront distribution from Phase 3
- [ ] Maintains compatibility with all previous phase functionality
- [ ] Database status, IAM status, and Secrets Manager status all visible simultaneously
- [ ] Consistent visual design across all status sections

## Architecture Notes

### Security Considerations
- IAM role permissions scoped to specific secret ARN only
- No AWS credentials stored in environment variables
- X.509 certificate-based authentication maintains security model
- Error messages don't expose sensitive information

### AWS Resources Created
- `aws_secretsmanager_secret`: Named secret for demonstration
- `aws_secretsmanager_secret_version`: JSON content for the secret
- Updated IAM role policy with Secrets Manager permissions

### Integration Points
- Reuses existing AWS session from Phase 4 IAM Roles Anywhere authentication
- Extends existing backend API structure with new endpoint
- Builds upon existing frontend status display pattern
- Maintains CloudFront routing for all requests

## Testing Strategy

### Unit Testing
- Secret retrieval function with mocked AWS responses
- Error handling for various AWS SDK exceptions
- JSON response structure validation

### Integration Testing
- End-to-end authentication flow from certificate to secret retrieval
- Frontend-to-backend API calls through CloudFront
- Database + IAM + Secrets Manager status display together

### Manual Testing Checklist
1. Visit CloudFront URL and verify all sections load
2. Confirm all three status badges (DB, IAM, Secrets) show "OK"
3. Verify secret value displays correctly
4. Test with invalid permissions (temporarily) to confirm error handling
5. Check browser developer tools for any console errors
6. Validate all styling is consistent across sections
