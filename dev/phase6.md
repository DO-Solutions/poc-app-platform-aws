# Phase 6: App Platform Worker for Continuous Data Updates

## Overview

Phase 6 adds a continuously running worker service to the App Platform that updates timestamps in all integrated services (PostgreSQL, Valkey, AWS Secrets Manager) every 60 seconds. This demonstrates real-time data flow and validates the operational stability of all service integrations.

## Architecture Changes

### New Components
- **Worker Service**: Python-based App Platform worker running alongside the existing API service
- **Database Schema**: New `last_update` table in PostgreSQL for timestamp tracking
- **Enhanced Frontend**: Real-time timestamp display with age indicators and color coding

### Data Flow
```
Worker Service (every 60s)
├── PostgreSQL → INSERT/UPDATE last_update table
├── Valkey → SET worker:last_update key
└── AWS Secrets Manager → Update secret with JSON timestamp

Frontend (every 30s)
├── GET /db/status → PostgreSQL + Valkey timestamps
├── GET /secret/status → AWS Secrets Manager timestamp
├── GET /iam/status → Credential expiry info
└── GET /worker/status → Aggregated status
```

## Technical Requirements

### 1. Worker Service Implementation
- **Runtime**: Python asyncio-based continuous loop
- **Frequency**: 60-second intervals
- **Error Handling**: Exponential backoff retry logic
- **Logging**: Structured logging for all operations
- **Graceful Shutdown**: Signal handling for clean termination

### 2. Database Schema Updates
```sql
CREATE TABLE last_update (
    source VARCHAR(50) PRIMARY KEY,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    metadata JSONB
);
```

### 3. API Endpoint Extensions
- **`/db/status`**: Add `postgres_last_update` and `valkey_last_update` fields
- **`/secret/status`**: Parse timestamp from JSON secret content
- **`/iam/status`**: Add `credentials_expiry` and `credentials_created` fields
- **`/worker/status`** (NEW): Aggregated timestamps with staleness indicators

### 4. Frontend Enhancements
- **New Column**: "Last Updated" with timestamp and age display
- **Color Coding**: 
  - Green: <60s old
  - Yellow: 60-90s old  
  - Red: >90s old or no valid timestamp or able to connect to the datasource.
- **Auto-refresh**: 30-second intervals or manual refresh button
- **Visual Indicators**: Loading spinners during refresh

### 5. Infrastructure as Code
- **App Platform**: Add worker service definition to digitalocean_app resource
- **IAM Permissions**: Add `secretsmanager:UpdateSecret` to existing role
- **Database Migration**: Terraform-managed schema updates

## Implementation Plan

### Phase 6.1: Worker Service Foundation
**Scope**: Core worker implementation and basic infrastructure

#### 6.1.1 Worker Service Code
- [ ] Create `app/worker.py` with asyncio main loop
- [ ] Implement PostgreSQL timestamp update function
- [ ] Implement Valkey timestamp update function  
- [ ] Implement AWS Secrets Manager timestamp update function
- [ ] Add structured logging throughout
- [ ] Implement graceful shutdown handling

#### 6.1.2 Database Schema
- [ ] Create PostgreSQL migration for `last_update` table
- [ ] Add database initialization to startup process
- [ ] Test schema creation in existing database

#### 6.1.3 Container Configuration
- [ ] Update Dockerfile to support both API and worker commands
- [ ] Test worker execution in local container
- [ ] Verify shared environment variables work for worker

### Phase 6.2: Infrastructure Integration
**Scope**: Terraform and App Platform configuration

#### 6.2.1 Terraform Updates
- [ ] Add worker service definition to `digitalocean_app` resource
- [ ] Configure worker environment variables (reuse from API)
- [ ] Update AWS IAM role permissions for `secretsmanager:UpdateSecret`
- [ ] Add database schema management to Terraform

#### 6.2.2 Secrets Manager Updates
- [ ] Modify existing secret to accept JSON format
- [ ] Test secret updates via IAM Roles Anywhere
- [ ] Verify secret permissions are sufficient

#### 6.2.3 Deployment Testing
- [ ] Test worker deployment via `make deploy`
- [ ] Verify worker starts and runs independently from API
- [ ] Confirm worker logs are accessible via App Platform console

