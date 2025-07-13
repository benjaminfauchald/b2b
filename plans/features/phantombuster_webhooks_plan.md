# PhantomBuster Webhooks Feature Implementation Plan

## Overview
Implement PhantomBuster webhook integration to enable sequential job processing and eliminate 429 rate limiting errors. Replace polling-based status checks with webhook-driven notifications for efficient, reliable job execution.

## Problem Analysis
- **Current Issue**: Multiple PhantomBuster jobs run concurrently causing 429 "Too Many Requests" errors
- **Root Cause**: No sequential processing coordination between Sidekiq workers
- **Impact**: Failed jobs due to API rate limits, wasted resources from continuous polling

## Solution Architecture

### 1. Webhook Integration
- **PhantomBuster Native Webhooks**: Use PhantomBuster's built-in webhook feature that triggers on job completion
- **Sequential Processing**: Implement job queueing that processes one PhantomBuster job at a time
- **Replace Polling**: Eliminate `PersonProfileExtractionStatusWorker` polling with webhook-driven notifications

### 2. Implementation Components

#### A. Webhook Controller (`webhooks_controller.rb`)
```ruby
# POST /webhooks/phantombuster/profile_extraction
class WebhooksController < ApplicationController
  def phantombuster_profile_extraction
    # Verify webhook signature
    # Process completion payload  
    # Queue next job if available
    # Update SCT audit logs
  end
end
```

#### B. Sequential Job Queue Manager
```ruby
class PhantomBusterSequentialQueue
  # Manage sequential processing using Redis locks
  # Ensure only one PhantomBuster job runs at a time
  # Queue pending jobs with priority ordering
end
```

#### C. Enhanced PersonProfileExtractionWorker
```ruby
class PersonProfileExtractionWorker
  # Remove polling logic
  # Configure PhantomBuster with webhook URL
  # Store job metadata for webhook tracking
  # Implement proper 429 error handling
end
```

#### D. Webhook Job Processor
```ruby
class PhantomBusterWebhookJob < ApplicationJob
  # Process webhook payloads asynchronously
  # Handle completion, failure, and timeout events
  # Trigger next job in queue
end
```

### 3. Technical Implementation Details

#### A. Gems Required
- `sidekiq-unique-jobs` - For sequential processing constraints
- `rack-attack` - Rate limiting protection for webhook endpoints  
- `ruby-limiter` - API call throttling
- `retries` - Enhanced retry mechanisms with exponential backoff

#### B. Database Schema
```sql
-- Add webhook tracking to service_audit_logs
ALTER TABLE service_audit_logs ADD COLUMN webhook_payload JSONB;
ALTER TABLE service_audit_logs ADD COLUMN phantom_container_id VARCHAR;
```

#### C. Configuration
- **Webhook URL**: `https://app.connectica.no/webhooks/phantombuster/profile_extraction?secret=WEBHOOK_SECRET`
- **Queue Configuration**: Single-threaded processing for PhantomBuster jobs
- **Rate Limiting**: Respect PhantomBuster API limits with exponential backoff

### 4. Sequential Processing Strategy

#### A. Using sidekiq-unique-jobs
```ruby
class PhantomBusterProfileExtractionWorker
  include Sidekiq::Worker
  
  sidekiq_options queue: :phantom_profile_extraction,
                  unique: :until_executed,
                  unique_args: ->(args) { ["phantom_profile_extraction"] }
                  
  # Ensures only one PhantomBuster profile extraction runs at a time
end
```

#### B. Job Queueing Flow
1. **Queue Request**: User requests processing of N companies
2. **Sequential Launch**: Launch first PhantomBuster job only
3. **Webhook Response**: PhantomBuster notifies completion via webhook
4. **Next Job**: Webhook handler launches next job if queue has pending companies
5. **Repeat**: Continue until all companies processed

### 5. Service Control Table (SCT) Integration

#### A. Audit Logging Enhancements
```ruby
# Enhanced metadata for webhook-based processing
metadata: {
  webhook_received_at: timestamp,
  phantom_container_id: container_id,
  webhook_payload: full_payload,
  next_job_queued: boolean,
  queue_position: integer
}
```

#### B. Status Tracking
- **pending**: Job queued but not yet launched
- **phantom_launched**: PhantomBuster job started
- **webhook_received**: Completion webhook received
- **success/failed**: Final status based on webhook payload

### 6. Error Handling & Recovery

#### A. Webhook Failure Scenarios
```ruby
# Timeout: No webhook received within 30 minutes
# Invalid payload: Webhook received but malformed
# PhantomBuster failure: Job failed in PhantomBuster
# Network issues: Webhook delivery failed
```

#### B. Recovery Mechanisms
- **Timeout Monitor**: Safety net job to handle stuck PhantomBuster jobs
- **Dead Letter Queue**: Handle permanently failed jobs
- **Manual Restart**: Web UI to restart stuck sequential processing