### Phase 6.3: API Endpoint Extensions
**Scope**: Backend API modifications for timestamp exposure

#### 6.3.1 Database Status Updates
- [ ] Modify `/db/status` to query `last_update` table
- [ ] Add Valkey `worker:last_update` key retrieval
- [ ] Return formatted timestamp data in responses

#### 6.3.2 Secrets and IAM Status
- [ ] Update `/secret/status` to parse JSON timestamp from secret
- [ ] Modify `/iam/status` to include credential timing info
- [ ] Handle JSON parsing errors gracefully

#### 6.3.3 New Worker Status Endpoint
- [ ] Create `/worker/status` endpoint
- [ ] Implement timestamp aggregation logic
- [ ] Add staleness detection (>90 seconds)
- [ ] Return comprehensive status JSON

### Phase 6.4: Frontend Enhancements
**Scope**: UI updates for real-time timestamp display

#### 6.4.1 UI Layout Changes
- [ ] Add "Last Updated" column to status table
- [ ] Implement timestamp formatting with age calculation
- [ ] Add color coding CSS classes for freshness indicators

#### 6.4.2 Auto-Refresh Implementation
- [ ] Add 30-second auto-refresh functionality
- [ ] Implement manual refresh button
- [ ] Add loading indicators during data fetch
- [ ] Handle refresh errors gracefully

#### 6.4.3 Status Integration
- [ ] Update API calls to fetch new timestamp fields
- [ ] Display PostgreSQL, Valkey, and AWS timestamps
- [ ] Show IAM credential timing information
- [ ] Add visual indicators for stale data

### Phase 6.5: Testing and Validation
**Scope**: Comprehensive testing of worker functionality

#### 6.5.1 Functional Testing
- [ ] Verify worker updates all three data sources every ~60s
- [ ] Test timestamp accuracy and consistency
- [ ] Validate frontend displays real-time updates
- [ ] Confirm color coding works correctly

#### 6.5.2 Failure Scenario Testing
- [ ] Test worker behavior when databases are unavailable
- [ ] Verify recovery after temporary AWS connectivity issues
- [ ] Test API independence when worker is stopped
- [ ] Validate graceful worker shutdown and restart

#### 6.5.3 Performance Testing
- [ ] Monitor worker memory usage over extended runs
- [ ] Verify no resource leaks in continuous operation
- [ ] Test frontend performance with auto-refresh
- [ ] Confirm minimal impact on API service resources

## Success Criteria

### Deployment Success
- [ ] Single `terraform apply` deploys both API and worker services
- [ ] Worker service starts automatically and begins updating timestamps
- [ ] All existing functionality continues to work without changes

### Operational Success
- [ ] All three data sources show timestamps updating every ~60 seconds
- [ ] Frontend displays current timestamps with accurate age indicators
- [ ] Auto-refresh keeps data current without manual intervention
- [ ] System remains stable during extended operation (>24 hours)

### Integration Success
- [ ] Worker operates independently from API service lifecycle
- [ ] Timestamps remain consistent across multiple frontend sessions
- [ ] Graceful degradation when individual services are unavailable
- [ ] Clean logs show successful operations and any error recovery

## Risk Mitigation

### Resource Management
- **Risk**: Worker consuming excessive resources
- **Mitigation**: Monitor memory/CPU usage, implement cleanup cycles

### Service Dependencies
- **Risk**: Worker failures causing cascade issues
- **Mitigation**: Independent service architecture, circuit breaker patterns

### Data Consistency
- **Risk**: Timestamp drift between services
- **Mitigation**: UTC standardization, synchronized update cycles

### Deployment Complexity
- **Risk**: Multi-service deployment failures
- **Mitigation**: Terraform state management, rollback procedures

## Post-Implementation

### Monitoring
- Worker service health and performance metrics
- Database update frequency and success rates
- Frontend refresh patterns and error rates
- AWS API usage and rate limiting

### Future Enhancements
- WebSocket connections for real-time updates
- Worker health check endpoints
- Configurable update intervals
- Historical timestamp tracking