### 7. UI/UX Enhancements

#### A. Queue Status Display (ViewComponent)
```ruby
class PhantomBusterQueueStatusComponent < ViewComponent::Base
  # Show current job in progress
  # Display queue length and estimated completion
  # Real-time updates via Turbo Streams
end
```

#### B. Progress Indicators
- Current job status with PhantomBuster container ID
- Queue position for pending jobs
- Estimated completion times
- Error states with retry options

### 8. Testing Strategy

#### A. Unit Tests
- `PhantomBusterWebhookController` webhook payload processing
- `PhantomBusterSequentialQueue` queueing logic
- `PhantomBusterWebhookJob` job processing

#### B. Integration Tests
- End-to-end webhook flow from PhantomBuster to completion
- Sequential processing with multiple companies
- Error handling and recovery scenarios

#### C. Performance Tests
- Webhook response time requirements (< 11 seconds)
- Queue throughput under load
- Memory usage with large queues

### 9. Implementation Steps

#### Phase 1: Core Webhook Infrastructure (2-3 hours)
1. **Webhook Controller**: Implement basic webhook endpoint with signature verification
2. **Webhook Job**: Create job to process webhook payloads asynchronously
3. **Basic Tests**: Unit tests for webhook processing

#### Phase 2: Sequential Processing (2-3 hours)
1. **Queue Manager**: Implement Redis-based sequential queue
2. **Worker Enhancement**: Update PersonProfileExtractionWorker for webhook mode
3. **Integration**: Connect webhook completion to next job launching

#### Phase 3: SCT Integration (1-2 hours)
1. **Database Migration**: Add webhook tracking fields
2. **Audit Logging**: Enhance ServiceAuditLog with webhook metadata
3. **Status Updates**: Real-time status updates via webhooks

#### Phase 4: UI/UX Components (1-2 hours)
1. **Queue Status Component**: ViewComponent for queue visualization
2. **Progress Indicators**: Real-time progress updates
3. **Error Handling UI**: User-friendly error states and recovery

#### Phase 5: Testing & Validation (1-2 hours)
1. **Comprehensive Testing**: Unit, integration, and performance tests
2. **Error Scenario Testing**: Timeout, failure, and recovery scenarios
3. **Documentation**: API documentation and troubleshooting guide

### 10. Deployment Plan

#### A. Environment Variables
```bash
PHANTOMBUSTER_WEBHOOK_SECRET=secure_random_secret
PHANTOMBUSTER_API_KEY=existing_api_key
SEQUENTIAL_QUEUE_TIMEOUT=1800  # 30 minutes
```

#### B. PhantomBuster Configuration
- Configure each PhantomBuster agent with webhook URL
- Set appropriate timeout values (30+ minutes for complex extractions)
- Test webhook delivery in staging environment

#### C. Production Rollout
1. **Deploy Code**: Deploy webhook infrastructure
2. **Configure Agents**: Update PhantomBuster agents with webhook URLs
3. **Migration**: Gradually migrate from polling to webhook mode
4. **Monitor**: Track performance and error rates

### 11. Success Metrics

#### A. Performance Improvements
- **Rate Limit Errors**: Reduce 429 errors to near zero
- **Processing Time**: Improve overall job completion time
- **Resource Usage**: Reduce API calls by eliminating polling

#### B. Reliability Improvements
- **Job Success Rate**: Increase from current rate to >95%
- **Queue Throughput**: Process more companies per hour
- **Error Recovery**: Automatic recovery from transient failures

### 12. Risk Mitigation

#### A. Fallback Mechanisms
- **Polling Backup**: Keep polling logic as fallback for webhook failures
- **Manual Override**: Admin interface to manually trigger next jobs
- **Queue Drain**: Ability to process queue manually if automation fails

#### B. Monitoring & Alerting
- **Webhook Health**: Monitor webhook delivery success rates
- **Queue Stalls**: Alert on stuck queues or long processing times
- **Error Rates**: Track and alert on increased failure rates

## Acceptance Criteria

1. **Sequential Processing**: Only one PhantomBuster job runs at a time
2. **Webhook Integration**: Reliable webhook processing with <11 second response time
3. **Error Elimination**: 429 rate limiting errors reduced to <1% of jobs
4. **SCT Compliance**: Full audit logging with webhook metadata
5. **UI Updates**: Real-time queue status and progress indicators
6. **Testing Coverage**: >90% test coverage for all new components
7. **Documentation**: Complete API docs and troubleshooting guide

## Implementation Timeline
- **Total Estimate**: 8-12 hours of development time
- **Testing**: 2-3 hours additional for comprehensive testing
- **Documentation**: 1 hour for API docs and troubleshooting

## Dependencies
- PhantomBuster webhook configuration access
- Redis availability for queue management
- Staging environment for webhook testing
- Production deployment coordination

---

**Next Steps**: Await user approval before beginning implementation.